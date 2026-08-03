import { describe, expect, it } from '@ohos/hypium';
import {
  AudioRecoveryAction,
  PlaybackAudioRecoveryCoordinator
} from '../main/ets/playback/coordinator/PlaybackAudioRecoveryCoordinator';
import { PlaybackMediaCoordinator } from '../main/ets/playback/coordinator/PlaybackMediaCoordinator';
import {
  ArtworkPrefetchCoordinator
} from '../main/ets/playback/coordinator/ArtworkPrefetchCoordinator';
import {
  PlaybackPersistenceCoordinator,
  PlaybackPersistenceSettings,
  PersistedPlaybackQueueItem,
  PersistedPlaybackQueueSnapshot,
  PlaybackRestoreRepository
} from
  '../main/ets/playback/coordinator/PlaybackPersistenceCoordinator';
import { PlayerState, QueueTrack } from '../main/ets/playback/model/PlaybackModels';

class FakePlaybackSettings implements PlaybackPersistenceSettings {
  lastTrackId: number = -1;
  lastPositionMs: number = 0;
  queueTrackIds: Array<number> = [];
  queueCurrentTrackId: number = -1;
  resumeWrites: Array<string> = [];
  legacyClearCount: number = 0;

  getPlaybackLastTrackId(defaultValue: number = -1): number {
    return this.lastTrackId < 0 ? defaultValue : this.lastTrackId;
  }

  getPlaybackLastPositionMs(defaultValue: number = 0): number {
    return this.lastPositionMs < 0 ? defaultValue : this.lastPositionMs;
  }

  getPlaybackQueueTrackIds(): Array<number> {
    return this.queueTrackIds.slice();
  }

  getPlaybackQueueCurrentTrackId(defaultValue: number = -1): number {
    return this.queueCurrentTrackId < 0 ? defaultValue : this.queueCurrentTrackId;
  }

  setPlaybackResumeState(trackId: number, positionMs: number): void {
    this.resumeWrites.push(`${trackId}:${positionMs}`);
  }

  clearLegacyPlaybackQueue(): void {
    this.legacyClearCount += 1;
  }
}

class StaticRestoreRepository implements PlaybackRestoreRepository {
  snapshot?: PersistedPlaybackQueueSnapshot;
  tracks: Array<QueueTrack> = [];
  queueWrites: Array<PersistedPlaybackQueueSnapshot> = [];
  cursorWrites: Array<number> = [];

  constructor(snapshot?: PersistedPlaybackQueueSnapshot, tracks: Array<QueueTrack> = []) {
    this.snapshot = snapshot;
    this.tracks = tracks;
  }

  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>> {
    return Promise.resolve(this.tracks.filter((track: QueueTrack): boolean =>
      trackIds.indexOf(track.id) >= 0));
  }

  getPersistedPlaybackQueue(): Promise<PersistedPlaybackQueueSnapshot | undefined> {
    return Promise.resolve(this.snapshot);
  }

  replacePersistedPlaybackQueue(snapshot: PersistedPlaybackQueueSnapshot): Promise<void> {
    this.queueWrites.push(snapshot);
    return Promise.resolve();
  }

  updatePersistedPlaybackQueuePosition(currentPosition: number): Promise<void> {
    this.cursorWrites.push(currentPosition);
    return Promise.resolve();
  }
}

class DeferredWriteRepository extends StaticRestoreRepository {
  private resolvers: Array<() => void> = [];

  replacePersistedPlaybackQueue(snapshot: PersistedPlaybackQueueSnapshot): Promise<void> {
    this.queueWrites.push(snapshot);
    return new Promise<void>((resolve: () => void): void => {
      this.resolvers.push(resolve);
    });
  }

  completeNext(): void {
    const resolve = this.resolvers.shift();
    resolve?.();
  }
}

class FailFirstWriteRepository extends StaticRestoreRepository {
  private shouldFail: boolean = true;

  replacePersistedPlaybackQueue(snapshot: PersistedPlaybackQueueSnapshot): Promise<void> {
    this.queueWrites.push(snapshot);
    if (this.shouldFail) {
      this.shouldFail = false;
      return Promise.reject(new Error('first write failed'));
    }
    return Promise.resolve();
  }
}

class FailThenDeferWriteRepository extends StaticRestoreRepository {
  private writeCount: number = 0;
  private resolveSecond?: () => void;

  replacePersistedPlaybackQueue(snapshot: PersistedPlaybackQueueSnapshot): Promise<void> {
    this.queueWrites.push(snapshot);
    this.writeCount += 1;
    if (this.writeCount === 1) {
      return Promise.reject(new Error('first write failed'));
    }
    return new Promise<void>((resolve: () => void): void => {
      this.resolveSecond = resolve;
    });
  }

  completeSecond(): void {
    this.resolveSecond?.();
  }
}

class DeferredRestoreRepository extends StaticRestoreRepository {
  private resolveLookup?: (tracks: Array<QueueTrack>) => void;

  constructor(snapshot: PersistedPlaybackQueueSnapshot) {
    super(snapshot);
  }

  getPlaybackQueueTracks(_trackIds: Array<number>): Promise<Array<QueueTrack>> {
    return new Promise<Array<QueueTrack>>(
      (resolve: (tracks: Array<QueueTrack>) => void): void => {
        this.resolveLookup = resolve;
      }
    );
  }

  resolve(tracks: Array<QueueTrack>): void {
    this.resolveLookup?.(tracks);
  }
}

function queueTrack(id: number): QueueTrack {
  return {
    id: id,
    title: `Track ${id}`,
    artistDisplay: '',
    albumDisplay: '',
    durationMs: 120000,
    smallArtworkHash: '',
    smallArtworkPath: '',
    largeArtworkHash: '',
    largeArtworkPath: '',
    artworkWidth: 0,
    artworkHeight: 0,
    palettePrimary: '',
    paletteSecondary: '',
    paletteAccent: ''
  };
}

function persistedQueue(trackIds: Array<number>, playbackPositions: Array<number>,
  currentPosition: number, shuffleEnabled: boolean): PersistedPlaybackQueueSnapshot {
  return {
    items: trackIds.map((trackId: number, position: number): PersistedPlaybackQueueItem => ({
      position: position,
      playbackPosition: playbackPositions[position],
      trackId: trackId
    })),
    currentPosition: currentPosition,
    shuffleEnabled: shuffleEnabled
  };
}

export default function playbackCoordinatorTest() {
  describe('Playback coordinators', () => {
    it('consumes output and focus recovery as one resume command', 0, () => {
      const coordinator = new PlaybackAudioRecoveryCoordinator();

      expect(coordinator.outputUnavailable(
        true,
        true,
        PlayerState.PLAYING,
        true
      )).assertEqual(AudioRecoveryAction.PAUSE);
      expect(coordinator.audioPauseHint(true, true)).assertEqual(AudioRecoveryAction.PAUSE);
      expect(coordinator.outputAvailable(
        true,
        PlayerState.PAUSED,
        true
      )).assertEqual(AudioRecoveryAction.RESUME);
      expect(coordinator.audioResumeHint(
        true,
        PlayerState.PAUSED
      )).assertEqual(AudioRecoveryAction.NONE);
    });

    it('does not recover after explicit intent clears pending state', 0, () => {
      const coordinator = new PlaybackAudioRecoveryCoordinator();
      coordinator.outputUnavailable(true, true, PlayerState.PLAYING, true);
      coordinator.audioPauseHint(true, true);
      coordinator.clear();

      expect(coordinator.outputAvailable(
        true,
        PlayerState.PAUSED,
        true
      )).assertEqual(AudioRecoveryAction.NONE);
      expect(coordinator.audioResumeHint(
        true,
        PlayerState.PAUSED
      )).assertEqual(AudioRecoveryAction.NONE);
    });

    it('uses one media request epoch for every track side effect', 0, () => {
      const coordinator = new PlaybackMediaCoordinator();
      const first = coordinator.beginRequest();
      expect(coordinator.isCurrent(first)).assertTrue();

      const second = coordinator.beginRequest();
      expect(coordinator.isCurrent(first)).assertFalse();
      expect(coordinator.isCurrent(second)).assertTrue();

      coordinator.reset();
      expect(coordinator.isCurrent(second)).assertFalse();
    });

    it('runs only the latest delayed artwork prefetch request', 0, async () => {
      const callbacks: Array<() => void> = [];
      const cancelled: Array<number> = [];
      const coordinator = new ArtworkPrefetchCoordinator(
        1500,
        (callback: () => void, _delayMs: number): number => {
          callbacks.push(callback);
          return callbacks.length;
        },
        (timerId: number): void => {
          cancelled.push(timerId);
        }
      );
      const runs: Array<string> = [];

      coordinator.schedule(async (_shouldContinue: () => boolean): Promise<void> => {
        runs.push('first');
      });
      coordinator.schedule(async (shouldContinue: () => boolean): Promise<void> => {
        if (shouldContinue()) {
          runs.push('second');
        }
      });
      callbacks[0]();
      callbacks[1]();
      await Promise.resolve();

      expect(cancelled[0]).assertEqual(1);
      expect(runs.length).assertEqual(1);
      expect(runs[0]).assertEqual('second');
    });

    it('invalidates delayed artwork prefetch before it starts', 0, async () => {
      const callbacks: Array<() => void> = [];
      const coordinator = new ArtworkPrefetchCoordinator(
        1500,
        (callback: () => void, _delayMs: number): number => {
          callbacks.push(callback);
          return callbacks.length;
        },
        (_timerId: number): void => {}
      );
      let runs = 0;
      coordinator.schedule(async (_shouldContinue: () => boolean): Promise<void> => {
        runs += 1;
      });
      coordinator.invalidate();

      callbacks[0]();
      await Promise.resolve();

      expect(runs).assertEqual(0);
    });

    it('normalizes persisted resume positions at playback boundaries', 0, () => {
      expect(PlaybackPersistenceCoordinator.validResumePosition(4999, 120000)).assertEqual(0);
      expect(PlaybackPersistenceCoordinator.validResumePosition(5000, 120000)).assertEqual(5000);
      expect(PlaybackPersistenceCoordinator.validResumePosition(111000, 120000)).assertEqual(0);
      expect(PlaybackPersistenceCoordinator.validResumePosition(60000, 120000)).assertEqual(60000);
    });

    it('rejects a stale restore after the current-track lookup completes', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new DeferredRestoreRepository(persistedQueue([1], [0], 0, false));
      settings.lastTrackId = 1;
      coordinator.bind(settings, repository);
      let currentEpoch = 1;

      const pending = coordinator.createRestorePlan(
        currentEpoch,
        false,
        (epoch: number): boolean => epoch === currentEpoch
      );
      currentEpoch = 2;
      repository.resolve([queueTrack(1)]);

      expect(await pending).assertUndefined();
      expect(settings.resumeWrites.length).assertEqual(0);
      expect(repository.queueWrites.length).assertEqual(0);
    });

    it('clears persisted state when the restored current track is missing', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      settings.lastTrackId = 7;
      const repository = new StaticRestoreRepository(persistedQueue([7], [0], 0, false));
      coordinator.bind(settings, repository);

      const plan = await coordinator.createRestorePlan(
        1,
        false,
        (_epoch: number): boolean => true
      );
      await coordinator.flush();

      expect(plan).assertUndefined();
      expect(settings.resumeWrites[0]).assertEqual('-1:0');
      expect(repository.queueWrites[0].items.length).assertEqual(0);
      expect(repository.queueWrites[0].currentPosition).assertEqual(-1);
    });

    it('restores duplicate order and remaps a missing current item by position', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new StaticRestoreRepository(
        persistedQueue([1, 2, 1], [2, 0, 1], 0, true),
        [queueTrack(1)]
      );
      coordinator.bind(settings, repository);

      const plan = await coordinator.createRestorePlan(
        4,
        false,
        (epoch: number): boolean => epoch === 4
      );

      expect(plan?.queueTracks.length).assertEqual(2);
      expect(plan?.queueTracks[0].id).assertEqual(1);
      expect(plan?.queueTracks[1].id).assertEqual(1);
      expect(plan?.playbackPositions.join(',')).assertEqual('1,0');
      expect(plan?.currentPosition).assertEqual(0);
      expect(plan?.shuffleEnabled).assertTrue();
    });

    it('deduplicates resume writes and resets the cache when rebound', 0, () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new StaticRestoreRepository();
      coordinator.bind(settings, repository);

      coordinator.persistResumeState(3, 9000);
      coordinator.persistResumeState(3, 9000);
      expect(settings.resumeWrites.length).assertEqual(1);

      coordinator.bind(settings, repository);
      coordinator.persistResumeState(3, 9000);
      expect(settings.resumeWrites.length).assertEqual(2);
    });

    it('persists a queue cursor without rewriting the queue structure', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new StaticRestoreRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueueCurrentPosition(8);
      await coordinator.flush();

      expect(repository.cursorWrites[0]).assertEqual(8);
      expect(repository.queueWrites.length).assertEqual(0);
    });

    it('coalesces writes during an in-flight snapshot to the latest complete state', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new DeferredWriteRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueue(persistedQueue([1, 2], [0, 1], 0, false));
      coordinator.persistQueue(persistedQueue([1, 2], [1, 0], 0, true));
      coordinator.persistQueueCurrentPosition(1);
      repository.completeNext();
      await Promise.resolve();
      await Promise.resolve();

      expect(repository.queueWrites.length).assertEqual(2);
      expect(repository.queueWrites[1].shuffleEnabled).assertTrue();
      expect(repository.queueWrites[1].currentPosition).assertEqual(1);
      repository.completeNext();
      await coordinator.flush();
      expect(settings.legacyClearCount).assertEqual(1);
    });

    it('lets a later structural snapshot supersede a pending cursor write', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new DeferredWriteRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueue(persistedQueue([1, 2], [0, 1], 0, false));
      coordinator.persistQueueCurrentPosition(1);
      coordinator.persistQueue(persistedQueue([1, 2], [1, 0], 0, true));
      repository.completeNext();
      await Promise.resolve();
      await Promise.resolve();

      expect(repository.queueWrites.length).assertEqual(2);
      expect(repository.queueWrites[1].currentPosition).assertEqual(0);
      expect(repository.cursorWrites.length).assertEqual(0);
      repository.completeNext();
      await coordinator.flush();
    });

    it('attempts the latest pending snapshot after an earlier write fails', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new FailFirstWriteRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueue(persistedQueue([1], [0], 0, false));
      coordinator.persistQueue(persistedQueue([2], [0], 0, true));
      await coordinator.flush();

      expect(repository.queueWrites.length).assertEqual(2);
      expect(repository.queueWrites[1].items[0].trackId).assertEqual(2);
      expect(settings.legacyClearCount).assertEqual(1);
    });

    it('does not apply a dependent cursor after its structural snapshot fails', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new FailFirstWriteRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueue(persistedQueue([1, 2], [1, 0], 0, true));
      coordinator.persistQueueCurrentPosition(1);
      await coordinator.flush();

      expect(repository.queueWrites.length).assertEqual(1);
      expect(repository.cursorWrites.length).assertEqual(0);
      expect(settings.legacyClearCount).assertEqual(0);
    });

    it('blocks later cursor writes until a full snapshot succeeds after failure', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new FailFirstWriteRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueue(persistedQueue([1, 2], [1, 0], 0, true));
      await coordinator.flush();
      coordinator.persistQueueCurrentPosition(1);
      await coordinator.flush();

      expect(repository.queueWrites.length).assertEqual(1);
      expect(repository.cursorWrites.length).assertEqual(0);
      coordinator.persistQueue(persistedQueue([1, 2], [1, 0], 1, true));
      await coordinator.flush();
      coordinator.persistQueueCurrentPosition(0);
      await coordinator.flush();
      expect(repository.queueWrites.length).assertEqual(2);
      expect(repository.cursorWrites[0]).assertEqual(0);
    });

    it('retains a cursor update while a later snapshot recovers from failure', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new FailThenDeferWriteRepository();
      coordinator.bind(settings, repository);

      coordinator.persistQueue(persistedQueue([1], [0], 0, false));
      await coordinator.flush();
      coordinator.persistQueue(persistedQueue([2, 3], [1, 0], 0, true));
      expect(repository.queueWrites.length).assertEqual(2);
      coordinator.persistQueueCurrentPosition(1);
      repository.completeSecond();
      await coordinator.flush();

      expect(repository.cursorWrites[0]).assertEqual(1);
      expect(settings.legacyClearCount).assertEqual(1);
    });

    it('rejects a corrupted persisted permutation without clearing it', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new StaticRestoreRepository({
        items: [
          { position: 0, playbackPosition: 0, trackId: 1 },
          { position: 1, playbackPosition: 0, trackId: 2 }
        ],
        currentPosition: 0,
        shuffleEnabled: true
      }, [queueTrack(1), queueTrack(2)]);
      coordinator.bind(settings, repository);

      const plan = await coordinator.createRestorePlan(1, false, (_epoch: number): boolean => true);

      expect(plan).assertUndefined();
      expect(repository.queueWrites.length).assertEqual(0);
      expect(settings.resumeWrites.length).assertEqual(0);
    });
  });
}
