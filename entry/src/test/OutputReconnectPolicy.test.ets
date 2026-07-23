import { describe, expect, it } from '@ohos/hypium';
import { PlayerState } from '../main/ets/playback/model/PlaybackModels';
import { OutputReconnectPolicy } from '../main/ets/playback/support/OutputReconnectPolicy';

export default function outputReconnectPolicyTest() {
  describe('Audio output reconnect policy', () => {
    it('records and consumes a pending resume for playback intent', 0, () => {
      const policy = new OutputReconnectPolicy();

      expect(policy.recordOutputUnavailable(true, true, PlayerState.PLAYING, true, 1000)).assertTrue();
      expect(policy.hasPendingResume()).assertTrue();
      expect(policy.shouldResume(true, PlayerState.PAUSED, 300000, 2000)).assertTrue();
      expect(policy.shouldResume(true, PlayerState.PAUSED, 300000, 2000)).assertFalse();
    });

    it('does not resume when playback was already paused', 0, () => {
      const policy = new OutputReconnectPolicy();

      expect(policy.recordOutputUnavailable(true, false, PlayerState.PAUSED)).assertFalse();
      expect(policy.hasPendingResume()).assertFalse();
      expect(policy.shouldResume(true, PlayerState.PAUSED)).assertFalse();
    });

    it('does not record pending resume when automatic resume is disabled', 0, () => {
      const policy = new OutputReconnectPolicy();

      expect(policy.recordOutputUnavailable(true, true, PlayerState.PLAYING, false, 1000)).assertFalse();
      expect(policy.hasPendingResume()).assertFalse();
      expect(policy.shouldResume(true, PlayerState.PAUSED, 300000, 2000)).assertFalse();
    });

    it('clears pending resume after explicit user intent changes', 0, () => {
      const policy = new OutputReconnectPolicy();

      policy.recordOutputUnavailable(true, true, PlayerState.PLAYING, true, 1000);
      policy.clear();
      expect(policy.hasPendingResume()).assertFalse();
      expect(policy.shouldResume(true, PlayerState.PAUSED)).assertFalse();
    });

    it('expires pending resume after the configured reconnect window', 0, () => {
      const policy = new OutputReconnectPolicy();

      policy.recordOutputUnavailable(true, true, PlayerState.PLAYING, true, 1000);
      expect(policy.shouldResume(true, PlayerState.PAUSED, 300000, 301001)).assertFalse();
      expect(policy.hasPendingResume()).assertFalse();
    });

    it('keeps loading playback recoverable inside the reconnect window', 0, () => {
      const policy = new OutputReconnectPolicy();

      policy.recordOutputUnavailable(true, true, PlayerState.LOADING, true, 1000);
      expect(policy.shouldResume(true, PlayerState.LOADING, 300000, 2000)).assertTrue();
    });

    it('consumes pending resume without playing when state is no longer recoverable', 0, () => {
      const policy = new OutputReconnectPolicy();

      policy.recordOutputUnavailable(true, true, PlayerState.PLAYING, true, 1000);
      expect(policy.shouldResume(true, PlayerState.IDLE)).assertFalse();
      expect(policy.hasPendingResume()).assertFalse();
    });
  });
}
