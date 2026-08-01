import { appSettings } from '../../settings/AppSettingsStore';
import { PlaybackTrack, QueueTrack } from '../model/PlaybackModels';
import { PlaybackPowerPolicy } from '../support/PlaybackPowerPolicy';

const RESUME_MINIMUM_MS = 5000;
const COMPLETION_REMAINING_MS = 10000;
const COMPLETION_POSITION_FRACTION = 0.95;

export interface PlaybackPersistenceSettings {
  getPlaybackLastTrackId(defaultValue?: number): number;
  getPlaybackLastPositionMs(defaultValue?: number): number;
  getPlaybackQueueTrackIds(): Array<number>;
  getPlaybackQueueCurrentTrackId(defaultValue?: number): number;
  setPlaybackResumeState(trackId: number, positionMs: number): void;
  setPlaybackQueue(trackIds: Array<number>, currentTrackId: number): void;
  setPlaybackQueueCurrentTrackId(currentTrackId: number): void;
}

export interface PlaybackRestoreRepository {
  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>>;
}

export class PlaybackRestorePlan {
  readonly ids: Array<number>;
  readonly currentTrack: QueueTrack;
  readonly queueTracks: Array<QueueTrack>;
  readonly resumePositionMs: number;

  constructor(
    ids: Array<number>,
    currentTrack: QueueTrack,
    queueTracks: Array<QueueTrack>,
    resumePositionMs: number
  ) {
    this.ids = ids;
    this.currentTrack = currentTrack;
    this.queueTracks = queueTracks;
    this.resumePositionMs = resumePositionMs;
  }
}

export class PlaybackRestoreBasePlan {
  readonly ids: Array<number>;
  readonly currentTrack: QueueTrack;
  readonly resumePositionMs: number;

  constructor(ids: Array<number>, currentTrack: QueueTrack, resumePositionMs: number) {
    this.ids = ids;
    this.currentTrack = currentTrack;
    this.resumePositionMs = resumePositionMs;
  }
}

export class PlaybackPersistenceCoordinator {
  private settings?: PlaybackPersistenceSettings;
  private lastPersistedTrackId: number = -2;
  private lastPersistedPositionMs: number = -1;

  bind(settings: PlaybackPersistenceSettings): void {
    this.settings = settings;
    this.resetWriteCache();
  }

  reset(): void {
    this.settings = undefined;
    this.resetWriteCache();
  }

  persistQueue(trackIds: Array<number>, currentTrackId: number): void {
    this.settings?.setPlaybackQueue(trackIds, currentTrackId);
  }

  persistQueueCurrentTrack(currentTrackId: number): void {
    this.settings?.setPlaybackQueueCurrentTrackId(currentTrackId);
  }

  clearResumeAndQueue(): void {
    this.persistResumeState(-1, 0);
    this.persistQueue([], -1);
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

  async createRestoreBasePlan(repository: PlaybackRestoreRepository, buildEpoch: number,
    isEpochCurrent: (epoch: number) => boolean): Promise<PlaybackRestoreBasePlan | undefined> {
    const storedIds = this.settings?.getPlaybackQueueTrackIds() ?? [];
    let trackId = this.settings?.getPlaybackQueueCurrentTrackId(-1) ?? -1;
    if (trackId < 0) {
      trackId = this.settings?.getPlaybackLastTrackId(-1) ?? -1;
    }
    if (trackId < 0 || !isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const ids = storedIds.length > 0 ? storedIds.slice() : [trackId];
    if (ids.indexOf(trackId) < 0) {
      ids.unshift(trackId);
    }
    const currentTracks = await repository.getPlaybackQueueTracks([trackId]);
    if (!isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    if (currentTracks.length === 0) {
      this.clearResumeAndQueue();
      return undefined;
    }
    const currentTrack = currentTracks[0];
    const storedTrackId = this.settings?.getPlaybackLastTrackId(-1) ?? -1;
    const storedPosition = appSettings.rememberPlaybackPosition && storedTrackId === trackId ?
      this.settings?.getPlaybackLastPositionMs(0) ?? 0 : 0;
    return new PlaybackRestoreBasePlan(
      ids,
      currentTrack,
      PlaybackPersistenceCoordinator.validResumePosition(storedPosition, currentTrack.durationMs)
    );
  }

  async completeRestorePlan(repository: PlaybackRestoreRepository, base: PlaybackRestoreBasePlan,
    buildEpoch: number, isEpochCurrent: (epoch: number) => boolean): Promise<PlaybackRestorePlan | undefined> {
    if (!isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const remainingIds = base.ids.filter((id: number): boolean => id !== base.currentTrack.id);
    const restoredTracks = await repository.getPlaybackQueueTracks(remainingIds);
    if (!isEpochCurrent(buildEpoch)) {
      return undefined;
    }
    const tracksById: Map<number, QueueTrack> = new Map<number, QueueTrack>();
    restoredTracks.forEach((track: QueueTrack): void => {
      tracksById.set(track.id, track);
    });
    tracksById.set(base.currentTrack.id, base.currentTrack);
    const queueTracks: Array<QueueTrack> = [];
    base.ids.forEach((id: number): void => {
      const track = tracksById.get(id);
      if (track !== undefined) {
        queueTracks.push(track);
      }
    });
    return new PlaybackRestorePlan(
      base.ids,
      base.currentTrack,
      queueTracks,
      base.resumePositionMs
    );
  }

  private resetWriteCache(): void {
    this.lastPersistedTrackId = -2;
    this.lastPersistedPositionMs = -1;
  }

  static validResumePosition(positionMs: number, durationMs: number): number {
    if (positionMs < RESUME_MINIMUM_MS || durationMs <= 0 ||
      durationMs - positionMs <= COMPLETION_REMAINING_MS ||
      positionMs >= durationMs * COMPLETION_POSITION_FRACTION) {
      return 0;
    }
    return positionMs;
  }
}
