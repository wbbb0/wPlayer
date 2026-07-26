import { describe, expect, it } from '@ohos/hypium';
import {
  DynamicBackgroundArtworkUploadState
} from '../main/ets/components/player/DynamicBackgroundArtworkUploadState';
import { PlayerMorphGeometry } from '../main/ets/components/player/PlayerMorphGeometry';
import {
  MiniBarResizeAction,
  PlayerMorphGesturePolicy
} from '../main/ets/components/player/PlayerMorphGesturePolicy';
import {
  MiniPlayerGestureRegion,
  PlayerFrame,
  PlayerGestureAxis,
  PlayerMorphPhase
} from '../main/ets/components/player/PlayerMotion';

export default function playerMorphPolicyTest() {
  describe('Player morph policies', () => {
    it('keeps only the newest artwork upload eligible to reach native rendering', 0, () => {
      const state = new DynamicBackgroundArtworkUploadState();
      state.attachContext();
      const first = state.begin('artwork:first');

      state.noteDesiredKey('artwork:second');
      expect(state.canCommit(first, 'artwork:second', true, true)).assertFalse();
      expect(state.finish(first)).assertTrue();

      const second = state.begin('artwork:second');
      expect(state.canCommit(second, 'artwork:second', true, true)).assertTrue();
      state.markUploaded(second);
      expect(state.finish(second)).assertFalse();
      expect(state.needsUpload('artwork:second')).assertFalse();
    });

    it('invalidates an in-flight upload when the native surface is replaced', 0, () => {
      const state = new DynamicBackgroundArtworkUploadState();
      state.attachContext();
      const obsolete = state.begin('artwork:one');

      state.attachContext();
      expect(state.canCommit(obsolete, 'artwork:one', true, true)).assertFalse();
      expect(state.hasUploadInProgress()).assertFalse();
      expect(state.needsUpload('artwork:one')).assertTrue();
    });

    it('separates axis locking and mini-bar resize intent from animation effects', 0, () => {
      expect(PlayerMorphGesturePolicy.resolveAxis(
        PlayerGestureAxis.UNDECIDED, 3, 2
      )).assertEqual(PlayerGestureAxis.UNDECIDED);
      expect(PlayerMorphGesturePolicy.resolveAxis(
        PlayerGestureAxis.UNDECIDED, 20, 5
      )).assertEqual(PlayerGestureAxis.HORIZONTAL);
      expect(PlayerMorphGesturePolicy.miniBarResizeAction(
        MiniPlayerGestureRegion.ARTWORK, false, -200
      )).assertEqual(MiniBarResizeAction.EXPAND);
      expect(PlayerMorphGesturePolicy.miniBarResizeAction(
        MiniPlayerGestureRegion.PLAYBACK_BUTTON, true, 200
      )).assertEqual(MiniBarResizeAction.COLLAPSE);
    });

    it('uses frozen geometry until the morph reaches the open phase', 0, () => {
      const root: PlayerFrame = { x: 0, y: 0, width: 800, height: 1200 };
      const frozen: PlayerFrame = { x: 0, y: 0, width: 400, height: 800 };
      expect(PlayerMorphGeometry.fullPlayerFrame(
        PlayerMorphPhase.OPENING, root, frozen
      ).width).assertEqual(400);
      expect(PlayerMorphGeometry.fullPlayerFrame(
        PlayerMorphPhase.OPEN, root, frozen
      ).width).assertEqual(800);
      expect(PlayerMorphGeometry.morphValue(10, 20, 1.5)).assertEqual(20);
    });
  });
}
