import { describe, expect, it } from '@ohos/hypium';
import {
  AudioRecoveryAction,
  PlaybackAudioRecoveryCoordinator
} from '../main/ets/playback/coordinator/PlaybackAudioRecoveryCoordinator';
import { PlaybackMediaCoordinator } from '../main/ets/playback/coordinator/PlaybackMediaCoordinator';
import {
  PlaybackPersistenceCoordinator,
  PlaybackPersistenceSettings,
  PlaybackRestoreBasePlan,
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
  queueWrites: Array<string> = [];

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

  setPlaybackQueue(trackIds: Array<number>, currentTrackId: number): void {
    this.queueWrites.push(`${trackIds.join(',')}:${currentTrackId}`);
  }
}

class StaticRestoreRepository implements PlaybackRestoreRepository {
  private readonly responses: Array<Array<QueueTrack>>;

  constructor(responses: Array<Array<QueueTrack>>) {
    this.responses = responses;
  }

  getPlaybackQueueTracks(_trackIds: Array<number>): Promise<Array<QueueTrack>> {
    return Promise.resolve(this.responses.shift() ?? []);
  }
}

class DeferredRestoreRepository implements PlaybackRestoreRepository {
  private resolveLookup?: (tracks: Array<QueueTrack>) => void;

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

    it('normalizes persisted resume positions at playback boundaries', 0, () => {
      expect(PlaybackPersistenceCoordinator.validResumePosition(4999, 120000)).assertEqual(0);
      expect(PlaybackPersistenceCoordinator.validResumePosition(5000, 120000)).assertEqual(5000);
      expect(PlaybackPersistenceCoordinator.validResumePosition(111000, 120000)).assertEqual(0);
      expect(PlaybackPersistenceCoordinator.validResumePosition(60000, 120000)).assertEqual(60000);
    });

    it('rejects a stale restore after the current-track lookup completes', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      const repository = new DeferredRestoreRepository();
      settings.lastTrackId = 1;
      coordinator.bind(settings);
      let currentEpoch = 1;

      const pending = coordinator.createRestoreBasePlan(
        repository,
        currentEpoch,
        (epoch: number): boolean => epoch === currentEpoch
      );
      currentEpoch = 2;
      repository.resolve([queueTrack(1)]);

      expect(await pending).assertUndefined();
      expect(settings.resumeWrites.length).assertEqual(0);
      expect(settings.queueWrites.length).assertEqual(0);
    });

    it('clears persisted state when the restored current track is missing', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      settings.lastTrackId = 7;
      coordinator.bind(settings);

      const plan = await coordinator.createRestoreBasePlan(
        new StaticRestoreRepository([[]]),
        1,
        (_epoch: number): boolean => true
      );

      expect(plan).assertUndefined();
      expect(settings.resumeWrites[0]).assertEqual('-1:0');
      expect(settings.queueWrites[0]).assertEqual(':-1');
    });

    it('restores persisted order while filtering tracks that no longer exist', 0, async () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const base = new PlaybackRestoreBasePlan([1, 2, 3], queueTrack(2), 5000);

      const plan = await coordinator.completeRestorePlan(
        new StaticRestoreRepository([[queueTrack(1)]]),
        base,
        4,
        (epoch: number): boolean => epoch === 4
      );

      expect(plan?.queueTracks.length).assertEqual(2);
      expect(plan?.queueTracks[0].id).assertEqual(1);
      expect(plan?.queueTracks[1].id).assertEqual(2);
      expect(plan?.resumePositionMs).assertEqual(5000);
    });

    it('deduplicates resume writes and resets the cache when rebound', 0, () => {
      const coordinator = new PlaybackPersistenceCoordinator();
      const settings = new FakePlaybackSettings();
      coordinator.bind(settings);

      coordinator.persistResumeState(3, 9000);
      coordinator.persistResumeState(3, 9000);
      expect(settings.resumeWrites.length).assertEqual(1);

      coordinator.bind(settings);
      coordinator.persistResumeState(3, 9000);
      expect(settings.resumeWrites.length).assertEqual(2);
    });
  });
}
