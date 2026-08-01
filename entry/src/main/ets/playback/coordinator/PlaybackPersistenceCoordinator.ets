import { appSettings } from '../../settings/AppSettingsStore';
import { PlaybackTrack, QueueTrack } from '../model/PlaybackModels';
import { PlaybackPowerPolicy } from '../support/PlaybackPowerPolicy';

const RESUME_MINIMUM_MS = 5000;
const COMPLETION_REMAINING_MS = 10000;
const COMPLETION_POSITION_FRACTION = 0.95;

export interface PersistedPlaybackQueueItem {
  position: number;
  trackId: number;
}

export interface PersistedPlaybackQueueSnapshot {
  items: Array<PersistedPlaybackQueueItem>;
  currentPosition: number;
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
  replacePersistedPlaybackQueue(trackIds: Array<number>, currentPosition: number): Promise<void>;
  updatePersistedPlaybackQueuePosition(currentPosition: number): Promise<void>;
}

export class PlaybackRestorePlan {
  readonly currentTrack: QueueTrack;
  readonly queueTracks: Array<QueueTrack>;
  readonly currentPosition: number;
  readonly resumePositionMs: number;

  constructor(currentTrack: QueueTrack, queueTracks: Array<QueueTrack>, currentPosition: number,
    resumePositionMs: number) {
    this.currentTrack = currentTrack;
    this.queueTracks = queueTracks;
    this.currentPosition = currentPosition;
    this.resumePositionMs = resumePositionMs;
  }
}

export class PlaybackPersistenceCoordinator {
  private settings?: PlaybackPersistenceSettings;
  private repository?: PlaybackRestoreRepository;
  private lastPersistedTrackId: number = -2;
  private lastPersistedPositionMs: number = -1;
  private writeTail: Promise<void> = Promise.resolve();

  bind(settings: PlaybackPersistenceSettings, repository: PlaybackRestoreRepository): void {
    this.settings = settings;
    this.repository = repository;
    this.resetWriteCache();
  }

  async reset(): Promise<void> {
    await this.flush();
    this.settings = undefined;
    this.repository = undefined;
    this.resetWriteCache();
  }

  persistQueue(trackIds: Array<number>, currentPosition: number): void {
    const repository = this.repository;
    const settings = this.settings;
    if (repository === undefined || settings === undefined) {
      return;
    }
    const snapshot = trackIds.slice();
    this.enqueueWrite(async (): Promise<void> => {
      await repository.replacePersistedPlaybackQueue(snapshot, currentPosition);
      settings.clearLegacyPlaybackQueue();
    });
  }

  persistQueueCurrentPosition(currentPosition: number): void {
    const repository = this.repository;
    if (repository === undefined) {
      return;
    }
    this.enqueueWrite(async (): Promise<void> => {
      await repository.updatePersistedPlaybackQueuePosition(currentPosition);
    });
  }

  clearResumeAndQueue(): void {
    this.persistResumeState(-1, 0);
    this.persistQueue([], -1);
  }

  flush(): Promise<void> {
    return this.writeTail;
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

  async createRestorePlan(buildEpoch: number,
    isEpochCurrent: (epoch: number) => boolean): Promise<PlaybackRestorePlan | undefined> {
    if (this.repository === undefined || !isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const stored = await this.repository.getPersistedPlaybackQueue();
    if (!isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const snapshot = stored ?? this.legacySnapshot();
    if (snapshot.items.length === 0) {
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
    const tracks: Array<QueueTrack> = [];
    const originalPositions: Array<number> = [];
    snapshot.items.forEach((item: PersistedPlaybackQueueItem): void => {
      const track = byId.get(item.trackId);
      if (track !== undefined) {
        tracks.push(track);
        originalPositions.push(item.position);
      }
    });
    if (tracks.length === 0) {
      this.clearResumeAndQueue();
      return undefined;
    }
    const currentPosition = PlaybackPersistenceCoordinator.restoredCurrentIndex(
      originalPositions,
      snapshot.currentPosition
    );
    const currentTrack = tracks[currentPosition];
    return new PlaybackRestorePlan(
      currentTrack,
      tracks,
      currentPosition,
      this.resumePositionFor(currentTrack.id, currentTrack.durationMs)
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

  private legacySnapshot(): PersistedPlaybackQueueSnapshot {
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
        trackId: trackId
      })),
      currentPosition: currentPosition
    };
  }

  private enqueueWrite(operation: () => Promise<void>): void {
    this.writeTail = this.writeTail.then(operation).catch((error: Object): void => {
      const message = error instanceof Error ? error.message : `${error}`;
      console.warn(`Unable to persist playback queue: ${message}`);
    });
  }

  private resetWriteCache(): void {
    this.lastPersistedTrackId = -2;
    this.lastPersistedPositionMs = -1;
  }
}
