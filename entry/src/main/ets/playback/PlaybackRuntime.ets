import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ArtworkCache } from '../library/artwork/ArtworkCache';
import { MusicRepository } from '../library/data/MusicRepository';
import { ensureReadPermission } from '../library/importer/MediaPickerService';
import { MetadataReader } from '../library/metadata/MetadataReader';
import {
  AvailabilityState,
  SortDirection,
  TrackListItem,
  TrackSortField
} from '../library/model/LibraryModels';
import { SettingsRepository } from '../settings/SettingsRepository';
import { appSettings } from '../settings/AppSettingsStore';
import { ArtworkMemoryCache, DecodedFullArtwork } from './artwork/ArtworkMemoryCache';
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
import { OutputReconnectPolicy } from './support/OutputReconnectPolicy';
import { DemoLibraryMode } from '../demo/DemoLibraryMode';
import { DemoMusicLibrary } from '../demo/DemoMusicLibrary';

const RESUME_MINIMUM_MS = 5000;
const COMPLETION_REMAINING_MS = 10000;
const COMPLETION_POSITION_FRACTION = 0.95;
const QUEUE_BUILD_CHUNK_SIZE = 64;
const OUTPUT_RECONNECT_RESUME_WINDOW_MS = 5 * 60 * 1000;

class PlaybackRuntime implements PlaybackEngineListener, PlaybackSessionCommands, LibraryPlaybackBridge {
  readonly repository: MusicRepository = new MusicRepository();
  readonly playerStore: PlayerStore = new PlayerStore();

  private readonly engine: PlaybackEngine = new PlaybackEngine();
  private readonly queue: PlaybackQueue = new PlaybackQueue();
  private readonly coverageTracker: PlaybackCoverageTracker = new PlaybackCoverageTracker();
  private readonly stateReducer: PlaybackStateReducer = new PlaybackStateReducer();
  private readonly outputReconnectPolicy: OutputReconnectPolicy = new OutputReconnectPolicy();
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
  private coverageNeedsRestart: boolean = false;
  private fullArtwork?: DecodedFullArtwork;
  private paletteChangeListener?: (primary: string, secondary: string, accent: string) => void;
  private demoProgressTimer: number = -1;
  private resumeAfterAudioFocusRelease: boolean = false;

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
    ++this.artworkEpoch;
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

  play(): void {
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    if (DemoLibraryMode.isEnabled()) {
      this.playerStore.playWhenReady = true;
      this.playerStore.state = PlayerState.PLAYING;
      this.playerStore.transportState = this.stateReducer.reduce(PlayerState.PLAYING, true);
      this.startDemoProgress();
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
    this.syncQueueSnapshot();
    if (next !== undefined) {
      this.clearAutomaticResumeIntents();
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
      this.clearAutomaticResumeIntents();
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
      this.clearAutomaticResumeIntents();
      this.beginTrack(selected);
    }
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
    this.persistResumeState(-1, 0);
    this.settings?.setPlaybackQueue([], -1);
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
    ++this.artworkEpoch;
    ++this.queueBuildEpoch;
    ++this.seekEpoch;
    this.pendingSeekPositionMs = undefined;
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
    this.lastPersistedTrackId = -2;
    this.lastPersistedPositionMs = -1;
    this.coverageNeedsRestart = false;
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
    this.syncQueueSnapshot();
    if (next !== undefined) {
      this.beginTrack(next, this.playerStore.playWhenReady);
    } else {
      this.playerStore.playWhenReady = false;
      this.playerStore.transportState = this.stateReducer.settleCompletion();
      this.syncSessionState();
    }
  }

  queueArtworkUri(relativePath: string): string {
    return this.resolveArtworkUri(relativePath);
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

  async setDemoLibraryEnabled(enabled: boolean): Promise<void> {
    if (!DemoLibraryMode.isAvailable() || DemoLibraryMode.isEnabled() === enabled) {
      return;
    }
    if (enabled) {
      this.persistProgress(false);
      await this.engine.invalidateAndStop();
      DemoLibraryMode.setEnabled(true);
      this.activateDemoPlayback();
      return;
    }
    this.stopDemoProgress();
    await this.engine.invalidateAndStop();
    DemoLibraryMode.setEnabled(false);
    this.resetPlaybackPresentation();
    await this.restoreLastPlayback();
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
    this.playerStore.completedCollectionMode = appSettings.completedCollectionMode;
    this.playerStore.completedCollectionEnabled =
      this.settings.getCompletedCollectionCurrentEnabled(true);
    this.artworkCache = new ArtworkMemoryCache(context);
    this.session = new PlaybackSession(context, this);
    await this.session.initialize();
    if (DemoLibraryMode.isEnabled()) {
      this.activateDemoPlayback();
    } else {
      await this.restoreLastPlayback();
    }
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
    const ids = storedIds.length > 0 ? storedIds.slice() : [trackId];
    if (ids.indexOf(trackId) < 0) {
      ids.unshift(trackId);
    }
    const currentTracks = await this.repository.getPlaybackQueueTracks([trackId]);
    if (currentTracks.length === 0) {
      this.persistResumeState(-1, 0);
      this.settings?.setPlaybackQueue([], -1);
      return;
    }
    const currentTrack = currentTracks[0];
    const buildEpoch = ++this.queueBuildEpoch;
    this.queue.clear();
    this.playerStore.queuePhase = QueueBuildPhase.BUILDING;
    this.playerStore.queueSize = 0;
    this.playerStore.queueDataSource.replace([]);
    this.playerStore.setQueueCurrentIndex(-1);
    await this.beginTrack(currentTrack, false, true);
    this.schedulePlaybackQueueRestore(ids, currentTrack, buildEpoch);
  }

  private schedulePlaybackQueueRestore(ids: Array<number>, currentTrack: QueueTrack, buildEpoch: number): void {
    setTimeout(() => {
      if (buildEpoch !== this.queueBuildEpoch) {
        return;
      }
      this.restorePlaybackQueue(ids, currentTrack, buildEpoch).catch((error: Object) => {
        if (buildEpoch !== this.queueBuildEpoch) {
          return;
        }
        this.playerStore.queuePhase = QueueBuildPhase.FAILED;
        console.warn(`Unable to restore playback queue: ${PlaybackRuntime.messageOf(error)}`);
      });
    }, 0);
  }

  private async restorePlaybackQueue(ids: Array<number>, currentTrack: QueueTrack,
    buildEpoch: number): Promise<void> {
    const remainingIds = ids.filter((id: number) => id !== currentTrack.id);
    const restoredTracks = await this.repository.getPlaybackQueueTracks(remainingIds);
    if (buildEpoch !== this.queueBuildEpoch) {
      return;
    }
    const tracksById: Map<number, QueueTrack> = new Map<number, QueueTrack>();
    restoredTracks.forEach((track: QueueTrack) => {
      tracksById.set(track.id, track);
    });
    tracksById.set(currentTrack.id, currentTrack);
    const queueTracks: Array<QueueTrack> = [];
    ids.forEach((id: number) => {
      const track = tracksById.get(id);
      if (track !== undefined) {
        queueTracks.push(track);
      }
    });
    const phase = this.queue.build(queueTracks, currentTrack.id, this.playerStore.shuffleEnabled);
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
    this.playerStore.transportState = this.stateReducer.beginSourceChange(playWhenReady);
    this.syncSessionState();
    this.playerStore.errorMessage = '';
    this.artworkCache?.pinCurrent(track);
    if (!sameSmallArtwork || this.playerStore.miniArtworkUri.length === 0) {
      this.playerStore.setMiniArtwork(
        undefined,
        this.resolveArtworkUri(track.smallArtworkPath)
      );
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
      this.session?.updateMetadata(track, this.sessionArtworkUri(track));
      if (!await ensureReadPermission(track.uri)) {
        await this.markUnavailableAndMaybeRemove(
          trackId,
          AvailabilityState.AUTHORIZATION_REVOKED
        );
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
      this.coverageTracker.begin(track.id, track.durationMs, resumePosition);
      this.coverageNeedsRestart = false;
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
      if (error instanceof PlaybackFileError) {
        await this.markUnavailableAndMaybeRemove(trackId, error.availability);
        if (epoch !== this.artworkEpoch) {
          return;
        }
      }
      console.warn(`Unable to start playback for track ${trackId}: ${message}`);
      this.onStateChanged(PlayerState.ERROR, message);
    }
  }

  private async markUnavailableAndMaybeRemove(trackId: number,
    state: AvailabilityState): Promise<void> {
    await this.repository.setTrackAvailability(trackId, state);
    if (!appSettings.autoRemoveUnavailableOnPlayback) {
      return;
    }
    await this.prepareForTrackRemoval([trackId]);
    await this.repository.removeTracks([trackId]);
  }

  private async loadCurrentHeroArtwork(track: QueueTrack, epoch: number): Promise<void> {
    const pixelMap = await this.artworkCache?.loadLarge(track);
    if (epoch === this.artworkEpoch && pixelMap !== undefined && this.fullArtwork === undefined) {
      this.playerStore.heroArtwork = pixelMap;
      this.playerStore.heroArtworkPreferPixelMap = true;
      this.playerStore.heroArtworkRevision += 1;
    }
  }

  onOutputDeviceUnavailable(): void {
    if (!this.outputReconnectPolicy.recordOutputUnavailable(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.playWhenReady,
      this.playerStore.state,
      appSettings.autoResumeAfterOutputReconnect
    )) {
      return;
    }
    this.updatePlaybackIntent(false);
    this.coverageTracker.recordPause(this.playerStore.progress.positionMs);
    if (this.playerStore.state !== PlayerState.PLAYING) {
      return;
    }
    this.engine.pause().catch((error: Object) => {
      this.clearAutomaticResumeIntents();
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  onOutputDeviceAvailable(): void {
    if (!appSettings.autoResumeAfterOutputReconnect) {
      this.outputReconnectPolicy.clear();
      return;
    }
    if (!this.outputReconnectPolicy.shouldResume(
      this.playerStore.hasCurrentTrack(),
      this.playerStore.state,
      OUTPUT_RECONNECT_RESUME_WINDOW_MS
    )) {
      return;
    }
    this.play();
  }

  onAudioSessionPauseHint(): void {
    if (!this.playerStore.hasCurrentTrack() || !this.playerStore.playWhenReady) {
      this.resumeAfterAudioFocusRelease = false;
      return;
    }
    this.resumeAfterAudioFocusRelease = true;
    this.updatePlaybackIntent(false);
    this.coverageTracker.recordPause(this.playerStore.progress.positionMs);
    if (this.playerStore.state !== PlayerState.PLAYING) {
      return;
    }
    this.engine.pause().catch((error: Object) => {
      this.resumeAfterAudioFocusRelease = false;
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  onAudioSessionResumeHint(): void {
    if (!this.resumeAfterAudioFocusRelease) {
      return;
    }
    this.resumeAfterAudioFocusRelease = false;
    if (!this.playerStore.hasCurrentTrack() ||
      (this.playerStore.state !== PlayerState.PAUSED &&
        this.playerStore.state !== PlayerState.READY &&
        this.playerStore.state !== PlayerState.COMPLETED &&
        this.playerStore.state !== PlayerState.LOADING)) {
      return;
    }
    this.play();
  }

  onAudioSessionStopHint(): void {
    this.clearAutomaticResumeIntents();
    if (!this.playerStore.hasCurrentTrack()) {
      return;
    }
    this.updatePlaybackIntent(false);
    this.coverageTracker.recordPause(this.playerStore.progress.positionMs);
    if (this.playerStore.state !== PlayerState.PLAYING) {
      this.onStateChanged(PlayerState.PAUSED);
      return;
    }
    this.engine.pause().catch((error: Object) => {
      this.onStateChanged(PlayerState.ERROR, PlaybackRuntime.messageOf(error));
    });
  }

  private clearAutomaticResumeIntents(): void {
    this.outputReconnectPolicy.clear();
    this.resumeAfterAudioFocusRelease = false;
  }

  private async loadCurrentLyrics(track: PlaybackTrack, epoch: number): Promise<void> {
    try {
      const lyrics = await MetadataReader.readLyrics(track.uri, track.fileSize, track.format);
      if (epoch === this.artworkEpoch) {
        this.playerStore.lyrics = lyrics;
        this.playerStore.setTimedLyrics(LyricsParser.parse(lyrics).lines);
        this.updateActiveLyricIndex(this.playerStore.progress.positionMs);
        this.session?.updateMetadata(track, this.sessionArtworkUri(track), lyrics);
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
    } catch (error) {
      console.warn(`Unable to load full artwork: ${PlaybackRuntime.messageOf(error)}`);
    }
  }

  private sessionArtworkUri(track: PlaybackTrack): string {
    return this.resolveArtworkUri(track.largeArtworkPath);
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
    this.playerStore.queueDataSource.replace(snapshot.entries);
    this.playerStore.setQueueCurrentIndex(snapshot.currentIndex);
    const currentTrackId = snapshot.currentIndex >= 0 && snapshot.currentIndex < snapshot.entries.length ?
      snapshot.entries[snapshot.currentIndex].track.id : -1;
    if (persist && !DemoLibraryMode.isEnabled()) {
      this.settings?.setPlaybackQueue(
        snapshot.entries.map((entry: QueueEntry) => entry.track.id),
        currentTrackId
      );
    }
  }

  private persistProgress(completed: boolean): void {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
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
      this.playerStore.transportState,
      this.playerStore.progress.positionMs,
      this.playerStore.repeatMode,
      this.playerStore.shuffleEnabled
    );
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

  private resolveArtworkUri(relativePath: string): string {
    if (DemoMusicLibrary.isArtworkPath(relativePath)) {
      return relativePath;
    }
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
    ++this.artworkEpoch;
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
    this.playerStore.heroArtworkUri = track.largeArtworkPath;
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
      this.syncQueueSnapshot(false);
      if (next !== undefined) {
        this.beginDemoTrack(next, true);
      } else {
        this.stopDemoProgress();
        this.playerStore.progress.positionMs = this.playerStore.progress.durationMs;
        this.playerStore.playWhenReady = false;
        this.playerStore.state = PlayerState.COMPLETED;
        this.playerStore.transportState = this.stateReducer.settleCompletion();
      }
    }, 1000);
  }

  private stopDemoProgress(): void {
    if (this.demoProgressTimer >= 0) {
      clearInterval(this.demoProgressTimer);
      this.demoProgressTimer = -1;
    }
  }

  private resetPlaybackPresentation(): void {
    ++this.artworkEpoch;
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
