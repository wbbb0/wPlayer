import { describe, expect, it } from '@ohos/hypium';
import {
  DynamicBackgroundArtworkUploadState
} from '../main/ets/components/player/DynamicBackgroundArtworkUploadState';
import {
  InterruptibleScalarMotion
} from '../main/ets/components/player/InterruptibleScalarMotion';
import {
  PresentationMotionState
} from '../main/ets/components/player/PresentationMotionState';
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
  PlayerLyricFocusPolicy,
  PlayerMotionSpec,
  PlayerFrame,
  PlayerGestureAxis,
  PlayerMorphPhase,
  PlayerMorphInteractionSpec,
  PlayerMorphVisualSpec
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

    it('suspends background rendering only while the full player is stably open', 0, () => {
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.IDLE
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.OPENING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.OPEN_DRAGGING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.OPEN
      )).assertTrue();
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.CLOSE_DRAGGING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.CLOSING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(
        PlayerMorphPhase.BACKGROUND_HANDOFF
      )).assertFalse();
    });

    it('owns white system-bar content only while the full player is stably open', 0, () => {
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.IDLE
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.OPEN_DRAGGING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.OPENING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.OPEN
      )).assertTrue();
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.CLOSE_DRAGGING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.CLOSING
      )).assertFalse();
      expect(PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(
        PlayerMorphPhase.BACKGROUND_HANDOFF
      )).assertFalse();
    });

    it('consumes back before navigation while any full-player transition is active', 0, () => {
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.IDLE
      )).assertFalse();
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.OPEN_DRAGGING
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.OPENING
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.OPEN
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.CLOSE_DRAGGING
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.CLOSING
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.shouldConsumeBackPress(
        PlayerMorphPhase.BACKGROUND_HANDOFF
      )).assertTrue();
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

    it('allows a page drag to take over the previous settle', 0, () => {
      expect(FullPlayerPagerSpec.canBeginGesture(
        PlayerMorphPhase.OPEN,
        FullPlayerPagerPhase.SETTLED
      )).assertTrue();
      expect(FullPlayerPagerSpec.canBeginGesture(
        PlayerMorphPhase.OPEN,
        FullPlayerPagerPhase.SETTLING
      )).assertTrue();
      expect(FullPlayerPagerSpec.canBeginGesture(
        PlayerMorphPhase.OPENING,
        FullPlayerPagerPhase.SETTLED
      )).assertFalse();
    });

    it('keeps presentation tracking separate from observable render progress', 0, () => {
      const motion = new InterruptibleScalarMotion(0.4);
      expect(motion.value()).assertEqual(0.4);
      expect(motion.isActive()).assertFalse();
      motion.setValue(0.65);
      expect(motion.value()).assertEqual(0.65);
    });

    it('keeps takeover active until render settling completes', 0, () => {
      const state = new PresentationMotionState(0.2);
      state.begin(0.2);
      state.sample(0.55);
      expect(state.isRenderSettling()).assertTrue();
      state.finishTracker();
      expect(state.isRenderSettling()).assertTrue();
      expect(state.takeOver()).assertEqual(0.55);
      expect(state.isRenderSettling()).assertFalse();

      state.begin(0.4);
      state.completeRender(0);
      expect(state.value()).assertEqual(0);
      expect(state.isRenderSettling()).assertFalse();
    });

    it('allows full-player vertical drag to take over morph settling', 0, () => {
      expect(PlayerMorphInteractionSpec.canBeginFullPlayerVerticalGesture(
        PlayerMorphPhase.OPEN
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.canBeginFullPlayerVerticalGesture(
        PlayerMorphPhase.OPENING
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.canBeginFullPlayerVerticalGesture(
        PlayerMorphPhase.CLOSING
      )).assertTrue();
      expect(PlayerMorphInteractionSpec.canBeginFullPlayerVerticalGesture(
        PlayerMorphPhase.IDLE
      )).assertFalse();
      expect(PlayerMorphInteractionSpec.canBeginFullPlayerVerticalGesture(
        PlayerMorphPhase.BACKGROUND_HANDOFF
      )).assertFalse();
    });

    it('measures the fixed morph threshold from each gesture takeover point', 0, () => {
      expect(PlayerMotionSpec.MORPH_GESTURE_COMPLETION_DISTANCE).assertEqual(56);
      expect(PlayerMorphGesturePolicy.morphTargetProgress(
        0.45, 0.50, 1, 700
      )).assertEqual(1);
      expect(PlayerMorphGesturePolicy.morphTargetProgress(
        0.45, 0.36, 1, 700
      )).assertEqual(0);
      expect(PlayerMorphGesturePolicy.morphTargetProgress(
        0.45, 0.50, 0, 700
      )).assertEqual(0);
      expect(PlayerMorphGesturePolicy.morphTargetProgress(
        0.45, 0.54, 0, 700
      )).assertEqual(1);
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

    it('grades lyric blur symmetrically and suspends it during manual scrolling', 0, () => {
      const nearBlur = PlayerLayoutSpec.FULL_PLAYER_LYRIC_NEAR_BLUR_RADIUS;
      const farBlur = PlayerLayoutSpec.FULL_PLAYER_LYRIC_FAR_BLUR_RADIUS;
      const farDistance = PlayerLayoutSpec.FULL_PLAYER_LYRIC_MAX_TRANSITION_DISTANCE;
      expect(PlayerLyricFocusPolicy.blurRadius(10, 10, true)).assertEqual(0);
      expect(PlayerLyricFocusPolicy.blurRadius(9, 10, true)).assertEqual(nearBlur);
      expect(PlayerLyricFocusPolicy.blurRadius(11, 10, true)).assertEqual(nearBlur);
      expect(PlayerLyricFocusPolicy.blurRadius(12, 10, true) > nearBlur).assertTrue();
      expect(PlayerLyricFocusPolicy.blurRadius(12, 10, true) < farBlur).assertTrue();
      expect(PlayerLyricFocusPolicy.blurRadius(
        10 + farDistance, 10, true
      )).assertEqual(farBlur);
      expect(PlayerLyricFocusPolicy.blurRadius(
        10 + farDistance + 5, 10, true
      )).assertEqual(farBlur);
      expect(PlayerLyricFocusPolicy.blurRadius(11, 10, false)).assertEqual(0);
      expect(PlayerLyricFocusPolicy.blurRadius(11, -1, true)).assertEqual(0);
      expect(PlayerLayoutSpec.FULL_PLAYER_LYRIC_HORIZONTAL_PADDING >=
        PlayerLayoutSpec.FULL_PLAYER_LYRIC_FAR_BLUR_RADIUS).assertTrue();
      expect(PlayerLayoutSpec.FULL_PLAYER_LYRICS_CONTAINER_HORIZONTAL_INSET +
        PlayerLayoutSpec.FULL_PLAYER_LYRIC_HORIZONTAL_PADDING)
        .assertEqual(PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET);
      expect(PlayerLayoutSpec.FULL_PLAYER_LYRIC_LIST_SPACE).assertEqual(0);
    });
  });
}
