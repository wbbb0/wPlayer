import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ArtworkCache } from '../library/artwork/ArtworkCache';
import { MusicRepository } from '../library/data/MusicRepository';
import { ensureReadPermission } from '../library/importer/MediaPickerService';
import { AvailabilityState, TrackListItem } from '../library/model/LibraryModels';
import { SettingsRepository } from '../settings/SettingsRepository';
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

const POSITION_WRITE_INTERVAL_MS = 5000;
const SESSION_POSITION_INTERVAL_MS = 1000;
const RESUME_MINIMUM_MS = 5000;
const COMPLETION_REMAINING_MS = 10000;
const QUEUE_BUILD_CHUNK_SIZE = 64;

class PlaybackRuntime implements PlaybackEngineListener, PlaybackSessionCommands {
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
  private currentPlaybackTrack?: PlaybackTrack;
  private lastPositionWriteAt: number = 0;
  private lastSessionPositionAt: number = 0;
  private fullArtwork?: DecodedFullArtwork;

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
    const selectedTrack = PlaybackRuntime.queueTrackOf(selected);
    const buildEpoch = ++this.queueBuildEpoch;
    this.queue.clear();
    this.playerStore.queuePhase = QueueBuildPhase.BUILDING;
    this.playerStore.queueSize = 0;
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
    this.setShuffleEnabled(false);
    this.playFromLibrary(selected, libraryItems);
  }

  shuffleAll(libraryItems: Array<TrackListItem>): void {
    if (libraryItems.length === 0) {
      return;
    }
    this.setShuffleEnabled(true);
    const selected = libraryItems[Math.floor(Math.random() * libraryItems.length)];
    this.playFromLibrary(selected, libraryItems);
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
    this.engine.togglePlayback().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  play(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    this.engine.play().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  pause(): void {
    if (!this.playerStore.hasCurrentTrack()) {
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
    if (next !== undefined) {
      this.beginTrack(next);
    }
  }

  previous(): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
    const previous = this.queue.previous();
    if (previous !== undefined) {
      this.beginTrack(previous);
    }
  }

  seek(positionMs: number): void {
    this.engine.seek(positionMs).catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  toggleShuffle(): void {
    this.setShuffleEnabled(!this.playerStore.shuffleEnabled);
    if (this.playerStore.currentTrack !== undefined) {
      this.queue.setShuffle(this.playerStore.shuffleEnabled, this.playerStore.currentTrack.id);
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
  }

  async prepareForLibraryClear(): Promise<void> {
    this.persistProgress(false);
    ++this.artworkEpoch;
    ++this.queueBuildEpoch;
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
    this.playerStore.positionMs = 0;
    this.playerStore.durationMs = 0;
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.onStateChanged(PlayerState.IDLE);
  }

  async shutdown(): Promise<void> {
    this.persistProgress(false);
    ++this.artworkEpoch;
    ++this.queueBuildEpoch;
    await this.engine.shutdown();
    await this.session?.shutdown();
    this.playerStore.miniArtwork = undefined;
    this.playerStore.miniArtworkUri = '';
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.currentTrack = undefined;
    this.playerStore.positionMs = 0;
    this.playerStore.durationMs = 0;
    this.playerStore.state = PlayerState.IDLE;
    this.playerStore.errorMessage = '';
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.queue.clear();
    this.currentPlaybackTrack = undefined;
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
    this.playerStore.errorMessage = message === undefined ? '' : message;
    if (state === PlayerState.PAUSED || state === PlayerState.ERROR) {
      this.persistProgress(false);
    }
    this.syncSessionState();
  }

  onPositionChanged(positionMs: number): void {
    this.playerStore.positionMs = positionMs;
    const now = Date.now();
    if (now - this.lastPositionWriteAt >= POSITION_WRITE_INTERVAL_MS) {
      this.lastPositionWriteAt = now;
      this.persistProgress(false);
    }
    if (now - this.lastSessionPositionAt >= SESSION_POSITION_INTERVAL_MS) {
      this.lastSessionPositionAt = now;
      this.syncSessionState();
    }
  }

  onDurationChanged(durationMs: number): void {
    this.playerStore.durationMs = durationMs;
  }

  onCompleted(): void {
    this.persistProgress(true);
    const next = this.queue.next(this.playerStore.repeatMode, true);
    if (next !== undefined) {
      this.beginTrack(next);
    }
  }

  retainArtwork(pixelMap?: image.PixelMap): void {
    this.artworkCache?.retain(pixelMap);
  }

  releaseArtwork(pixelMap?: image.PixelMap): void {
    this.artworkCache?.releaseRetained(pixelMap);
  }

  private async initializeInternal(context: common.UIAbilityContext,
    providedSettings?: SettingsRepository): Promise<void> {
    this.context = context;
    this.settings = providedSettings === undefined ? new SettingsRepository(context) : providedSettings;
    await this.repository.initialize(context);
    const repeatMode = this.settings.getPlaybackRepeatMode(RepeatMode.ALL);
    this.playerStore.repeatMode = repeatMode >= RepeatMode.OFF && repeatMode <= RepeatMode.ONE ?
      repeatMode as RepeatMode : RepeatMode.ALL;
    this.playerStore.shuffleEnabled = this.settings.getPlaybackShuffleEnabled(false);
    this.artworkCache = new ArtworkMemoryCache(context);
    this.session = new PlaybackSession(context, this);
    await this.session.initialize();
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

  private beginTrack(track: QueueTrack): Promise<void> {
    this.persistProgress(false);
    this.engine.invalidateAndStop().catch((error: Object) => {
      if (PlaybackRuntime.messageOf(error) !== 'Playback request superseded') {
        console.warn(`Unable to stop previous playback: ${PlaybackRuntime.messageOf(error)}`);
      }
    });
    const epoch = ++this.artworkEpoch;
    this.retireFullArtwork();
    this.currentPlaybackTrack = undefined;
    this.playerStore.currentTrack = track;
    this.playerStore.positionMs = 0;
    this.playerStore.durationMs = track.durationMs;
    this.playerStore.state = PlayerState.LOADING;
    this.playerStore.errorMessage = '';
    this.artworkCache?.pinCurrent(track);
    this.playerStore.miniArtwork = undefined;
    this.playerStore.miniArtworkUri = this.resolveArtworkUri(track.smallArtworkPath);
    this.playerStore.heroArtwork = this.artworkCache?.getLarge(track);
    this.playerStore.heroArtworkUri = this.resolveArtworkUri(track.largeArtworkPath);
    this.playerStore.heroArtworkPreferPixelMap = this.playerStore.heroArtwork !== undefined;
    this.loadCurrentHeroArtwork(track, epoch);
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
      const results = await Promise.all([
        this.repository.getPlaybackTrack(trackId),
        this.repository.getResumeState(trackId)
      ]);
      if (epoch !== this.artworkEpoch) {
        return;
      }
      const track = results[0];
      if (track === undefined) {
        throw new Error('音乐记录不存在，可能已从音乐库移除');
      }
      this.currentPlaybackTrack = track;
      this.playerStore.durationMs = track.durationMs;
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
      const resumePosition = PlaybackRuntime.validResumePosition(results[1].positionMs, track.durationMs);
      await this.engine.playTrack(track, resumePosition);
      if (epoch !== this.artworkEpoch) {
        return;
      }
      this.loadFullArtwork(track, epoch);
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

  private persistProgress(completed: boolean): void {
    const track = this.currentPlaybackTrack;
    if (track === undefined) {
      return;
    }
    const duration = this.playerStore.durationMs > 0 ? this.playerStore.durationMs : track.durationMs;
    let position = this.playerStore.positionMs;
    let consideredCompleted = completed;
    if (!consideredCompleted && duration > 0 &&
      (duration - position <= COMPLETION_REMAINING_MS || position >= duration * 0.95)) {
      consideredCompleted = true;
    }
    if (position < RESUME_MINIMUM_MS || consideredCompleted) {
      position = 0;
    }
    this.repository.savePlaybackState(track.id, position, duration, consideredCompleted).catch((error: Object) => {
      console.warn(`Unable to persist playback progress: ${PlaybackRuntime.messageOf(error)}`);
    });
  }

  private syncSessionState(): void {
    this.session?.updatePlaybackState(
      this.playerStore.state,
      this.playerStore.positionMs,
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
      artworkHeight: item.artworkHeight
    };
  }

  private static validResumePosition(positionMs: number, durationMs: number): number {
    if (positionMs < RESUME_MINIMUM_MS || durationMs <= 0 ||
      durationMs - positionMs <= COMPLETION_REMAINING_MS || positionMs >= durationMs * 0.95) {
      return 0;
    }
    return positionMs;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}

export const playbackRuntime: PlaybackRuntime = new PlaybackRuntime();
