import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { BundledArtworkCatalog } from '../library/artwork/BundledArtworkCatalog';
import { MusicRepository } from '../library/data/MusicRepository';
import { ensureReadPermission } from '../library/importer/MediaPickerService';
import {
  AvailabilityState,
  SortDirection,
  TrackListItem,
  TrackSortField
} from '../library/model/LibraryModels';
import { SettingsRepository } from '../settings/SettingsRepository';
import { appSettings } from '../settings/AppSettingsStore';
import { DecodedFullArtwork } from './artwork/ArtworkMemoryCache';
import {
  PlaybackEngine,
  PlaybackEngineListener,
  PlaybackFileError
} from './engine/PlaybackEngine';
import {
  CompletedCollectionMode,
  PlaybackOriginKind,
  PlaybackTrack,
  PlayerState,
  PlayerStore,
  QueueBuildPhase,
  QueueEntry,
  QueueTrack,
  RepeatMode
} from './model/PlaybackModels';
import { PlaybackQueue, PlaybackQueueRemovalResult } from './queue/PlaybackQueue';
import { PlaybackSession, PlaybackSessionCommands } from './session/PlaybackSession';
import { LyricsParser } from './lyrics/LyricsParser';
import { LyricTimeline } from './lyrics/LyricTimeline';
import { LibraryPlaybackBridge } from '../library/store/LibraryPlaybackBridge';
import { PlaybackPowerPolicy } from './support/PlaybackPowerPolicy';
import { PlaybackCoverageTracker } from './history/PlaybackCoverageTracker';
import { PlaybackStateReducer } from './support/PlaybackStateReducer';
import { DemoLibraryMode } from '../demo/DemoLibraryMode';
import { DemoMusicLibrary } from '../demo/DemoMusicLibrary';
import { LibraryRemovalService } from '../library/maintenance/LibraryRemovalService';
import {
  PlaybackPictureInPictureCommands,
  PlaybackPictureInPictureSnapshot
} from './pip/PlaybackPictureInPicture';
import { PlaybackPictureInPicturePolicy } from './pip/PlaybackPictureInPicturePolicy';
import {
  PlaybackPersistenceCoordinator,
  PlaybackRestorePlan
} from './coordinator/PlaybackPersistenceCoordinator';
import {
  AudioRecoveryAction,
  PlaybackAudioRecoveryCoordinator
} from './coordinator/PlaybackAudioRecoveryCoordinator';
import { PlaybackPictureInPictureCoordinator } from './coordinator/PlaybackPictureInPictureCoordinator';
import {
  PlaybackMediaCoordinator
} from './coordinator/PlaybackMediaCoordinator';
import {
  PlaybackMediaHostAdapter,
  PlaybackPersistencePort
} from './coordinator/PlaybackCoordinatorPorts';

const QUEUE_BUILD_CHUNK_SIZE = 64;

class PlaybackRuntime implements PlaybackEngineListener, PlaybackSessionCommands, LibraryPlaybackBridge,
  PlaybackPictureInPictureCommands {
  readonly repository: MusicRepository = new MusicRepository();
  readonly playerStore: PlayerStore = new PlayerStore();

  private readonly engine: PlaybackEngine = new PlaybackEngine();
  private readonly queue: PlaybackQueue = new PlaybackQueue();
  private readonly coverageTracker: PlaybackCoverageTracker = new PlaybackCoverageTracker();
  private readonly stateReducer: PlaybackStateReducer = new PlaybackStateReducer();
  private readonly persistence: PlaybackPersistenceCoordinator = new PlaybackPersistenceCoordinator();
  private readonly audioRecovery: PlaybackAudioRecoveryCoordinator = new PlaybackAudioRecoveryCoordinator();
  private readonly media: PlaybackMediaCoordinator = new PlaybackMediaCoordinator();
  private readonly persistencePort: PlaybackPersistencePort;
  private readonly mediaHost: PlaybackMediaHostAdapter;
  private readonly libraryRemoval: LibraryRemovalService =
    new LibraryRemovalService(this.repository);
  private readonly pictureInPicture: PlaybackPictureInPictureCoordinator;
  private context?: common.UIAbilityContext;
  private settings?: SettingsRepository;
  private session?: PlaybackSession;
  private initializePromise?: Promise<void>;
  private queueBuildEpoch: number = 0;
  private seekEpoch: number = 0;
  private pendingSeekPositionMs?: number;
  private currentPlaybackTrack?: PlaybackTrack;
  private artworkPrefetchReadyEpoch: number = -1;
  private lastPositionWriteAt: number = 0;
  private coverageNeedsRestart: boolean = false;
  private paletteChangeListener?: (primary: string, secondary: string, accent: string) => void;
  private demoProgressTimer: number = -1;

  constructor() {
    this.engine.setListener(this);
    this.persistencePort = new PlaybackPersistencePort(
      this.repository,
      (): SettingsRepository | undefined => this.settings
    );
    this.mediaHost = new PlaybackMediaHostAdapter(
      (token: number): boolean => this.isTrackRequestCurrent(token),
      (pixelMap: image.PixelMap): void => this.commitHeroArtwork(pixelMap),
      (artwork: DecodedFullArtwork): void => this.commitFullArtwork(artwork),
      (track: PlaybackTrack, lyrics: string): void => this.commitLyrics(track, lyrics),
      (): void => this.clearLyricsAfterFailure(),
      (track: QueueTrack): void => this.commitRefreshedPalette(track)
    );
    this.pictureInPicture = new PlaybackPictureInPictureCoordinator(this);
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

  playFromLibrary(selected: TrackListItem, libraryItems: Array<TrackListItem>,
    origin: PlaybackOriginKind = PlaybackOriginKind.LIBRARY): void {
    this.applyCompletedCollectionDefault(origin);
    if (!appSettings.preserveShuffleOnManualPlay && this.playerStore.shuffleEnabled) {
      this.setShuffleEnabled(false);
    }
    this.startLibraryPlayback(selected, libraryItems);
  }

  private startLibraryPlayback(selected: TrackListItem, libraryItems: Array<TrackListItem>): void {
    const selectedTrack = PlaybackRuntime.queueTrackOf(selected);
    const buildEpoch = ++this.queueBuildEpoch;
    this.clearAutomaticResumeIntents();
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

  playInOrder(selected: TrackListItem, libraryItems: Array<TrackListItem>,
    origin: PlaybackOriginKind = PlaybackOriginKind.LIBRARY): void {
    this.playFromLibrary(selected, libraryItems, origin);
  }

  shuffleAll(libraryItems: Array<TrackListItem>,
    origin: PlaybackOriginKind = PlaybackOriginKind.LIBRARY): void {
    if (libraryItems.length === 0) {
      return;
    }
    this.applyCompletedCollectionDefault(origin);
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

  insertCurrentNext(): void {
    const current = this.playerStore.currentTrack;
    if (current !== undefined) {
      this.enqueueQueueItems([current], true);
    }
  }

  appendCurrentToQueue(): void {
    const current = this.playerStore.currentTrack;
    if (current !== undefined) {
      this.enqueueQueueItems([current], false);
    }
  }

  playQueueSelection(items: Array<QueueTrack>): void {
    if (items.length === 0) {
      return;
    }
    const buildEpoch = ++this.queueBuildEpoch;
    const phase = this.queue.build(items, items[0].id, false);
    this.playerStore.queuePhase = phase;
    this.playerStore.queueSize = this.queue.size();
    this.syncQueueSnapshot();
    if (phase === QueueBuildPhase.READY) {
      this.beginTrack(items[0]).catch((error: Object): void => {
        if (buildEpoch === this.queueBuildEpoch) {
          console.warn(`Unable to play queue selection: ${PlaybackRuntime.messageOf(error)}`);
        }
      });
    }
  }

  insertQueueTracks(items: Array<QueueTrack>): void {
    this.enqueueQueueItems(items, true);
  }

  appendQueueTracks(items: Array<QueueTrack>): void {
    this.enqueueQueueItems(items, false);
  }

  removeQueueEntries(entryIds: Array<number>): void {
    if (entryIds.length === 0 || this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
    const result: PlaybackQueueRemovalResult = this.queue.removeEntries(entryIds);
    this.playerStore.queueSize = this.queue.size();
    this.playerStore.queuePhase =
      this.playerStore.queueSize > 0 ? QueueBuildPhase.READY : QueueBuildPhase.EMPTY;
    this.syncQueueSnapshot();
    if (result.removedCurrent && result.current !== undefined) {
      this.beginTrack(result.current);
    } else if (result.removedCurrent) {
      this.clearRemovedQueuePlayback();
    }
  }

  private clearRemovedQueuePlayback(): void {
    this.clearAutomaticResumeIntents();
    this.interruptCoverage();
    this.media.invalidate();
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    this.currentPlaybackTrack = undefined;
    this.playerStore.currentTrack = undefined;
    this.playerStore.playWhenReady = false;
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = 0;
    this.playerStore.setMiniArtwork(undefined, '');
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkRevision += 1;
    this.notifyPaletteChange();
    this.playerStore.transportState = this.stateReducer.reset();
    this.engine.invalidateAndStop().then((): void => {
      this.onStateChanged(PlayerState.IDLE);
    }).catch((error: Object): void => {
      console.warn(`Unable to stop an emptied playback queue: ${PlaybackRuntime.messageOf(error)}`);
    });
  }

  togglePlayback(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    if (this.playerStore.playWhenReady) {
      this.pause();
    } else {
      this.play();
    }
  }

  async enterPictureInPicture(uiContext: UIContext): Promise<boolean> {
    return this.pictureInPicture.enter(uiContext, this.pictureInPictureSnapshot());
  }

  bindPictureInPictureContext(uiContext: UIContext): void {
    this.pictureInPicture.bind(uiContext, this.pictureInPictureSnapshot());
  }

  unbindPictureInPictureContext(): void {
    this.pictureInPicture.unbind();
  }

  refreshPictureInPicturePreferences(): void {
    this.syncPictureInPicture();
  }

  onForeground(): void {
    this.pictureInPicture.onForeground();
  }

  onFullPlayerOpened(): void {
    this.pictureInPicture.onFullPlayerOpened();
  }

  play(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    if (DemoLibraryMode.isEnabled()) {
      this.playerStore.playWhenReady = true;
      this.playerStore.state = PlayerState.PLAYING;
      this.playerStore.transportState = this.stateReducer.reduce(PlayerState.PLAYING, true);
      this.startDemoProgress();
      this.syncSessionState();
      return;
    }
    this.updatePlaybackIntent(true);
    if (this.playerStore.state === PlayerState.LOADING) {
      return;
    }
    if (this.playerStore.state === PlayerState.IDLE || this.playerStore.state === PlayerState.ERROR) {
      this.reloadCurrentTrackForPlayback();
      return;
    }
    this.restartCoverageAfterInterruption();
    this.coverageTracker.recordResume(this.playerStore.progress.positionMs);
    this.engine.play().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  pause(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    this.clearAutomaticResumeIntents();
    if (DemoLibraryMode.isEnabled()) {
      this.stopDemoProgress();
      this.playerStore.playWhenReady = false;
      this.playerStore.state = PlayerState.PAUSED;
      this.playerStore.transportState = this.stateReducer.reduce(PlayerState.PAUSED, false);
      this.syncSessionState();
      return;
    }
    this.updatePlaybackIntent(false);
    this.coverageTracker.recordPause(this.playerStore.progress.positionMs);
    if (this.playerStore.state === PlayerState.LOADING || this.playerStore.state === PlayerState.READY) {
      return;
    }
    this.engine.pause().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  stop(): void {
    this.clearAutomaticResumeIntents();
    this.pause();
    this.interruptCoverage();
    this.persistProgress(false);
  }

  next(): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
    const next = this.queue.next(this.playerStore.repeatMode, false);
    if (next !== undefined) {
      this.clearAutomaticResumeIntents();
      this.beginTrack(next);
    }
    this.syncQueueCursor();
  }

  previous(): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
    const previous = this.queue.previous();
    if (previous !== undefined) {
      this.clearAutomaticResumeIntents();
      this.beginTrack(previous);
    }
    this.syncQueueCursor();
  }

  playQueueTrack(trackId: number): void {
    if (this.playerStore.queuePhase !== QueueBuildPhase.READY ||
      this.playerStore.currentTrack?.id === trackId) {
      return;
    }
    const selected = this.queue.select(trackId);
    if (selected !== undefined) {
      this.clearAutomaticResumeIntents();
      this.beginTrack(selected);
    }
    this.syncQueueCursor();
  }

  seek(positionMs: number): void {
    const targetPositionMs = Math.max(0, Math.min(positionMs, this.playerStore.progress.durationMs));
    if (DemoLibraryMode.isEnabled()) {
      this.playerStore.progress.positionMs = targetPositionMs;
      this.updateActiveLyricIndex(targetPositionMs);
      return;
    }
    const seekEpoch = ++this.seekEpoch;
    this.pendingSeekPositionMs = targetPositionMs;
    this.coverageTracker.seekTo(targetPositionMs);
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
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    this.clearAutomaticResumeIntents();
    this.interruptCoverage();
    this.persistProgress(false);
    this.media.invalidate();
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    await this.engine.invalidateAndStop();
    this.media.clearArtwork();
    this.queue.clear();
    this.currentPlaybackTrack = undefined;
    this.playerStore.currentTrack = undefined;
    this.playerStore.setMiniArtwork(undefined, '');
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.heroArtworkRevision += 1;
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = 0;
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.playerStore.playWhenReady = false;
    this.playerStore.transportState = this.stateReducer.reset();
    this.notifyPaletteChange();
    this.persistence.clearResumeAndQueue();
    this.syncQueueSnapshot();
    this.onStateChanged(PlayerState.IDLE);
  }

  async prepareForTrackRemoval(trackIds: Array<number>): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    if (trackIds.length === 0) {
      return;
    }
    const selected = new Set<number>(trackIds);
    ++this.queueBuildEpoch;
    const entryIds = this.queue.snapshot().entries
      .filter((entry: QueueEntry): boolean => selected.has(entry.track.id))
      .map((entry: QueueEntry): number => entry.queueEntryId);
    if (entryIds.length > 0) {
      this.removeQueueEntries(entryIds);
      return;
    }
    if (this.playerStore.currentTrack !== undefined &&
      selected.has(this.playerStore.currentTrack.id)) {
      this.queue.clear();
      this.playerStore.queueSize = 0;
      this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
      this.syncQueueSnapshot();
      this.clearRemovedQueuePlayback();
    }
  }

  async shutdown(): Promise<void> {
    this.clearAutomaticResumeIntents();
    this.stopDemoProgress();
    this.interruptCoverage();
    this.persistProgress(false);
    await this.persistence.flush();
    this.media.invalidate();
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    await this.pictureInPicture.dispose();
    await this.engine.shutdown();
    await this.session?.shutdown();
    this.playerStore.setMiniArtwork(undefined, '');
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.heroArtworkRevision += 1;
    this.playerStore.currentTrack = undefined;
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = 0;
    this.playerStore.playWhenReady = false;
    this.playerStore.state = PlayerState.IDLE;
    this.playerStore.transportState = this.stateReducer.reset();
    this.playerStore.errorMessage = '';
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.queue.clear();
    this.syncQueueSnapshot(false);
    this.currentPlaybackTrack = undefined;
    this.lastPositionWriteAt = 0;
    this.coverageNeedsRestart = false;
    this.media.reset();
    this.context = undefined;
    this.settings = undefined;
    await this.persistence.reset();
    this.session = undefined;
    this.initializePromise = undefined;
  }

  onStateChanged(state: PlayerState, message?: string): void {
    const previousState = this.playerStore.state;
    const previousTransportState = this.playerStore.transportState;
    if (state === PlayerState.ERROR) {
      this.playerStore.playWhenReady = false;
      this.interruptCoverage();
    }
    this.playerStore.state = state;
    this.playerStore.transportState = this.stateReducer.reduce(
      state,
      this.playerStore.playWhenReady
    );
    if (message === undefined &&
      state === previousState &&
      this.playerStore.transportState === previousTransportState) {
      return;
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
      this.coverageTracker.advanceTo(positionMs);
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
    const completion = this.coverageTracker.finishNaturally(this.playerStore.progress.durationMs);
    this.coverageNeedsRestart = true;
    if (completion.qualifies && completion.trackId >= 0) {
      this.repository.recordCompletedPlayback(
        completion.trackId,
        Date.now(),
        this.playerStore.completedCollectionEnabled
      ).catch((error: Object) => {
        console.warn(`Unable to record completed playback: ${PlaybackRuntime.messageOf(error)}`);
      });
    }
    const next = this.queue.next(this.playerStore.repeatMode, true);
    if (next !== undefined) {
      this.beginTrack(next, this.playerStore.playWhenReady);
    } else {
      this.playerStore.playWhenReady = false;
      this.playerStore.transportState = this.stateReducer.settleCompletion();
      this.syncSessionState();
    }
    this.syncQueueCursor();
  }

  queueArtworkUri(relativePath: string): string {
    return this.media.resolveArtworkUri(relativePath);
  }

  setCompletedCollectionEnabled(enabled: boolean): void {
    if (this.playerStore.completedCollectionEnabled === enabled) {
      return;
    }
    this.playerStore.completedCollectionEnabled = enabled;
    this.settings?.setCompletedCollectionCurrentEnabled(enabled);
  }

  setCompletedCollectionMode(mode: CompletedCollectionMode): void {
    appSettings.setCompletedCollectionMode(mode);
    this.playerStore.completedCollectionMode = appSettings.completedCollectionMode;
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

  private isTrackRequestCurrent(token: number): boolean {
    return this.media.isCurrent(token);
  }

  private commitHeroArtwork(pixelMap: image.PixelMap): void {
    this.playerStore.heroArtwork = pixelMap;
    this.playerStore.heroArtworkPreferPixelMap = true;
    this.playerStore.heroArtworkRevision += 1;
  }

  private commitFullArtwork(artwork: DecodedFullArtwork): void {
    this.playerStore.heroArtwork = artwork.pixelMap;
    this.playerStore.heroArtworkPreferPixelMap = true;
    this.playerStore.heroArtworkRevision += 1;
  }

  private commitLyrics(track: PlaybackTrack, lyrics: string): void {
    this.playerStore.lyrics = lyrics;
    this.playerStore.setTimedLyrics(LyricsParser.parse(lyrics).lines);
    this.updateActiveLyricIndex(this.playerStore.progress.positionMs);
    this.session?.updateMetadata(track, this.sessionArtworkUri(track), lyrics);
  }

  private clearLyricsAfterFailure(): void {
    this.playerStore.lyrics = '';
    this.playerStore.setTimedLyrics([]);
    this.playerStore.setActiveLyricIndex(-1);
  }

  private commitRefreshedPalette(track: QueueTrack): void {
    this.applyCurrentTrackPalette(track);
  }

  async refreshCurrentTrackPalette(): Promise<void> {
    const current = this.playerStore.currentTrack;
    if (current === undefined) {
      return;
    }
    const token = this.media.currentRequest();
    const refreshed = await this.repository.getPlaybackTrack(current.id);
    if (refreshed === undefined || !this.isTrackRequestCurrent(token) ||
      this.playerStore.currentTrack?.id !== current.id) {
      return;
    }
    this.applyCurrentTrackPalette(refreshed);
  }

  async setDemoLibraryEnabled(enabled: boolean): Promise<void> {
    if (!DemoLibraryMode.isAvailable() || DemoLibraryMode.isEnabled() === enabled) {
      return;
    }
    this.clearAutomaticResumeIntents();
    ++this.queueBuildEpoch;
    if (enabled) {
      this.persistProgress(false);
      this.media.invalidate();
      await this.engine.invalidateAndStop();
      DemoLibraryMode.setEnabled(true);
      this.activateDemoPlayback();
      return;
    }
    this.stopDemoProgress();
    this.media.invalidate();
    await this.engine.invalidateAndStop();
    DemoLibraryMode.setEnabled(false);
    this.resetPlaybackPresentation();
    await this.restoreLastPlayback();
  }

  private async initializeInternal(context: common.UIAbilityContext,
    providedSettings?: SettingsRepository): Promise<void> {
    this.pictureInPicture.reopen();
    this.context = context;
    this.settings = providedSettings === undefined ? new SettingsRepository(context) : providedSettings;
    this.persistence.bind(this.persistencePort, this.persistencePort);
    appSettings.initialize(this.settings);
    await this.repository.initialize(context);
    const repeatMode = this.settings.getPlaybackRepeatMode(RepeatMode.ALL);
    this.playerStore.repeatMode = repeatMode >= RepeatMode.OFF && repeatMode <= RepeatMode.ONE ?
      repeatMode as RepeatMode : RepeatMode.ALL;
    this.playerStore.shuffleEnabled = this.settings.getPlaybackShuffleEnabled(false);
    this.playerStore.completedCollectionMode = appSettings.completedCollectionMode;
    this.playerStore.completedCollectionEnabled =
      this.settings.getCompletedCollectionCurrentEnabled(true);
    this.media.initialize(context);
    this.session = new PlaybackSession(context, this);
    await this.session.initialize();
    if (DemoLibraryMode.isEnabled()) {
      this.activateDemoPlayback();
    } else {
      await this.restoreLastPlayback();
    }
  }

  private async restoreLastPlayback(): Promise<void> {
    const buildEpoch = ++this.queueBuildEpoch;
    const plan = await this.persistence.createRestorePlan(
      buildEpoch,
      (epoch: number): boolean => epoch === this.queueBuildEpoch
    );
    if (plan === undefined || buildEpoch !== this.queueBuildEpoch) {
      return;
    }
    this.queue.clear();
    this.playerStore.queuePhase = QueueBuildPhase.BUILDING;
    this.playerStore.queueSize = 0;
    this.playerStore.queueDataSource.replace([]);
    this.playerStore.setQueueCurrentIndex(-1);
    await this.beginTrack(plan.currentTrack, false, true, plan.resumePositionMs);
    if (buildEpoch !== this.queueBuildEpoch) {
      return;
    }
    this.commitRestoredQueue(plan);
  }

  private commitRestoredQueue(plan: PlaybackRestorePlan): void {
    const phase = this.queue.restore(
      plan.queueTracks,
      plan.currentPosition
    );
    this.playerStore.queuePhase = phase;
    this.playerStore.queueSize = this.queue.size();
    if (phase === QueueBuildPhase.READY) {
      this.syncQueueSnapshot();
      this.prefetchCurrentWindow();
    }
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
    this.enqueueQueueItems(queueItems, insertNext);
  }

  private enqueueQueueItems(queueItems: Array<QueueTrack>, insertNext: boolean): void {
    if (queueItems.length === 0 || this.playerStore.queuePhase !== QueueBuildPhase.READY) {
      return;
    }
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
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    this.audioRecovery.clear();
    try {
      await this.session?.shutdown();
    } catch (error) {
      console.warn(`Unable to clean up failed playback initialization: ${PlaybackRuntime.messageOf(error)}`);
    }
    try {
      await this.pictureInPicture.dispose();
    } catch (error) {
      console.warn(`Unable to dispose PiP after playback initialization failure: ${PlaybackRuntime.messageOf(error)}`);
    }
    this.media.reset();
    this.context = undefined;
    this.settings = undefined;
    await this.persistence.reset();
    this.session = undefined;
  }

  private beginTrack(track: QueueTrack, playWhenReady: boolean = true,
    preserveStoredPosition: boolean = false, restoredPositionMs?: number): Promise<void> {
    this.clearAutomaticResumeIntents();
    if (DemoLibraryMode.isEnabled()) {
      this.beginDemoTrack(track, playWhenReady);
      return Promise.resolve();
    }
    this.interruptCoverage();
    this.persistProgress(false);
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    this.engine.invalidateAndStop().catch((error: Object) => {
      if (PlaybackRuntime.messageOf(error) !== 'Playback request superseded') {
        console.warn(`Unable to stop previous playback: ${PlaybackRuntime.messageOf(error)}`);
      }
    });
    const previousTrack = this.playerStore.currentTrack;
    const sameLargeArtwork = PlaybackMediaCoordinator.sameArtwork(previousTrack, track, true);
    const sameSmallArtwork = PlaybackMediaCoordinator.sameArtwork(previousTrack, track, false);
    const epoch = this.media.beginRequest();
    this.artworkPrefetchReadyEpoch = -1;
    if (!sameLargeArtwork) {
      this.media.retireFullArtwork();
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
    this.playerStore.transportState = this.stateReducer.beginSourceChange(playWhenReady);
    this.syncSessionState();
    this.playerStore.errorMessage = '';
    this.media.pinCurrent(track);
    if (!sameSmallArtwork || this.playerStore.miniArtworkUri.length === 0) {
      this.playerStore.setMiniArtwork(
        undefined,
        this.media.resolveArtworkUri(track.smallArtworkPath)
      );
    }
    if (!sameLargeArtwork) {
      this.playerStore.heroArtwork = this.media.cachedLarge(track);
      this.playerStore.heroArtworkUri = this.media.resolveArtworkUri(track.largeArtworkPath);
      this.playerStore.heroArtworkPreferPixelMap = this.playerStore.heroArtwork !== undefined;
      this.playerStore.heroArtworkRevision += 1;
      this.media.loadHeroArtwork(track, epoch, this.mediaHost);
    }
    const playbackStarted = this.loadAndPlayTrack(track.id, epoch, restoredPositionMs);
    return playbackStarted;
  }

  private reloadCurrentTrackForPlayback(): void {
    const track = this.playerStore.currentTrack;
    if (track === undefined) {
      return;
    }
    this.beginTrack(track, true, true).catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
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

  private async loadAndPlayTrack(trackId: number, epoch: number,
    restoredPositionMs?: number): Promise<void> {
    try {
      const track = await this.repository.getPlaybackTrack(trackId);
      if (!this.isTrackRequestCurrent(epoch)) {
        return;
      }
      if (track === undefined) {
        throw new Error('音乐记录不存在，可能已从音乐库移除');
      }
      this.currentPlaybackTrack = track;
      this.applyCurrentTrackPalette(track);
      this.media.refreshPalette(this.repository, trackId, epoch, this.mediaHost);
      this.playerStore.progress.durationMs = track.durationMs;
      this.session?.updateMetadata(track, this.sessionArtworkUri(track));
      if (!await ensureReadPermission(track.uri)) {
        await this.markUnavailableAndMaybeRemove(
          trackId,
          AvailabilityState.AUTHORIZATION_REVOKED,
          epoch
        );
        throw new Error('音乐文件授权已失效，请重新导入该文件');
      }
      if (!this.isTrackRequestCurrent(epoch)) {
        return;
      }
      if (track.availability !== AvailabilityState.AVAILABLE) {
        track.availability = AvailabilityState.AVAILABLE;
        this.repository.setTrackAvailability(trackId, AvailabilityState.AVAILABLE).catch((error: Object) => {
          console.warn(`Unable to restore track availability: ${PlaybackRuntime.messageOf(error)}`);
        });
      }
      this.media.loadLyrics(track, epoch, this.mediaHost);
      const resumePosition = restoredPositionMs === undefined ?
        this.persistence.resumePositionFor(trackId, track.durationMs) : restoredPositionMs;
      this.coverageTracker.begin(track.id, track.durationMs, resumePosition);
      this.coverageNeedsRestart = false;
      await this.engine.playTrack(track, resumePosition, () => this.playerStore.playWhenReady);
      if (!this.isTrackRequestCurrent(epoch)) {
        return;
      }
      const fullArtworkWork = this.media.hasFullArtwork() ? Promise.resolve() :
        this.media.loadFullArtwork(track, epoch, this.mediaHost);
      fullArtworkWork.finally((): void => {
        if (this.isTrackRequestCurrent(epoch)) {
          this.artworkPrefetchReadyEpoch = epoch;
          this.prefetchCurrentWindow();
        }
      });
    } catch (error) {
      if (!this.isTrackRequestCurrent(epoch)) {
        return;
      }
      const message = PlaybackRuntime.messageOf(error);
      if (error instanceof PlaybackFileError) {
        await this.markUnavailableAndMaybeRemove(trackId, error.availability, epoch);
        if (!this.isTrackRequestCurrent(epoch)) {
          return;
        }
      }
      console.warn(`Unable to start playback for track ${trackId}: ${message}`);
      this.onStateChanged(PlayerState.ERROR, message);
    }
  }

  private applyCurrentTrackPalette(refreshed: QueueTrack): void {
    const current = this.playerStore.currentTrack;
    if (current === undefined || current.id !== refreshed.id) {
      return;
    }
    const currentChanged = current.palettePrimary !== refreshed.palettePrimary ||
      current.paletteSecondary !== refreshed.paletteSecondary ||
      current.paletteAccent !== refreshed.paletteAccent;
    const updatedQueueIndices = this.queue.updateArtworkPalette(
      refreshed,
      refreshed.palettePrimary,
      refreshed.paletteSecondary,
      refreshed.paletteAccent
    );
    current.palettePrimary = refreshed.palettePrimary;
    current.paletteSecondary = refreshed.paletteSecondary;
    current.paletteAccent = refreshed.paletteAccent;
    this.playerStore.palettePrimary = refreshed.palettePrimary;
    this.playerStore.paletteSecondary = refreshed.paletteSecondary;
    this.playerStore.paletteAccent = refreshed.paletteAccent;
    if (updatedQueueIndices.length > 0 && this.playerStore.queuePhase === QueueBuildPhase.READY) {
      this.playerStore.queueDataSource.notifyChanged(updatedQueueIndices);
    }
    if (currentChanged || updatedQueueIndices.length > 0) {
      this.notifyPaletteChange();
    }
  }

  private async markUnavailableAndMaybeRemove(trackId: number,
    state: AvailabilityState, token: number): Promise<void> {
    if (!this.isTrackRequestCurrent(token)) {
      return;
    }
    await this.repository.setTrackAvailability(trackId, state);
    if (!this.isTrackRequestCurrent(token) || !appSettings.autoRemoveUnavailableOnPlayback) {
      return;
    }
    await this.prepareForTrackRemoval([trackId]);
    await this.libraryRemoval.removeTracks([trackId]);
  }

  onOutputDeviceUnavailable(): void {
    const action = this.audioRecovery.outputUnavailable(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.playWhenReady,
      this.playerStore.state,
      appSettings.autoResumeAfterOutputReconnect
    );
    if (action !== AudioRecoveryAction.PAUSE) {
      return;
    }
    this.pauseForAutomaticRecovery(true);
  }

  onOutputDeviceAvailable(): void {
    const action = this.audioRecovery.outputAvailable(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.state,
      appSettings.autoResumeAfterOutputReconnect
    );
    if (action === AudioRecoveryAction.RESUME) {
      this.play();
    }
  }

  onAudioSessionPauseHint(): void {
    const action = this.audioRecovery.audioPauseHint(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.playWhenReady
    );
    if (action !== AudioRecoveryAction.PAUSE) {
      return;
    }
    this.pauseForAutomaticRecovery(true);
  }

  onAudioSessionResumeHint(): void {
    const action = this.audioRecovery.audioResumeHint(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.state
    );
    if (action === AudioRecoveryAction.RESUME) {
      this.play();
    }
  }

  onAudioSessionStopHint(): void {
    const action = this.audioRecovery.audioStopHint(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.state
    );
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    this.updatePlaybackIntent(false);
    this.coverageTracker.recordPause(this.playerStore.progress.positionMs);
    if (action !== AudioRecoveryAction.PAUSE) {
      this.onStateChanged(PlayerState.PAUSED);
      return;
    }
    this.engine.pause().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  private clearAutomaticResumeIntents(): void {
    this.audioRecovery.clear();
  }

  private pauseForAutomaticRecovery(clearOnFailure: boolean): void {
    this.updatePlaybackIntent(false);
    this.coverageTracker.recordPause(this.playerStore.progress.positionMs);
    if (this.playerStore.state !== PlayerState.PLAYING) {
      return;
    }
    this.engine.pause().catch((error: Object) => {
      if (clearOnFailure) {
        this.clearAutomaticResumeIntents();
      }
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  private sessionArtworkUri(track: PlaybackTrack): string {
    return this.media.resolveArtworkUri(track.largeArtworkPath);
  }

  private prefetchCurrentWindow(): void {
    if (this.playerStore.currentTrack === undefined ||
      this.playerStore.queuePhase !== QueueBuildPhase.READY ||
      this.artworkPrefetchReadyEpoch !== this.media.currentRequest()) {
      return;
    }
    const radius = Math.max(0, Math.min(8, this.settings?.getPlaybackArtworkWindowRadius(2) ?? 2));
    const window = this.queue.playbackWindow(radius, this.playerStore.repeatMode);
    this.media.schedulePrefetchWindow(window.items, window.currentIndex, radius);
  }

  private syncQueueCursor(persist: boolean = true): void {
    const current = this.queue.current();
    this.playerStore.setQueueCurrentIndex(this.queue.currentIndex());
    if (persist && !DemoLibraryMode.isEnabled()) {
      this.persistence.persistQueueCurrentPosition(current === undefined ? -1 : this.queue.currentIndex());
    }
    this.syncPictureInPicture();
  }

  private syncQueueSnapshot(persist: boolean = true): void {
    const snapshot = this.queue.snapshot();
    this.playerStore.queueDataSource.replace(snapshot.entries);
    this.playerStore.setQueueCurrentIndex(snapshot.currentIndex);
    if (persist && !DemoLibraryMode.isEnabled()) {
      this.persistence.persistQueue(
        snapshot.entries.map((entry: QueueEntry) => entry.track.id),
        snapshot.currentIndex
      );
    }
    this.syncPictureInPicture();
  }

  private persistProgress(completed: boolean): void {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    this.persistence.persistProgress(
      this.currentPlaybackTrack,
      this.playerStore.progress.positionMs,
      this.playerStore.progress.durationMs,
      completed
    );
  }

  private persistResumeState(trackId: number, positionMs: number): void {
    this.persistence.persistResumeState(trackId, positionMs);
  }

  private syncSessionState(): void {
    this.session?.updatePlaybackState(
      this.playerStore.transportState,
      this.playerStore.progress.positionMs,
      this.playerStore.repeatMode,
      this.playerStore.shuffleEnabled
    );
    this.syncPictureInPicture();
  }

  private pictureInPictureSnapshot(): PlaybackPictureInPictureSnapshot {
    const track = this.playerStore.currentTrack;
    return new PlaybackPictureInPictureSnapshot(
      track?.id ?? -1,
      track === undefined ? '' : this.media.resolveArtworkUri(track.largeArtworkPath),
      track?.artworkWidth ?? 0,
      track?.artworkHeight ?? 0,
      track !== undefined,
      this.playerStore.showsPauseControl(),
      PlaybackPictureInPicturePolicy.transportControlsEnabled(
        this.playerStore.queuePhase === QueueBuildPhase.READY,
        this.playerStore.queueSize
      )
    );
  }

  private syncPictureInPicture(): void {
    this.pictureInPicture.sync(this.pictureInPictureSnapshot());
  }

  private updatePlaybackIntent(playWhenReady: boolean): void {
    const previousIntent = this.playerStore.playWhenReady;
    const previousTransportState = this.playerStore.transportState;
    this.playerStore.playWhenReady = playWhenReady;
    this.playerStore.transportState = this.stateReducer.updateIntent(playWhenReady);
    if (previousIntent !== playWhenReady ||
      previousTransportState !== this.playerStore.transportState) {
      this.syncSessionState();
    }
  }

  private setShuffleEnabled(enabled: boolean): void {
    this.playerStore.shuffleEnabled = enabled;
    this.settings?.setPlaybackShuffleEnabled(enabled);
    this.syncSessionState();
  }

  private applyCompletedCollectionDefault(origin: PlaybackOriginKind): void {
    const mode = appSettings.completedCollectionMode;
    this.playerStore.completedCollectionMode = mode;
    if (mode === CompletedCollectionMode.DEFAULT_ON) {
      this.setCompletedCollectionEnabled(true);
      return;
    }
    if (mode === CompletedCollectionMode.DEFAULT_OFF) {
      this.setCompletedCollectionEnabled(false);
      return;
    }
    this.setCompletedCollectionEnabled(origin !== PlaybackOriginKind.COMPLETED_PLAYLIST);
  }

  private interruptCoverage(): void {
    this.coverageTracker.finishInterrupted(this.playerStore.progress.positionMs);
    this.coverageNeedsRestart = true;
  }

  private restartCoverageAfterInterruption(): void {
    const track = this.currentPlaybackTrack;
    if (!this.coverageNeedsRestart || track === undefined) {
      return;
    }
    const initialPosition = this.playerStore.state === PlayerState.COMPLETED ?
      0 : this.playerStore.progress.positionMs;
    if (initialPosition === 0 && this.playerStore.state === PlayerState.COMPLETED) {
      this.playerStore.progress.positionMs = 0;
      this.updateActiveLyricIndex(0);
    }
    const duration = this.playerStore.progress.durationMs > 0 ?
      this.playerStore.progress.durationMs : track.durationMs;
    this.coverageTracker.begin(track.id, duration, initialPosition);
    this.coverageNeedsRestart = false;
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

  private activateDemoPlayback(): void {
    const tracks = DemoMusicLibrary.tracks(TrackSortField.TITLE, SortDirection.ASCENDING);
    if (tracks.length === 0) {
      this.resetPlaybackPresentation();
      return;
    }
    const queueTracks = tracks.map((track: TrackListItem): QueueTrack => PlaybackRuntime.queueTrackOf(track));
    const selected = DemoMusicLibrary.defaultTrack();
    const selectedTrack = PlaybackRuntime.queueTrackOf(selected);
    ++this.queueBuildEpoch;
    this.queue.clear();
    const phase = this.queue.build(queueTracks, selected.id, false);
    this.playerStore.queuePhase = phase;
    this.playerStore.queueSize = this.queue.size();
    this.syncQueueSnapshot(false);
    this.beginDemoTrack(selectedTrack, false, 42000);
  }

  private beginDemoTrack(track: QueueTrack, playWhenReady: boolean,
    initialPositionMs: number = 0): void {
    this.stopDemoProgress();
    this.media.invalidate();
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    this.currentPlaybackTrack = DemoMusicLibrary.playbackTrack(track.id);
    this.playerStore.currentTrack = track;
    const lyrics = DemoMusicLibrary.lyrics(track.id);
    this.playerStore.lyrics = lyrics;
    this.playerStore.setTimedLyrics(LyricsParser.parse(lyrics).lines);
    this.playerStore.progress.positionMs = Math.max(0, Math.min(initialPositionMs, track.durationMs));
    this.playerStore.progress.durationMs = track.durationMs;
    this.playerStore.palettePrimary = track.palettePrimary;
    this.playerStore.paletteSecondary = track.paletteSecondary;
    this.playerStore.paletteAccent = track.paletteAccent;
    this.playerStore.setMiniArtwork(undefined, track.smallArtworkPath);
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = BundledArtworkCatalog.fullPath(track.largeArtworkPath);
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.heroArtworkRevision += 1;
    this.playerStore.playWhenReady = playWhenReady;
    this.playerStore.state = playWhenReady ? PlayerState.PLAYING : PlayerState.PAUSED;
    this.playerStore.transportState = this.stateReducer.reduce(this.playerStore.state, playWhenReady);
    this.playerStore.errorMessage = '';
    this.updateActiveLyricIndex(this.playerStore.progress.positionMs);
    this.notifyPaletteChange();
    if (playWhenReady) {
      this.startDemoProgress();
    }
    this.syncSessionState();
  }

  private startDemoProgress(): void {
    this.stopDemoProgress();
    this.demoProgressTimer = setInterval((): void => {
      if (!DemoLibraryMode.isEnabled() || !this.playerStore.playWhenReady ||
        this.playerStore.currentTrack === undefined) {
        return;
      }
      const nextPosition = this.playerStore.progress.positionMs + 1000;
      if (nextPosition < this.playerStore.progress.durationMs) {
        this.playerStore.progress.positionMs = nextPosition;
        this.updateActiveLyricIndex(nextPosition);
        return;
      }
      const next = this.queue.next(this.playerStore.repeatMode, true);
      if (next !== undefined) {
        this.beginDemoTrack(next, true);
      } else {
        this.stopDemoProgress();
        this.playerStore.progress.positionMs = this.playerStore.progress.durationMs;
        this.playerStore.playWhenReady = false;
        this.playerStore.state = PlayerState.COMPLETED;
        this.playerStore.transportState = this.stateReducer.settleCompletion();
        this.syncSessionState();
      }
      this.syncQueueCursor(false);
    }, 1000);
  }

  private stopDemoProgress(): void {
    if (this.demoProgressTimer >= 0) {
      clearInterval(this.demoProgressTimer);
      this.demoProgressTimer = -1;
    }
  }

  private resetPlaybackPresentation(): void {
    this.media.invalidate();
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
    this.queue.clear();
    this.currentPlaybackTrack = undefined;
    this.playerStore.currentTrack = undefined;
    this.playerStore.setMiniArtwork(undefined, '');
    this.playerStore.heroArtwork = undefined;
    this.playerStore.heroArtworkUri = '';
    this.playerStore.heroArtworkPreferPixelMap = false;
    this.playerStore.heroArtworkRevision += 1;
    this.playerStore.lyrics = '';
    this.playerStore.setTimedLyrics([]);
    this.playerStore.setActiveLyricIndex(-1);
    this.playerStore.progress.positionMs = 0;
    this.playerStore.progress.durationMs = 0;
    this.playerStore.queuePhase = QueueBuildPhase.EMPTY;
    this.playerStore.queueSize = 0;
    this.playerStore.queueDataSource.replace([]);
    this.playerStore.setQueueCurrentIndex(-1);
    this.playerStore.playWhenReady = false;
    this.playerStore.state = PlayerState.IDLE;
    this.playerStore.transportState = this.stateReducer.reset();
    this.playerStore.errorMessage = '';
    this.notifyPaletteChange();
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}

export const playbackRuntime: PlaybackRuntime = new PlaybackRuntime();
