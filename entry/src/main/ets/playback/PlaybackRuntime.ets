import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ArtworkCache } from '../library/artwork/ArtworkCache';
import { MusicRepository } from '../library/data/MusicRepository';
import { ensureReadPermission } from '../library/importer/MediaPickerService';
import { MetadataReader } from '../library/metadata/MetadataReader';
import { AvailabilityState, TrackListItem } from '../library/model/LibraryModels';
import { SettingsRepository } from '../settings/SettingsRepository';
import { appSettings } from '../settings/AppSettingsStore';
import { ArtworkMemoryCache, DecodedFullArtwork } from './artwork/ArtworkMemoryCache';
import { PlaybackEngine, PlaybackEngineListener } from './engine/PlaybackEngine';
import {
  PlaybackTrack,
  PlayerState,
  PlayerStore,
  QueueBuildPhase,
  QueueTrack,
  RepeatMode
} from './model/PlaybackModels';
import { PlaybackQueue } from './queue/PlaybackQueue';
import { PlaybackSession, PlaybackSessionCommands } from './session/PlaybackSession';
import { LyricsParser } from './lyrics/LyricsParser';
import { LyricTimeline } from './lyrics/LyricTimeline';
import { LibraryPlaybackBridge } from '../library/store/LibraryPlaybackBridge';
import { PlaybackPowerPolicy } from './support/PlaybackPowerPolicy';

const RESUME_MINIMUM_MS = 5000;
const COMPLETION_REMAINING_MS = 10000;
const COMPLETION_POSITION_FRACTION = 0.95;
const QUEUE_BUILD_CHUNK_SIZE = 64;

class PlaybackRuntime implements PlaybackEngineListener, PlaybackSessionCommands, LibraryPlaybackBridge {
  readonly repository: MusicRepository = new MusicRepository();
  readonly playerStore: PlayerStore = new PlayerStore();

  private readonly engine: PlaybackEngine = new PlaybackEngine();
  private readonly queue: PlaybackQueue = new PlaybackQueue();
  private context?: common.UIAbilityContext;
  private settings?: SettingsRepository;
  private session?: PlaybackSession;
  private artworkCache?: ArtworkMemoryCache;
  private initializePromise?: Promise<void>;
  private artworkEpoch: number = 0;
  private queueBuildEpoch: number = 0;
  private seekEpoch: number = 0;
  private pendingSeekPositionMs?: number;
  private currentPlaybackTrack?: PlaybackTrack;
  private lastPositionWriteAt: number = 0;
  private lastPersistedTrackId: number = -2;
  private lastPersistedPositionMs: number = -1;
  private fullArtwork?: DecodedFullArtwork;
  private paletteChangeListener?: (primary: string, secondary: string, accent: string) => void;

  constructor() {
    this.engine.setListener(this);
  }

  initialize(context: common.UIAbilityContext, settings?: SettingsRepository): Promise<void> {
    if (this.initializePromise !== undefined) {
      return this.initializePromise;
    }
    if (this.context !== undefined) {
      return Promise.resolve();
    }
    this.initializePromise = this.initializeInternal(context, settings).catch(async (error: Object) => {
      await this.resetFailedInitialization();
      throw error instanceof Error ? error : new Error(`${error}`);
    }).finally(() => {
      this.initializePromise = undefined;
    });
    return this.initializePromise;
  }

  playFromLibrary(selected: TrackListItem, libraryItems: Array<TrackListItem>): void {
    if (!appSettings.preserveShuffleOnManualPlay && this.playerStore.shuffleEnabled) {
      this.setShuffleEnabled(false);
    }
    this.startLibraryPlayback(selected, libraryItems);
  }

  private startLibraryPlayback(selected: TrackListItem, libraryItems: Array<TrackListItem>): void {
    const selectedTrack = PlaybackRuntime.queueTrackOf(selected);
    const buildEpoch = ++this.queueBuildEpoch;
    this.queue.clear();
    this.playerStore.queuePhase = QueueBuildPhase.BUILDING;
    this.playerStore.queueSize = 0;
    this.syncQueueSnapshot();
    this.beginTrack(selectedTrack).then(() => {
      return this.buildQueueAsync(libraryItems, selected.id, buildEpoch);
    }).catch((error: Object) => {
      if (buildEpoch !== this.queueBuildEpoch) {
        return;
      }
      this.playerStore.queuePhase = QueueBuildPhase.FAILED;
      console.warn(`Unable to build playback queue: ${PlaybackRuntime.messageOf(error)}`);
    });
  }

  playInOrder(selected: TrackListItem, libraryItems: Array<TrackListItem>): void {
    this.playFromLibrary(selected, libraryItems);
  }

  shuffleAll(libraryItems: Array<TrackListItem>): void {
    if (libraryItems.length === 0) {
      return;
    }
    this.setShuffleEnabled(true);
    const selected = libraryItems[Math.floor(Math.random() * libraryItems.length)];
    this.startLibraryPlayback(selected, libraryItems);
  }

  insertNext(items: Array<TrackListItem>): void {
    this.enqueueLibraryItems(items, true);
  }

  appendToQueue(items: Array<TrackListItem>): void {
    this.enqueueLibraryItems(items, false);
  }

  togglePlayback(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    if (this.playerStore.isPlaying()) {
      this.pause();
    } else {
      this.play();
    }
  }

  play(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    this.playerStore.playWhenReady = true;
    if (this.playerStore.state === PlayerState.LOADING) {
      return;
    }
    this.engine.play().catch((error: Object) => {
      this.playerStore.playWhenReady = false;
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  pause(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    this.playerStore.playWhenReady = false;
    if (this.playerStore.state === PlayerState.LOADING || this.playerStore.state === PlayerState.READY) {
      return;
    }
    this.engine.pause().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  stop(): void {
    this.pause();
    this.persistProgress(false);
  }

  next(): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
    const next = this.queue.next(this.playerStore.repeatMode, false);
    this.syncQueueSnapshot();
    if (next !== undefined) {
      this.beginTrack(next);
    }
  }

  previous(): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
    const previous = this.queue.previous();
    this.syncQueueSnapshot();
    if (previous !== undefined) {
      this.beginTrack(previous);
    }
  }

  playQueueTrack(trackId: number): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY ||
      this.playerStore.currentTrack?.id === trackId) {
      return;
    }
    const selected = this.queue.select(trackId);
    this.syncQueueSnapshot();
    if (selected !== undefined) {
      this.beginTrack(selected);
    }
  }

  seek(positionMs: number): void {
    const targetPositionMs = Math.max(0, Math.min(positionMs, this.playerStore.progress.durationMs));
    const seekEpoch = ++this.seekEpoch;
    this.pendingSeekPositionMs = targetPositionMs;
    this.playerStore.progress.positionMs = targetPositionMs;
    this.updateActiveLyricIndex(targetPositionMs);
    this.engine.seek(targetPositionMs).then(() => {
      if (seekEpoch !== this.seekEpoch) {
        return;
      }
      this.playerStore.progress.positionMs = targetPositionMs;
      this.updateActiveLyricIndex(targetPositionMs);
      this.pendingSeekPositionMs = undefined;
      this.persistProgress(false);
      this.lastPositionWriteAt = Date.now();
      this.syncSessionState();
    }).catch((error: Object) => {
      if (seekEpoch !== this.seekEpoch) {
        return;
      }
      this.pendingSeekPositionMs = undefined;
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  toggleShuffle(): void {
    this.setShuffleEnabled(!this.playerStore.shuffleEnabled);
    if (this.playerStore.currentTrack !== undefined) {
      this.queue.setShuffle(this.playerStore.shuffleEnabled, this.playerStore.currentTrack.id);
      this.syncQueueSnapshot();
      this.prefetchCurrentWindow();
    }
  }

  cycleRepeatMode(): void {
    if (this.playerStore.repeatMode === RepeatMode.OFF) {
      this.playerStore.repeatMode = RepeatMode.ALL;
    } else if (this.playerStore.repeatMode === RepeatMode.ALL) {
      this.playerStore.repeatMode = RepeatMode.ONE;
    } else {
      this.playerStore.repeatMode = RepeatMode.OFF;
    }
    this.settings?.setPlaybackRepeatMode(this.playerStore.repeatMode);
    this.syncSessionState();
    this.prefetchCurrentWindow();
  }

  onBackground(): void {
    this.persistProgress(false);
    this.lastPositionWriteAt = Date.now();
  }

  async prepareForLibraryClear(): Promise<void> {
    this.persistProgress(false);
    ++this.artworkEpoch;
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    await this.engine.invalidateAndStop();
    this.retireFullArtwork();
    this.artworkCache?.clear();
    this.queue.clear();
    this.currentPlaybackTrack = undefined;
    this.playerStore.currentTrack = undefined;
    this.playerStore.miniArtwork = undefined;
    this.playerStore.miniArtworkUri = '';
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.heroArtworkRevision += 1;
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = 0;
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.playerStore.playWhenReady = false;
    this.persistResumeState(-1, 0);
    this.settings?.setPlaybackQueue([], -1);
    this.syncQueueSnapshot();
    this.onStateChanged(PlayerState.IDLE);
  }

  async shutdown(): Promise<void> {
    this.persistProgress(false);
    ++this.artworkEpoch;
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    await this.engine.shutdown();
    await this.session?.shutdown();
    this.playerStore.miniArtwork = undefined;
    this.playerStore.miniArtworkUri = '';
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.heroArtworkRevision += 1;
    this.playerStore.currentTrack = undefined;
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = 0;
    this.playerStore.state = PlayerState.IDLE;
    this.playerStore.playWhenReady = false;
    this.playerStore.errorMessage = '';
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.queue.clear();
    this.syncQueueSnapshot(false);
    this.currentPlaybackTrack = undefined;
    this.lastPositionWriteAt = 0;
    this.lastPersistedTrackId = -2;
    this.lastPersistedPositionMs = -1;
    this.artworkCache?.releaseAll();
    this.artworkCache?.releaseFullArtwork(this.fullArtwork);
    this.fullArtwork = undefined;
    this.context = undefined;
    this.settings = undefined;
    this.session = undefined;
    this.artworkCache = undefined;
    this.initializePromise = undefined;
  }

  onStateChanged(state: PlayerState, message?: string): void {
    this.playerStore.state = state;
    if (state === PlayerState.ERROR) {
      this.playerStore.playWhenReady = false;
    }
    this.playerStore.errorMessage = message === undefined ? '' : message;
    if (state === PlayerState.PAUSED || state === PlayerState.ERROR) {
      this.persistProgress(false);
      this.lastPositionWriteAt = Date.now();
    }
    this.syncSessionState();
  }

  onPositionChanged(positionMs: number): void {
    if (this.pendingSeekPositionMs === undefined) {
      this.playerStore.progress.positionMs = positionMs;
      this.updateActiveLyricIndex(positionMs);
    }
    const now = Date.now();
    if (PlaybackPowerPolicy.shouldPersistProgress(
      this.playerStore.state === PlayerState.PLAYING,
      now,
      this.lastPositionWriteAt
    )) {
      this.lastPositionWriteAt = now;
      this.persistProgress(false);
    }
  }

  onDurationChanged(durationMs: number): void {
    this.playerStore.progress.durationMs = durationMs;
  }

  onCompleted(): void {
    this.persistProgress(true);
    const next = this.queue.next(this.playerStore.repeatMode, true);
    this.syncQueueSnapshot();
    if (next !== undefined) {
      this.beginTrack(next);
    } else {
      this.playerStore.playWhenReady = false;
      this.syncSessionState();
    }
  }

  retainArtwork(pixelMap?: image.PixelMap): void {
    this.artworkCache?.retain(pixelMap);
  }

  releaseArtwork(pixelMap?: image.PixelMap): void {
    this.artworkCache?.releaseRetained(pixelMap);
  }

  queueArtworkUri(relativePath: string): string {
    return this.resolveArtworkUri(relativePath);
  }

  setPaletteChangeListener(listener?: (primary: string, secondary: string, accent: string) => void): void {
    this.paletteChangeListener = listener;
    if (listener !== undefined) {
      listener(this.playerStore.themePrimary(), this.playerStore.themeSecondary(), this.playerStore.themeAccent());
    }
  }

  private notifyPaletteChange(): void {
    this.paletteChangeListener?.(
      this.playerStore.themePrimary(), this.playerStore.themeSecondary(), this.playerStore.themeAccent()
    );
  }

  async refreshCurrentTrackPalette(): Promise<void> {
    const current = this.playerStore.currentTrack;
    if (current === undefined) {
      return;
    }
    const refreshed = await this.repository.getPlaybackTrack(current.id);
    if (refreshed === undefined || this.playerStore.currentTrack?.id !== current.id) {
      return;
    }
    current.palettePrimary = refreshed.palettePrimary;
    current.paletteSecondary = refreshed.paletteSecondary;
    current.paletteAccent = refreshed.paletteAccent;
    this.playerStore.palettePrimary = refreshed.palettePrimary;
    this.playerStore.paletteSecondary = refreshed.paletteSecondary;
    this.playerStore.paletteAccent = refreshed.paletteAccent;
    this.notifyPaletteChange();
  }

  private async initializeInternal(context: common.UIAbilityContext,
    providedSettings?: SettingsRepository): Promise<void> {
    this.context = context;
    this.settings = providedSettings === undefined ? new SettingsRepository(context) : providedSettings;
    appSettings.initialize(this.settings);
    await this.repository.initialize(context);
    const repeatMode = this.settings.getPlaybackRepeatMode(RepeatMode.ALL);
    this.playerStore.repeatMode = repeatMode >= RepeatMode.OFF && repeatMode <= RepeatMode.ONE ?
      repeatMode as RepeatMode : RepeatMode.ALL;
    this.playerStore.shuffleEnabled = this.settings.getPlaybackShuffleEnabled(false);
    this.artworkCache = new ArtworkMemoryCache(context);
    this.session = new PlaybackSession(context, this);
    await this.session.initialize();
    await this.restoreLastPlayback();
  }

  private async restoreLastPlayback(): Promise<void> {
    const storedIds = this.settings?.getPlaybackQueueTrackIds() ?? [];
    let trackId = this.settings?.getPlaybackQueueCurrentTrackId(-1) ?? -1;
    if (trackId < 0) {
      trackId = this.settings?.getPlaybackLastTrackId(-1) ?? -1;
    }
    if (trackId < 0) {
      return;
    }
    const ids = storedIds.length > 0 ? storedIds : [trackId];
    const pendingTracks: Array<Promise<PlaybackTrack | undefined>> = ids.map((id: number) => {
      return this.repository.getPlaybackTrack(id);
    });
    const restoredTracks = await Promise.all(pendingTracks);
    const queueTracks: Array<QueueTrack> = [];
    let track: PlaybackTrack | undefined;
    restoredTracks.forEach((restored: PlaybackTrack | undefined) => {
      if (restored !== undefined) {
        queueTracks.push(PlaybackRuntime.queueTrackOfPlaybackTrack(restored));
        if (restored.id === trackId) {
          track = restored;
        }
      }
    });
    if (track === undefined) {
      this.persistResumeState(-1, 0);
      this.settings?.setPlaybackQueue([], -1);
      return;
    }
    const queueTrack = PlaybackRuntime.queueTrackOfPlaybackTrack(track);
    this.queue.build(queueTracks, track.id, this.playerStore.shuffleEnabled);
    this.playerStore.queuePhase = QueueBuildPhase.READY;
    this.playerStore.queueSize = queueTracks.length;
    this.syncQueueSnapshot();
    await this.beginTrack(queueTrack, false, true);
  }

  private enqueueLibraryItems(items: Array<TrackListItem>, insertNext: boolean): void {
    if (items.length === 0) {
      return;
    }
    if (!this.playerStore.hasCurrentTrack() || this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      this.playInOrder(items[0], items);
      return;
    }
    const queueItems = items.map((item: TrackListItem) => PlaybackRuntime.queueTrackOf(item));
    if (insertNext) {
      this.queue.insertNext(queueItems);
    } else {
      this.queue.append(queueItems);
    }
    this.playerStore.queueSize = this.queue.size();
    this.syncQueueSnapshot();
    this.prefetchCurrentWindow();
  }

  private async resetFailedInitialization(): Promise<void> {
    try {
      await this.session?.shutdown();
    } catch (error) {
      console.warn(`Unable to clean up failed playback initialization: ${PlaybackRuntime.messageOf(error)}`);
    }
    this.artworkCache?.releaseAll();
    this.context = undefined;
    this.settings = undefined;
    this.session = undefined;
    this.artworkCache = undefined;
  }

  private beginTrack(track: QueueTrack, playWhenReady: boolean = true,
    preserveStoredPosition: boolean = false): Promise<void> {
    this.persistProgress(false);
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    this.engine.invalidateAndStop().catch((error: Object) => {
      if (PlaybackRuntime.messageOf(error) !== 'Playback request superseded') {
        console.warn(`Unable to stop previous playback: ${PlaybackRuntime.messageOf(error)}`);
      }
    });
    const previousTrack = this.playerStore.currentTrack;
    const sameLargeArtwork = PlaybackRuntime.sameArtwork(previousTrack, track, true);
    const sameSmallArtwork = PlaybackRuntime.sameArtwork(previousTrack, track, false);
    const epoch = ++this.artworkEpoch;
    if (!sameLargeArtwork) {
      this.retireFullArtwork();
    }
    this.currentPlaybackTrack = undefined;
    this.lastPositionWriteAt = Date.now();
    this.playerStore.currentTrack = track;
    this.playerStore.lyrics = '';
    this.playerStore.setTimedLyrics([]);
    this.playerStore.setActiveLyricIndex(-1);
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = track.durationMs;
    this.playerStore.palettePrimary = track.palettePrimary;
    this.playerStore.paletteSecondary = track.paletteSecondary;
    this.playerStore.paletteAccent = track.paletteAccent;
    this.notifyPaletteChange();
    this.playerStore.playWhenReady = playWhenReady;
    if (!preserveStoredPosition) {
      this.persistResumeState(track.id, 0);
    }
    this.playerStore.state = PlayerState.LOADING;
    this.playerStore.errorMessage = '';
    this.artworkCache?.pinCurrent(track);
    if (!sameSmallArtwork) {
      this.playerStore.miniArtwork = undefined;
      this.playerStore.miniArtworkUri = this.resolveArtworkUri(track.smallArtworkPath);
    }
    if (!sameLargeArtwork) {
      this.playerStore.heroArtwork = this.artworkCache?.getLarge(track);
      this.playerStore.heroArtworkUri = this.resolveArtworkUri(track.largeArtworkPath);
      this.playerStore.heroArtworkPreferPixelMap = this.playerStore.heroArtwork !== undefined;
      this.playerStore.heroArtworkRevision += 1;
      this.loadCurrentHeroArtwork(track, epoch);
    }
    const playbackStarted = this.loadAndPlayTrack(track.id, epoch);
    if (this.playerStore.queuePhase === QueueBuildPhase.READY) {
      this.prefetchCurrentWindow();
    }
    return playbackStarted;
  }

  private buildQueueAsync(libraryItems: Array<TrackListItem>, selectedId: number,
    buildEpoch: number): Promise<void> {
    const queueItems: Array<QueueTrack> = [];
    return new Promise<void>((resolve, reject) => {
      let index = 0;
      const appendChunk = (): void => {
        if (buildEpoch !== this.queueBuildEpoch) {
          resolve();
          return;
        }
        try {
          const end = Math.min(index + QUEUE_BUILD_CHUNK_SIZE, libraryItems.length);
          while (index < end) {
            queueItems.push(PlaybackRuntime.queueTrackOf(libraryItems[index]));
            index += 1;
          }
          if (index < libraryItems.length) {
            setTimeout(appendChunk, 0);
            return;
          }
          const phase = this.queue.build(queueItems, selectedId, this.playerStore.shuffleEnabled);
          this.playerStore.queuePhase = phase;
          this.playerStore.queueSize = this.queue.size();
          this.syncQueueSnapshot();
          this.prefetchCurrentWindow();
          resolve();
        } catch (error) {
          reject(error);
        }
      };
      setTimeout(appendChunk, 0);
    });
  }

  private async loadAndPlayTrack(trackId: number, epoch: number): Promise<void> {
    try {
      const track = await this.repository.getPlaybackTrack(trackId);
      if (epoch !== this.artworkEpoch) {
        return;
      }
      if (track === undefined) {
        throw new Error('音乐记录不存在，可能已从音乐库移除');
      }
      this.currentPlaybackTrack = track;
      this.playerStore.progress.durationMs = track.durationMs;
      this.session?.updateMetadata(track, this.playerStore.heroArtworkUri);
      if (!await ensureReadPermission(track.uri)) {
        this.repository.setTrackAvailability(trackId, AvailabilityState.AUTHORIZATION_REVOKED)
          .catch(() => undefined);
        throw new Error('音乐文件授权已失效，请重新导入该文件');
      }
      if (epoch !== this.artworkEpoch) {
        return;
      }
      if (track.availability !== AvailabilityState.AVAILABLE) {
        track.availability = AvailabilityState.AVAILABLE;
        this.repository.setTrackAvailability(trackId, AvailabilityState.AVAILABLE).catch((error: Object) => {
          console.warn(`Unable to restore track availability: ${PlaybackRuntime.messageOf(error)}`);
        });
      }
      this.loadCurrentLyrics(track, epoch);
      const storedTrackId = this.settings?.getPlaybackLastTrackId(-1) ?? -1;
      const storedPosition = appSettings.rememberPlaybackPosition && storedTrackId === trackId ?
        this.settings?.getPlaybackLastPositionMs(0) ?? 0 : 0;
      const resumePosition = PlaybackRuntime.validResumePosition(storedPosition, track.durationMs);
      await this.engine.playTrack(track, resumePosition, () => this.playerStore.playWhenReady);
      if (epoch !== this.artworkEpoch) {
        return;
      }
      if (this.fullArtwork === undefined) {
        this.loadFullArtwork(track, epoch);
      }
    } catch (error) {
      if (epoch !== this.artworkEpoch) {
        return;
      }
      const message = PlaybackRuntime.messageOf(error);
      console.warn(`Unable to start playback for track ${trackId}: ${message}`);
      this.onStateChanged(PlayerState.ERROR, message);
    }
  }

  private async loadCurrentHeroArtwork(track: QueueTrack, epoch: number): Promise<void> {
    const pixelMap = await this.artworkCache?.loadLarge(track);
    if (epoch === this.artworkEpoch && pixelMap !== undefined && this.fullArtwork === undefined) {
      this.playerStore.heroArtwork = pixelMap;
      this.playerStore.heroArtworkPreferPixelMap = true;
      this.playerStore.heroArtworkRevision += 1;
    }
  }

  private async loadCurrentLyrics(track: PlaybackTrack, epoch: number): Promise<void> {
    try {
      const lyrics = await MetadataReader.readLyrics(track.uri, track.fileSize, track.format);
      if (epoch === this.artworkEpoch) {
        this.playerStore.lyrics = lyrics;
        this.playerStore.setTimedLyrics(LyricsParser.parse(lyrics).lines);
        this.updateActiveLyricIndex(this.playerStore.progress.positionMs);
        this.session?.updateMetadata(track, this.playerStore.heroArtworkUri, lyrics);
      }
    } catch (error) {
      if (epoch === this.artworkEpoch) {
        this.playerStore.lyrics = '';
        this.playerStore.setTimedLyrics([]);
        this.playerStore.setActiveLyricIndex(-1);
      }
      console.warn(`Unable to read embedded lyrics: ${PlaybackRuntime.messageOf(error)}`);
    }
  }

  private async loadFullArtwork(track: PlaybackTrack, epoch: number): Promise<void> {
    try {
      const artwork = await this.artworkCache?.decodeFullArtwork(track);
      if (artwork === undefined) {
        return;
      }
      if (epoch !== this.artworkEpoch) {
        this.artworkCache?.releaseFullArtwork(artwork);
        return;
      }
      this.fullArtwork = artwork;
      this.playerStore.heroArtwork = artwork.pixelMap;
      this.playerStore.heroArtworkPreferPixelMap = true;
      this.playerStore.heroArtworkRevision += 1;
      try {
        await this.session?.updateMetadata(track, artwork.pixelMap);
      } catch (error) {
        console.warn(`Unable to publish full artwork to AVSession: ${PlaybackRuntime.messageOf(error)}`);
      }
    } catch (error) {
      console.warn(`Unable to load full artwork: ${PlaybackRuntime.messageOf(error)}`);
    }
  }

  private prefetchCurrentWindow(): void {
    if (this.playerStore.currentTrack === undefined || this.artworkCache === undefined) {
      return;
    }
    const radius = Math.max(0, Math.min(8, this.settings?.getPlaybackArtworkWindowRadius(2) ?? 2));
    const window = this.queue.playbackWindow(radius, this.playerStore.repeatMode);
    this.artworkCache.prefetchWindow(window.items, window.currentIndex, radius).catch((error: Object) => {
      console.warn(`Unable to prefetch artwork window: ${PlaybackRuntime.messageOf(error)}`);
    });
  }

  private syncQueueSnapshot(persist: boolean = true): void {
    const snapshot = this.queue.snapshot();
    this.playerStore.queueDataSource.replace(snapshot.items);
    this.playerStore.queueItems = snapshot.items;
    this.playerStore.queueCurrentIndex = snapshot.currentIndex;
    const currentTrackId = snapshot.currentIndex >= 0 && snapshot.currentIndex < snapshot.items.length ?
      snapshot.items[snapshot.currentIndex].id : -1;
    if (persist) {
      this.settings?.setPlaybackQueue(
        snapshot.items.map((track: QueueTrack) => track.id),
        currentTrackId
      );
    }
  }

  private persistProgress(completed: boolean): void {
    const track = this.currentPlaybackTrack;
    if (track === undefined) {
      return;
    }
    const duration = this.playerStore.progress.durationMs > 0 ?
      this.playerStore.progress.durationMs : track.durationMs;
    let position = this.playerStore.progress.positionMs;
    let consideredCompleted = completed;
    if (!consideredCompleted && duration > 0 &&
      (duration - position <= COMPLETION_REMAINING_MS || position >= duration * COMPLETION_POSITION_FRACTION)) {
      consideredCompleted = true;
    }
    if (position < RESUME_MINIMUM_MS || consideredCompleted) {
      position = 0;
    }
    if (!appSettings.rememberPlaybackPosition) {
      position = 0;
    }
    this.persistResumeState(track.id, position);
  }

  private persistResumeState(trackId: number, positionMs: number): void {
    if (this.settings === undefined || !PlaybackPowerPolicy.resumeStateChanged(
      trackId,
      positionMs,
      this.lastPersistedTrackId,
      this.lastPersistedPositionMs
    )) {
      return;
    }
    this.lastPersistedTrackId = trackId;
    this.lastPersistedPositionMs = positionMs;
    this.settings.setPlaybackResumeState(trackId, positionMs);
  }

  private syncSessionState(): void {
    this.session?.updatePlaybackState(
      this.playerStore.state,
      this.playerStore.progress.positionMs,
      this.playerStore.repeatMode,
      this.playerStore.shuffleEnabled
    );
  }

  private setShuffleEnabled(enabled: boolean): void {
    this.playerStore.shuffleEnabled = enabled;
    this.settings?.setPlaybackShuffleEnabled(enabled);
    this.syncSessionState();
  }

  private resolveArtworkUri(relativePath: string): string {
    if (relativePath.length === 0 || this.context === undefined) {
      return '';
    }
    return `file://${ArtworkCache.resolvePath(this.context, relativePath)}`;
  }

  private retireFullArtwork(): void {
    this.artworkCache?.releaseFullArtwork(this.fullArtwork);
    this.fullArtwork = undefined;
  }

  private static sameArtwork(previous: QueueTrack | undefined, next: QueueTrack, large: boolean): boolean {
    if (previous === undefined) {
      return false;
    }
    const previousHash = large ? previous.largeArtworkHash : previous.smallArtworkHash;
    const nextHash = large ? next.largeArtworkHash : next.smallArtworkHash;
    if (previousHash.length > 0 && nextHash.length > 0) {
      return previousHash === nextHash;
    }
    const previousPath = large ? previous.largeArtworkPath : previous.smallArtworkPath;
    const nextPath = large ? next.largeArtworkPath : next.smallArtworkPath;
    return previousPath.length > 0 && previousPath === nextPath;
  }

  private updateActiveLyricIndex(positionMs: number): void {
    this.playerStore.setActiveLyricIndex(
      LyricTimeline.activeIndexAt(this.playerStore.timedLyrics, positionMs)
    );
  }

  private static queueTrackOf(item: TrackListItem): QueueTrack {
    return {
      id: item.id,
      title: item.title,
      artistDisplay: item.artistDisplay,
      albumDisplay: item.albumDisplay,
      durationMs: item.durationMs,
      smallArtworkHash: item.smallArtworkHash,
      smallArtworkPath: item.smallArtworkPath,
      largeArtworkHash: item.artworkHash,
      largeArtworkPath: item.artworkPath,
      artworkWidth: item.artworkWidth,
      artworkHeight: item.artworkHeight,
      palettePrimary: item.palettePrimary,
      paletteSecondary: item.paletteSecondary,
      paletteAccent: item.paletteAccent
    };
  }

  private static queueTrackOfPlaybackTrack(track: PlaybackTrack): QueueTrack {
    return {
      id: track.id,
      title: track.title,
      artistDisplay: track.artistDisplay,
      albumDisplay: track.albumDisplay,
      durationMs: track.durationMs,
      smallArtworkHash: track.smallArtworkHash,
      smallArtworkPath: track.smallArtworkPath,
      largeArtworkHash: track.largeArtworkHash,
      largeArtworkPath: track.largeArtworkPath,
      artworkWidth: track.artworkWidth,
      artworkHeight: track.artworkHeight,
      palettePrimary: track.palettePrimary,
      paletteSecondary: track.paletteSecondary,
      paletteAccent: track.paletteAccent
    };
  }

  private static validResumePosition(positionMs: number, durationMs: number): number {
    if (positionMs < RESUME_MINIMUM_MS || durationMs <= 0 ||
      durationMs - positionMs <= COMPLETION_REMAINING_MS ||
      positionMs >= durationMs * COMPLETION_POSITION_FRACTION) {
      return 0;
    }
    return positionMs;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}

export const playbackRuntime: PlaybackRuntime = new PlaybackRuntime();
