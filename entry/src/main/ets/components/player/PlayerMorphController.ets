import { HdsBarStyle, HdsTabsController } from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { vibrator } from '@kit.SensorServiceKit';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import {
  HarmonySystemBarFrameHost,
  systemBarStyleController
} from '../../appearance/SystemBarStyleController';
import { DynamicColor, DynamicContainerRole } from '../../appearance/DynamicColor';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import {
  LyricsAvailability,
  LyricsAvailabilityListener,
  PlayerStore
} from '../../playback/model/PlaybackModels';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { LayoutLength } from '../layout/LayoutLength';
import {
  FullPlayerPage,
  FullPlayerPagerMemory,
  FullPlayerPagerPhase,
  FullPlayerPagerSpec,
  MiniPlayerGestureRegion,
  PlayerFrame,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMorphInteractionSpec,
  PlayerMorphPhase,
  PlayerMorphVisualSpec,
  PlayerMotionSpec
} from './PlayerMotion';
import { MiniPlayerBinding, PlayerDynamicBackgroundBinding } from './MiniPlayerBinding';
import { PlayerMorphGeometry } from './PlayerMorphGeometry';
import {
  MiniBarResizeAction,
  PlayerMorphGesturePolicy
} from './PlayerMorphGesturePolicy';
import { PlayerMorphTransitionCoordinator } from './PlayerMorphTransitionCoordinator';
import { PlayerGestureCadenceProbe } from './PlayerGestureCadenceProbe';
import { InterruptibleScalarMotion } from './InterruptibleScalarMotion';
import {
  FullPlayerImmersiveSplitMotion,
  HarmonyFullPlayerImmersiveSplitFrameHost
} from './FullPlayerImmersiveSplitMotion';
import {
  MiniPlayerTrackPagerPolicy,
  MiniPlayerTrackPageTarget,
  MiniPlayerTrackWindow
} from './MiniPlayerTrackPagerPolicy';
import {
  FullPlayerArtworkStagePolicy,
  FullPlayerImmersiveLayoutPolicy,
  FullPlayerImmersivePhase
} from './FullPlayerArtworkStagePolicy';
import {
  FullPlayerImmersiveIntent,
  FullPlayerImmersiveIntentCoordinator
} from './FullPlayerImmersiveIntentCoordinator';
import { PlayerArtworkImmersiveVisualBinding } from './PlayerArtworkPlaybackVisualState';

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
  readonly fullPlayerArtworkImmersiveVisual: PlayerArtworkImmersiveVisualBinding =
    new PlayerArtworkImmersiveVisualBinding();
  playerExpandProgress: number = 0;
  playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  swipeHapticTriggered: boolean = false;
  playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  fullPlayerSideContentReady: boolean = false;
  playerMorphBackgroundOpacity: number = 1;
  fullPlayerPage: FullPlayerPage = FullPlayerPage.COVER;
  fullPlayerPagePosition: number = FullPlayerPage.COVER;
  fullPlayerPagerPhase: FullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
  fullPlayerImmersivePhase: FullPlayerImmersivePhase = FullPlayerImmersivePhase.NORMAL;
  fullPlayerImmersiveProgress: number = 0;
  frozenMorphArtwork: image.PixelMap | undefined = undefined;
  frozenMorphArtworkUri: string = '';
  frozenMorphArtworkPreferPixelMap: boolean = false;
  frozenMorphArtworkWidth: number = 0;
  frozenMorphArtworkHeight: number = 0;
  frozenMorphArtworkRevision: number = 0;
  morphArtworkSourceFrozen: boolean = false;
  rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  frozenRootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  artworkTarget: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
  };
  centeredArtworkTarget: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
  };
  artworkViewportTarget: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
  };
  frozenArtworkTarget: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
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
  private miniPlayerGestureStartExpandProgress: number = 0;
  private miniPlayerGestureStartOffsetX: number = 0;
  private miniPlayerTrackPagerEpoch: number = 0;
  private fullPlayerGestureStartPosition: number = FullPlayerPage.COVER;
  private fullPlayerGestureStartExpandProgress: number = 1;
  private fullPlayerGestureFallbackTarget: number = 1;
  private fullPlayerPagerEpoch: number = 0;
  private fullPlayerImmersiveEpoch: number = 0;
  private fullPlayerImmersiveWideLyricsEnabled: boolean = true;
  private morphUsesSharedGeometry: boolean = true;
  private miniPlayerGestureRegion: MiniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
  private miniPlayerHorizontalGestureOffset: number = 0;
  private readonly transitionCoordinator: PlayerMorphTransitionCoordinator =
    new PlayerMorphTransitionCoordinator();
  private readonly miniPlayerGestureCadenceProbe: PlayerGestureCadenceProbe =
    new PlayerGestureCadenceProbe();
  private readonly playerMorphMotion: InterruptibleScalarMotion =
    new InterruptibleScalarMotion(0);
  private readonly fullPlayerPageMotion: InterruptibleScalarMotion =
    new InterruptibleScalarMotion(FullPlayerPage.COVER);
  private readonly fullPlayerImmersiveMotion: InterruptibleScalarMotion =
    new InterruptibleScalarMotion(0);
  private readonly fullPlayerImmersiveIntentCoordinator: FullPlayerImmersiveIntentCoordinator =
    new FullPlayerImmersiveIntentCoordinator();
  readonly fullPlayerImmersiveSplitMotion: FullPlayerImmersiveSplitMotion =
    new FullPlayerImmersiveSplitMotion(0);
  private readonly miniPlayerTrackPageMotion: InterruptibleScalarMotion =
    new InterruptibleScalarMotion(0);
  private readonly fullPlayerPagerMemory: FullPlayerPagerMemory =
    new FullPlayerPagerMemory();
  private readonly playerStore: PlayerStore;
  private readonly compactTabsController: HdsTabsController;
  private readonly condensedCompactTabsController: HdsTabsController;
  private fullPlayerVisibilityListener?: (visible: boolean) => void;
  private fullPlayerVisible: boolean = false;
  private readonly lyricsAvailabilityListener: LyricsAvailabilityListener =
    (_availability: LyricsAvailability): void => this.reconcileFullPlayerImmersiveLayout();

  constructor(playerStore: PlayerStore, compactTabsController: HdsTabsController,
    condensedCompactTabsController: HdsTabsController) {
    this.playerStore = playerStore;
    this.compactTabsController = compactTabsController;
    this.condensedCompactTabsController = condensedCompactTabsController;
    this.playerStore.addLyricsAvailabilityListener(this.lyricsAvailabilityListener);
    this.reconcileFullPlayerImmersiveLayout();
  }

  syncSystemBarContentColor(): void {
    if (PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(this.playerMorphPhase)) {
      systemBarStyleController.submitContentColor(
        PLAYER_SYSTEM_BAR_OWNER,
        PlayerMotionSpec.FULL_PLAYER_CONTENT_COLOR
      );
    } else {
      systemBarStyleController.removeContentColor(PLAYER_SYSTEM_BAR_OWNER);
    }
  }

  reapplySystemBarAfterResponsiveLayoutChange(): void {
    if (!PlayerMorphVisualSpec.shouldOwnSystemBarContentColor(this.playerMorphPhase)) {
      return;
    }
    systemBarStyleController.scheduleReapplyAcrossLayoutFrames(
      new HarmonySystemBarFrameHost(this.context())
    );
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

  setFullPlayerVisibilityListener(listener?: (visible: boolean) => void): void {
    this.fullPlayerVisibilityListener = listener;
    listener?.(this.fullPlayerVisible);
  }

  dispose(): void {
    this.playerStore.removeLyricsAvailabilityListener(this.lyricsAvailabilityListener);
    this.miniPlayerGestureCadenceProbe.cancel();
    this.setPlayerMorphPhase(PlayerMorphPhase.IDLE);
    this.playerMorphMotion.dispose();
    this.fullPlayerPageMotion.dispose();
    this.fullPlayerImmersiveMotion.dispose();
    this.fullPlayerImmersiveSplitMotion.dispose();
    this.miniPlayerTrackPageMotion.dispose();
    this.transitionCoordinator.dispose();
    this.fullPlayerPagerEpoch += 1;
    this.fullPlayerImmersiveEpoch += 1;
    this.miniPlayerTrackPagerEpoch += 1;
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
    this.fullPlayerSideContentReady = false;
    this.playerExpandProgress = 0;
    this.playerMorphMotion.setValue(0);
    this.playerMorphBackgroundOpacity = 1;
    this.dynamicBackgroundBinding.active = false;
    this.miniPlayerBinding.sourceVisible = true;
    this.miniPlayerBinding.sourceMarqueeActive = true;
    this.clearMiniPlayerTrackPager();
    this.resetFullPlayerImmersiveStage();
    this.releaseMorphArtworkSource();
    this.setFullPlayerVisibilityListener(undefined);
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
    const rememberedPosition = this.fullPlayerPagerMemory.restore(nextPaneCount);
    this.fullPlayerPagerEpoch += 1;
    this.fullPlayerPageMotion.complete(rememberedPosition);
    this.context().animateToImmediately({
      duration: 0
    }, () => {
      this.setFullPlayerPagePosition(rememberedPosition);
      this.fullPlayerPage = FullPlayerPagerSpec.nearestPage(
        rememberedPosition,
        nextPaneCount
      );
    });
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
    this.reconcileFullPlayerImmersiveLayout();
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
      y: this.centeredArtworkTarget.y,
      width: this.centeredArtworkTarget.width,
      height: this.centeredArtworkTarget.height
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
    this.frozenMorphArtworkRevision = this.playerStore.heroArtworkRevision;
    this.morphArtworkSourceFrozen = true;
  }

  private releaseMorphArtworkSource(): void {
    this.morphArtworkSourceFrozen = false;
    this.frozenMorphArtwork = undefined;
    this.frozenMorphArtworkUri = '';
    this.frozenMorphArtworkPreferPixelMap = false;
    this.frozenMorphArtworkWidth = 0;
    this.frozenMorphArtworkHeight = 0;
    this.frozenMorphArtworkRevision = 0;
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
    return BundledArtworkCatalog.resolve(BundledArtworkCatalog.DEFAULT_FULL);
  }

  morphArtworkSourceWidth(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkWidth :
      (this.playerStore.currentTrack?.artworkWidth ?? 0);
  }

  morphArtworkSourceHeight(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkHeight :
      (this.playerStore.currentTrack?.artworkHeight ?? 0);
  }

  morphArtworkSourceRevision(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkRevision :
      this.playerStore.heroArtworkRevision;
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

  fullPlayerArtworkTarget(): PlayerFrame {
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
    const sourceFrame = this.miniPlaybackButtonFrame();
    const geometryProgress = this.morphGeometryProgress();
    const positionProgress = this.morphPositionProgress();
    return {
      x: PlayerMorphGeometry.morphValue(
        sourceFrame.x,
        this.frozenPlaybackButtonTarget.x,
        positionProgress
      ),
      y: PlayerMorphGeometry.morphValue(
        sourceFrame.y,
        this.frozenPlaybackButtonTarget.y,
        positionProgress
      ),
      width: PlayerMorphGeometry.morphValue(
        sourceFrame.width,
        this.frozenPlaybackButtonTarget.width,
        geometryProgress
      ),
      height: PlayerMorphGeometry.morphValue(
        sourceFrame.height,
        this.frozenPlaybackButtonTarget.height,
        geometryProgress
      )
    };
  }

  morphPlaybackButtonIconSize(): number {
    return PlayerMorphGeometry.morphValue(
      PlayerLayoutSpec.MINI_PLAYBACK_ICON_SIZE,
      PlayerLayoutSpec.targetPlaybackIconSize(this.frozenPlaybackButtonTarget.width),
      this.morphGeometryProgress()
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
    return this.morphElementOpacity();
  }

  morphGeometryProgress(): number {
    return PlayerMorphVisualSpec.morphGeometryProgress(
      this.playerMorphPhase,
      this.playerExpandProgress,
      this.morphUsesSharedGeometry
    );
  }

  morphPositionProgress(): number {
    return PlayerMorphVisualSpec.morphPositionProgress(
      this.playerMorphPhase,
      this.playerExpandProgress,
      this.morphUsesSharedGeometry
    );
  }

  morphElementOpacity(): number {
    return PlayerMorphVisualSpec.coverElementOpacity(
      this.playerMorphPhase,
      this.fullPlayerPagePosition,
      this.renderedFullPlayerPaneCount(),
      this.playerExpandProgress,
      this.morphUsesSharedGeometry
    );
  }

  morphPlaybackButtonColor(): string {
    return DynamicColor.blendOpaque(
      this.frozenMiniPlayerForeground,
      PlayerMotionSpec.FULL_PLAYER_CONTENT_COLOR,
      PlayerMotionSpec.foregroundColorProgress(this.playerExpandProgress)
    );
  }

  private currentPagerArtworkTarget(): PlayerFrame {
    return {
      x: FullPlayerPagerSpec.pagerPageTargetX(
        this.centeredArtworkTarget.x,
        FullPlayerPage.COVER,
        this.fullPlayerPagePosition,
        this.fullPlayerPageSpan()
      ),
      y: this.centeredArtworkTarget.y,
      width: this.centeredArtworkTarget.width,
      height: this.centeredArtworkTarget.height
    };
  }

  handleBackPress(): boolean {
    if (!PlayerMorphInteractionSpec.shouldConsumeBackPress(this.playerMorphPhase)) {
      return false;
    }
    if (this.fullPlayerImmersiveProgress > 0 && this.fullPlayerPaneCount() === 1 &&
      this.fullPlayerPagePosition > FullPlayerPage.COVER + 0.0001) {
      this.navigateFullPlayerPage(FullPlayerPage.COVER);
      return true;
    }
    if (this.exitFullPlayerImmersive()) {
      return true;
    }
    this.hideFullPlayer();
    return true;
  }

  private resetFullPlayerImmersiveStage(): void {
    this.fullPlayerImmersiveIntentCoordinator.reset();
    this.fullPlayerImmersiveEpoch += 1;
    this.fullPlayerImmersiveMotion.complete(0);
    this.fullPlayerImmersiveSplitMotion.complete(0);
    this.fullPlayerImmersivePhase = FullPlayerImmersivePhase.NORMAL;
    this.setFullPlayerImmersiveProgress(0);
  }

  private syncFullPlayerArtworkImmersiveVisual(): void {
    this.fullPlayerArtworkImmersiveVisual.progress =
      this.effectiveFullPlayerImmersiveProgress();
  }

  private setFullPlayerImmersiveProgress(progress: number): void {
    this.fullPlayerImmersiveProgress = progress;
    this.syncFullPlayerArtworkImmersiveVisual();
  }

  private setFullPlayerPagePosition(position: number): void {
    this.fullPlayerPagePosition = position;
    this.syncFullPlayerArtworkImmersiveVisual();
  }

  private takeOverFullPlayerImmersivePresentation(): void {
    if (!this.fullPlayerImmersiveMotion.isActive()) {
      this.fullPlayerImmersiveMotion.setValue(this.fullPlayerImmersiveProgress);
      return;
    }
    const presentation = this.clamp(this.fullPlayerImmersiveMotion.value(), 0, 1);
    this.fullPlayerImmersiveEpoch += 1;
    this.fullPlayerImmersiveMotion.cancel();
    this.context().animateToImmediately({ duration: 0 }, () => {
      this.setFullPlayerImmersiveProgress(presentation);
    });
  }

  private animateFullPlayerImmersive(target: number): void {
    this.takeOverFullPlayerImmersivePresentation();
    const normalizedTarget = this.clamp(target, 0, 1);
    const start = this.fullPlayerImmersiveProgress;
    const epoch = ++this.fullPlayerImmersiveEpoch;
    this.fullPlayerImmersivePhase = normalizedTarget === 1 ?
      FullPlayerImmersivePhase.ENTERING : FullPlayerImmersivePhase.EXITING;
    const easing = PlayerMotionSpec.interpolatingSpringEasing(
      FullPlayerArtworkStagePolicy.IMMERSIVE_SPRING_RESPONSE,
      FullPlayerArtworkStagePolicy.IMMERSIVE_SPRING_DAMPING
    );
    this.fullPlayerImmersiveMotion.animate(
      this.context(),
      start,
      normalizedTarget,
      FullPlayerArtworkStagePolicy.IMMERSIVE_DURATION,
      easing
    );
    this.context().animateToImmediately({
      duration: FullPlayerArtworkStagePolicy.IMMERSIVE_DURATION,
      curve: easing,
      onFinish: (): void => {
        if (epoch !== this.fullPlayerImmersiveEpoch) {
          return;
        }
        this.fullPlayerImmersiveMotion.complete(normalizedTarget);
        this.setFullPlayerImmersiveProgress(normalizedTarget);
        this.fullPlayerImmersivePhase = normalizedTarget === 1 ?
          FullPlayerImmersivePhase.IMMERSIVE : FullPlayerImmersivePhase.NORMAL;
      }
    }, () => {
      this.setFullPlayerImmersiveProgress(normalizedTarget);
    });
  }

  private currentFullPlayerImmersiveIntent(): boolean {
    return this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.ENTERING ||
      this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.IMMERSIVE;
  }

  private applyFullPlayerImmersiveIntent(intent: FullPlayerImmersiveIntent): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    this.fullPlayerImmersiveWideLyricsEnabled = intent.wideLyricsEnabled;
    if (!intent.immersive) {
      if (this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.EXITING ||
        (this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.NORMAL &&
          this.fullPlayerImmersiveProgress <= 0)) {
        return;
      }
      this.animateFullPlayerImmersive(0);
      return;
    }
    if (this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.ENTERING ||
      this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.IMMERSIVE) {
      return;
    }
    this.reconcileFullPlayerImmersiveLayout();
    const paneCount = this.fullPlayerPaneCount();
    const resolvedSplitTarget = this.fullPlayerImmersiveSplitMotion.resolvedTarget();
    const immersivePagePosition = FullPlayerImmersiveLayoutPolicy.entryPagePosition(
      this.fullPlayerPagePosition,
      paneCount,
      this.playerStore.lyricsAvailability,
      resolvedSplitTarget,
      this.fullPlayerImmersiveWideLyricsEnabled
    );
    if (Math.abs(immersivePagePosition - this.fullPlayerPagePosition) > 0.0001) {
      this.settleFullPlayerPage(immersivePagePosition, paneCount);
    }
    this.animateFullPlayerImmersive(1);
  }

  private requestFullPlayerImmersive(immersive: boolean,
    wideLyricsEnabled: boolean): void {
    const intent = this.fullPlayerImmersiveIntentCoordinator.request(
      immersive,
      wideLyricsEnabled
    );
    if (intent !== undefined) {
      this.applyFullPlayerImmersiveIntent(intent);
    }
  }

  setFullPlayerArtworkMotionActive(active: boolean): void {
    const intent = this.fullPlayerImmersiveIntentCoordinator.updateArtworkMotion(active);
    if (intent !== undefined) {
      this.applyFullPlayerImmersiveIntent(intent);
    }
    if (!active && this.playerMorphPhase === PlayerMorphPhase.OPEN) {
      this.reconcileFullPlayerImmersiveLayout();
    }
  }

  toggleFullPlayerImmersive(enabled: boolean, wideLyricsEnabled: boolean = true): void {
    if (!enabled || this.playerMorphPhase !== PlayerMorphPhase.OPEN ||
      FullPlayerPagerSpec.pageViewportVisibility(
        FullPlayerPage.COVER,
        this.fullPlayerPagePosition,
        this.fullPlayerPaneCount()
      ) < 0.5) {
      return;
    }
    const intendedImmersive = this.fullPlayerImmersiveIntentCoordinator.intendedImmersive(
      this.currentFullPlayerImmersiveIntent()
    );
    this.requestFullPlayerImmersive(!intendedImmersive, wideLyricsEnabled);
  }

  effectiveFullPlayerImmersiveProgress(): number {
    return this.fullPlayerImmersiveProgress * FullPlayerPagerSpec.pageViewportVisibility(
      FullPlayerPage.COVER,
      this.fullPlayerPagePosition,
      this.fullPlayerPaneCount()
    );
  }

  reconcileFullPlayerImmersiveLayout(): void {
    if (this.fullPlayerImmersiveIntentCoordinator.isArtworkMotionActive()) {
      return;
    }
    const paneCount = this.fullPlayerPaneCount();
    const resolvedSplitTarget = this.fullPlayerImmersiveSplitMotion.resolvedTarget();
    const target = FullPlayerImmersiveLayoutPolicy.splitTarget(
      paneCount,
      this.playerStore.lyricsAvailability,
      resolvedSplitTarget,
      this.fullPlayerImmersiveWideLyricsEnabled
    );
    if (this.fullPlayerImmersiveProgress > 0) {
      const immersivePagePosition = FullPlayerImmersiveLayoutPolicy.entryPagePosition(
        this.fullPlayerPagePosition,
        paneCount,
        this.playerStore.lyricsAvailability,
        resolvedSplitTarget,
        this.fullPlayerImmersiveWideLyricsEnabled
      );
      if (Math.abs(immersivePagePosition - this.fullPlayerPagePosition) > 0.0001) {
        this.settleFullPlayerPage(immersivePagePosition, paneCount);
      }
    }
    if (this.fullPlayerImmersiveSplitMotion.isActive() &&
      this.fullPlayerImmersiveSplitMotion.targets(target)) {
      return;
    }
    if (!this.fullPlayerImmersiveSplitMotion.isActive() &&
      Math.abs(target - this.fullPlayerImmersiveSplitMotion.progress) < 0.0001) {
      return;
    }
    if (this.fullPlayerImmersiveProgress <= 0) {
      this.fullPlayerImmersiveSplitMotion.complete(target);
      return;
    }
    this.fullPlayerImmersiveSplitMotion.animate(
      new HarmonyFullPlayerImmersiveSplitFrameHost(this.context()),
      target,
      FullPlayerArtworkStagePolicy.IMMERSIVE_DURATION
    );
  }

  exitFullPlayerImmersive(): boolean {
    const intendedImmersive = this.fullPlayerImmersiveIntentCoordinator.intendedImmersive(
      this.currentFullPlayerImmersiveIntent()
    );
    if (!intendedImmersive &&
      this.fullPlayerImmersivePhase === FullPlayerImmersivePhase.NORMAL &&
      this.fullPlayerImmersiveProgress <= 0) {
      return false;
    }
    this.requestFullPlayerImmersive(false, this.fullPlayerImmersiveWideLyricsEnabled);
    return true;
  }

  isMorphActive(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.IDLE;
  }

  shouldSuspendBackgroundRendering(): boolean {
    return PlayerMorphVisualSpec.shouldSuspendBackgroundRendering(this.playerMorphPhase);
  }

  shouldRenderFullPlayerSideContent(): boolean {
    return this.fullPlayerSideContentReady;
  }

  private takeOverMorphPresentation(): void {
    if (!this.playerMorphMotion.isActive()) {
      this.playerMorphMotion.setValue(this.playerExpandProgress);
      return;
    }
    const presentationProgress = this.clamp(this.playerMorphMotion.value(), 0, 1);
    this.playerMorphMotion.cancel();
    this.context().animateToImmediately({
      duration: 0
    }, () => {
      this.playerExpandProgress = presentationProgress;
    });
  }

  private takeOverFullPlayerPagePresentation(): void {
    if (!this.fullPlayerPageMotion.isActive()) {
      this.fullPlayerPageMotion.setValue(this.fullPlayerPagePosition);
      return;
    }
    const presentationPosition = FullPlayerPagerSpec.clampPosition(
      this.fullPlayerPageMotion.value(),
      this.fullPlayerPaneCount()
    );
    this.fullPlayerPageMotion.cancel();
    this.context().animateToImmediately({
      duration: 0
    }, () => {
      this.setFullPlayerPagePosition(presentationPosition);
    });
  }

  private freezeFullPlayerCloseGeometry(): void {
    this.fullPlayerPagerEpoch += 1;
    this.takeOverFullPlayerPagePresentation();
    this.freezeMiniPlayerGeometry(false);
    this.freezeMorphArtworkSource();
  }

  private captureMorphGeometryMode(): void {
    this.morphUsesSharedGeometry = FullPlayerPagerSpec.usesSharedMorphGeometry(
      this.fullPlayerPagePosition,
      this.fullPlayerPaneCount()
    );
  }

  private beginMorphPhase(phase: PlayerMorphPhase): number {
    const epoch = this.transitionCoordinator.beginTransition();
    this.fullPlayerPagerEpoch += 1;
    this.takeOverMorphPresentation();
    this.takeOverFullPlayerPagePresentation();
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
    this.fullPlayerPage = FullPlayerPagerSpec.nearestPage(
      this.fullPlayerPagePosition,
      this.fullPlayerPaneCount()
    );
    this.setPlayerMorphPhase(phase);
    this.dynamicBackgroundBinding.active = true;
    this.miniPlayerBinding.sourceVisible = false;
    this.miniPlayerBinding.sourceMarqueeActive = false;
    return epoch;
  }

  private animateMorphProgress(target: number, phase: PlayerMorphPhase, duration: number,
    easing: string, sourceVisible: boolean,
    onFinish: (epoch: number) => void): void {
    const epoch = this.beginMorphPhase(phase);
    this.miniPlayerBinding.sourceVisible = sourceVisible;
    const startProgress = this.playerExpandProgress;
    this.playerMorphMotion.animate(
      this.context(),
      startProgress,
      target,
      duration,
      easing
    );
    this.context().animateToImmediately({
      duration: duration,
      curve: easing,
      onFinish: (): void => {
        if (this.isCurrentMorphTransition(epoch)) {
          this.playerMorphMotion.complete(target);
          this.playerExpandProgress = target;
          onFinish(epoch);
        }
      }
    }, () => {
      this.playerExpandProgress = target;
    });
  }

  private setPlayerMorphPhase(phase: PlayerMorphPhase): void {
    this.playerMorphPhase = phase;
    const visible = phase !== PlayerMorphPhase.IDLE;
    if (this.fullPlayerVisible !== visible) {
      this.fullPlayerVisible = visible;
      this.fullPlayerVisibilityListener?.(visible);
    }
    this.syncSystemBarContentColor();
    if (phase === PlayerMorphPhase.OPEN) {
      systemBarStyleController.scheduleReapplyAfterFrame(
        new HarmonySystemBarFrameHost(this.context())
      );
    }
  }

  private isCurrentMorphTransition(epoch: number): boolean {
    return this.transitionCoordinator.isCurrentTransition(epoch);
  }

  private morphVerticalTravelDistance(): number {
    return PlayerMorphGeometry.verticalTravelDistance(
      this.frozenMiniPlayerFrame,
      this.frozenRootFrame
    );
  }

  private beginMorphBackgroundHandoff(epoch: number): void {
    if (!this.isCurrentMorphTransition(epoch)) {
      return;
    }
    this.setPlayerMorphPhase(PlayerMorphPhase.BACKGROUND_HANDOFF);
    this.miniPlayerBinding.sourceVisible = true;
    this.context().animateTo({
      duration: PlayerMotionSpec.BACKGROUND_HANDOFF_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        this.setPlayerMorphPhase(PlayerMorphPhase.IDLE);
        this.dynamicBackgroundBinding.active = false;
        this.fullPlayerSideContentReady = false;
        this.miniPlayerBinding.sourceVisible = true;
        this.miniPlayerBinding.sourceMarqueeActive = true;
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

  private activateMiniPlayerTrackPager(): boolean {
    if (this.miniPlayerBinding.trackPagerActive) {
      return true;
    }
    const window = MiniPlayerTrackPagerPolicy.window(
      this.playerStore.queueDataSource.snapshot(),
      this.playerStore.queueCurrentIndex,
      this.playerStore.repeatMode
    );
    if (window.current === undefined) {
      return false;
    }
    this.miniPlayerBinding.trackPagerPrevious = window.previous;
    this.miniPlayerBinding.trackPagerCurrent = window.current;
    this.miniPlayerBinding.trackPagerNext = window.next;
    this.miniPlayerBinding.trackPagerActive = true;
    return true;
  }

  private clearMiniPlayerTrackPager(): void {
    this.miniPlayerBinding.offsetX = 0;
    this.miniPlayerBinding.trackPagerActive = false;
    this.miniPlayerBinding.trackPagerPrevious = undefined;
    this.miniPlayerBinding.trackPagerCurrent = undefined;
    this.miniPlayerBinding.trackPagerNext = undefined;
    this.miniPlayerTrackPageMotion.setValue(0);
  }

  private cancelMiniPlayerTrackPager(): void {
    this.miniPlayerTrackPagerEpoch += 1;
    this.miniPlayerTrackPageMotion.cancel();
    this.context().animateToImmediately({ duration: 0 }, () => {
      this.clearMiniPlayerTrackPager();
    });
  }

  private takeOverMiniPlayerTrackPagerPresentation(): void {
    if (!this.miniPlayerBinding.trackPagerActive ||
      !this.miniPlayerTrackPageMotion.isActive()) {
      this.miniPlayerTrackPageMotion.setValue(this.miniPlayerOffsetX);
      return;
    }
    let presentationOffset = this.miniPlayerTrackPageMotion.value();
    const projection = this.playerStore.queueDataSource.projectionState;
    const currentId = projection.entryAt(projection.activeIndex())?.queueEntryId;
    if (currentId !== this.miniPlayerBinding.trackPagerCurrent?.queueEntryId) {
      presentationOffset = MiniPlayerTrackPagerPolicy.rebaseOffset(
        this.miniPlayerTrackWindow(), currentId ?? -1, presentationOffset,
        this.miniPlayerBinding.trackPagerViewportWidth
      );
      this.miniPlayerBinding.trackPagerActive = false;
      this.activateMiniPlayerTrackPager();
    }
    this.miniPlayerTrackPagerEpoch += 1;
    this.miniPlayerTrackPageMotion.cancel();
    this.context().animateToImmediately({ duration: 0 }, () => {
      this.miniPlayerOffsetX = presentationOffset;
    });
  }

  private miniPlayerTrackWindow(): MiniPlayerTrackWindow {
    return {
      previous: this.miniPlayerBinding.trackPagerPrevious,
      current: this.miniPlayerBinding.trackPagerCurrent,
      next: this.miniPlayerBinding.trackPagerNext
    };
  }

  beginMiniPlayerGesture(): void {
    this.takeOverMiniPlayerTrackPagerPresentation();
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
    this.miniPlayerHorizontalGestureOffset = 0;
    this.miniPlayerGestureStartOffsetX = this.miniPlayerOffsetX;
    this.miniPlayerGestureStartExpandProgress = this.playerExpandProgress;
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
      if (!this.activateMiniPlayerTrackPager()) {
        return;
      }
      const window = this.miniPlayerTrackWindow();
      this.miniPlayerOffsetX = MiniPlayerTrackPagerPolicy.dragOffset(
        this.miniPlayerGestureStartOffsetX + horizontalOffset,
        this.miniPlayerBinding.trackPagerViewportWidth,
        window.previous !== undefined,
        window.next !== undefined
      );
      this.miniPlayerTrackPageMotion.setValue(this.miniPlayerOffsetX);
      const reachedActionPoint = MiniPlayerTrackPagerPolicy.target(
        this.miniPlayerOffsetX,
        window.previous !== undefined,
        window.next !== undefined
      ) !== MiniPlayerTrackPageTarget.CURRENT;
      if (reachedActionPoint && !this.swipeHapticTriggered) {
        this.swipeHapticTriggered = true;
        this.triggerSwipeHaptic();
      }
      return;
    }
    if (this.playerGestureAxis === PlayerGestureAxis.VERTICAL) {
      if (this.miniPlayerBinding.trackPagerActive) {
        this.cancelMiniPlayerTrackPager();
      }
      this.miniPlayerGestureCadenceProbe.startIfNeeded(this.playerExpandProgress);
      if (!this.isMorphActive()) {
        this.freezeMiniPlayerGeometry();
        this.freezeMorphArtworkSource();
        this.fullPlayerSideContentReady = false;
        this.captureMorphGeometryMode();
        this.beginMorphPhase(PlayerMorphPhase.OPEN_DRAGGING);
        this.playerMorphBackgroundOpacity = 1;
      }
      const verticalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetY);
      this.playerExpandProgress = this.clamp(
        this.miniPlayerGestureStartExpandProgress -
          verticalOffset / this.morphVerticalTravelDistance(),
        0,
        1
      );
      this.playerMorphMotion.setValue(this.playerExpandProgress);
      this.miniPlayerGestureCadenceProbe.recordGestureUpdate();
    }
  }

  finishMiniPlayerGesture(): void {
    const wasVerticalGesture = this.playerGestureAxis === PlayerGestureAxis.VERTICAL;
    const wasHorizontalGesture = this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL;
    if (wasVerticalGesture) {
      this.miniPlayerGestureCadenceProbe.finish(this.playerExpandProgress);
    } else {
      this.miniPlayerGestureCadenceProbe.cancel();
    }
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
      this.miniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
      this.settleMiniPlayerTrackPager();
      return;
    }
    this.miniPlayerGestureRegion = MiniPlayerGestureRegion.OTHER;
    if (!wasVerticalGesture) {
      this.miniPlayerOffsetX = 0;
      this.miniPlayerHorizontalGestureOffset = 0;
      return;
    }
    const shouldExpand = PlayerMorphGesturePolicy.morphTargetProgress(
      this.miniPlayerGestureStartExpandProgress,
      this.playerExpandProgress,
      0,
      this.morphVerticalTravelDistance()
    ) === 1;
    const duration = shouldExpand ? PlayerMotionSpec.OPEN_DURATION : PlayerMotionSpec.CANCEL_DURATION;
    this.animateMorphProgress(
      shouldExpand ? 1 : 0,
      shouldExpand ? PlayerMorphPhase.OPENING : PlayerMorphPhase.CLOSING,
      duration,
      shouldExpand ? PlayerMotionSpec.interpolatingSpringEasing(
        PlayerMotionSpec.OPEN_SPRING_RESPONSE,
        PlayerMotionSpec.OPEN_SPRING_DAMPING
      ) : 'ease-out',
      !shouldExpand,
      (epoch: number): void => {
        if (shouldExpand) {
          this.setPlayerMorphPhase(PlayerMorphPhase.OPEN);
          this.fullPlayerSideContentReady = true;
          this.releaseMorphArtworkSource();
          playbackRuntime.onFullPlayerOpened();
        } else {
          this.beginMorphBackgroundHandoff(epoch);
        }
      }
    );
    this.miniPlayerOffsetX = 0;
  }

  private settleMiniPlayerTrackPager(): void {
    if (!this.miniPlayerBinding.trackPagerActive) {
      this.miniPlayerOffsetX = 0;
      this.miniPlayerHorizontalGestureOffset = 0;
      return;
    }
    const window = this.miniPlayerTrackWindow();
    const target = MiniPlayerTrackPagerPolicy.target(
      this.miniPlayerOffsetX,
      window.previous !== undefined,
      window.next !== undefined
    );
    const targetOffset = MiniPlayerTrackPagerPolicy.targetOffset(
      target,
      this.miniPlayerBinding.trackPagerViewportWidth
    );
    const activeIndex = this.playerStore.queueDataSource.projectionState.activeIndex();
    const activeEntryId = this.playerStore.queueDataSource.projectionState
      .entryAt(activeIndex)?.queueEntryId ?? -1;
    const targetEntry = MiniPlayerTrackPagerPolicy.commitEntry(
      window,
      target,
      activeEntryId
    );
    if (targetEntry !== undefined) {
      playbackRuntime.selectQueueEntryPreservingPlaybackIntent(targetEntry.queueEntryId);
    }
    const epoch = ++this.miniPlayerTrackPagerEpoch;
    const startOffset = this.miniPlayerOffsetX;
    const easing = PlayerMotionSpec.interpolatingSpringEasing(
      MiniPlayerTrackPagerPolicy.SETTLE_SPRING_RESPONSE,
      MiniPlayerTrackPagerPolicy.SETTLE_SPRING_DAMPING
    );
    this.miniPlayerTrackPageMotion.animate(
      this.context(),
      startOffset,
      targetOffset,
      MiniPlayerTrackPagerPolicy.SETTLE_DURATION,
      easing
    );
    this.context().animateToImmediately({
      duration: MiniPlayerTrackPagerPolicy.SETTLE_DURATION,
      curve: easing,
      onFinish: (): void => {
        if (epoch !== this.miniPlayerTrackPagerEpoch) {
          return;
        }
        this.miniPlayerTrackPageMotion.complete(targetOffset);
        this.context().animateToImmediately({ duration: 0 }, () => {
          this.clearMiniPlayerTrackPager();
          this.miniPlayerHorizontalGestureOffset = 0;
        });
      }
    }, () => {
      this.miniPlayerOffsetX = targetOffset;
      this.miniPlayerHorizontalGestureOffset = 0;
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
    if (this.playerMorphPhase !== PlayerMorphPhase.IDLE) {
      return;
    }
    if (!this.miniBarExpanded) {
      this.applyCompactMiniBarStyle(HdsBarStyle.EXPAND);
      return;
    }
    this.freezeMiniPlayerGeometry();
    this.freezeMorphArtworkSource();
    this.fullPlayerSideContentReady = false;
    this.playerMorphBackgroundOpacity = 1;
    this.captureMorphGeometryMode();
    this.animateMorphProgress(
      1,
      PlayerMorphPhase.OPENING,
      PlayerMotionSpec.OPEN_DURATION,
      PlayerMotionSpec.interpolatingSpringEasing(
        PlayerMotionSpec.OPEN_SPRING_RESPONSE,
        PlayerMotionSpec.OPEN_SPRING_DAMPING
      ),
      false,
      (_epoch: number): void => {
        this.setPlayerMorphPhase(PlayerMorphPhase.OPEN);
        this.fullPlayerSideContentReady = true;
        this.releaseMorphArtworkSource();
        playbackRuntime.onFullPlayerOpened();
      }
    );
  }

  hideFullPlayer(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.IDLE ||
      this.playerMorphPhase === PlayerMorphPhase.CLOSING ||
      this.playerMorphPhase === PlayerMorphPhase.BACKGROUND_HANDOFF) {
      return;
    }
    this.resetFullPlayerImmersiveStage();
    const stableOpen = this.playerMorphPhase === PlayerMorphPhase.OPEN;
    this.restoreReturnMiniBarStyle();
    this.freezeFullPlayerCloseGeometry();
    if (stableOpen) {
      this.captureMorphGeometryMode();
    }
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
    this.animateMorphProgress(
      0,
      PlayerMorphPhase.CLOSING,
      PlayerMotionSpec.CLOSE_DURATION,
      PlayerMotionSpec.closeEasing(),
      true,
      (epoch: number): void => {
        this.beginMorphBackgroundHandoff(epoch);
      }
    );
  }

  beginFullPlayerHorizontalGesture(): void {
    if (this.fullPlayerImmersiveProgress > 0 && this.fullPlayerPaneCount() > 1) {
      return;
    }
    if (FullPlayerPagerSpec.canBeginGesture(
      this.playerMorphPhase,
      this.fullPlayerPagerPhase
    )) {
      this.fullPlayerPagerEpoch += 1;
      this.takeOverFullPlayerPagePresentation();
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
    const candidate = this.fullPlayerGestureStartPosition - horizontalOffset / pageSpan;
    this.setFullPlayerPagePosition(this.fullPlayerImmersiveProgress > 0 ?
      Math.max(FullPlayerPage.COVER, Math.min(FullPlayerPage.LYRICS, candidate)) :
      FullPlayerPagerSpec.clampPosition(candidate, this.fullPlayerPaneCount()));
    this.fullPlayerPageMotion.setValue(this.fullPlayerPagePosition);
  }

  finishFullPlayerHorizontalGesture(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.OPEN &&
      this.fullPlayerPagerPhase === FullPlayerPagerPhase.DRAGGING) {
      this.finishFullPlayerPageGesture();
    }
  }

  beginFullPlayerVerticalGesture(): void {
    if (this.fullPlayerImmersivePhase !== FullPlayerImmersivePhase.NORMAL) {
      return;
    }
    if (!PlayerMorphInteractionSpec.canBeginFullPlayerVerticalGesture(
      this.playerMorphPhase
    )) {
      return;
    }
    const previousPhase = this.playerMorphPhase;
    const stableOpen = previousPhase === PlayerMorphPhase.OPEN;
    this.fullPlayerGestureFallbackTarget =
      previousPhase === PlayerMorphPhase.CLOSING ? 0 : 1;
    this.takeOverMorphPresentation();
    if (stableOpen) {
      this.freezeFullPlayerCloseGeometry();
      this.captureMorphGeometryMode();
    }
    this.beginMorphPhase(PlayerMorphPhase.CLOSE_DRAGGING);
    this.fullPlayerGestureStartExpandProgress = this.playerExpandProgress;
    this.playerMorphBackgroundOpacity = 1;
  }

  updateFullPlayerVerticalGesture(event: GestureEvent): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.CLOSE_DRAGGING) {
      return;
    }
    const verticalOffset = PlayerMotionSpec.distanceFromRecognitionOrigin(event.offsetY);
    this.playerExpandProgress = this.clamp(
      this.fullPlayerGestureStartExpandProgress -
        verticalOffset / this.morphVerticalTravelDistance(),
      0,
      1
    );
    this.playerMorphMotion.setValue(this.playerExpandProgress);
  }

  finishFullPlayerVerticalGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.CLOSE_DRAGGING) {
      return;
    }
    const targetProgress = PlayerMorphGesturePolicy.morphTargetProgress(
      this.fullPlayerGestureStartExpandProgress,
      this.playerExpandProgress,
      this.fullPlayerGestureFallbackTarget,
      this.morphVerticalTravelDistance()
    );
    const shouldClose = targetProgress === 0;
    if (shouldClose) {
      this.restoreReturnMiniBarStyle();
      this.animateFullPlayerClose();
      return;
    }
    this.animateMorphProgress(
      1,
      PlayerMorphPhase.OPENING,
      PlayerMotionSpec.CLOSE_CANCEL_DURATION,
      'ease-out',
      false,
      (_epoch: number): void => {
        this.setPlayerMorphPhase(PlayerMorphPhase.OPEN);
        this.fullPlayerSideContentReady = true;
        this.releaseMorphArtworkSource();
      }
    );
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
    const epoch = ++this.fullPlayerPagerEpoch;
    this.takeOverFullPlayerPagePresentation();
    const targetPage = FullPlayerPagerSpec.nearestPage(targetPosition, paneCount);
    this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLING;
    const startPosition = this.fullPlayerPagePosition;
    const easing = PlayerMotionSpec.interpolatingSpringEasing(
      FullPlayerPagerSpec.PAGE_SETTLE_SPRING_RESPONSE,
      FullPlayerPagerSpec.PAGE_SETTLE_SPRING_DAMPING
    );
    this.fullPlayerPageMotion.animate(
      this.context(),
      startPosition,
      targetPosition,
      FullPlayerPagerSpec.PAGE_SETTLE_DURATION,
      easing
    );
    this.context().animateToImmediately({
      duration: FullPlayerPagerSpec.PAGE_SETTLE_DURATION,
      curve: easing,
      onFinish: (): void => {
        if (epoch !== this.fullPlayerPagerEpoch) {
          return;
        }
        this.fullPlayerPageMotion.complete(targetPosition);
        this.setFullPlayerPagePosition(targetPosition);
        this.fullPlayerPage = targetPage;
        this.fullPlayerPagerMemory.commitSettled(targetPosition, paneCount);
        this.fullPlayerPagerPhase = FullPlayerPagerPhase.SETTLED;
      }
    }, () => {
      this.setFullPlayerPagePosition(targetPosition);
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
