import { HdsBarStyle, HdsTabsController } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { vibrator } from '@kit.SensorServiceKit';
import { systemBarStyleController } from '../../appearance/SystemBarStyleController';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { LayoutLength } from '../layout/LayoutLength';
import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec,
  PlayerPoint
} from './PlayerMotion';
import { MiniPlayerBinding } from './MiniPlayerBinding';

export interface ResponsiveLayoutChange {
  previousWideLayout: boolean;
  nextWideLayout: boolean;
}

@Observed
export class PlayerMorphController {
  readonly miniPlayerBinding: MiniPlayerBinding = new MiniPlayerBinding();
  playerExpandProgress: number = 0;
  playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  swipeHapticTriggered: boolean = false;
  playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  playerMorphBackgroundOpacity: number = 1;
  fullPlayerPage: FullPlayerPage = FullPlayerPage.COVER;
  fullPlayerPagePosition: number = FullPlayerPage.COVER;
  frozenMorphArtwork: image.PixelMap | undefined = undefined;
  frozenMorphArtworkUri: string = '';
  frozenMorphArtworkPreferPixelMap: boolean = false;
  frozenMorphArtworkWidth: number = 0;
  frozenMorphArtworkHeight: number = 0;
  morphArtworkSourceFrozen: boolean = false;
  rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  frozenRootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  artworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  centeredArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  frozenArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  private returnToExpandedMiniBar: boolean = false;
  private fullPlayerGestureStartPosition: number = FullPlayerPage.COVER;
  private morphTransitionEpoch: number = 0;
  private lifecycleEpoch: number = 0;
  private attached: boolean = false;
  private uiContext?: UIContext;
  private readonly playerStore: PlayerStore;
  private readonly compactTabsController: HdsTabsController;

  constructor(playerStore: PlayerStore, compactTabsController: HdsTabsController) {
    this.playerStore = playerStore;
    this.compactTabsController = compactTabsController;
  }

  get miniBarExpanded(): boolean {
    return this.miniPlayerBinding.expanded;
  }

  set miniBarExpanded(expanded: boolean) {
    this.miniPlayerBinding.expanded = expanded;
  }

  get miniPlayerOffsetX(): number {
    return this.miniPlayerBinding.offsetX;
  }

  set miniPlayerOffsetX(offsetX: number) {
    this.miniPlayerBinding.offsetX = offsetX;
  }

  get measuredMiniPlayerFrame(): PlayerFrame {
    return this.miniPlayerBinding.measuredFrame;
  }

  set measuredMiniPlayerFrame(frame: PlayerFrame) {
    this.miniPlayerBinding.measuredFrame = frame;
  }

  attach(uiContext: UIContext): void {
    this.lifecycleEpoch += 1;
    this.attached = true;
    this.uiContext = uiContext;
  }

  dispose(): void {
    this.attached = false;
    this.lifecycleEpoch += 1;
    this.morphTransitionEpoch += 1;
    this.playerMorphPhase = PlayerMorphPhase.IDLE;
    this.playerExpandProgress = 0;
    this.playerMorphBackgroundOpacity = 1;
    this.miniPlayerBinding.sourceVisible = true;
    this.releaseMorphArtworkSource();
    this.uiContext = undefined;
  }

  private context(): UIContext {
    if (this.uiContext === undefined) {
      throw new Error('PlayerMorphController is not attached to a UIContext');
    }
    return this.uiContext;
  }

  clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  usesWideLayout(width: number = this.rootFrame.width): boolean {
    return width >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT;
  }

  fullPlayerPaneCount(width: number = this.rootFrame.width,
    height: number = this.rootFrame.height): number {
    return FullPlayerPagerSpec.paneCount(width, height);
  }

  fullPlayerPageSpan(): number {
    return FullPlayerPagerSpec.pageSpan(this.fullPlayerFrame().width, this.renderedFullPlayerPaneCount());
  }

  reconcileFullPlayerPager(previousPaneCount: number, nextPaneCount: number): void {
    if (previousPaneCount === nextPaneCount) {
      return;
    }
    this.fullPlayerPagePosition = FullPlayerPagerSpec.positionForPage(
      this.fullPlayerPage,
      nextPaneCount
    );
  }

  updateRootFrame(newValue: Area): ResponsiveLayoutChange {
    const previousWideLayout = this.usesWideLayout();
    const previousPlayerPaneCount = this.fullPlayerPaneCount();
    const nextWidth = LayoutLength.toNumber(newValue.width, this.rootFrame.width);
    const nextHeight = LayoutLength.toNumber(newValue.height, this.rootFrame.height);
    this.rootFrame = {
      x: LayoutLength.toNumber(newValue.globalPosition.x, this.rootFrame.x),
      y: LayoutLength.toNumber(newValue.globalPosition.y, this.rootFrame.y),
      width: nextWidth,
      height: nextHeight
    };
    const nextWideLayout = this.usesWideLayout(nextWidth);
    const nextPlayerPaneCount = this.fullPlayerPaneCount(nextWidth, nextHeight);
    this.reconcileFullPlayerPager(previousPlayerPaneCount, nextPlayerPaneCount);
    if (previousWideLayout !== nextWideLayout) {
      this.miniBarExpanded = nextWideLayout;
    }
    return { previousWideLayout, nextWideLayout };
  }

  freezeMiniPlayerGeometry(captureReturnStyle: boolean = true): void {
    if (captureReturnStyle) {
      this.returnToExpandedMiniBar = this.miniBarExpanded;
    }
    try {
      const uiContext = this.context();
      const componentUtils = uiContext.getComponentUtils();
      const miniPlayerRectangle = componentUtils.getRectangleById('mini_player_surface');
      const rootRectangle = componentUtils.getRectangleById('player_page_root');
      const wideLayout = this.usesWideLayout(uiContext.px2vp(rootRectangle.size.width));
      const sourceHostId = wideLayout ?
        'wide_mini_player_hds_host' : 'player_tabs_compact_content_host';
      const sourceHostRectangle = componentUtils.getRectangleById(sourceHostId);
      const horizontalMargin = uiContext.vp2px(AppShellLayoutSpec.COMPACT_SIDE_MARGIN);
      const bottomMargin = uiContext.vp2px(AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN);
      const visibleMiniPlayerX = wideLayout || this.miniBarExpanded ?
        sourceHostRectangle.windowOffset.x +
          (sourceHostRectangle.size.width - miniPlayerRectangle.size.width) / 2 :
        sourceHostRectangle.windowOffset.x + sourceHostRectangle.size.width -
          miniPlayerRectangle.size.width - horizontalMargin;
      const visibleMiniPlayerY = sourceHostRectangle.windowOffset.y + sourceHostRectangle.size.height -
        miniPlayerRectangle.size.height - bottomMargin;
      this.frozenMiniPlayerFrame = {
        x: uiContext.px2vp(visibleMiniPlayerX - rootRectangle.windowOffset.x),
        y: uiContext.px2vp(visibleMiniPlayerY - rootRectangle.windowOffset.y),
        width: uiContext.px2vp(miniPlayerRectangle.size.width),
        height: uiContext.px2vp(miniPlayerRectangle.size.height)
      };
      this.frozenRootFrame = {
        x: 0,
        y: 0,
        width: uiContext.px2vp(rootRectangle.size.width),
        height: uiContext.px2vp(rootRectangle.size.height)
      };
      this.freezeArtworkTargetForCurrentPage();
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to query mini player geometry: ${businessError.code}, ${businessError.message}`);
      this.frozenMiniPlayerFrame = {
        x: this.measuredMiniPlayerFrame.x - this.rootFrame.x,
        y: this.measuredMiniPlayerFrame.y - this.rootFrame.y,
        width: this.measuredMiniPlayerFrame.width,
        height: this.measuredMiniPlayerFrame.height
      };
      this.frozenRootFrame = {
        x: 0,
        y: 0,
        width: this.rootFrame.width,
        height: this.rootFrame.height
      };
      this.freezeArtworkTargetForCurrentPage();
    }
  }

  syncSystemBarContentColor(): void {
    systemBarStyleController.setPlayerContentColor(
      this.isMorphActive(),
      this.playerStore.themeOnPrimary()
    );
  }

  private freezeArtworkTargetForCurrentPage(): void {
    const usesSidePageProxy = this.fullPlayerPaneCount() === 1 &&
      Math.abs(this.fullPlayerPagePosition - FullPlayerPage.COVER) > 0.5;
    const target = usesSidePageProxy ? this.centeredArtworkTarget : this.currentPagerArtworkTarget();
    this.frozenArtworkTarget = { x: target.x, y: target.y };
  }

  private freezeMorphArtworkSource(): void {
    this.releaseMorphArtworkSource();
    this.frozenMorphArtwork = this.playerStore.heroArtwork;
    this.frozenMorphArtworkUri = this.playerStore.heroArtworkUri;
    this.frozenMorphArtworkPreferPixelMap = this.playerStore.heroArtworkPreferPixelMap;
    this.frozenMorphArtworkWidth = this.playerStore.currentTrack?.artworkWidth ?? 0;
    this.frozenMorphArtworkHeight = this.playerStore.currentTrack?.artworkHeight ?? 0;
    this.morphArtworkSourceFrozen = true;
    if (this.frozenMorphArtworkPreferPixelMap) {
      playbackRuntime.retainArtwork(this.frozenMorphArtwork);
    }
  }

  private releaseMorphArtworkSource(): void {
    if (this.morphArtworkSourceFrozen && this.frozenMorphArtworkPreferPixelMap) {
      playbackRuntime.releaseArtwork(this.frozenMorphArtwork);
    }
    this.morphArtworkSourceFrozen = false;
    this.frozenMorphArtwork = undefined;
    this.frozenMorphArtworkUri = '';
    this.frozenMorphArtworkPreferPixelMap = false;
    this.frozenMorphArtworkWidth = 0;
    this.frozenMorphArtworkHeight = 0;
  }

  morphArtworkSource(): image.PixelMap | ResourceStr {
    if (this.morphArtworkSourceFrozen) {
      if (this.frozenMorphArtworkPreferPixelMap && this.frozenMorphArtwork !== undefined) {
        return this.frozenMorphArtwork;
      }
      if (this.frozenMorphArtworkUri.length > 0) {
        return this.frozenMorphArtworkUri;
      }
    } else {
      if (this.playerStore.heroArtworkPreferPixelMap && this.playerStore.heroArtwork !== undefined) {
        return this.playerStore.heroArtwork;
      }
      if (this.playerStore.heroArtworkUri.length > 0) {
        return this.playerStore.heroArtworkUri;
      }
    }
    return $r('app.media.default_album_cover');
  }

  morphArtworkSourceWidth(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkWidth :
      (this.playerStore.currentTrack?.artworkWidth ?? 0);
  }

  morphArtworkSourceHeight(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkHeight :
      (this.playerStore.currentTrack?.artworkHeight ?? 0);
  }

  morphValue(start: number, end: number): number {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    return start + (end - start) * progress;
  }

  fullPlayerFrame(): PlayerFrame {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ? this.rootFrame : this.frozenRootFrame;
  }

  renderedFullPlayerPaneCount(): number {
    const frame = this.fullPlayerFrame();
    return FullPlayerPagerSpec.paneCount(frame.width, frame.height);
  }

  fullPlayerArtworkTarget(): PlayerPoint {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ?
      this.currentPagerArtworkTarget() : this.frozenArtworkTarget;
  }

  private currentPagerArtworkTarget(): PlayerPoint {
    return {
      x: FullPlayerPagerSpec.pagerArtworkTargetX(
        this.centeredArtworkTarget.x,
        this.fullPlayerPagePosition,
        this.fullPlayerPageSpan()
      ),
      y: this.centeredArtworkTarget.y
    };
  }

  handleBackPress(): boolean {
    if (!this.isMorphActive()) {
      return false;
    }
    this.hideFullPlayer();
    return true;
  }

  isMorphActive(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.IDLE;
  }

  private beginMorphPhase(phase: PlayerMorphPhase): number {
    this.morphTransitionEpoch += 1;
    this.playerMorphPhase = phase;
    this.miniPlayerBinding.sourceVisible = false;
    this.syncSystemBarContentColor();
    return this.morphTransitionEpoch;
  }

  private isCurrentMorphTransition(epoch: number): boolean {
    return this.attached && epoch === this.morphTransitionEpoch;
  }

  private isCurrentLifecycle(epoch: number): boolean {
    return this.attached && epoch === this.lifecycleEpoch;
  }

  private morphVerticalTravelDistance(): number {
    return Math.max(1, this.frozenMiniPlayerFrame.y - this.frozenRootFrame.y);
  }

  private morphGestureCompletionProgress(): number {
    return Math.min(
      PlayerMotionSpec.GESTURE_COMPLETION_FRACTION,
      PlayerMotionSpec.GESTURE_COMPLETION_MAX_DISTANCE / this.morphVerticalTravelDistance()
    );
  }

  private beginMorphBackgroundHandoff(epoch: number): void {
    if (!this.isCurrentMorphTransition(epoch)) {
      return;
    }
    this.playerMorphPhase = PlayerMorphPhase.BACKGROUND_HANDOFF;
    this.context().animateTo({
      duration: PlayerMotionSpec.BACKGROUND_HANDOFF_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        this.playerMorphPhase = PlayerMorphPhase.IDLE;
        this.miniPlayerBinding.sourceVisible = true;
        this.syncSystemBarContentColor();
        this.playerMorphBackgroundOpacity = 1;
        this.releaseMorphArtworkSource();
      }
    }, () => {
      this.playerMorphBackgroundOpacity = 0;
    });
  }

  private triggerSwipeHaptic(): void {
    const effectId: string = 'haptic.effect.soft';
    try {
      if (!vibrator.isSupportEffectSync(effectId)) {
        return;
      }
      vibrator.startVibration({
        type: 'preset',
        effectId: effectId,
        count: 1,
        intensity: 35
      }, {
        id: 0,
        usage: 'touch'
      }).catch((error: BusinessError) => {
        console.warn(`Mini player haptic failed: ${error.code}, ${error.message}`);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Mini player haptic unavailable: ${businessError.code}, ${businessError.message}`);
    }
  }

  beginMiniPlayerGesture(): void {
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
  }

  updateMiniPlayerGesture(event: GestureEvent): void {
    const horizontalDistance = Math.abs(event.offsetX);
    const verticalDistance = Math.abs(event.offsetY);
    if (this.playerGestureAxis === PlayerGestureAxis.UNDECIDED &&
      Math.max(horizontalDistance, verticalDistance) > PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE) {
      this.playerGestureAxis = horizontalDistance > verticalDistance ?
        PlayerGestureAxis.HORIZONTAL : PlayerGestureAxis.VERTICAL;
    }
    if (this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL) {
      const horizontalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetX);
      const renderDistance = Math.abs(horizontalOffset);
      this.miniPlayerOffsetX = horizontalOffset /
        (1 + renderDistance / PlayerMotionSpec.HORIZONTAL_SWIPE_RESISTANCE);
      const reachedActionPoint = Math.abs(this.miniPlayerOffsetX) >=
        PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
      if (reachedActionPoint && !this.swipeHapticTriggered) {
        this.swipeHapticTriggered = true;
        this.triggerSwipeHaptic();
      }
      return;
    }
    if (this.playerGestureAxis === PlayerGestureAxis.VERTICAL) {
      if (!this.isMorphActive()) {
        this.freezeMiniPlayerGeometry();
        this.freezeMorphArtworkSource();
        this.beginMorphPhase(PlayerMorphPhase.OPEN_DRAGGING);
        this.playerMorphBackgroundOpacity = 1;
      }
      const verticalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetY);
      const upwardDistance = Math.max(0, -verticalOffset);
      this.playerExpandProgress = this.clamp(
        upwardDistance / this.morphVerticalTravelDistance(),
        0,
        1
      );
    }
  }

  finishMiniPlayerGesture(): void {
    const wasVerticalGesture = this.playerGestureAxis === PlayerGestureAxis.VERTICAL;
    const wasHorizontalGesture = this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL;
    const swipeOffset = this.miniPlayerOffsetX;
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
    this.swipeHapticTriggered = false;
    if (wasHorizontalGesture) {
      const shouldChangeTrack = Math.abs(swipeOffset) >=
        PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
      const lifecycleEpoch = this.lifecycleEpoch;
      this.context().animateTo({
        duration: PlayerMotionSpec.CANCEL_DURATION,
        curve: Curve.EaseOut,
        onFinish: () => {
          if (!this.isCurrentLifecycle(lifecycleEpoch) || !shouldChangeTrack) {
            return;
          }
          if (swipeOffset < 0) {
            playbackRuntime.next();
          } else {
            playbackRuntime.previous();
          }
        }
      }, () => {
        this.miniPlayerOffsetX = 0;
      });
      return;
    }
    if (!wasVerticalGesture) {
      this.miniPlayerOffsetX = 0;
      return;
    }
    const shouldExpand = this.playerExpandProgress >= this.morphGestureCompletionProgress();
    const duration = shouldExpand ? PlayerMotionSpec.OPEN_DURATION : PlayerMotionSpec.CANCEL_DURATION;
    const epoch = this.beginMorphPhase(
      shouldExpand ? PlayerMorphPhase.OPENING : PlayerMorphPhase.CLOSING
    );
    this.context().animateTo({
      duration,
      curve: shouldExpand ? curves.springMotion(
        PlayerMotionSpec.OPEN_SPRING_RESPONSE,
        PlayerMotionSpec.OPEN_SPRING_DAMPING
      ) : Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        if (shouldExpand) {
          this.playerMorphPhase = PlayerMorphPhase.OPEN;
          this.releaseMorphArtworkSource();
        } else {
          this.beginMorphBackgroundHandoff(epoch);
        }
      }
    }, () => {
      this.miniPlayerOffsetX = 0;
      this.playerExpandProgress = shouldExpand ? 1 : 0;
    });
  }

  showFullPlayer(): void {
    if (!this.miniBarExpanded) {
      this.compactTabsController.applyMiniBarStyle(HdsBarStyle.EXPAND);
      return;
    }
    this.freezeMiniPlayerGeometry();
    this.freezeMorphArtworkSource();
    const epoch = this.beginMorphPhase(PlayerMorphPhase.OPENING);
    this.playerMorphBackgroundOpacity = 1;
    this.context().animateTo({
      duration: PlayerMotionSpec.OPEN_DURATION,
      curve: curves.springMotion(
        PlayerMotionSpec.OPEN_SPRING_RESPONSE,
        PlayerMotionSpec.OPEN_SPRING_DAMPING
      ),
      onFinish: () => {
        if (this.isCurrentMorphTransition(epoch)) {
          this.playerMorphPhase = PlayerMorphPhase.OPEN;
          this.releaseMorphArtworkSource();
        }
      }
    }, () => {
      this.playerExpandProgress = 1;
    });
  }

  hideFullPlayer(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.IDLE ||
      this.playerMorphPhase === PlayerMorphPhase.CLOSING ||
      this.playerMorphPhase === PlayerMorphPhase.BACKGROUND_HANDOFF) {
      return;
    }
    this.restoreReturnMiniBarStyle();
    this.freezeMiniPlayerGeometry(false);
    this.freezeMorphArtworkSource();
    this.animateFullPlayerClose();
  }

  private restoreReturnMiniBarStyle(): void {
    if (this.miniBarExpanded === this.returnToExpandedMiniBar) {
      return;
    }
    this.compactTabsController.applyMiniBarStyle(
      this.returnToExpandedMiniBar ? HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE
    );
  }

  private animateFullPlayerClose(): void {
    const epoch = this.beginMorphPhase(PlayerMorphPhase.CLOSING);
    this.context().animateTo({
      duration: PlayerMotionSpec.CLOSE_DURATION,
      curve: curves.cubicBezierCurve(
        PlayerMotionSpec.CLOSE_CURVE_X1,
        PlayerMotionSpec.CLOSE_CURVE_Y1,
        PlayerMotionSpec.CLOSE_CURVE_X2,
        PlayerMotionSpec.CLOSE_CURVE_Y2
      ),
      onFinish: () => {
        this.beginMorphBackgroundHandoff(epoch);
      }
    }, () => {
      this.playerExpandProgress = 0;
    });
  }

  beginFullPlayerHorizontalGesture(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.OPEN) {
      this.fullPlayerGestureStartPosition = this.fullPlayerPagePosition;
    }
  }

  updateFullPlayerHorizontalGesture(event: GestureEvent): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    const pageSpan = Math.max(1, this.fullPlayerPageSpan());
    const horizontalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetX);
    this.fullPlayerPagePosition = FullPlayerPagerSpec.clampPosition(
      this.fullPlayerGestureStartPosition - horizontalOffset / pageSpan,
      this.fullPlayerPaneCount()
    );
  }

  finishFullPlayerHorizontalGesture(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.OPEN) {
      this.finishFullPlayerPageGesture();
    }
  }

  beginFullPlayerVerticalGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    this.freezeMiniPlayerGeometry(false);
    this.freezeMorphArtworkSource();
    this.beginMorphPhase(PlayerMorphPhase.CLOSE_DRAGGING);
    this.playerMorphBackgroundOpacity = 1;
  }

  updateFullPlayerVerticalGesture(event: GestureEvent): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.CLOSE_DRAGGING) {
      return;
    }
    const verticalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetY);
    const downwardDistance = Math.max(0, verticalOffset);
    this.playerExpandProgress = 1 - this.clamp(
      downwardDistance / this.morphVerticalTravelDistance(),
      0,
      1
    );
  }

  finishFullPlayerVerticalGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.CLOSE_DRAGGING) {
      return;
    }
    const shouldClose = this.playerExpandProgress <= 1 - this.morphGestureCompletionProgress();
    if (shouldClose) {
      this.restoreReturnMiniBarStyle();
      this.animateFullPlayerClose();
      return;
    }
    const epoch = this.beginMorphPhase(PlayerMorphPhase.OPENING);
    this.context().animateTo({
      duration: PlayerMotionSpec.CLOSE_CANCEL_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        this.playerMorphPhase = PlayerMorphPhase.OPEN;
        this.releaseMorphArtworkSource();
      }
    }, () => {
      this.playerExpandProgress = 1;
    });
  }

  private finishFullPlayerPageGesture(): void {
    const paneCount = this.fullPlayerPaneCount();
    const pageSpan = Math.max(1, this.fullPlayerPageSpan());
    const movement = this.fullPlayerPagePosition - this.fullPlayerGestureStartPosition;
    let targetPosition = Math.round(this.fullPlayerGestureStartPosition);
    if (Math.abs(movement) * pageSpan >= FullPlayerPagerSpec.swipeCompletionDistance(pageSpan)) {
      targetPosition += movement > 0 ? 1 : -1;
    }
    targetPosition = FullPlayerPagerSpec.clampPosition(targetPosition, paneCount);
    this.fullPlayerPage = FullPlayerPagerSpec.nearestPage(targetPosition, paneCount);
    this.context().animateTo({
      curve: curves.springMotion(
        FullPlayerPagerSpec.PAGE_SETTLE_SPRING_RESPONSE,
        FullPlayerPagerSpec.PAGE_SETTLE_SPRING_DAMPING
      )
    }, () => {
      this.fullPlayerPagePosition = targetPosition;
    });
  }

  navigateFullPlayerPage(page: FullPlayerPage): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    const paneCount = this.fullPlayerPaneCount();
    const targetPosition = FullPlayerPagerSpec.positionForPage(page, paneCount);
    if (Math.abs(this.fullPlayerPagePosition - targetPosition) < 0.0001) {
      return;
    }
    this.fullPlayerPage = page;
    this.context().animateTo({
      curve: curves.springMotion(
        FullPlayerPagerSpec.PAGE_SETTLE_SPRING_RESPONSE,
        FullPlayerPagerSpec.PAGE_SETTLE_SPRING_DAMPING
      )
    }, () => {
      this.fullPlayerPagePosition = targetPosition;
    });
  }
}
