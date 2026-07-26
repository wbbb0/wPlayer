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
  FullPlayerPagerPhase,
  FullPlayerPagerSpec,
  MiniPlayerGestureRegion,
  PlayerLayoutSpec,
  PlayerMotionSpec,
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
      const root: PlayerFrame = { x: 48, y: 72, width: 800, height: 1200 };
      const frozen: PlayerFrame = { x: 12, y: 16, width: 400, height: 800 };
      expect(PlayerMorphGeometry.fullPlayerFrame(
        PlayerMorphPhase.OPENING, root, frozen
      ).width).assertEqual(400);
      const openFrame = PlayerMorphGeometry.fullPlayerFrame(
        PlayerMorphPhase.OPEN, root, frozen
      );
      expect(openFrame.width).assertEqual(800);
      expect(openFrame.x).assertEqual(0);
      expect(openFrame.y).assertEqual(0);
      expect(PlayerMorphGeometry.morphValue(10, 20, 1.5)).assertEqual(20);
    });

    it('keeps a paused artwork preview at its visual rest size', 0, () => {
      expect(PlayerMotionSpec.artworkContextPreviewAnimationEndScale(
        PlayerMotionSpec.PAUSED_ARTWORK_SCALE
      )).assertEqual(
        PlayerMotionSpec.ARTWORK_CONTEXT_PREVIEW_END_SCALE /
          PlayerMotionSpec.PAUSED_ARTWORK_SCALE
      );
    });

    it('maps playback artwork motion to its final visual states', 0, () => {
      const pausedProgress = PlayerMotionSpec.artworkPlaybackVisualTarget(false);
      const activeProgress = PlayerMotionSpec.artworkPlaybackVisualTarget(true);
      expect(pausedProgress).assertEqual(0);
      expect(activeProgress).assertEqual(1);
      expect(PlayerMotionSpec.artworkPlaybackVisualValue(
        PlayerMotionSpec.PAUSED_ARTWORK_SCALE,
        1,
        pausedProgress
      )).assertEqual(PlayerMotionSpec.PAUSED_ARTWORK_SCALE);
      expect(PlayerMotionSpec.artworkPlaybackVisualValue(
        PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_RADIUS,
        PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS,
        activeProgress
      )).assertEqual(PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS);
    });

    it('does not restart a page drag while the previous settle is active', 0, () => {
      expect(FullPlayerPagerSpec.canBeginGesture(
        PlayerMorphPhase.OPEN,
        FullPlayerPagerPhase.SETTLED
      )).assertTrue();
      expect(FullPlayerPagerSpec.canBeginGesture(
        PlayerMorphPhase.OPEN,
        FullPlayerPagerPhase.SETTLING
      )).assertFalse();
      expect(FullPlayerPagerSpec.canBeginGesture(
        PlayerMorphPhase.OPENING,
        FullPlayerPagerPhase.SETTLED
      )).assertFalse();
    });

    it('uses enlarged playback targets in both full-player layouts', 0, () => {
      expect(PlayerMotionSpec.FULL_PLAYER_CONTENT_COLOR).assertEqual('#FFFFFFFF');
      expect(PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE % 8).assertEqual(0);
      expect(PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_BUTTON_SIZE % 8).assertEqual(0);
      expect(PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE).assertEqual(72);
      expect(PlayerLayoutSpec.FULL_PLAYBACK_ICON_SIZE).assertEqual(50);
      expect(PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_BUTTON_SIZE).assertEqual(64);
      expect(PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_ICON_SIZE).assertEqual(40);
      expect(PlayerLayoutSpec.ULTRA_COMPACT_CONTROL_RAIL_WIDTH)
        .assertEqual(PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_BUTTON_SIZE);
      expect(PlayerLayoutSpec.ultraCompactArtworkSize(326, 326, 0, 0))
        .assertEqual(222);
      expect(PlayerLayoutSpec.fullArtworkSize(360, 600, 0, 0, 1))
        .assertEqual(282);
      expect(PlayerLayoutSpec.targetPlaybackIconSize(64)).assertEqual(40);
      expect(PlayerLayoutSpec.targetPlaybackIconSize(72)).assertEqual(50);
    });
  });
}
