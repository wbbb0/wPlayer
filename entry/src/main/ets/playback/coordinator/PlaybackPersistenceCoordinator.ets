import { appSettings } from '../../settings/AppSettingsStore';
import { PlaybackTrack, QueueTrack } from '../model/PlaybackModels';
import { PlaybackPowerPolicy } from '../support/PlaybackPowerPolicy';

const RESUME_MINIMUM_MS = 5000;
const COMPLETION_REMAINING_MS = 10000;
const COMPLETION_POSITION_FRACTION = 0.95;

export interface PersistedPlaybackQueueItem {
  position: number;
  playbackPosition: number;
  trackId: number;
}

export interface PersistedPlaybackQueueSnapshot {
  items: Array<PersistedPlaybackQueueItem>;
  currentPosition: number;
  shuffleEnabled: boolean;
}

export enum ExactQueuePersistenceResult {
  PERSISTED,
  FAILED,
  UNAVAILABLE
}

class ExactQueuePersistenceRequest {
  readonly sequence: number;
  readonly snapshot: PersistedPlaybackQueueSnapshot;
  readonly completion: Promise<ExactQueuePersistenceResult>;
  private resolveCompletion?: (result: ExactQueuePersistenceResult) => void;

  constructor(sequence: number, snapshot: PersistedPlaybackQueueSnapshot) {
    this.sequence = sequence;
    this.snapshot = snapshot;
    this.completion = new Promise<ExactQueuePersistenceResult>((resolve) => {
      this.resolveCompletion = resolve;
    });
  }

  resolve(result: ExactQueuePersistenceResult): void {
    this.resolveCompletion?.(result);
    this.resolveCompletion = undefined;
  }
}

export interface PlaybackPersistenceSettings {
  getPlaybackLastTrackId(defaultValue?: number): number;
  getPlaybackLastPositionMs(defaultValue?: number): number;
  getPlaybackQueueTrackIds(): Array<number>;
  getPlaybackQueueCurrentTrackId(defaultValue?: number): number;
  setPlaybackResumeState(trackId: number, positionMs: number): void;
  clearLegacyPlaybackQueue(): void;
}

export interface PlaybackRestoreRepository {
  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>>;
  getPersistedPlaybackQueue(): Promise<PersistedPlaybackQueueSnapshot | undefined>;
  replacePersistedPlaybackQueue(snapshot: PersistedPlaybackQueueSnapshot): Promise<void>;
  updatePersistedPlaybackQueuePosition(currentPosition: number): Promise<void>;
}

export class PlaybackRestorePlan {
  readonly currentTrack: QueueTrack;
  readonly queueTracks: Array<QueueTrack>;
  readonly playbackPositions: Array<number>;
  readonly currentPosition: number;
  readonly resumePositionMs: number;
  readonly shuffleEnabled: boolean;

  constructor(currentTrack: QueueTrack, queueTracks: Array<QueueTrack>,
    playbackPositions: Array<number>, currentPosition: number, resumePositionMs: number,
    shuffleEnabled: boolean) {
    this.currentTrack = currentTrack;
    this.queueTracks = queueTracks;
    this.playbackPositions = playbackPositions;
    this.currentPosition = currentPosition;
    this.resumePositionMs = resumePositionMs;
    this.shuffleEnabled = shuffleEnabled;
  }
}

interface ResolvedPersistedQueueItem extends PersistedPlaybackQueueItem {
  track: QueueTrack;
}

export class PlaybackPersistenceCoordinator {
  private settings?: PlaybackPersistenceSettings;
  private repository?: PlaybackRestoreRepository;
  private lastPersistedTrackId: number = -2;
  private lastPersistedPositionMs: number = -1;
  private pendingSnapshot?: PersistedPlaybackQueueSnapshot;
  private pendingSnapshotSequence: number = -1;
  private pendingCurrentPosition?: number;
  private pendingCurrentPositionSequence: number = -1;
  private readonly exactQueueRequests: Array<ExactQueuePersistenceRequest> = [];
  private nextWriteSequence: number = 0;
  private writePumpRunning: boolean = false;
  private writePump: Promise<void> = Promise.resolve();
  private legacyQueueCleared: boolean = false;
  private cursorWritesBlocked: boolean = false;

  bind(settings: PlaybackPersistenceSettings, repository: PlaybackRestoreRepository): void {
    this.settings = settings;
    this.repository = repository;
    this.resetWriteCache();
    this.legacyQueueCleared = false;
    this.cursorWritesBlocked = false;
  }

  async reset(): Promise<void> {
    await this.flush();
    this.settings = undefined;
    this.repository = undefined;
    this.pendingSnapshot = undefined;
    this.pendingSnapshotSequence = -1;
    this.pendingCurrentPosition = undefined;
    this.pendingCurrentPositionSequence = -1;
    this.legacyQueueCleared = false;
    this.cursorWritesBlocked = false;
    this.resetWriteCache();
  }

  persistQueue(snapshot: PersistedPlaybackQueueSnapshot): void {
    if (this.repository === undefined || this.settings === undefined) {
      return;
    }
    this.pendingSnapshot = PlaybackPersistenceCoordinator.copySnapshot(snapshot);
    this.pendingSnapshotSequence = ++this.nextWriteSequence;
    this.pendingCurrentPosition = undefined;
    this.cursorWritesBlocked = false;
    this.ensureWritePump();
  }

  persistQueueExact(snapshot: PersistedPlaybackQueueSnapshot): Promise<ExactQueuePersistenceResult> {
    if (this.repository === undefined || this.settings === undefined) {
      return Promise.resolve(ExactQueuePersistenceResult.UNAVAILABLE);
    }
    const request = new ExactQueuePersistenceRequest(
      ++this.nextWriteSequence,
      PlaybackPersistenceCoordinator.copySnapshot(snapshot)
    );
    this.exactQueueRequests.push(request);
    this.ensureWritePump();
    return request.completion;
  }

  persistQueueCurrentPosition(currentPosition: number): void {
    if (this.repository === undefined) {
      return;
    }
    if (this.pendingSnapshot !== undefined && this.exactQueueRequests.length === 0) {
      this.pendingSnapshot.currentPosition = currentPosition;
    } else if (!this.cursorWritesBlocked) {
      this.pendingCurrentPosition = currentPosition;
      this.pendingCurrentPositionSequence = ++this.nextWriteSequence;
    }
    this.ensureWritePump();
  }

  clearResumeAndQueue(): void {
    this.persistResumeState(-1, 0);
    this.persistQueue({ items: [], currentPosition: -1, shuffleEnabled: false });
  }

  async flush(): Promise<void> {
    while (this.writePumpRunning || this.pendingSnapshot !== undefined ||
      this.pendingCurrentPosition !== undefined || this.exactQueueRequests.length > 0) {
      this.ensureWritePump();
      const currentPump = this.writePump;
      await currentPump;
    }
  }

  persistProgress(track: PlaybackTrack | undefined, positionMs: number, durationMs: number,
    completed: boolean): void {
    if (track === undefined) {
      return;
    }
    const effectiveDuration = durationMs > 0 ? durationMs : track.durationMs;
    let effectivePosition = positionMs;
    let consideredCompleted = completed;
    if (!consideredCompleted && effectiveDuration > 0 &&
      (effectiveDuration - effectivePosition <= COMPLETION_REMAINING_MS ||
        effectivePosition >= effectiveDuration * COMPLETION_POSITION_FRACTION)) {
      consideredCompleted = true;
    }
    if (effectivePosition < RESUME_MINIMUM_MS || consideredCompleted ||
      !appSettings.rememberPlaybackPosition) {
      effectivePosition = 0;
    }
    this.persistResumeState(track.id, effectivePosition);
  }

  persistResumeState(trackId: number, positionMs: number): void {
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

  resumePositionFor(trackId: number, durationMs: number): number {
    const storedTrackId = this.settings?.getPlaybackLastTrackId(-1) ?? -1;
    const storedPosition = appSettings.rememberPlaybackPosition && storedTrackId === trackId ?
      this.settings?.getPlaybackLastPositionMs(0) ?? 0 : 0;
    return PlaybackPersistenceCoordinator.validResumePosition(storedPosition, durationMs);
  }

  async createRestorePlan(buildEpoch: number, fallbackShuffleEnabled: boolean,
    isEpochCurrent: (epoch: number) => boolean): Promise<PlaybackRestorePlan | undefined> {
    if (this.repository === undefined || !isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const stored = await this.repository.getPersistedPlaybackQueue();
    if (!isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const snapshot = stored ?? this.legacySnapshot(fallbackShuffleEnabled);
    if (snapshot.items.length === 0) {
      return undefined;
    }
    if (!PlaybackPersistenceCoordinator.validSnapshot(snapshot)) {
      console.warn('Ignoring invalid persisted playback queue snapshot');
      return undefined;
    }
    const uniqueTrackIds: Array<number> = [];
    snapshot.items.forEach((item: PersistedPlaybackQueueItem): void => {
      if (uniqueTrackIds.indexOf(item.trackId) < 0) {
        uniqueTrackIds.push(item.trackId);
      }
    });
    const resolvedTracks = await this.repository.getPlaybackQueueTracks(uniqueTrackIds);
    if (!isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const byId: Map<number, QueueTrack> = new Map<number, QueueTrack>();
    resolvedTracks.forEach((track: QueueTrack): void => {
      byId.set(track.id, track);
    });
    const resolvedItems: Array<ResolvedPersistedQueueItem> = [];
    snapshot.items.slice().sort((left: PersistedPlaybackQueueItem,
      right: PersistedPlaybackQueueItem): number => left.position - right.position)
      .forEach((item: PersistedPlaybackQueueItem): void => {
      const track = byId.get(item.trackId);
      if (track !== undefined) {
        resolvedItems.push({
          position: item.position,
          playbackPosition: item.playbackPosition,
          trackId: item.trackId,
          track: track
        });
      }
    });
    if (resolvedItems.length === 0) {
      this.clearResumeAndQueue();
      return undefined;
    }
    const playbackItems = resolvedItems.slice().sort((left: ResolvedPersistedQueueItem,
      right: ResolvedPersistedQueueItem): number =>
      left.playbackPosition - right.playbackPosition);
    const playbackPositionByBasePosition: Map<number, number> = new Map<number, number>();
    playbackItems.forEach((item: ResolvedPersistedQueueItem, playbackPosition: number): void => {
      playbackPositionByBasePosition.set(item.position, playbackPosition);
    });
    const tracks = resolvedItems.map((item: ResolvedPersistedQueueItem): QueueTrack => item.track);
    const playbackPositions = resolvedItems.map((item: ResolvedPersistedQueueItem): number =>
      playbackPositionByBasePosition.get(item.position) as number);
    const currentPosition = PlaybackPersistenceCoordinator.restoredCurrentIndex(
      playbackItems.map((item: ResolvedPersistedQueueItem): number => item.playbackPosition),
      snapshot.currentPosition
    );
    const currentTrack = playbackItems[currentPosition].track;
    return new PlaybackRestorePlan(
      currentTrack,
      tracks,
      playbackPositions,
      currentPosition,
      this.resumePositionFor(currentTrack.id, currentTrack.durationMs),
      snapshot.shuffleEnabled
    );
  }

  static restoredCurrentIndex(originalPositions: Array<number>, storedPosition: number): number {
    if (originalPositions.length === 0) {
      return -1;
    }
    for (let index = 0; index < originalPositions.length; index += 1) {
      if (originalPositions[index] >= storedPosition) {
        return index;
      }
    }
    return originalPositions.length - 1;
  }

  static validResumePosition(positionMs: number, durationMs: number): number {
    if (positionMs < RESUME_MINIMUM_MS || durationMs <= 0 ||
      durationMs - positionMs <= COMPLETION_REMAINING_MS ||
      positionMs >= durationMs * COMPLETION_POSITION_FRACTION) {
      return 0;
    }
    return positionMs;
  }

  private legacySnapshot(shuffleEnabled: boolean): PersistedPlaybackQueueSnapshot {
    const storedIds = this.settings?.getPlaybackQueueTrackIds() ?? [];
    const currentTrackId = this.settings?.getPlaybackQueueCurrentTrackId(-1) ?? -1;
    const ids = storedIds.slice();
    if (currentTrackId >= 0 && ids.indexOf(currentTrackId) < 0) {
      ids.unshift(currentTrackId);
    }
    if (ids.length === 0 && currentTrackId < 0) {
      const lastTrackId = this.settings?.getPlaybackLastTrackId(-1) ?? -1;
      if (lastTrackId >= 0) {
        ids.push(lastTrackId);
      }
    }
    let currentPosition = currentTrackId >= 0 ? ids.indexOf(currentTrackId) : 0;
    if (currentPosition < 0) {
      currentPosition = 0;
    }
    return {
      items: ids.map((trackId: number, position: number): PersistedPlaybackQueueItem => ({
        position: position,
        playbackPosition: position,
        trackId: trackId
      })),
      currentPosition: currentPosition,
      shuffleEnabled: shuffleEnabled
    };
  }

  private ensureWritePump(): void {
    if (this.writePumpRunning || this.repository === undefined ||
      (this.pendingSnapshot === undefined && this.pendingCurrentPosition === undefined &&
        this.exactQueueRequests.length === 0)) {
      return;
    }
    this.writePumpRunning = true;
    this.writePump = this.drainWrites().finally((): void => {
      this.writePumpRunning = false;
      this.ensureWritePump();
    });
  }

  private async drainWrites(): Promise<void> {
    while (this.pendingSnapshot !== undefined || this.pendingCurrentPosition !== undefined ||
      this.exactQueueRequests.length > 0) {
      const repository = this.repository;
      if (repository === undefined) {
        this.resolveExactRequestsUnavailable();
        this.pendingSnapshot = undefined;
        this.pendingSnapshotSequence = -1;
        this.pendingCurrentPosition = undefined;
        this.pendingCurrentPositionSequence = -1;
        return;
      }
      const exactRequest = this.exactQueueRequests[0];
      const exactSequence = exactRequest?.sequence ?? Number.MAX_SAFE_INTEGER;
      const snapshotSequence = this.pendingSnapshot === undefined ?
        Number.MAX_SAFE_INTEGER : this.pendingSnapshotSequence;
      const cursorSequence = this.pendingCurrentPosition === undefined ?
        Number.MAX_SAFE_INTEGER : this.pendingCurrentPositionSequence;
      if (exactRequest !== undefined && exactSequence < snapshotSequence &&
        exactSequence < cursorSequence) {
        this.exactQueueRequests.shift();
        try {
          await repository.replacePersistedPlaybackQueue(exactRequest.snapshot);
          exactRequest.resolve(ExactQueuePersistenceResult.PERSISTED);
          this.cursorWritesBlocked = false;
          this.clearLegacyQueueAfterSnapshot();
        } catch (error) {
          PlaybackPersistenceCoordinator.logWriteFailure(error);
          exactRequest.resolve(ExactQueuePersistenceResult.FAILED);
          this.handleStructuralWriteFailure();
        }
        continue;
      }
      if (this.pendingSnapshot !== undefined && snapshotSequence < cursorSequence) {
        const snapshot = this.pendingSnapshot;
        this.pendingSnapshot = undefined;
        this.pendingSnapshotSequence = -1;
        try {
          await repository.replacePersistedPlaybackQueue(snapshot);
          this.cursorWritesBlocked = false;
          this.clearLegacyQueueAfterSnapshot();
        } catch (error) {
          PlaybackPersistenceCoordinator.logWriteFailure(error);
          this.handleStructuralWriteFailure();
        }
        continue;
      }
      const currentPosition = this.pendingCurrentPosition as number;
      this.pendingCurrentPosition = undefined;
      this.pendingCurrentPositionSequence = -1;
      try {
        await repository.updatePersistedPlaybackQueuePosition(currentPosition);
      } catch (error) {
        PlaybackPersistenceCoordinator.logWriteFailure(error);
      }
    }
  }

  private clearLegacyQueueAfterSnapshot(): void {
    if (!this.legacyQueueCleared && this.settings !== undefined) {
      this.settings.clearLegacyPlaybackQueue();
      this.legacyQueueCleared = true;
    }
  }

  private resolveExactRequestsUnavailable(): void {
    while (this.exactQueueRequests.length > 0) {
      this.exactQueueRequests.shift()?.resolve(ExactQueuePersistenceResult.UNAVAILABLE);
    }
  }

  private handleStructuralWriteFailure(): void {
    if (this.pendingCurrentPosition !== undefined &&
      !this.hasQueuedFullWriteBefore(this.pendingCurrentPositionSequence)) {
      this.pendingCurrentPosition = undefined;
      this.pendingCurrentPositionSequence = -1;
    }
    this.cursorWritesBlocked = this.pendingSnapshot === undefined &&
      this.exactQueueRequests.length === 0;
  }

  private hasQueuedFullWriteBefore(sequence: number): boolean {
    if (this.pendingSnapshot !== undefined && this.pendingSnapshotSequence < sequence) {
      return true;
    }
    return this.exactQueueRequests.some((request: ExactQueuePersistenceRequest): boolean =>
      request.sequence < sequence);
  }

  private static copySnapshot(snapshot: PersistedPlaybackQueueSnapshot): PersistedPlaybackQueueSnapshot {
    return {
      items: snapshot.items.map((item: PersistedPlaybackQueueItem): PersistedPlaybackQueueItem => ({
        position: item.position,
        playbackPosition: item.playbackPosition,
        trackId: item.trackId
      })),
      currentPosition: snapshot.currentPosition,
      shuffleEnabled: snapshot.shuffleEnabled
    };
  }

  private static validSnapshot(snapshot: PersistedPlaybackQueueSnapshot): boolean {
    if (snapshot.items.length === 0) {
      return snapshot.currentPosition === -1;
    }
    if (snapshot.currentPosition < 0 || snapshot.currentPosition >= snapshot.items.length) {
      return false;
    }
    const basePositions = snapshot.items.map((item: PersistedPlaybackQueueItem): number => item.position);
    const playbackPositions = snapshot.items.map(
      (item: PersistedPlaybackQueueItem): number => item.playbackPosition);
    return PlaybackPersistenceCoordinator.isPermutation(basePositions) &&
      PlaybackPersistenceCoordinator.isPermutation(playbackPositions);
  }

  private static isPermutation(positions: Array<number>): boolean {
    const seen = new Set<number>();
    for (let index = 0; index < positions.length; index += 1) {
      const position = positions[index];
      if (!Number.isInteger(position) || position < 0 || position >= positions.length ||
        seen.has(position)) {
        return false;
      }
      seen.add(position);
    }
    return seen.size === positions.length;
  }

  private static logWriteFailure(error: Object): void {
    const message = error instanceof Error ? error.message : `${error}`;
    console.warn(`Unable to persist playback queue: ${message}`);
  }

  private resetWriteCache(): void {
    this.lastPersistedTrackId = -2;
    this.lastPersistedPositionMs = -1;
    this.nextWriteSequence = 0;
  }
}
