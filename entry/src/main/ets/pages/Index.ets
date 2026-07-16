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
  ALL_ROOT_NAVIGATION_ITEMS,
  DEFAULT_NAVIGATION_ORDER,
  NavigationPageItem,
  NavigationRoute,
  PRIMARY_NAVIGATION_COUNT,
  SETTINGS_NAVIGATION_ITEM,
  navigationItem,
  navigationItemIndex,
  normalizeNavigationOrder,
  orderedNavigationItems
} from '../components/navigation/MoreNavigation';
import { ResponsiveNavigationShell } from '../components/navigation/ResponsiveNavigationShell';
import {
  AppAppearanceListener,
  AppAppearancePalette,
  appAppearanceController
} from '../appearance/AppAppearance';
import { PaletteMotionSpec } from '../appearance/PaletteMotionSpec';

const MORE_TAB_INDEX: number = PRIMARY_NAVIGATION_COUNT;
@Entry
@Component
struct Index {
  @State statusBarAvoidHeight: number = 0;
  @State navigationAvoidHeight: number = 0;
  @State appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();
  @State navigationOrder: Array<string> = DEFAULT_NAVIGATION_ORDER;
  @State selectedRouteId: string = NavigationRoute.PLAYLISTS;
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
  private readonly rootTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> =
    new Array<ComponentContent<AppPrimaryTitleParams> | undefined>(ALL_ROOT_NAVIGATION_ITEMS.length);
  private readonly rootPathStacks: Array<NavPathStack> = ALL_ROOT_NAVIGATION_ITEMS.map(() => new NavPathStack());
  private readonly rootScrollers: Array<Scroller> = ALL_ROOT_NAVIGATION_ITEMS.map(() => new Scroller());
  private readonly morePathStack: NavPathStack = new NavPathStack();
  private readonly moreScroller: Scroller = new Scroller();
  private readonly customizationScroller: Scroller = new Scroller();

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
        this.navigationOrder = normalizeNavigationOrder(
          this.settingsRepository.getNavigationOrder(DEFAULT_NAVIGATION_ORDER)
        );
        const oldTabIndex = this.normalizeTabIndex(this.settingsRepository.getLastTabIndex());
        const fallbackRoute = oldTabIndex < PRIMARY_NAVIGATION_COUNT ?
          this.navigationOrder[oldTabIndex] : this.navigationOrder[PRIMARY_NAVIGATION_COUNT];
        const storedRoute = this.settingsRepository.getLastNavigationRoute(fallbackRoute);
        this.selectedRouteId = navigationItem(storedRoute) === undefined ? NavigationRoute.PLAYLISTS : storedRoute;
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
    for (let index = 0; index < this.rootTitleContents.length; index += 1) {
      this.rootTitleContents[index]?.dispose();
      this.rootTitleContents[index] = undefined;
    }
  }

  private initializePrimaryTitleContents(): void {
    const uiContext = this.getUIContext();
    for (let index = 0; index < ALL_ROOT_NAVIGATION_ITEMS.length; index += 1) {
      if (this.rootTitleContents[index] === undefined) {
        this.rootTitleContents[index] = new ComponentContent(
          uiContext,
          wrapBuilder(AppPrimaryTitleContent),
          new AppPrimaryTitleParams(ALL_ROOT_NAVIGATION_ITEMS[index].label, this.appearancePalette.titlePrimary)
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
    for (let index = 0; index < this.rootTitleContents.length; index += 1) {
      this.rootTitleContents[index]?.update(
        new AppPrimaryTitleParams(ALL_ROOT_NAVIGATION_ITEMS[index].label, palette.titlePrimary)
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
    return Number.isInteger(index) && index >= 0 && index <= MORE_TAB_INDEX ? index : 0;
  }

  private orderedItems(): Array<NavigationPageItem> {
    return orderedNavigationItems(this.navigationOrder);
  }

  private primaryItems(): Array<NavigationPageItem> {
    return this.orderedItems().slice(0, PRIMARY_NAVIGATION_COUNT);
  }

  private moreItems(): Array<NavigationPageItem> {
    return this.orderedItems().slice(PRIMARY_NAVIGATION_COUNT).concat([SETTINGS_NAVIGATION_ITEM]);
  }

  private expandedItems(): Array<NavigationPageItem> {
    return this.orderedItems().concat([SETTINGS_NAVIGATION_ITEM]);
  }

  private compactTabIndex(): number {
    const primary = this.primaryItems();
    for (let index = 0; index < primary.length; index += 1) {
      if (primary[index].routeId === this.selectedRouteId) {
        return index;
      }
    }
    return MORE_TAB_INDEX;
  }

  private selectRoute(routeId: string): void {
    if (navigationItem(routeId) === undefined) {
      return;
    }
    this.selectedRouteId = routeId;
    this.settingsRepository?.setLastNavigationRoute(routeId);
    this.settingsRepository?.setLastTabIndex(this.compactTabIndex());
  }

  private handleCompactTabChange(index: number): void {
    const normalizedIndex = this.normalizeTabIndex(index);
    if (normalizedIndex < PRIMARY_NAVIGATION_COUNT) {
      this.selectRoute(this.primaryItems()[normalizedIndex].routeId);
      return;
    }
    if (this.compactTabIndex() !== MORE_TAB_INDEX) {
      this.selectRoute(this.moreItems()[0].routeId);
    }
  }

  private handleCompactTabBarClick(index: number): void {
    if (index !== this.compactTabIndex()) {
      return;
    }
    if (index < PRIMARY_NAVIGATION_COUNT) {
      this.rootPathStacks[navigationItemIndex(this.selectedRouteId)].clear(true);
    } else {
      this.morePathStack.clear(true);
    }
  }

  private expandedTabIndex(): number {
    const items = this.expandedItems();
    for (let index = 0; index < items.length; index += 1) {
      if (items[index].routeId === this.selectedRouteId) {
        return index;
      }
    }
    return 0;
  }

  private handleExpandedTabChange(index: number): void {
    const items = this.expandedItems();
    if (index < 0 || index >= items.length) {
      return;
    }
    this.selectRoute(items[index].routeId);
    this.morePathStack.clear(false);
  }

  private handleExpandedTabBarClick(index: number): void {
    if (index !== this.expandedTabIndex()) {
      return;
    }
    this.rootPathStacks[navigationItemIndex(this.selectedRouteId)].clear(true);
  }

  private openMoreDestination(routeId: string): void {
    const moreItems = this.moreItems();
    let isMoreItem = false;
    for (let index = 0; index < moreItems.length; index += 1) {
      if (moreItems[index].routeId === routeId) {
        isMoreItem = true;
        break;
      }
    }
    if (!isMoreItem) {
      return;
    }
    this.selectRoute(routeId);
    this.morePathStack.pushPath({ name: routeId });
  }

  private openNavigationCustomization(): void {
    this.selectRoute(NavigationRoute.SETTINGS);
    const pathStack = this.usesWideLayout() ?
      this.rootPathStacks[navigationItemIndex(NavigationRoute.SETTINGS)] : this.morePathStack;
    pathStack.pushPath({ name: NavigationRoute.NAVIGATION_CUSTOMIZATION });
  }

  private moveNavigationItem(from: number, to: number): void {
    const normalized = normalizeNavigationOrder(this.navigationOrder);
    if (from < 0 || from >= normalized.length || to < 0 || to >= normalized.length || from === to) {
      return;
    }
    const moved = normalized[from];
    normalized.splice(from, 1);
    normalized.splice(to, 0, moved);
    this.navigationOrder = normalized;
    this.settingsRepository?.setNavigationOrder(normalized);
  }

  private reconcileResponsiveNavigation(previousWideLayout: boolean, nextWideLayout: boolean): void {
    if (previousWideLayout === nextWideLayout || this.compactTabIndex() !== MORE_TAB_INDEX) {
      return;
    }
    this.morePathStack.clear(false);
    if (!nextWideLayout) {
      this.morePathStack.pushPath({ name: this.selectedRouteId }, false);
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

  private pageThemeTintOpacity(): number {
    return this.appearancePalette.windowBackground.toUpperCase() === '#FF000000' ? 0.14 : 0.08;
  }

  private fullPlayerFrame(): PlayerFrame {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ? this.rootFrame : this.frozenRootFrame;
  }

  private fullPlayerArtworkTarget(): PlayerPoint {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ? this.artworkTarget : this.frozenArtworkTarget;
  }

  onBackPress(): boolean {
    if (!this.isMorphActive()) {
      return false;
    }
    this.hideFullPlayer();
    return true;
  }

  private fullArtworkSlotSize(): number {
    const fullPlayerFrame = this.fullPlayerFrame();
    return PlayerLayoutSpec.fullArtworkSize(
      fullPlayerFrame.width,
      fullPlayerFrame.height,
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
        this.freezeMiniPlayerGeometry();
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
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
    this.swipeHapticTriggered = false;

    if (wasHorizontalGesture) {
      const shouldChangeTrack = Math.abs(swipeOffset) >=
        PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
      this.getUIContext().animateTo({
        duration: PlayerMotionSpec.CANCEL_DURATION,
        curve: Curve.EaseOut,
        onFinish: () => {
          if (!shouldChangeTrack) {
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
    this.getUIContext().animateTo({
      duration: duration,
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
      navigationOrder: this.navigationOrder,
      selectedRouteId: this.selectedRouteId,
      miniBarExpanded: this.miniBarExpanded,
      miniPlayerOffsetX: this.miniPlayerOffsetX,
      morphActive: this.isMorphActive(),
      measuredMiniPlayerFrame: this.measuredMiniPlayerFrame,
      appearancePalette: this.appearancePalette,
      compactTabsController: this.compactTabsController,
      expandedTabsController: this.expandedTabsController,
      rootTitleContents: this.rootTitleContents,
      rootPathStacks: this.rootPathStacks,
      rootScrollers: this.rootScrollers,
      morePathStack: this.morePathStack,
      moreScroller: this.moreScroller,
      customizationScroller: this.customizationScroller,
      onCompactTabChange: (index: number): void => this.handleCompactTabChange(index),
      onCompactTabClick: (index: number): void => this.handleCompactTabBarClick(index),
      onExpandedTabChange: (index: number): void => this.handleExpandedTabChange(index),
      onExpandedTabClick: (index: number): void => this.handleExpandedTabBarClick(index),
      onOpenMoreDestination: (routeId: string): void => this.openMoreDestination(routeId),
      onOpenNavigationCustomization: (): void => this.openNavigationCustomization(),
      onNavigationItemMove: (from: number, to: number): void => this.moveNavigationItem(from, to),
      onMiniBarStyleChange: (expanded: boolean): void => {
        this.miniBarExpanded = expanded;
      },
      onShowFullPlayer: (): void => this.showFullPlayer(),
      onMeasuredMiniPlayerFrame: (frame: PlayerFrame): void => {
        this.measuredMiniPlayerFrame = frame;
      },
      onMiniPlayerGestureStart: (): void => {
        this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
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
      .backgroundColor(this.playerStore.themePrimary())
      .opacity(this.playerMorphBackgroundOpacity)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })

      Stack() {
        Stack() {
          FullPlayerContent({
            playerStore: this.playerStore,
            topInset: this.statusBarAvoidHeight,
            bottomInset: this.navigationAvoidHeight,
            showArtwork: false,
            rootFrame: this.fullPlayerFrame(),
            previousArtworkTarget: this.artworkTarget,
            onClose: () => this.hideFullPlayer()
          })
        }
        .width(this.fullPlayerFrame().width)
        .height(this.fullPlayerFrame().height)
        .position({ x: 0, y: 0 })
        .opacity(PlayerMotionSpec.fullContentOpacity(this.playerExpandProgress))

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
    .width(this.morphValue(this.frozenMiniPlayerFrame.width, this.fullPlayerFrame().width))
    .height(this.morphValue(this.frozenMiniPlayerFrame.height, this.fullPlayerFrame().height))
    .position({ x: 0, y: 0 })
    .translate({
      x: this.morphValue(this.frozenMiniPlayerFrame.x, this.fullPlayerFrame().x),
      y: this.morphValue(this.frozenMiniPlayerFrame.y, this.fullPlayerFrame().y)
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
        this.fullPlayerArtworkTarget().x +
          (this.fullArtworkSlotSize() - this.morphTargetArtworkWidth()) / 2
      ),
      y: this.morphValue(
        this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.fullPlayerArtworkTarget().y +
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
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .hitTestBehavior(HitTestMode.None)

      if (this.playerStore.hasCurrentTrack()) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.playerStore.themePrimary())
          .opacity(this.pageThemeTintOpacity())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          .hitTestBehavior(HitTestMode.None)
      }

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
