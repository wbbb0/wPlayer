import { describe, expect, it } from '@ohos/hypium';
import { PlayerState } from '../main/ets/playback/model/PlaybackModels';
import { OutputReconnectPolicy } from '../main/ets/playback/support/OutputReconnectPolicy';

export default function outputReconnectPolicyTest() {
  describe('Audio output reconnect policy', () => {
    it('records and consumes a pending resume for playback intent', 0, () => {
      const policy = new OutputReconnectPolicy();

      expect(policy.recordOutputUnavailable(true, true, PlayerState.PLAYING)).assertTrue();
      expect(policy.hasPendingResume()).assertTrue();
      expect(policy.shouldResume(true, PlayerState.PAUSED)).assertTrue();
      expect(policy.shouldResume(true, PlayerState.PAUSED)).assertFalse();
    });

    it('does not resume when playback was already paused', 0, () => {
      const policy = new OutputReconnectPolicy();

      expect(policy.recordOutputUnavailable(true, false, PlayerState.PAUSED)).assertFalse();
      expect(policy.hasPendingResume()).assertFalse();
      expect(policy.shouldResume(true, PlayerState.PAUSED)).assertFalse();
    });

    it('clears pending resume after explicit user intent changes', 0, () => {
      const policy = new OutputReconnectPolicy();

      policy.recordOutputUnavailable(true, true, PlayerState.PLAYING);
      policy.clear();
      expect(policy.hasPendingResume()).assertFalse();
      expect(policy.shouldResume(true, PlayerState.PAUSED)).assertFalse();
    });

    it('consumes pending resume without playing when state is no longer recoverable', 0, () => {
      const policy = new OutputReconnectPolicy();

      policy.recordOutputUnavailable(true, true, PlayerState.PLAYING);
      expect(policy.shouldResume(true, PlayerState.IDLE)).assertFalse();
      expect(policy.hasPendingResume()).assertFalse();
    });
  });
}
