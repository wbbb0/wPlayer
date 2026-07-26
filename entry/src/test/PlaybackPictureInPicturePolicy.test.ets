import { describe, expect, it } from '@ohos/hypium';
import {
  PlaybackPictureInPicturePolicy
} from '../main/ets/playback/pip/PlaybackPictureInPicturePolicy';

export default function playbackPictureInPicturePolicyTest() {
  describe('Playback picture-in-picture policy', () => {
    it('preserves valid artwork aspect ratios with integer dimensions', 0, () => {
      const size = PlaybackPictureInPicturePolicy.contentSize(1600.4, 900.4);

      expect(size.width).assertEqual(1600);
      expect(size.height).assertEqual(900);
    });

    it('uses a square fallback when artwork dimensions are unavailable', 0, () => {
      const missingWidth = PlaybackPictureInPicturePolicy.contentSize(0, 900);
      const missingHeight = PlaybackPictureInPicturePolicy.contentSize(1600, -1);

      expect(missingWidth.width).assertEqual(missingWidth.height);
      expect(missingHeight.width).assertEqual(missingHeight.height);
    });

    it('keeps transport controls disabled until a multi-item queue is ready', 0, () => {
      expect(PlaybackPictureInPicturePolicy.transportControlsEnabled(false, 3)).assertFalse();
      expect(PlaybackPictureInPicturePolicy.transportControlsEnabled(true, 1)).assertFalse();
      expect(PlaybackPictureInPicturePolicy.transportControlsEnabled(true, 2)).assertTrue();
    });
  });
}
