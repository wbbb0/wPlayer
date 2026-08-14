import { FrameCallback } from '@kit.ArkUI';
import { describe, expect, it } from '@ohos/hypium';
import {
  DynamicBackgroundArtworkUploadState
} from '../main/ets/components/player/DynamicBackgroundArtworkUploadState';
import {
  InterruptibleScalarMotion
} from '../main/ets/components/player/InterruptibleScalarMotion';
import {
  FrameScalarMotionTimeline,
  FullPlayerImmersiveSplitFrameHost,
  FullPlayerImmersiveSplitMotion
} from '../main/ets/components/player/FullPlayerImmersiveSplitMotion';
import {
  PresentationMotionState
} from '../main/ets/components/player/PresentationMotionState';
import {
  PlayerArtworkPlaybackVisualAction,
  PlayerArtworkPlaybackVisualState,
  PlayerArtworkSourceBinding
} from '../main/ets/components/player/PlayerArtworkPlaybackVisualState';
import { PlayerMorphGeometry } from '../main/ets/components/player/PlayerMorphGeometry';
import {
  LyricsAvailability,
  PlayerStore,
  QueueEntry
} from '../main/ets/playback/model/PlaybackModels';
import {
  FullPlayerArtworkStagePolicy,
  FullPlayerImmersiveLayoutPolicy
} from '../main/ets/components/player/FullPlayerArtworkStagePolicy';
import {
  FullPlayerArtworkPagerCommandKind,
  FullPlayerArtworkPagerCoordinator,
  FullPlayerArtworkGestureSequence,
  FullPlayerArtworkPagerPhase,
  FullPlayerArtworkPagerScrollMode
} from '../main/ets/components/player/FullPlayerArtworkPagerCoordinator';
import {
  FullPlayerArtworkSlotDataSource
} from '../main/ets/components/player/FullPlayerArtworkSlotDataSource';
import {
  MiniBarResizeAction,
  PlayerMorphGesturePolicy
} from '../main/ets/components/player/PlayerMorphGesturePolicy';
import {
  FullPlayerPage,
  FullPlayerListFocusState,
  FullPlayerPagerMemory,
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

function artworkQueueEntry(id: number): QueueEntry {
  return {
    queueEntryId: id,
    track: {
      id: id,
      title: `Track ${id}`,
      artistDisplay: 'Artist',
      albumDisplay: 'Album',
      durationMs: 1000,
      smallArtworkHash: '',
      smallArtworkPath: '',
      largeArtworkHash: '',
      largeArtworkPath: '',
      artworkWidth: 600,
      artworkHeight: 600,
      palettePrimary: '#FF000000',
      paletteSecondary: '#FF000000',
      paletteAccent: '#FFFFFFFF'
    }
  };
}

class ArtworkSlotDataListener implements DataChangeListener {
  batches: Array<Array<DataOperation>> = [];

  onDataReloaded(): void {}
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}
  onDatasetChange(dataOperations: Array<DataOperation>): void {
    this.batches.push(dataOperations);
  }
}

class FakeImmersiveSplitFrameHost extends FullPlayerImmersiveSplitFrameHost {
  readonly callbacks: Array<FrameCallback> = [];

  constructor() {
    super();
  }

  postFrameCallback(callback: FrameCallback): void {
    this.callbacks.push(callback);
  }

  runFrame(index: number, frameTimeInNano: number): void {
    this.callbacks[index].onFrame(frameTimeInNano);
  }
}

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

    it('defers playback artwork motion until opening completes', 0, () => {
      const state = new PlayerArtworkPlaybackVisualState();
      state.reset(0);

      expect(state.updateTarget(1, PlayerMorphPhase.OPENING)).assertEqual(
        PlayerArtworkPlaybackVisualAction.NONE
      );
      expect(state.value()).assertEqual(0);

      expect(state.updatePhase(PlayerMorphPhase.OPEN)).assertEqual(
        PlayerArtworkPlaybackVisualAction.ANIMATE_TO_TARGET
      );
      expect(state.value()).assertEqual(1);
    });

    it('coalesces playback changes while artwork morphing is active', 0, () => {
      const state = new PlayerArtworkPlaybackVisualState();
      state.reset(0);

      expect(state.updateTarget(1, PlayerMorphPhase.OPENING)).assertEqual(
        PlayerArtworkPlaybackVisualAction.NONE
      );
      expect(state.updateTarget(0, PlayerMorphPhase.OPENING)).assertEqual(
        PlayerArtworkPlaybackVisualAction.NONE
      );
      expect(state.updatePhase(PlayerMorphPhase.OPEN)).assertEqual(
        PlayerArtworkPlaybackVisualAction.NONE
      );
      expect(state.value()).assertEqual(0);
    });

    it('animates playback artwork changes immediately after opening', 0, () => {
      const state = new PlayerArtworkPlaybackVisualState();
      state.reset(1);

      expect(state.updateTarget(0, PlayerMorphPhase.OPEN)).assertEqual(
        PlayerArtworkPlaybackVisualAction.ANIMATE_TO_TARGET
      );
      expect(state.value()).assertEqual(0);
      expect(state.updatePhase(PlayerMorphPhase.CLOSING)).assertEqual(
        PlayerArtworkPlaybackVisualAction.NONE
      );
    });

    it('uses hero artwork only for pages sharing the current artwork identity', 0, () => {
      const binding = new PlayerArtworkSourceBinding();
      binding.sync('current-hash', 'artwork/current.webp', 7);

      expect(binding.matches('current-hash', 'artwork/renamed.webp')).assertTrue();
      expect(binding.matches('other-hash', 'artwork/current.webp')).assertFalse();
      expect(binding.actorRevision(12, 'current-hash', 'artwork/current.webp'))
        .assertEqual(15);
      expect(binding.actorRevision(12, 'current-hash', 'artwork/current.webp', false))
        .assertEqual(24);
      expect(binding.actorRevision(12, 'other-hash', 'artwork/other.webp'))
        .assertEqual(24);
    });

    it('publishes a new current artwork source only when hero revision advances', 0, () => {
      const binding = new PlayerArtworkSourceBinding();
      binding.sync('first-hash', 'artwork/first.webp', 3);
      binding.sync('second-hash', 'artwork/second.webp', 3);
      expect(binding.matches('first-hash', 'artwork/first.webp')).assertTrue();
      expect(binding.matches('second-hash', 'artwork/second.webp')).assertFalse();

      binding.sync('second-hash', 'artwork/second.webp', 4);
      expect(binding.matches('second-hash', 'artwork/second.webp')).assertTrue();
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

    it('restores independent single-pane and dual-pane page memories', 0, () => {
      const memory = new FullPlayerPagerMemory();
      expect(memory.restore(1)).assertEqual(FullPlayerPage.COVER);
      expect(FullPlayerPagerSpec.DEFAULT_TWO_PANE_PAGE).assertEqual(FullPlayerPage.LYRICS);
      expect(memory.restore(2)).assertEqual(
        FullPlayerPagerSpec.positionForPage(FullPlayerPage.LYRICS, 2)
      );

      memory.commitSettled(FullPlayerPage.LYRICS, 1);
      expect(memory.restore(1)).assertEqual(FullPlayerPage.LYRICS);
      expect(memory.restore(2)).assertEqual(
        FullPlayerPagerSpec.positionForPage(FullPlayerPage.LYRICS, 2)
      );

      memory.commitSettled(0, 2);
      expect(memory.restore(1)).assertEqual(FullPlayerPage.LYRICS);
      expect(memory.restore(2)).assertEqual(0);
    });

    it('activates only pages inside the settled full-player viewport', 0, () => {
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.QUEUE, FullPlayerPage.QUEUE, 1
      )).assertTrue();
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.COVER, FullPlayerPage.QUEUE, 1
      )).assertFalse();
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.QUEUE, FullPlayerPage.QUEUE, 2
      )).assertTrue();
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.COVER, FullPlayerPage.QUEUE, 2
      )).assertTrue();
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.LYRICS, FullPlayerPage.QUEUE, 2
      )).assertFalse();
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.COVER, FullPlayerPage.LYRICS, 2
      )).assertTrue();
      expect(FullPlayerPagerSpec.pageIsInActiveViewport(
        FullPlayerPage.LYRICS, FullPlayerPage.LYRICS, 2
      )).assertTrue();
    });

    it('detects a side page as soon as it enters the presentation viewport', 0, () => {
      expect(FullPlayerPagerSpec.pageViewportVisibility(
        FullPlayerPage.LYRICS, FullPlayerPage.COVER, 1
      )).assertEqual(0);
      expect(FullPlayerPagerSpec.pageViewportVisibility(
        FullPlayerPage.LYRICS, FullPlayerPage.COVER + 0.01, 1
      ) > 0).assertTrue();
      expect(FullPlayerPagerSpec.pageViewportVisibility(
        FullPlayerPage.QUEUE, FullPlayerPage.COVER, 1
      )).assertEqual(0);
      expect(FullPlayerPagerSpec.pageViewportVisibility(
        FullPlayerPage.QUEUE, FullPlayerPage.COVER - 0.01, 1
      ) > 0).assertTrue();
    });

    it('waits for list layout before immediate focus and animates the first follow-up', 0, () => {
      const focusState = new FullPlayerListFocusState();
      expect(focusState.canSynchronizeImmediately(true, 4, 10)).assertFalse();
      expect(focusState.consumeFollowAnimation(true)).assertTrue();
      focusState.markLayoutReady();
      expect(focusState.canSynchronizeImmediately(true, 4, 10)).assertTrue();
      focusState.completeImmediateFocus();
      expect(focusState.canSynchronizeImmediately(true, 4, 10)).assertFalse();
      expect(focusState.consumeFollowAnimation(true)).assertTrue();
      focusState.reset();
      expect(focusState.canSynchronizeImmediately(false, 4, 10)).assertFalse();
      expect(focusState.canSynchronizeImmediately(true, -1, 10)).assertFalse();
      expect(focusState.canSynchronizeImmediately(true, 4, 0)).assertFalse();
      expect(focusState.canSynchronizeImmediately(true, 4, 10)).assertTrue();
      expect(focusState.consumeFollowAnimation(true)).assertTrue();
    });

    it('does not change pager memory until a settle is committed', 0, () => {
      const memory = new FullPlayerPagerMemory();
      memory.commitSettled(FullPlayerPage.QUEUE, 1);
      const interruptedSinglePaneTarget = FullPlayerPage.LYRICS;
      const interruptedDualPaneTarget = 0;
      expect(interruptedSinglePaneTarget).assertEqual(FullPlayerPage.LYRICS);
      expect(interruptedDualPaneTarget).assertEqual(0);
      expect(memory.restore(1)).assertEqual(FullPlayerPage.QUEUE);
      expect(memory.restore(2)).assertEqual(1);
    });

    it('uses shared morph geometry only while the cover owns the viewport', 0, () => {
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(
        FullPlayerPage.QUEUE, 1
      )).assertFalse();
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(
        FullPlayerPage.COVER, 1
      )).assertTrue();
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(
        FullPlayerPage.LYRICS, 1
      )).assertFalse();
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(0.49, 1)).assertFalse();
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(0.5, 1)).assertTrue();
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(0, 2)).assertTrue();
      expect(FullPlayerPagerSpec.usesSharedMorphGeometry(1, 2)).assertTrue();
    });

    it('keeps non-shared morph geometry at its source with a short translated fade', 0, () => {
      expect(PlayerMorphVisualSpec.morphGeometryProgress(
        PlayerMorphPhase.OPENING, 0.4, false
      )).assertEqual(0);
      expect(PlayerMorphVisualSpec.morphGeometryProgress(
        PlayerMorphPhase.CLOSING, 0.4, false
      )).assertEqual(0);
      expect(PlayerMorphVisualSpec.morphGeometryProgress(
        PlayerMorphPhase.OPEN, 0.4, false
      )).assertEqual(1);
      expect(PlayerMorphVisualSpec.morphGeometryProgress(
        PlayerMorphPhase.OPENING, 0.4, true
      )).assertEqual(0.4);
      expect(PlayerMorphVisualSpec.NON_SHARED_POSITION_FRACTION).assertEqual(0.1);
      expect(PlayerMorphVisualSpec.morphPositionProgress(
        PlayerMorphPhase.OPENING, 0.5, false
      )).assertEqual(0.05);
      expect(PlayerMorphVisualSpec.morphPositionProgress(
        PlayerMorphPhase.CLOSING, 1, false
      )).assertEqual(0.1);
      expect(PlayerMorphVisualSpec.morphPositionProgress(
        PlayerMorphPhase.OPENING, 0.4, true
      )).assertEqual(0.4);
      expect(PlayerMorphVisualSpec.morphPositionProgress(
        PlayerMorphPhase.OPEN, 0.4, false
      )).assertEqual(1);
      expect(PlayerMorphVisualSpec.coverElementOpacity(
        PlayerMorphPhase.OPENING, FullPlayerPage.LYRICS, 1, 0.4, false
      )).assertEqual(0.6);
      expect(PlayerMorphVisualSpec.coverElementOpacity(
        PlayerMorphPhase.CLOSING, FullPlayerPage.QUEUE, 1, 0.4, false
      )).assertEqual(0.6);
      expect(PlayerMorphVisualSpec.coverElementOpacity(
        PlayerMorphPhase.OPENING, FullPlayerPage.LYRICS, 1, 0.4, true
      )).assertEqual(1);
      expect(PlayerMorphVisualSpec.coverElementOpacity(
        PlayerMorphPhase.OPEN, FullPlayerPage.LYRICS, 1, 1, false
      )).assertEqual(0);
      expect(PlayerMorphVisualSpec.coverElementOpacity(
        PlayerMorphPhase.OPEN, FullPlayerPage.COVER, 1, 1, false
      )).assertEqual(1);
    });

    it('keeps presentation tracking separate from observable render progress', 0, () => {
      const motion = new InterruptibleScalarMotion(0.4);
      expect(motion.value()).assertEqual(0.4);
      expect(motion.isActive()).assertFalse();
      motion.setValue(0.65);
      expect(motion.value()).assertEqual(0.65);
    });

    it('starts frame-driven split motion at the exact presentation value', 0, () => {
      const timeline = new FrameScalarMotionTimeline(
        0.25,
        1,
        400,
        (fraction: number): number => fraction
      );
      const first = timeline.sample(1_000_000_000);
      const middle = timeline.sample(1_200_000_000);
      const last = timeline.sample(1_400_000_000);
      expect(first.value).assertEqual(0.25);
      expect(first.finished).assertFalse();
      expect(middle.value).assertEqual(0.625);
      expect(middle.finished).assertFalse();
      expect(last.value).assertEqual(1);
      expect(last.finished).assertTrue();
    });

    it('keeps the resolved split target while presentation is mid-motion', 0, () => {
      const frameHost = new FakeImmersiveSplitFrameHost();
      const motion = new FullPlayerImmersiveSplitMotion(0);
      motion.animate(frameHost, 1, 400);
      frameHost.runFrame(0, 1_000_000_000);
      frameHost.runFrame(1, 1_200_000_000);
      expect(motion.progress > 0 && motion.progress < 1).assertTrue();
      expect(motion.resolvedTarget()).assertEqual(1);
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        2,
        LyricsAvailability.LOADING,
        motion.resolvedTarget()
      )).assertEqual(1);
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

    it('keeps immersive artwork adaptive inside the full-player safe rectangle', 0, () => {
      const landscape = FullPlayerArtworkStagePolicy.immersiveFrame(
        { x: 0, y: 0, width: 360, height: 720 }, 24, 20, 800, 400
      );
      const portrait = FullPlayerArtworkStagePolicy.immersiveFrame(
        { x: 0, y: 0, width: 360, height: 720 }, 24, 20, 400, 800
      );
      expect(landscape.width / landscape.height).assertEqual(2);
      expect(portrait.width / portrait.height).assertEqual(0.5);
      expect(landscape.x >= 20).assertTrue();
      expect(portrait.y >= 44).assertTrue();
    });

    it('limits artwork paging input to the scaled visible artwork frame', 0, () => {
      const frame = FullPlayerArtworkStagePolicy.scaledFrame(
        { x: 10, y: 20, width: 200, height: 100 },
        0.8
      );
      expect(frame.x).assertEqual(30);
      expect(frame.y).assertEqual(30);
      expect(frame.width).assertEqual(160);
      expect(frame.height).assertEqual(80);
    });

    it('keeps artwork pager slots stable when only queue selection changes', 0, () => {
      const source = new FullPlayerArtworkSlotDataSource();
      const listener = new ArtworkSlotDataListener();
      source.registerDataChangeListener(listener);
      source.syncCount(3);
      const firstSlot = source.getData(0);
      const currentSlot = source.getData(1);
      expect(listener.batches.length).assertEqual(1);
      expect(listener.batches[0][0].type).assertEqual(DataOperationType.RELOAD);

      source.syncCount(3);
      expect(listener.batches.length).assertEqual(1);
      expect(source.getData(0)).assertEqual(firstSlot);
      expect(source.getData(1)).assertEqual(currentSlot);
    });

    it('keeps the ready pager behind the closing morph actor until its image is ready', 0, () => {
      expect(FullPlayerArtworkStagePolicy.shouldShowPager(
        PlayerMorphPhase.OPEN, true, false, false
      )).assertTrue();
      expect(FullPlayerArtworkStagePolicy.shouldShowPager(
        PlayerMorphPhase.CLOSE_DRAGGING, true, true, false
      )).assertTrue();
      expect(FullPlayerArtworkStagePolicy.shouldShowPager(
        PlayerMorphPhase.CLOSING, true, true, true
      )).assertFalse();
      expect(FullPlayerArtworkStagePolicy.shouldShowPager(
        PlayerMorphPhase.OPENING, false, false, false
      )).assertFalse();
    });

    it('keeps only a transparent morph actor resident outside active transitions', 0, () => {
      expect(FullPlayerArtworkStagePolicy.morphActorOpacity(
        PlayerMorphPhase.IDLE, false, 1
      )).assertEqual(0);
      expect(FullPlayerArtworkStagePolicy.shouldMountPager(
        PlayerMorphPhase.IDLE
      )).assertFalse();
      expect(FullPlayerArtworkStagePolicy.morphActorOpacity(
        PlayerMorphPhase.OPENING, false, 0.75
      )).assertEqual(0.75);
      expect(FullPlayerArtworkStagePolicy.morphActorOpacity(
        PlayerMorphPhase.OPEN, true, 1
      )).assertEqual(0);
      expect(FullPlayerArtworkStagePolicy.shouldMountPager(
        PlayerMorphPhase.OPEN
      )).assertTrue();
      expect(FullPlayerArtworkStagePolicy.shouldEnableMorphActorInteraction(
        PlayerMorphPhase.IDLE, false
      )).assertFalse();
      expect(FullPlayerArtworkStagePolicy.shouldEnableMorphActorInteraction(
        PlayerMorphPhase.OPEN, true
      )).assertFalse();
      expect(FullPlayerArtworkStagePolicy.shouldEnableMorphActorInteraction(
        PlayerMorphPhase.OPENING, false
      )).assertTrue();
      expect(FullPlayerArtworkStagePolicy.shouldPreloadAdjacentArtwork(
        PlayerMorphPhase.OPENING, true
      )).assertFalse();
      expect(FullPlayerArtworkStagePolicy.shouldPreloadAdjacentArtwork(
        PlayerMorphPhase.OPEN, false
      )).assertFalse();
      expect(FullPlayerArtworkStagePolicy.shouldPreloadAdjacentArtwork(
        PlayerMorphPhase.OPEN, true
      )).assertTrue();
      expect(FullPlayerArtworkStagePolicy.shouldApplyPagerEdgeMasks(false)).assertFalse();
      expect(FullPlayerArtworkStagePolicy.shouldApplyPagerEdgeMasks(true)).assertTrue();
      expect(PlayerLayoutSpec.FULL_PLAYER_ARTWORK_PAGE_GAP >
        PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET).assertTrue();
    });

    it('reveals only the current artwork page from the active readiness generation', 0, () => {
      const first = artworkQueueEntry(101);
      const second = artworkQueueEntry(102);
      const third = artworkQueueEntry(103);
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize([first, second, third], 1);
      const generation = coordinator.readyGeneration;
      expect(coordinator.pagerVisible).assertFalse();
      expect(coordinator.onPageReady(second.queueEntryId, generation - 1)).assertFalse();
      expect(coordinator.onPageReady(first.queueEntryId, generation)).assertFalse();
      expect(coordinator.onPageReady(second.queueEntryId, generation)).assertTrue();
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.IDLE);
      expect(coordinator.pagerVisible).assertTrue();
    });

    it('selects a user-settled page once and treats the synchronous queue callback as ack', 0, () => {
      const first = artworkQueueEntry(101);
      const second = artworkQueueEntry(102);
      const entries = [first, second];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(first.queueEntryId, coordinator.readyGeneration);
      coordinator.onAnimationStart(entries, 1);
      const selection = coordinator.onAnimationEnd(entries, 1);
      expect(selection.kind).assertEqual(FullPlayerArtworkPagerCommandKind.SELECT_ENTRY);
      expect(selection.queueEntryId).assertEqual(second.queueEntryId);
      const ack = coordinator.onQueueIndexChanged(entries, 1);
      expect(ack.kind).assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.IDLE);
    });

    it('animates adjacent external changes normally and distant changes quickly', 0, () => {
      const entries = [
        artworkQueueEntry(101), artworkQueueEntry(102),
        artworkQueueEntry(103), artworkQueueEntry(104)
      ];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      const adjacent = coordinator.onQueueIndexChanged(entries, 1);
      expect(adjacent.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(adjacent.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.DEFAULT);
      coordinator.onAnimationEnd(entries, 1);
      const distant = coordinator.onQueueIndexChanged(entries, 3);
      expect(distant.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(distant.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.FAST);
    });

    it('treats the repeat-all queue boundary as an adjacent programmatic page', 0, () => {
      const entries = [
        artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)
      ];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 2);
      coordinator.onPageReady(entries[2].queueEntryId, coordinator.readyGeneration);
      const wrapped = coordinator.onQueueIndexChanged(entries, 0, true);
      expect(wrapped.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(wrapped.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.DEFAULT);
    });

    it('serializes programmatic scrolls and continues to the latest external target', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      const first = coordinator.onQueueIndexChanged(entries, 1);
      expect(first.queueEntryId).assertEqual(entries[1].queueEntryId);
      expect(coordinator.isMotionActive()).assertTrue();
      const queued = coordinator.onQueueIndexChanged(entries, 2);
      expect(queued.kind).assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      const continuation = coordinator.onAnimationEnd(entries, 1);
      expect(continuation.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(continuation.queueEntryId).assertEqual(entries[2].queueEntryId);
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.PROGRAMMATIC);
      expect(coordinator.isMotionActive()).assertTrue();
      expect(coordinator.onAnimationEnd(entries, 2).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.IDLE);
      expect(coordinator.isMotionActive()).assertFalse();
    });

    it('collapses rapid programmatic changes to the latest target', 0, () => {
      const entries = [
        artworkQueueEntry(101), artworkQueueEntry(102),
        artworkQueueEntry(103), artworkQueueEntry(104)
      ];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onQueueIndexChanged(entries, 1);
      expect(coordinator.onQueueIndexChanged(entries, 2).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.onQueueIndexChanged(entries, 3).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      const continuation = coordinator.onAnimationEnd(entries, 1);
      expect(continuation.queueEntryId).assertEqual(entries[3].queueEntryId);
      expect(continuation.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.FAST);
    });

    it('clears or reverses a queued target when playback changes again', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onQueueIndexChanged(entries, 1);
      coordinator.onQueueIndexChanged(entries, 2);
      coordinator.onQueueIndexChanged(entries, 1);
      expect(coordinator.onAnimationEnd(entries, 1).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.IDLE);

      const reverseCoordinator = new FullPlayerArtworkPagerCoordinator();
      reverseCoordinator.initialize(entries, 0);
      reverseCoordinator.onPageReady(entries[0].queueEntryId, reverseCoordinator.readyGeneration);
      reverseCoordinator.onQueueIndexChanged(entries, 1);
      reverseCoordinator.onQueueIndexChanged(entries, 0);
      const reverse = reverseCoordinator.onAnimationEnd(entries, 1);
      expect(reverse.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(reverse.queueEntryId).assertEqual(entries[0].queueEntryId);
      expect(reverse.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.DEFAULT);
    });

    it('invalidates a queued programmatic target when the projection changes', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onQueueIndexChanged(entries, 1);
      coordinator.onQueueIndexChanged(entries, 2);
      const reordered = [entries[2], entries[0], entries[1]];
      const reanchor = coordinator.onProjectionChanged(reordered, 1);
      expect(reanchor.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(reanchor.queueEntryId).assertEqual(entries[0].queueEntryId);
      expect(reanchor.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.NONE);
      expect(coordinator.onAnimationEnd(reordered, 2).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR);
    });

    it('lets a user gesture take over a running programmatic scroll', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onQueueIndexChanged(entries, 2);
      expect(coordinator.allowsUserSwipe()).assertTrue();
      coordinator.onUserGesture();
      expect(coordinator.acceptsAnimationEnd(entries, 2)).assertFalse();
      expect(coordinator.onAnimationEnd(entries, 2).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      coordinator.onAnimationStart(entries, 1);
      expect(coordinator.acceptsAnimationEnd(entries, 1)).assertTrue();
      const selection = coordinator.onAnimationEnd(entries, 1);
      expect(selection.kind).assertEqual(FullPlayerArtworkPagerCommandKind.SELECT_ENTRY);
      expect(selection.queueEntryId).assertEqual(entries[1].queueEntryId);
    });

    it('samples only one swipe callback from each touch sequence', 0, () => {
      const sequence = new FullPlayerArtworkGestureSequence();
      sequence.onTouchDown();
      expect(sequence.consumeSwipeFrame()).assertTrue();
      expect(sequence.consumeSwipeFrame()).assertFalse();
      sequence.onAnimationEnd();
      expect(sequence.consumeSwipeFrame()).assertFalse();
      sequence.onTouchDown();
      expect(sequence.consumeSwipeFrame()).assertTrue();
      sequence.onTouchEnd();
      sequence.onAnimationEnd();
      expect(sequence.consumeSwipeFrame()).assertTrue();
    });

    it('lets a completed user page win over an external change during settling', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onAnimationStart(entries, 1);
      expect(coordinator.onQueueIndexChanged(entries, 2).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      const selection = coordinator.onAnimationEnd(entries, 1);
      expect(selection.kind).assertEqual(FullPlayerArtworkPagerCommandKind.SELECT_ENTRY);
      expect(selection.queueEntryId).assertEqual(entries[1].queueEntryId);
    });

    it('does not reselect when playback already reached the user-settled page', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onAnimationStart(entries, 1);
      coordinator.onQueueIndexChanged(entries, 1);
      expect(coordinator.onAnimationEnd(entries, 1).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.phase).assertEqual(FullPlayerArtworkPagerPhase.IDLE);
    });

    it('consumes the latest external change when a user gesture returns to its original page', 0, () => {
      const entries = [artworkQueueEntry(101), artworkQueueEntry(102), artworkQueueEntry(103)];
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize(entries, 0);
      coordinator.onPageReady(entries[0].queueEntryId, coordinator.readyGeneration);
      coordinator.onAnimationStart(entries, 1);
      coordinator.onQueueIndexChanged(entries, 2);
      const command = coordinator.onAnimationEnd(entries, 0);
      expect(command.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(command.queueEntryId).assertEqual(entries[2].queueEntryId);
      expect(command.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.FAST);
    });

    it('invalidates stale settle and ready callbacks when the queue projection changes', 0, () => {
      const first = artworkQueueEntry(101);
      const second = artworkQueueEntry(102);
      const third = artworkQueueEntry(103);
      const coordinator = new FullPlayerArtworkPagerCoordinator();
      coordinator.initialize([first, second, third], 0);
      coordinator.onPageReady(first.queueEntryId, coordinator.readyGeneration);
      coordinator.onAnimationStart([first, second, third], 1);
      const previousGeneration = coordinator.readyGeneration;
      const reordered = [second, first, third];
      const reanchor = coordinator.onProjectionChanged(reordered, 1);
      expect(reanchor.kind).assertEqual(FullPlayerArtworkPagerCommandKind.CHANGE_INDEX);
      expect(reanchor.scrollMode).assertEqual(FullPlayerArtworkPagerScrollMode.NONE);
      expect(coordinator.onAnimationEnd(reordered, 0).kind)
        .assertEqual(FullPlayerArtworkPagerCommandKind.NONE);
      expect(coordinator.onPageReady(first.queueEntryId, previousGeneration)).assertFalse();
      expect(coordinator.onPageReady(first.queueEntryId, coordinator.readyGeneration)).assertFalse();
      expect(coordinator.onReanchorApplied(
        first.queueEntryId, coordinator.readyGeneration
      )).assertTrue();
    });

    it('keeps vertical shadow overflow outside the horizontal pager clip', 0, () => {
      const viewport: PlayerFrame = { x: 20, y: 40, width: 320, height: 400 };
      const clip = FullPlayerArtworkStagePolicy.shadowSafePagerFrame(
        viewport, 52, 28
      );
      expect(clip.x).assertEqual(viewport.x);
      expect(clip.width).assertEqual(viewport.width);
      expect(clip.y).assertEqual(-12);
      expect(clip.height).assertEqual(532);
    });

    it('fits immersive artwork inside a selected pane viewport', 0, () => {
      const full = FullPlayerArtworkStagePolicy.immersiveFrameInViewport(
        { x: 0, y: 0, width: 800, height: 600 }, 24, 20, 800, 800
      );
      const split = FullPlayerArtworkStagePolicy.immersiveFrameInViewport(
        { x: 0, y: 0, width: 400, height: 600 }, 24, 20, 800, 800
      );
      expect(split.width < full.width).assertTrue();
      expect(split.x + split.width <= 400).assertTrue();
      expect(split.y >= 44).assertTrue();
    });

    it('freezes the resolved immersive split while lyrics are loading', 0, () => {
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        2, LyricsAvailability.LOADING, 1
      )).assertEqual(1);
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        2, LyricsAvailability.UNAVAILABLE, 1
      )).assertEqual(0);
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        2, LyricsAvailability.AVAILABLE, 0
      )).assertEqual(1);
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        1, LyricsAvailability.AVAILABLE, 1
      )).assertEqual(0);
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        2, LyricsAvailability.AVAILABLE, 1, false
      )).assertEqual(0);
      expect(FullPlayerImmersiveLayoutPolicy.splitTarget(
        2, LyricsAvailability.LOADING, 1, false
      )).assertEqual(0);
    });

    it('moves a dual-pane immersive entry from queue-cover to cover-lyrics', 0, () => {
      expect(FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        0, 2, LyricsAvailability.AVAILABLE, 0
      )).assertEqual(1);
      expect(FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        0, 2, LyricsAvailability.UNAVAILABLE, 1
      )).assertEqual(0);
      expect(FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        1, 1, LyricsAvailability.AVAILABLE, 1
      )).assertEqual(1);
      expect(FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        0, 2, LyricsAvailability.LOADING, 1
      )).assertEqual(1);
      expect(FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        0, 2, LyricsAvailability.LOADING, 0
      )).assertEqual(0);
      expect(FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        0, 2, LyricsAvailability.AVAILABLE, 1, false
      )).assertEqual(0);
    });

    it('publishes lyrics availability only when the resolved state changes', 0, () => {
      const store = new PlayerStore();
      let notifications = 0;
      store.addLyricsAvailabilityListener((_availability: LyricsAvailability): void => {
        notifications += 1;
      });
      store.setLyricsAvailability(LyricsAvailability.LOADING);
      store.setLyricsAvailability(LyricsAvailability.LOADING);
      store.setLyricsAvailability(LyricsAvailability.UNAVAILABLE);
      expect(notifications).assertEqual(2);
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
