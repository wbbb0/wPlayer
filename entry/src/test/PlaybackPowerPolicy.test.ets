import { describe, expect, it } from '@ohos/hypium';
import {
  PlaybackPowerPolicy,
  PERIODIC_PROGRESS_PERSIST_INTERVAL_MS
} from '../main/ets/playback/support/PlaybackPowerPolicy';

export default function playbackPowerPolicyTest() {
  describe('Playback power policy', () => {
    it('does not persist periodic progress while playback is inactive', 0, () => {
      expect(PlaybackPowerPolicy.shouldPersistProgress(
        false,
        PERIODIC_PROGRESS_PERSIST_INTERVAL_MS * 2,
        0
      )).assertFalse();
    });

    it('persists playing progress only after the low-frequency interval', 0, () => {
      const lastWriteAt = 1000;
      expect(PlaybackPowerPolicy.shouldPersistProgress(
        true,
        lastWriteAt + PERIODIC_PROGRESS_PERSIST_INTERVAL_MS - 1,
        lastWriteAt
      )).assertFalse();
      expect(PlaybackPowerPolicy.shouldPersistProgress(
        true,
        lastWriteAt + PERIODIC_PROGRESS_PERSIST_INTERVAL_MS,
        lastWriteAt
      )).assertTrue();
    });

    it('suppresses duplicate resume-state writes', 0, () => {
      expect(PlaybackPowerPolicy.resumeStateChanged(7, 30000, 7, 30000)).assertFalse();
      expect(PlaybackPowerPolicy.resumeStateChanged(7, 31000, 7, 30000)).assertTrue();
      expect(PlaybackPowerPolicy.resumeStateChanged(8, 30000, 7, 30000)).assertTrue();
    });
  });
}
