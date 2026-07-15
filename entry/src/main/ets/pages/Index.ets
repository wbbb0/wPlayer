import {
  HdsBarStyle,
  HdsTabsController,
} from '@kit.UIDesignKit';
import { ComponentContent, curves, window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import {
  PlayerFrame,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec,
  PlayerPoint
} from '../components/player/PlayerMotion';
import {
  AppPrimaryTitleContent,
  AppPrimaryTitleParams
} from '../components/navigation/AppPrimaryTitleContent';
import { LibraryStore } from '../library/store/LibraryStore';
import { playbackRuntime } from '../playback/PlaybackRuntime';
import { PlayerStore } from '../playback/model/PlaybackModels';
import { SettingsRepository } from '../settings/SettingsRepository';
import { AppShellLayoutSpec } from '../components/layout/AppShellLayoutSpec';
import { WindowAvoidAreaController } from '../components/layout/WindowAvoidAreaController';
import { FullPlayerContent } from '../components/player/FullPlayerContent';
import {
  MiniPlayerContent,
  MiniPlayerSurface
} from '../components/player/MiniPlayerSurface';
import { ArtworkLayout } from '../components/artwork/ArtworkLayout';
import {
  MORE_NAVIGATION_ITEMS,
  MoreRoute
} from '../components/navigation/MoreNavigation';
import { ResponsiveNavigationShell } from '../components/navigation/ResponsiveNavigationShell';
import {
  AppAppearanceListener,
  AppAppearancePalette,
  appAppearanceController
} from '../appearance/AppAppearance';

const MORE_TAB_INDEX: number = 3;

@Entry
@Component
struct Index {
  @State statusBarAvoidHeight: number = 0;
  @State navigationAvoidHeight: number = 0;
  @State appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();
  @State selectedTabIndex: number = 0;
  @State selectedMoreRouteId: string = MoreRoute.LIBRARY_MANAGEMENT;
  @State libraryStore: LibraryStore = new LibraryStore(playbackRuntime.repository);
  @State playerStore: PlayerStore = playbackRuntime.playerStore;
  @State miniBarExpanded: boolean = false;
  @State miniPlayerOffsetX: number = 0;
  @State playerExpandProgress: number = 0;
  @State playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  @State swipeHapticTriggered: boolean = false;
  @State playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @State playerMorphBackgroundOpacity: number = 1;
  @State frozenMorphArtwork: image.PixelMap | undefined = undefined;
  @State frozenMorphArtworkUri: string = '';
  @State frozenMorphArtworkPreferPixelMap: boolean = false;
  @State frozenMorphArtworkWidth: number = 0;
  @State frozenMorphArtworkHeight: number = 0;
  @State morphArtworkSourceFrozen: boolean = false;
  @State rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @State measuredMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @State frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @State frozenRootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @State artworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @State frozenArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  private returnToExpandedMiniBar: boolean = false;
  private morphTransitionEpoch: number = 0;
  private readonly appearanceListener: AppAppearanceListener = (_epoch: number): void => {
    this.refreshAppearance();
  };
  private readonly avoidAreaController: WindowAvoidAreaController =
    new WindowAvoidAreaController((type: window.AvoidAreaType, area: window.AvoidArea): void => {
      this.applyAvoidArea(type, area);
    });

  private readonly compactTabsController: HdsTabsController = new HdsTabsController();
  private readonly expandedTabsController: HdsTabsController = new HdsTabsController();
  private settingsRepository?: SettingsRepository;
  private readonly primaryTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> = [
    undefined, undefined, undefined, undefined
  ];
  private readonly moreTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> =
    new Array<ComponentContent<AppPrimaryTitleParams> | undefined>(MORE_NAVIGATION_ITEMS.length);
  private readonly tabPathStacks: Array<NavPathStack> = [
    new NavPathStack(), new NavPathStack(), new NavPathStack(), new NavPathStack()
  ];
  private readonly expandedMorePathStacks: Array<NavPathStack> =
    MORE_NAVIGATION_ITEMS.map(() => new NavPathStack());
  private readonly pageScrollers: Array<Scroller> = [
    new Scroller(), new Scroller(), new Scroller(), new Scroller()
  ];
  private readonly libraryManagementScroller: Scroller = new Scroller();
  private readonly navigationLabels: Array<string> = ['播放列表', '音乐', '专辑', '更多'];

  aboutToAppear(): void {
    appAppearanceController.addListener(this.appearanceListener);
    this.refreshAppearance();
    this.initializePrimaryTitleContents();
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      const abilityContext = context as common.UIAbilityContext;
      this.avoidAreaController.start(abilityContext);
      try {
        this.settingsRepository = new SettingsRepository(abilityContext);
        this.selectedTabIndex = this.normalizeTabIndex(this.settingsRepository.getLastTabIndex());
      } catch (error) {
        const businessError = error as BusinessError;
        console.warn(`Unable to initialize settings: ${businessError.code}, ${businessError.message}`);
      }
      this.libraryStore.initialize(abilityContext, this.settingsRepository);
      playbackRuntime.initialize(abilityContext, this.settingsRepository).catch((error: Object) => {
        console.warn(`Unable to initialize playback: ${error instanceof Error ? error.message : error}`);
      });
    }
  }

  aboutToDisappear(): void {
    appAppearanceController.removeListener(this.appearanceListener);
    this.avoidAreaController.stop();
    for (let index = 0; index < this.primaryTitleContents.length; index += 1) {
      this.primaryTitleContents[index]?.dispose();
      this.primaryTitleContents[index] = undefined;
    }
    for (let index = 0; index < this.moreTitleContents.length; index += 1) {
      this.moreTitleContents[index]?.dispose();
      this.moreTitleContents[index] = undefined;
    }
  }

  private initializePrimaryTitleContents(): void {
    const uiContext = this.getUIContext();
    for (let index = 0; index < this.navigationLabels.length; index += 1) {
      if (this.primaryTitleContents[index] === undefined) {
        this.primaryTitleContents[index] = new ComponentContent(
          uiContext,
          wrapBuilder(AppPrimaryTitleContent),
          new AppPrimaryTitleParams(this.navigationLabels[index], this.appearancePalette.titlePrimary)
        );
      }
    }
    for (let index = 0; index < MORE_NAVIGATION_ITEMS.length; index += 1) {
      if (this.moreTitleContents[index] === undefined) {
        this.moreTitleContents[index] = new ComponentContent(
          uiContext,
          wrapBuilder(AppPrimaryTitleContent),
          new AppPrimaryTitleParams(MORE_NAVIGATION_ITEMS[index].label, this.appearancePalette.titlePrimary)
        );
      }
    }
  }

  private refreshAppearance(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const palette = AppAppearancePalette.resolve(context as common.UIAbilityContext);
    this.appearancePalette = palette;
    for (let index = 0; index < this.primaryTitleContents.length; index += 1) {
      this.primaryTitleContents[index]?.update(
        new AppPrimaryTitleParams(this.navigationLabels[index], palette.titlePrimary)
      );
    }
    for (let index = 0; index < this.moreTitleContents.length; index += 1) {
      this.moreTitleContents[index]?.update(
        new AppPrimaryTitleParams(MORE_NAVIGATION_ITEMS[index].label, palette.titlePrimary)
      );
    }
  }

  private applyAvoidArea(type: window.AvoidAreaType, area: window.AvoidArea): void {
    const uiContext = this.getUIContext();
    if (type === window.AvoidAreaType.TYPE_SYSTEM) {
      this.statusBarAvoidHeight = uiContext.px2vp(area.topRect.height);
    } else if (type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.navigationAvoidHeight = uiContext.px2vp(area.bottomRect.height);
    }
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private usesWideLayout(width: number = this.rootFrame.width): boolean {
    return width >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT;
  }

  private normalizeTabIndex(index: number): number {
    return Number.isInteger(index) && index >= 0 && index < this.navigationLabels.length ? index : 0;
  }

  private handleCompactTabChange(index: number): void {
    const normalizedIndex = this.normalizeTabIndex(index);
    this.selectedTabIndex = normalizedIndex;
    this.settingsRepository?.setLastTabIndex(normalizedIndex);
  }

  private handleCompactTabBarClick(index: number): void {
    if (index === this.selectedTabIndex) {
      this.tabPathStacks[index].clear(true);
    }
  }

  private expandedTabIndex(): number {
    if (this.selectedTabIndex < MORE_TAB_INDEX) {
      return this.selectedTabIndex;
    }
    return MORE_TAB_INDEX + this.moreNavigationIndex();
  }

  private handleExpandedTabChange(index: number): void {
    if (index < MORE_TAB_INDEX) {
      const normalizedIndex = this.normalizeTabIndex(index);
      this.selectedTabIndex = normalizedIndex;
      this.settingsRepository?.setLastTabIndex(normalizedIndex);
      return;
    }
    const moreIndex = index - MORE_TAB_INDEX;
    if (moreIndex < 0 || moreIndex >= MORE_NAVIGATION_ITEMS.length) {
      return;
    }
    this.selectedMoreRouteId = MORE_NAVIGATION_ITEMS[moreIndex].routeId;
    this.selectedTabIndex = MORE_TAB_INDEX;
    this.tabPathStacks[MORE_TAB_INDEX].clear(false);
    this.settingsRepository?.setLastTabIndex(MORE_TAB_INDEX);
  }

  private handleExpandedTabBarClick(index: number): void {
    if (index !== this.expandedTabIndex()) {
      return;
    }
    if (index < MORE_TAB_INDEX) {
      this.tabPathStacks[index].clear(true);
      return;
    }
    this.expandedMorePathStacks[index - MORE_TAB_INDEX].clear(true);
  }

  private moreNavigationIndex(routeId: string = this.selectedMoreRouteId): number {
    for (let index = 0; index < MORE_NAVIGATION_ITEMS.length; index += 1) {
      if (MORE_NAVIGATION_ITEMS[index].routeId === routeId) {
        return index;
      }
    }
    return 0;
  }

  private openMoreDestination(routeId: string): void {
    const routeIndex = this.moreNavigationIndex(routeId);
    const item = MORE_NAVIGATION_ITEMS[routeIndex];
    if (item.routeId !== routeId) {
      return;
    }
    this.selectedMoreRouteId = routeId;
    this.tabPathStacks[MORE_TAB_INDEX].pushPath({ name: routeId });
  }

  private reconcileResponsiveNavigation(previousWideLayout: boolean, nextWideLayout: boolean): void {
    if (previousWideLayout === nextWideLayout || this.selectedTabIndex !== MORE_TAB_INDEX) {
      return;
    }
    this.tabPathStacks[MORE_TAB_INDEX].clear(false);
    if (!nextWideLayout) {
      this.tabPathStacks[MORE_TAB_INDEX].pushPath({ name: this.selectedMoreRouteId }, false);
    }
  }

  private lengthToNumber(value: Length | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsedValue = Number.parseFloat(value);
      return Number.isNaN(parsedValue) ? fallback : parsedValue;
    }
    return fallback;
  }

  private freezeMiniPlayerGeometry(captureReturnStyle: boolean = true): void {
    if (captureReturnStyle) {
      this.returnToExpandedMiniBar = this.miniBarExpanded;
    }
    try {
      const uiContext = this.getUIContext();
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
      this.frozenArtworkTarget = { x: this.artworkTarget.x, y: this.artworkTarget.y };
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
      this.frozenArtworkTarget = { x: this.artworkTarget.x, y: this.artworkTarget.y };
    }
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

  private morphArtworkSource(): image.PixelMap | ResourceStr {
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

  private morphValue(start: number, end: number): number {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private fullArtworkSlotSize(): number {
    return PlayerLayoutSpec.fullArtworkSize(
      this.frozenRootFrame.width,
      this.frozenRootFrame.height,
      this.statusBarAvoidHeight,
      this.navigationAvoidHeight
    );
  }

  private containedArtworkWidth(width: number, height: number): number {
    return ArtworkLayout.containedSize(width, height,
      this.fullArtworkSlotSize(), this.fullArtworkSlotSize()).width;
  }

  private containedArtworkHeight(width: number, height: number): number {
    return ArtworkLayout.containedSize(width, height,
      this.fullArtworkSlotSize(), this.fullArtworkSlotSize()).height;
  }

  private morphTargetArtworkWidth(): number {
    const width = this.morphArtworkSourceFrozen ? this.frozenMorphArtworkWidth :
      (this.playerStore.currentTrack?.artworkWidth ?? 0);
    const height = this.morphArtworkSourceFrozen ? this.frozenMorphArtworkHeight :
      (this.playerStore.currentTrack?.artworkHeight ?? 0);
    return this.containedArtworkWidth(width, height);
  }

  private morphTargetArtworkHeight(): number {
    const width = this.morphArtworkSourceFrozen ? this.frozenMorphArtworkWidth :
      (this.playerStore.currentTrack?.artworkWidth ?? 0);
    const height = this.morphArtworkSourceFrozen ? this.frozenMorphArtworkHeight :
      (this.playerStore.currentTrack?.artworkHeight ?? 0);
    return this.containedArtworkHeight(width, height);
  }

  private morphArtworkWidth(): number {
    return this.morphValue(PlayerLayoutSpec.MINI_ARTWORK_SIZE, this.morphTargetArtworkWidth());
  }

  private morphArtworkHeight(): number {
    return this.morphValue(PlayerLayoutSpec.MINI_ARTWORK_SIZE, this.morphTargetArtworkHeight());
  }

  private isMorphActive(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.IDLE;
  }

  private beginMorphPhase(phase: PlayerMorphPhase): number {
    this.morphTransitionEpoch += 1;
    this.playerMorphPhase = phase;
    return this.morphTransitionEpoch;
  }

  private isCurrentMorphTransition(epoch: number): boolean {
    return epoch === this.morphTransitionEpoch;
  }

  private morphVerticalTravelDistance(): number {
    return Math.max(
      1,
      this.frozenMiniPlayerFrame.y - this.frozenRootFrame.y
    );
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
    this.getUIContext().animateTo({
      duration: PlayerMotionSpec.BACKGROUND_HANDOFF_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        this.playerMorphPhase = PlayerMorphPhase.IDLE;
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

  private updateMiniPlayerGesture(event: GestureEvent): void {
    const horizontalDistance = Math.abs(event.offsetX);
    const upwardDistance = Math.max(0, -event.offsetY);
    const verticalDistance = Math.abs(event.offsetY);
    if (this.playerGestureAxis === PlayerGestureAxis.UNDECIDED &&
      Math.max(horizontalDistance, verticalDistance) > PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE) {
      this.playerGestureAxis = horizontalDistance > verticalDistance ?
        PlayerGestureAxis.HORIZONTAL : PlayerGestureAxis.VERTICAL;
    }

    if (this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL) {
      this.miniPlayerOffsetX = event.offsetX /
        (1 + horizontalDistance / PlayerMotionSpec.HORIZONTAL_SWIPE_RESISTANCE);
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
        this.freezeMorphArtworkSource();
        this.beginMorphPhase(PlayerMorphPhase.DRAGGING);
        this.playerMorphBackgroundOpacity = 1;
      }
      this.playerExpandProgress = this.clamp(
        upwardDistance / this.morphVerticalTravelDistance(),
        0,
        1
      );
    }
  }

  private finishMiniPlayerGesture(): void {
    const wasVerticalGesture = this.playerGestureAxis === PlayerGestureAxis.VERTICAL;
    const wasHorizontalGesture = this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL;
    const swipeOffset = this.miniPlayerOffsetX;
    const shouldChangeTrack = wasHorizontalGesture && Math.abs(swipeOffset) >=
      PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
    const shouldExpand = wasVerticalGesture &&
      this.playerExpandProgress >= this.morphGestureCompletionProgress();
    const duration = shouldExpand ? PlayerMotionSpec.OPEN_DURATION : PlayerMotionSpec.CANCEL_DURATION;
    const epoch = wasVerticalGesture ? this.beginMorphPhase(
      shouldExpand ? PlayerMorphPhase.OPENING : PlayerMorphPhase.CLOSING
    ) : this.morphTransitionEpoch;
    this.getUIContext().animateTo({
      duration: duration,
      curve: shouldExpand ? curves.springMotion(
        PlayerMotionSpec.OPEN_SPRING_RESPONSE,
        PlayerMotionSpec.OPEN_SPRING_DAMPING
      ) : Curve.EaseOut,
      onFinish: () => {
        if (shouldChangeTrack) {
          if (swipeOffset < 0) {
            playbackRuntime.next();
          } else {
            playbackRuntime.previous();
          }
        }
        if (!wasVerticalGesture || !this.isCurrentMorphTransition(epoch)) {
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
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
    this.swipeHapticTriggered = false;
  }

  private showFullPlayer(): void {
    if (!this.miniBarExpanded) {
      this.compactTabsController.applyMiniBarStyle(HdsBarStyle.EXPAND);
      return;
    }
    this.freezeMiniPlayerGeometry();
    this.freezeMorphArtworkSource();
    const epoch = this.beginMorphPhase(PlayerMorphPhase.OPENING);
    this.playerMorphBackgroundOpacity = 1;
    this.getUIContext().animateTo({
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

  private hideFullPlayer(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.IDLE ||
      this.playerMorphPhase === PlayerMorphPhase.CLOSING ||
      this.playerMorphPhase === PlayerMorphPhase.BACKGROUND_HANDOFF) {
      return;
    }
    this.restoreReturnMiniBarStyle();
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
    this.getUIContext().animateTo({
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

  private beginFullPlayerGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    this.freezeMiniPlayerGeometry(false);
    this.freezeMorphArtworkSource();
    this.beginMorphPhase(PlayerMorphPhase.DRAGGING);
    this.playerMorphBackgroundOpacity = 1;
  }

  private updateFullPlayerGesture(event: GestureEvent): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.DRAGGING) {
      return;
    }
    const downwardDistance = Math.max(0, event.offsetY);
    this.playerExpandProgress = 1 - this.clamp(
      downwardDistance / this.morphVerticalTravelDistance(),
      0,
      1
    );
  }

  private finishFullPlayerGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.DRAGGING) {
      return;
    }
    const shouldClose = this.playerExpandProgress <= 1 - this.morphGestureCompletionProgress();
    if (shouldClose) {
      this.restoreReturnMiniBarStyle();
      this.animateFullPlayerClose();
      return;
    }
    const epoch = this.beginMorphPhase(PlayerMorphPhase.OPENING);
    this.getUIContext().animateTo({
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

  private morphArtworkSourceRadius(): number {
    const fullRadius = Math.min(
      PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
      Math.min(this.morphTargetArtworkWidth(), this.morphTargetArtworkHeight()) / 2
    );
    return this.morphValue(
      PlayerLayoutSpec.MINI_ARTWORK_RADIUS,
      fullRadius
    );
  }

  @Builder
  private NavigationShell() {
    ResponsiveNavigationShell({
      libraryStore: this.libraryStore,
      playerStore: this.playerStore,
      topInset: this.statusBarAvoidHeight,
      bottomInset: this.navigationAvoidHeight,
      rootWidth: this.rootFrame.width,
      rootHeight: this.rootFrame.height,
      selectedTabIndex: this.selectedTabIndex,
      selectedMoreRouteId: this.selectedMoreRouteId,
      miniBarExpanded: this.miniBarExpanded,
      miniPlayerOffsetX: this.miniPlayerOffsetX,
      morphActive: this.isMorphActive(),
      measuredMiniPlayerFrame: this.measuredMiniPlayerFrame,
      appearancePalette: this.appearancePalette,
      compactTabsController: this.compactTabsController,
      expandedTabsController: this.expandedTabsController,
      primaryTitleContents: this.primaryTitleContents,
      moreTitleContents: this.moreTitleContents,
      tabPathStacks: this.tabPathStacks,
      expandedMorePathStacks: this.expandedMorePathStacks,
      pageScrollers: this.pageScrollers,
      libraryManagementScroller: this.libraryManagementScroller,
      onCompactTabChange: (index: number): void => this.handleCompactTabChange(index),
      onCompactTabClick: (index: number): void => this.handleCompactTabBarClick(index),
      onExpandedTabChange: (index: number): void => this.handleExpandedTabChange(index),
      onExpandedTabClick: (index: number): void => this.handleExpandedTabBarClick(index),
      onOpenMoreDestination: (routeId: string): void => this.openMoreDestination(routeId),
      onMiniBarStyleChange: (expanded: boolean): void => {
        this.miniBarExpanded = expanded;
      },
      onShowFullPlayer: (): void => this.showFullPlayer(),
      onMeasuredMiniPlayerFrame: (frame: PlayerFrame): void => {
        this.measuredMiniPlayerFrame = frame;
      },
      onMiniPlayerGestureStart: (): void => {
        this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
        this.freezeMiniPlayerGeometry();
      },
      onMiniPlayerGestureUpdate: (event: GestureEvent): void => this.updateMiniPlayerGesture(event),
      onMiniPlayerGestureFinish: (): void => this.finishMiniPlayerGesture()
    })
  }

  @Builder
  private MorphPlayer() {
    Stack() {
      Stack() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [
          [$r('app.color.full_player_gradient_start'), 0.0],
          [$r('app.color.full_player_gradient_middle'), 0.55],
          [$r('app.color.full_player_gradient_end'), 1.0]
        ]
      })
      .opacity(this.playerMorphBackgroundOpacity)

      Stack() {
        Stack() {
          FullPlayerContent({
            playerStore: this.playerStore,
            topInset: this.statusBarAvoidHeight,
            bottomInset: this.navigationAvoidHeight,
            showArtwork: false,
            rootFrame: this.frozenRootFrame,
            previousArtworkTarget: this.artworkTarget,
            onClose: () => this.hideFullPlayer()
          })
        }
        .width(this.frozenRootFrame.width)
        .height(this.frozenRootFrame.height)
        .position({ x: 0, y: 0 })
        .opacity(this.clamp(
          (this.playerExpandProgress - PlayerMotionSpec.FULL_CONTENT_FADE_START) *
            PlayerMotionSpec.FULL_CONTENT_FADE_RATE,
          0,
          1
        ))

        if (this.playerExpandProgress < PlayerMotionSpec.MINI_CONTENT_VISIBLE_LIMIT) {
          Stack() {
            MiniPlayerContent({
              playerStore: this.playerStore,
              expanded: this.miniBarExpanded,
              showArtwork: false,
              followsSwipeOffset: false,
              swipeOffsetX: 0,
              onShowFullPlayer: () => this.showFullPlayer()
            })
          }
          .width('100%')
          .height('100%')
          .opacity(1 - this.clamp(
            (this.playerExpandProgress - PlayerMotionSpec.MINI_CONTENT_FADE_START) *
              PlayerMotionSpec.MINI_CONTENT_FADE_RATE,
            0,
            1
          ))
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(this.morphValue(this.frozenMiniPlayerFrame.width, this.frozenRootFrame.width))
    .height(this.morphValue(this.frozenMiniPlayerFrame.height, this.frozenRootFrame.height))
    .position({ x: 0, y: 0 })
    .translate({
      x: this.morphValue(this.frozenMiniPlayerFrame.x, this.frozenRootFrame.x),
      y: this.morphValue(this.frozenMiniPlayerFrame.y, this.frozenRootFrame.y)
    })
    .borderRadius(28 * (1 - this.clamp(this.playerExpandProgress, 0, 1)))
    .clip(true)
  }

  @Builder
  private FullPlayerOverlay() {
    Stack() {
      this.MorphPlayer()

      Stack() {
        this.MorphArtwork()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 3 })
        .onActionStart(() => {
          this.beginFullPlayerGesture();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateFullPlayerGesture(event);
        })
        .onActionEnd(() => {
          this.finishFullPlayerGesture();
        })
        .onActionCancel(() => {
          this.finishFullPlayerGesture();
        })
    )
  }

  @Builder
  private MorphArtwork() {
    Stack() {
      Image(this.morphArtworkSource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
    .width(this.morphArtworkWidth())
    .height(this.morphArtworkHeight())
    .borderRadius(this.morphArtworkSourceRadius())
    .clip(true)
    .shadow({
      radius: PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS *
        this.clamp(this.playerExpandProgress, 0, 1),
      color: $r('app.color.artwork_shadow'),
      offsetY: PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y *
        this.clamp(this.playerExpandProgress, 0, 1)
    })
    .position({ x: 0, y: 0 })
    .translate({
      x: this.morphValue(
        this.frozenMiniPlayerFrame.x + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.frozenArtworkTarget.x +
          (this.fullArtworkSlotSize() - this.morphTargetArtworkWidth()) / 2
      ),
      y: this.morphValue(
        this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.frozenArtworkTarget.y +
          (this.fullArtworkSlotSize() - this.morphTargetArtworkHeight()) / 2
      )
    })
  }

  @Builder
  private FullPlayerGeometryProbe() {
    Stack() {
      FullPlayerContent({
        playerStore: this.playerStore,
        topInset: this.statusBarAvoidHeight,
        bottomInset: this.navigationAvoidHeight,
        showArtwork: false,
        measuresArtworkTarget: true,
        rootFrame: this.rootFrame,
        previousArtworkTarget: this.artworkTarget,
        onClose: () => this.hideFullPlayer(),
        onArtworkTarget: (target: PlayerPoint): void => {
          this.artworkTarget = target;
        }
      })
    }
    .width('100%')
    .height('100%')
    .opacity(0)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      this.FullPlayerGeometryProbe()

      this.NavigationShell()

      if (this.isMorphActive()) {
        this.FullPlayerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .id('player_page_root')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const previousWideLayout = this.usesWideLayout();
      const nextWidth = this.lengthToNumber(newValue.width, this.rootFrame.width);
      const nextHeight = this.lengthToNumber(newValue.height, this.rootFrame.height);
      this.rootFrame = {
        x: this.lengthToNumber(newValue.globalPosition.x, this.rootFrame.x),
        y: this.lengthToNumber(newValue.globalPosition.y, this.rootFrame.y),
        width: nextWidth,
        height: nextHeight
      };
      const nextWideLayout = this.usesWideLayout(nextWidth);
      if (previousWideLayout !== nextWideLayout) {
        this.miniBarExpanded = nextWideLayout;
        this.reconcileResponsiveNavigation(previousWideLayout, nextWideLayout);
      }
    })
  }
}
