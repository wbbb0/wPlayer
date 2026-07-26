import { HdsBarStyle, HdsTabsController } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { vibrator } from '@kit.SensorServiceKit';
import { systemBarStyleController } from '../../appearance/SystemBarStyleController';
import { DynamicColor, DynamicContainerRole } from '../../appearance/DynamicColor';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { LayoutLength } from '../layout/LayoutLength';
import {
  FullPlayerPage,
  FullPlayerPagerPhase,
  FullPlayerPagerSpec,
  MiniPlayerGestureRegion,
  PlayerFrame,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMorphVisualSpec,
  PlayerMotionSpec,
  PlayerPoint
} from './PlayerMotion';
import { MiniPlayerBinding, PlayerDynamicBackgroundBinding } from './MiniPlayerBinding';
import { PlayerMorphGeometry } from './PlayerMorphGeometry';
import {
  MiniBarResizeAction,
  PlayerMorphGesturePolicy
} from './PlayerMorphGesturePolicy';
import { PlayerMorphTransitionCoordinator } from './PlayerMorphTransitionCoordinator';

const PLAYER_SYSTEM_BAR_OWNER = 'full_player';

export interface ResponsiveLayoutChange {
  previousWideLayout: boolean;
  nextWideLayout: boolean;
}

@Observed
export class PlayerMorphController {
  readonly miniPlayerBinding: MiniPlayerBinding = new MiniPlayerBinding();
  readonly dynamicBackgroundBinding: PlayerDynamicBackgroundBinding =
    new PlayerDynamicBackgroundBinding();
  playerExpandProgress: number = 0;
  playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  swipeHapticTriggered: boolean = false;
  playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  fullPlayerSideContentReady: boolean = false;
  playerMorphBackgroundOpacity: number = 1;
  fullPlayerPage: FullPlayerPage = FullPlayerPage.COVER;
  fullPlayerPagePosition: number = FullPlayerPage.COVER;
  fullPlayerPagerPhase: FullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
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
  playbackButtonTarget: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE,
    height: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE
  };
  frozenPlaybackButtonTarget: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE,
    height: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE
  };
  frozenMiniPlayerForeground: string = '#FFFFFFFF';
  private returnToExpandedMiniBar: boolean = false;
  private fullPlayerGestureStartPosition: number = FullPlayerPage.COVER;
  private fullPlayerPagerEpoch: number = 0;
  private miniPlayerGestureRegion: MiniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
  private miniPlayerHorizontalGestureOffset: number = 0;
  private readonly transitionCoordinator: PlayerMorphTransitionCoordinator =
    new PlayerMorphTransitionCoordinator();
  private readonly playerStore: PlayerStore;
  private readonly compactTabsController: HdsTabsController;
  private readonly condensedCompactTabsController: HdsTabsController;

  constructor(playerStore: PlayerStore, compactTabsController: HdsTabsController,
    condensedCompactTabsController: HdsTabsController) {
    this.playerStore = playerStore;
    this.compactTabsController = compactTabsController;
    this.condensedCompactTabsController = condensedCompactTabsController;
  }

  syncSystemBarContentColor(): void {
    if (this.isMorphActive()) {
      systemBarStyleController.submitContentColor(
        PLAYER_SYSTEM_BAR_OWNER,
        PlayerMotionSpec.FULL_PLAYER_CONTENT_COLOR
      );
    } else {
      systemBarStyleController.removeContentColor(PLAYER_SYSTEM_BAR_OWNER);
    }
  }

  private applyCompactMiniBarStyle(style: HdsBarStyle): void {
    this.compactTabsController.applyMiniBarStyle(style);
    this.condensedCompactTabsController.applyMiniBarStyle(style);
  }

  collapseCondensedMiniBar(): void {
    if (!this.miniBarExpanded || this.isMorphActive()) {
      return;
    }
    this.condensedCompactTabsController.applyMiniBarStyle(HdsBarStyle.COLLAPSE);
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
    this.transitionCoordinator.attach(uiContext);
  }

  dispose(): void {
    systemBarStyleController.removeContentColor(PLAYER_SYSTEM_BAR_OWNER);
    this.transitionCoordinator.dispose();
    this.playerMorphPhase = PlayerMorphPhase.IDLE;
    this.fullPlayerPagerEpoch += 1;
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
    this.fullPlayerSideContentReady = false;
    this.playerExpandProgress = 0;
    this.playerMorphBackgroundOpacity = 1;
    this.dynamicBackgroundBinding.active = false;
    this.miniPlayerBinding.sourceVisible = true;
    this.miniPlayerBinding.sourceMarqueeActive = true;
    this.releaseMorphArtworkSource();
  }

  private context(): UIContext {
    return this.transitionCoordinator.context();
  }

  clamp(value: number, minimum: number, maximum: number): number {
    return PlayerMorphGeometry.clamp(value, minimum, maximum);
  }

  usesWideLayout(width: number = this.rootFrame.width): boolean {
    return PlayerMorphGeometry.usesWideLayout(width);
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
    this.fullPlayerPagerEpoch += 1;
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
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
      if (this.isMorphActive() && !nextWideLayout) {
        this.returnToExpandedMiniBar = true;
        this.miniBarExpanded = true;
        this.applyCompactMiniBarStyle(HdsBarStyle.EXPAND);
      } else {
        this.miniBarExpanded = nextWideLayout;
      }
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
      const hostWidth = uiContext.px2vp(rootRectangle.size.width);
      const wideLayout = this.usesWideLayout(hostWidth);
      const sourceHostId = wideLayout ?
        AppShellLayoutSpec.WIDE_MINI_PLAYER_HOST_ID :
        AppShellLayoutSpec.compactTabsHostId(hostWidth);
      const sourceHostRectangle = componentUtils.getRectangleById(sourceHostId);
      const horizontalMargin = uiContext.vp2px(AppShellLayoutSpec.COMPACT_SIDE_MARGIN);
      const bottomMargin = uiContext.vp2px(AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN);
      const compactExpandedStart = uiContext.vp2px(
        AppShellLayoutSpec.compactExpandedMiniPlayerStart(
          uiContext.px2vp(sourceHostRectangle.size.width),
          uiContext.px2vp(miniPlayerRectangle.size.width)
        )
      );
      const visibleMiniPlayerX = wideLayout ?
        sourceHostRectangle.windowOffset.x + sourceHostRectangle.size.width -
          miniPlayerRectangle.size.width -
          uiContext.vp2px(AppShellLayoutSpec.WIDE_SIDE_MARGIN) :
        this.miniBarExpanded ?
        sourceHostRectangle.windowOffset.x + compactExpandedStart :
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
      this.freezePlaybackButtonTarget();
      this.freezeMiniPlayerForeground();
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
      this.freezePlaybackButtonTarget();
      this.freezeMiniPlayerForeground();
    }
  }

  private freezeMiniPlayerForeground(): void {
    this.frozenMiniPlayerForeground = DynamicColor.foreground(
      this.playerStore.themeBaseBackground,
      DynamicContainerRole.PRIMARY
    );
  }

  private freezeArtworkTargetForCurrentPage(): void {
    const paneCount = this.fullPlayerPaneCount();
    this.frozenArtworkTarget = {
      x: FullPlayerPagerSpec.frozenMorphPageTargetX(
        this.centeredArtworkTarget.x,
        FullPlayerPage.COVER,
        this.fullPlayerPagePosition,
        paneCount,
        FullPlayerPagerSpec.pageSpan(this.frozenRootFrame.width, paneCount)
      ),
      y: this.centeredArtworkTarget.y
    };
  }

  private freezePlaybackButtonTarget(): void {
    this.frozenPlaybackButtonTarget = {
      x: FullPlayerPagerSpec.frozenMorphPageTargetX(
        this.playbackButtonTarget.x,
        FullPlayerPage.COVER,
        this.fullPlayerPagePosition,
        this.fullPlayerPaneCount(),
        this.fullPlayerPageSpan()
      ),
      y: this.playbackButtonTarget.y,
      width: this.playbackButtonTarget.width,
      height: this.playbackButtonTarget.height
    };
  }

  private freezeMorphArtworkSource(): void {
    this.releaseMorphArtworkSource();
    this.frozenMorphArtwork = this.playerStore.heroArtwork;
    this.frozenMorphArtworkUri = this.playerStore.heroArtworkUri;
    this.frozenMorphArtworkPreferPixelMap = this.playerStore.heroArtworkPreferPixelMap;
    this.frozenMorphArtworkWidth = this.playerStore.currentTrack?.artworkWidth ?? 0;
    this.frozenMorphArtworkHeight = this.playerStore.currentTrack?.artworkHeight ?? 0;
    this.morphArtworkSourceFrozen = true;
  }

  private releaseMorphArtworkSource(): void {
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
      const track = this.playerStore.currentTrack;
      if (track !== undefined) {
        const artworkUri = playbackRuntime.queueArtworkUri(track.largeArtworkPath);
        if (artworkUri.length > 0) {
          return artworkUri;
        }
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
    return PlayerMorphGeometry.morphValue(start, end, this.playerExpandProgress);
  }

  fullPlayerFrame(): PlayerFrame {
    return PlayerMorphGeometry.fullPlayerFrame(
      this.playerMorphPhase,
      this.rootFrame,
      this.frozenRootFrame
    );
  }

  renderedFullPlayerPaneCount(): number {
    return PlayerMorphGeometry.paneCount(this.fullPlayerFrame());
  }

  fullPlayerArtworkTarget(): PlayerPoint {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ?
      this.currentPagerArtworkTarget() : this.frozenArtworkTarget;
  }

  miniPlaybackButtonFrame(): PlayerFrame {
    return PlayerMorphGeometry.miniPlaybackButtonFrame(this.frozenMiniPlayerFrame);
  }

  private miniPlaybackButtonVisible(): boolean {
    return this.frozenMiniPlayerFrame.width > PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE +
      PlayerLayoutSpec.MINI_PLAYBACK_BUTTON_SIZE;
  }

  morphPlaybackButtonFrame(): PlayerFrame {
    return PlayerMorphGeometry.interpolateFrame(
      this.miniPlaybackButtonFrame(),
      this.frozenPlaybackButtonTarget,
      this.playerExpandProgress
    );
  }

  morphPlaybackButtonIconSize(): number {
    return PlayerMorphGeometry.morphValue(
      PlayerLayoutSpec.MINI_PLAYBACK_ICON_SIZE,
      PlayerLayoutSpec.targetPlaybackIconSize(this.frozenPlaybackButtonTarget.width),
      this.playerExpandProgress
    );
  }

  shouldRenderPlaybackButtonProxy(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.OPEN &&
      this.miniPlaybackButtonVisible();
  }

  shouldShowFullPlaybackButton(): boolean {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ||
      !this.miniPlaybackButtonVisible();
  }

  morphPlaybackButtonOpacity(): number {
    return PlayerMorphVisualSpec.coverElementOpacity(
      this.playerMorphPhase,
      this.fullPlayerPage,
      this.fullPlayerPagePosition,
      this.renderedFullPlayerPaneCount(),
      this.playerExpandProgress
    );
  }

  morphPlaybackButtonColor(): string {
    return DynamicColor.blendOpaque(
      this.frozenMiniPlayerForeground,
      PlayerMotionSpec.FULL_PLAYER_CONTENT_COLOR,
      PlayerMotionSpec.foregroundColorProgress(this.playerExpandProgress)
    );
  }

  private currentPagerArtworkTarget(): PlayerPoint {
    return {
      x: FullPlayerPagerSpec.pagerPageTargetX(
        this.centeredArtworkTarget.x,
        FullPlayerPage.COVER,
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

  shouldRenderFullPlayerSideContent(): boolean {
    return this.fullPlayerSideContentReady;
  }

  private beginMorphPhase(phase: PlayerMorphPhase): number {
    this.fullPlayerPagerEpoch += 1;
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
    this.fullPlayerPage = FullPlayerPagerSpec.nearestPage(
      this.fullPlayerPagePosition,
      this.fullPlayerPaneCount()
    );
    const epoch = this.transitionCoordinator.beginTransition();
    this.playerMorphPhase = phase;
    this.dynamicBackgroundBinding.active = true;
    this.miniPlayerBinding.sourceVisible = false;
    this.miniPlayerBinding.sourceMarqueeActive = false;
    this.syncSystemBarContentColor();
    return epoch;
  }

  private isCurrentMorphTransition(epoch: number): boolean {
    return this.transitionCoordinator.isCurrentTransition(epoch);
  }

  private isCurrentLifecycle(epoch: number): boolean {
    return this.transitionCoordinator.isCurrentLifecycle(epoch);
  }

  private morphVerticalTravelDistance(): number {
    return PlayerMorphGeometry.verticalTravelDistance(
      this.frozenMiniPlayerFrame,
      this.frozenRootFrame
    );
  }

  private morphGestureCompletionProgress(): number {
    return PlayerMorphGeometry.gestureCompletionProgress(
      this.frozenMiniPlayerFrame,
      this.frozenRootFrame
    );
  }

  private beginMorphBackgroundHandoff(epoch: number): void {
    if (!this.isCurrentMorphTransition(epoch)) {
      return;
    }
    this.playerMorphPhase = PlayerMorphPhase.BACKGROUND_HANDOFF;
    this.miniPlayerBinding.sourceVisible = true;
    this.context().animateTo({
      duration: PlayerMotionSpec.BACKGROUND_HANDOFF_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        this.playerMorphPhase = PlayerMorphPhase.IDLE;
        this.dynamicBackgroundBinding.active = false;
        this.fullPlayerSideContentReady = false;
        this.miniPlayerBinding.sourceVisible = true;
        this.miniPlayerBinding.sourceMarqueeActive = true;
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

  beginMiniPlayerTouch(localX: number): void {
    this.miniPlayerGestureRegion = PlayerMorphGesturePolicy.miniPlayerRegion(
      localX,
      this.miniPlayerBinding.measuredFrame.width,
      this.miniBarExpanded
    );
  }

  beginMiniPlayerGesture(): void {
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
    this.miniPlayerHorizontalGestureOffset = 0;
  }

  updateMiniPlayerGesture(event: GestureEvent): void {
    this.playerGestureAxis = PlayerMorphGesturePolicy.resolveAxis(
      this.playerGestureAxis,
      event.offsetX,
      event.offsetY
    );
    if (this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL) {
      const horizontalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetX);
      this.miniPlayerHorizontalGestureOffset = horizontalOffset;
      if (this.isMiniBarResizeGesture()) {
        const reachedActionPoint = this.miniBarResizeStyle(horizontalOffset) !== undefined;
        if (reachedActionPoint && !this.swipeHapticTriggered) {
          this.swipeHapticTriggered = true;
          this.triggerSwipeHaptic();
        }
        return;
      }
      this.miniPlayerOffsetX =
        PlayerMorphGesturePolicy.resistedHorizontalOffset(horizontalOffset);
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
        this.fullPlayerSideContentReady = false;
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
      const resizeStyle = this.miniBarResizeStyle(this.miniPlayerHorizontalGestureOffset);
      if (resizeStyle !== undefined) {
        this.applyCompactMiniBarStyle(resizeStyle);
        this.miniPlayerOffsetX = 0;
        this.miniPlayerHorizontalGestureOffset = 0;
        this.miniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
        return;
      }
      const shouldChangeTrack = Math.abs(swipeOffset) >=
        PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
      const lifecycleEpoch = this.transitionCoordinator.currentLifecycle();
      this.miniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
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
        this.miniPlayerHorizontalGestureOffset = 0;
      });
      return;
    }
    this.miniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
    if (!wasVerticalGesture) {
      this.miniPlayerOffsetX = 0;
      this.miniPlayerHorizontalGestureOffset = 0;
      return;
    }
    const shouldExpand = this.playerExpandProgress >= this.morphGestureCompletionProgress();
    const duration = shouldExpand ? PlayerMotionSpec.OPEN_DURATION : PlayerMotionSpec.CANCEL_DURATION;
    const epoch = this.beginMorphPhase(
      shouldExpand ? PlayerMorphPhase.OPENING : PlayerMorphPhase.CLOSING
    );
    if (!shouldExpand) {
      this.miniPlayerBinding.sourceVisible = true;
    }
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
          this.fullPlayerSideContentReady = true;
          this.releaseMorphArtworkSource();
          playbackRuntime.onFullPlayerOpened();
        } else {
          this.beginMorphBackgroundHandoff(epoch);
        }
      }
    }, () => {
      this.miniPlayerOffsetX = 0;
      this.playerExpandProgress = shouldExpand ? 1 : 0;
    });
  }

  private isMiniBarResizeGesture(): boolean {
    return this.miniPlayerGestureRegion === MiniPlayerGestureRegion.ARTWORK ||
      this.miniPlayerGestureRegion === MiniPlayerGestureRegion.PLAYBACK_BUTTON;
  }

  private miniBarResizeStyle(horizontalOffset: number): HdsBarStyle | undefined {
    const action = PlayerMorphGesturePolicy.miniBarResizeAction(
      this.miniPlayerGestureRegion,
      this.miniBarExpanded,
      horizontalOffset
    );
    if (action === MiniBarResizeAction.EXPAND) {
      return HdsBarStyle.EXPAND;
    }
    if (action === MiniBarResizeAction.COLLAPSE) {
      return HdsBarStyle.COLLAPSE;
    }
    return undefined;
  }

  showFullPlayer(): void {
    if (!this.miniBarExpanded) {
      this.applyCompactMiniBarStyle(HdsBarStyle.EXPAND);
      return;
    }
    this.freezeMiniPlayerGeometry();
    this.freezeMorphArtworkSource();
    this.fullPlayerSideContentReady = false;
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
          this.fullPlayerSideContentReady = true;
          this.releaseMorphArtworkSource();
          playbackRuntime.onFullPlayerOpened();
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
    this.applyCompactMiniBarStyle(
      this.returnToExpandedMiniBar ? HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE
    );
  }

  private animateFullPlayerClose(): void {
    const epoch = this.beginMorphPhase(PlayerMorphPhase.CLOSING);
    this.miniPlayerBinding.sourceVisible = true;
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
    if (FullPlayerPagerSpec.canBeginGesture(
      this.playerMorphPhase,
      this.fullPlayerPagerPhase
    )) {
      this.fullPlayerPagerEpoch += 1;
      this.fullPlayerPagerPhase = FullPlayerPagerPhase.DRAGGING;
      this.fullPlayerGestureStartPosition = this.fullPlayerPagePosition;
    }
  }

  updateFullPlayerHorizontalGesture(event: GestureEvent): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN ||
      this.fullPlayerPagerPhase !== FullPlayerPagerPhase.DRAGGING) {
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
    if (this.playerMorphPhase === PlayerMorphPhase.OPEN &&
      this.fullPlayerPagerPhase === FullPlayerPagerPhase.DRAGGING) {
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
        this.fullPlayerSideContentReady = true;
        this.releaseMorphArtworkSource();
      }
    }, () => {
      this.playerExpandProgress = 1;
    });
  }

  private finishFullPlayerPageGesture(): void {
    const paneCount = this.fullPlayerPaneCount();
    const pageSpan = Math.max(1, this.fullPlayerPageSpan());
    const targetPosition = PlayerMorphGesturePolicy.fullPlayerTargetPosition(
      this.fullPlayerGestureStartPosition,
      this.fullPlayerPagePosition,
      pageSpan,
      paneCount
    );
    this.settleFullPlayerPage(targetPosition, paneCount);
  }

  private settleFullPlayerPage(targetPosition: number, paneCount: number): void {
    const targetPage = FullPlayerPagerSpec.nearestPage(targetPosition, paneCount);
    const epoch = ++this.fullPlayerPagerEpoch;
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLING;
    this.context().animateTo({
      curve: curves.springMotion(
        FullPlayerPagerSpec.PAGE_SETTLE_SPRING_RESPONSE,
        FullPlayerPagerSpec.PAGE_SETTLE_SPRING_DAMPING
      ),
      onFinish: () => {
        if (epoch !== this.fullPlayerPagerEpoch) {
          return;
        }
        this.fullPlayerPage = targetPage;
        this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
      }
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
    this.settleFullPlayerPage(targetPosition, paneCount);
  }
}
