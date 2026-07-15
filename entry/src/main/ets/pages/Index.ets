import {
  HdsBarLayoutMode,
  HdsBarStyle,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  hdsMaterial
} from '@kit.UIDesignKit';
import { ComponentContent, curves, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import {
  PlayerFrame,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec,
  PlayerPoint
} from '../components/player/PlayerMotion';
import { AppNavigationStyle } from '../components/navigation/AppNavigationStyle';
import {
  AppPrimaryTitleContent,
  AppPrimaryTitleParams
} from '../components/navigation/AppPrimaryTitleContent';
import {
  LibrarySortMenu,
  LibrarySortMenuParams
} from '../components/library/LibrarySortMenu';
import {
  AlbumSortField,
  SortDirection,
  TrackSortField
} from '../library/model/LibraryModels';
import { LibraryStore } from '../library/store/LibraryStore';
import { AlbumsPage } from './library/AlbumsPage';
import { LibraryManagementPage } from './library/LibraryManagementPage';
import { MorePage } from './library/MorePage';
import { PlaylistsPage } from './library/PlaylistsPage';
import { SongsPage } from './library/SongsPage';
import { SettingsRepository } from '../settings/SettingsRepository';
import { AppShellLayoutSpec } from '../components/layout/AppShellLayoutSpec';
import {
  MORE_NAVIGATION_ITEMS,
  MoreNavigationItem,
  MoreRoute
} from '../components/navigation/MoreNavigation';

interface NavigationItem {
  label: string;
  symbol: Resource;
}

const TRACK_SORT_LABELS: Array<string> = ['名称', '专辑', '艺术家', '发行日期', '添加时间'];
const ALBUM_SORT_LABELS: Array<string> = ['名称', '艺术家', '发行日期', '添加时间'];
const TRACK_SORT_MENU_ID: string = 'track_sort_menu';
const ALBUM_SORT_MENU_ID: string = 'album_sort_menu';
const MORE_TAB_INDEX: number = 3;

@Entry
@Component
struct Index {
  @State statusBarAvoidHeight: number = 0;
  @State navigationAvoidHeight: number = 0;
  @State selectedTabIndex: number = 0;
  @State selectedMoreRouteId: string = MoreRoute.LIBRARY_MANAGEMENT;
  @State libraryStore: LibraryStore = new LibraryStore();
  @State isPlaying: boolean = false;
  @State miniBarExpanded: boolean = false;
  @State miniPlayerOffsetX: number = 0;
  @State playerExpandProgress: number = 0;
  @State playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  @State swipeHapticTriggered: boolean = false;
  @State playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @State playerMorphBackgroundOpacity: number = 1;
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
  private avoidAreaObserverEpoch: number = 0;
  private avoidAreaObserverActive: boolean = false;
  private mainWindow?: window.Window;
  private readonly avoidAreaChangeCallback = (options: window.AvoidAreaOptions): void => {
    if (this.avoidAreaObserverActive) {
      this.applyAvoidArea(options.type, options.area);
    }
  };

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
  private readonly navigationItems: NavigationItem[] = [
    { label: '播放列表', symbol: $r('sys.symbol.music_note_list_fill') },
    { label: '音乐', symbol: $r('sys.symbol.music_fill') },
    { label: '专辑', symbol: $r('sys.symbol.opticaldisc') },
    { label: '更多', symbol: $r('sys.symbol.square_fill_grid_2x2') }
  ];

  aboutToAppear(): void {
    this.initializePrimaryTitleContents();
    this.avoidAreaObserverActive = true;
    const observerEpoch = ++this.avoidAreaObserverEpoch;
    this.initializeWindowAvoidAreas(observerEpoch);
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      const abilityContext = context as common.UIAbilityContext;
      try {
        this.settingsRepository = new SettingsRepository(abilityContext);
        this.selectedTabIndex = this.normalizeTabIndex(this.settingsRepository.getLastTabIndex());
      } catch (error) {
        const businessError = error as BusinessError;
        console.warn(`Unable to initialize settings: ${businessError.code}, ${businessError.message}`);
      }
      this.libraryStore.initialize(abilityContext, this.settingsRepository);
    }
  }

  aboutToDisappear(): void {
    this.avoidAreaObserverActive = false;
    ++this.avoidAreaObserverEpoch;
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      this.mainWindow = undefined;
    }
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
    for (let index = 0; index < this.navigationItems.length; index += 1) {
      if (this.primaryTitleContents[index] === undefined) {
        this.primaryTitleContents[index] = new ComponentContent(
          uiContext,
          wrapBuilder(AppPrimaryTitleContent),
          new AppPrimaryTitleParams(this.navigationItems[index].label)
        );
      }
    }
    for (let index = 0; index < MORE_NAVIGATION_ITEMS.length; index += 1) {
      if (this.moreTitleContents[index] === undefined) {
        this.moreTitleContents[index] = new ComponentContent(
          uiContext,
          wrapBuilder(AppPrimaryTitleContent),
          new AppPrimaryTitleParams(MORE_NAVIGATION_ITEMS[index].label)
        );
      }
    }
  }

  private async initializeWindowAvoidAreas(observerEpoch: number): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const mainWindow = await window.getLastWindow(context);
      if (!this.avoidAreaObserverActive || observerEpoch !== this.avoidAreaObserverEpoch) {
        return;
      }
      if (this.mainWindow !== undefined) {
        this.mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      }
      this.mainWindow = mainWindow;
      this.applyAvoidArea(
        window.AvoidAreaType.TYPE_SYSTEM,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      );
      this.applyAvoidArea(
        window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      );
      mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to observe window avoid areas: ${businessError.code}, ${businessError.message}`);
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

  private usesPortraitSideNavigation(
    width: number = this.rootFrame.width,
    height: number = this.rootFrame.height
  ): boolean {
    return this.usesWideLayout(width) && width < height;
  }

  private wideMiniPlayerWidth(): number {
    return this.usesPortraitSideNavigation() ?
      AppShellLayoutSpec.MINI_PLAYER_MEDIUM_WIDTH : AppShellLayoutSpec.MINI_PLAYER_LARGE_WIDTH;
  }

  private expandedTabBarWidth(): number {
    return this.usesPortraitSideNavigation() ?
      AppShellLayoutSpec.EXPANDED_TAB_BAR_PORTRAIT_WIDTH :
      AppShellLayoutSpec.EXPANDED_TAB_BAR_LANDSCAPE_WIDTH;
  }

  private compactTabsFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barWidth: {
        smallWidth: AppShellLayoutSpec.COMPACT_TAB_SMALL_WIDTH,
        mediumWidth: AppShellLayoutSpec.COMPACT_TAB_MEDIUM_WIDTH,
        largeWidth: AppShellLayoutSpec.COMPACT_TAB_LARGE_WIDTH
      },
      barBottomMargin: AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN,
      gradientMask: { maskColor: $r('app.color.float_bar_gradient_mask'), maskHeight: 84 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      miniBar: {
        miniBarBuilder: () => this.MiniPlayer(),
        miniBarWidth: {
          smallWidth: AppShellLayoutSpec.MINI_PLAYER_SMALL_WIDTH,
          mediumWidth: AppShellLayoutSpec.MINI_PLAYER_MEDIUM_WIDTH,
          largeWidth: AppShellLayoutSpec.MINI_PLAYER_LARGE_WIDTH
        },
        miniBarStyle: HdsBarStyle.COLLAPSE,
        barLayoutMode: HdsBarLayoutMode.HORIZONTAL,
        onBarStyleChange: (miniBarStyle: HdsBarStyle) => {
          this.miniBarExpanded = miniBarStyle === HdsBarStyle.EXPAND;
        },
        enableMiniBarBackground: true,
        enableMiniBarClip: true
      }
    };
  }

  private wideMiniPlayerFloatingStyle(): HdsTabsFloatingStyle {
    const miniPlayerWidth = this.wideMiniPlayerWidth();
    return {
      barWidth: {
        smallWidth: AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH,
        mediumWidth: AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH,
        largeWidth: AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH
      },
      barSideMargin: AppShellLayoutSpec.WIDE_SIDE_MARGIN,
      barBottomMargin: AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      barOpacity: 0,
      miniBar: {
        miniBarBuilder: () => this.MiniPlayer(),
        miniBarWidth: {
          smallWidth: miniPlayerWidth,
          mediumWidth: miniPlayerWidth,
          largeWidth: miniPlayerWidth
        },
        miniBarStyle: HdsBarStyle.EXPAND,
        barLayoutMode: HdsBarLayoutMode.HORIZONTAL,
        onBarStyleChange: (miniBarStyle: HdsBarStyle) => {
          this.miniBarExpanded = miniBarStyle === HdsBarStyle.EXPAND;
        },
        enableMiniBarBackground: true,
        enableMiniBarClip: true
      }
    };
  }

  private normalizeTabIndex(index: number): number {
    return Number.isInteger(index) && index >= 0 && index < this.navigationItems.length ? index : 0;
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

  private applyTrackSort(field: TrackSortField, direction: SortDirection): void {
    this.libraryStore.setTrackSort(field, direction).then(() => {
      if (this.libraryStore.trackDataSource.totalCount() > 0) {
        this.pageScrollers[1].scrollToIndex(0, false, ScrollAlign.START);
      }
    });
  }

  private applyAlbumSort(field: AlbumSortField, direction: SortDirection): void {
    this.libraryStore.setAlbumSort(field, direction).then(() => {
      if (this.libraryStore.albumDataSource.totalCount() > 0) {
        this.pageScrollers[2].scrollToIndex(0, false, ScrollAlign.START);
      }
    });
  }

  private openSortMenu(tabIndex: number, targetId: string): void {
    const isTracks = tabIndex === 1;
    const params = isTracks ? new LibrarySortMenuParams(
      TRACK_SORT_LABELS,
      this.libraryStore.trackSortField,
      this.libraryStore.trackSortDirection === SortDirection.DESCENDING,
      (index: number) => this.applyTrackSort(index as TrackSortField, this.libraryStore.trackSortDirection),
      (descending: boolean) => this.applyTrackSort(this.libraryStore.trackSortField,
        descending ? SortDirection.DESCENDING : SortDirection.ASCENDING)
    ) : new LibrarySortMenuParams(
      ALBUM_SORT_LABELS,
      this.libraryStore.albumSortField,
      this.libraryStore.albumSortDirection === SortDirection.DESCENDING,
      (index: number) => this.applyAlbumSort(index as AlbumSortField, this.libraryStore.albumSortDirection),
      (descending: boolean) => this.applyAlbumSort(this.libraryStore.albumSortField,
        descending ? SortDirection.DESCENDING : SortDirection.ASCENDING)
    );
    const content = new ComponentContent(
      this.getUIContext(), wrapBuilder(LibrarySortMenu), params
    );
    this.getUIContext().getPromptAction().openMenu(content, { id: targetId }, { enableArrow: true })
      .catch((error: BusinessError) => {
        console.warn(`Unable to open sort menu: ${error.code}, ${error.message}`);
      });
  }

  private sortTitleMenu(index: number): HdsNavigationMenuContentOptions | undefined {
    if (index !== 1 && index !== 2) {
      return undefined;
    }
    const targetId = index === 1 ? TRACK_SORT_MENU_ID : ALBUM_SORT_MENU_ID;
    const descending = index === 1 ?
      this.libraryStore.trackSortDirection === SortDirection.DESCENDING :
      this.libraryStore.albumSortDirection === SortDirection.DESCENDING;
    return {
      maxCount: 1,
      value: [{
        content: {
          label: '排序',
          icon: descending ? $r('sys.symbol.arrow_down') : $r('sys.symbol.arrow_up'),
          componentId: targetId,
          action: () => this.openSortMenu(index, targetId)
        }
      }]
    };
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

  private freezeMiniPlayerGeometry(): void {
    this.returnToExpandedMiniBar = this.miniBarExpanded;
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

  private morphValue(start: number, end: number): number {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private morphArtworkShadowColor(): string {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    const alpha = Math.round(0x3A * progress).toString(16).padStart(2, '0').toUpperCase();
    return `#${alpha}30319B`;
  }

  private morphArtworkScale(): number {
    return this.morphValue(
      PlayerLayoutSpec.MINI_ARTWORK_SIZE,
      PlayerLayoutSpec.FULL_ARTWORK_SIZE
    ) / PlayerLayoutSpec.FULL_ARTWORK_SIZE;
  }

  private morphArtworkSourceRadius(): number {
    return this.morphValue(
      PlayerLayoutSpec.MINI_ARTWORK_RADIUS,
      PlayerLayoutSpec.FULL_ARTWORK_RADIUS
    ) / this.morphArtworkScale();
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
        this.beginMorphPhase(PlayerMorphPhase.DRAGGING);
        this.playerMorphBackgroundOpacity = 1;
      }
      this.playerExpandProgress = this.clamp(
        upwardDistance / PlayerMotionSpec.DRAG_DISTANCE,
        0,
        1
      );
    }
  }

  private finishMiniPlayerGesture(): void {
    const wasVerticalGesture = this.playerGestureAxis === PlayerGestureAxis.VERTICAL;
    const shouldExpand = wasVerticalGesture &&
      this.playerExpandProgress >= PlayerMotionSpec.EXPAND_THRESHOLD;
    const duration = shouldExpand ? PlayerMotionSpec.OPEN_DURATION : PlayerMotionSpec.CANCEL_DURATION;
    const epoch = wasVerticalGesture ? this.beginMorphPhase(
      shouldExpand ? PlayerMorphPhase.OPENING : PlayerMorphPhase.CLOSING
    ) : this.morphTransitionEpoch;
    this.getUIContext().animateTo({
      duration: duration,
      curve: shouldExpand ? curves.springMotion(0.5, 0.7) : Curve.EaseOut,
      onFinish: () => {
        if (!wasVerticalGesture || !this.isCurrentMorphTransition(epoch)) {
          return;
        }
        if (shouldExpand) {
          this.playerMorphPhase = PlayerMorphPhase.OPEN;
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
    const epoch = this.beginMorphPhase(PlayerMorphPhase.OPENING);
    this.playerMorphBackgroundOpacity = 1;
    this.getUIContext().animateTo({
      duration: PlayerMotionSpec.OPEN_DURATION,
      curve: curves.springMotion(0.5, 0.7),
      onFinish: () => {
        if (this.isCurrentMorphTransition(epoch)) {
          this.playerMorphPhase = PlayerMorphPhase.OPEN;
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
    if (this.miniBarExpanded !== this.returnToExpandedMiniBar) {
      this.compactTabsController.applyMiniBarStyle(
        this.returnToExpandedMiniBar ? HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE
      );
    }
    const epoch = this.beginMorphPhase(PlayerMorphPhase.CLOSING);
    this.getUIContext().animateTo({
      duration: PlayerMotionSpec.CLOSE_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.beginMorphBackgroundHandoff(epoch);
      }
    }, () => {
      this.playerExpandProgress = 0;
    });
  }

  @Builder
  private LibraryPage(index: number) {
    if (index === 0) {
      PlaylistsPage({
        store: this.libraryStore,
        topInset: this.statusBarAvoidHeight,
        bottomInset: this.navigationAvoidHeight,
        scroller: this.pageScrollers[0]
      })
    } else if (index === 1) {
      SongsPage({
        store: this.libraryStore,
        topInset: this.statusBarAvoidHeight,
        bottomInset: this.navigationAvoidHeight,
        scroller: this.pageScrollers[1]
      })
    } else if (index === 2) {
      AlbumsPage({
        store: this.libraryStore,
        topInset: this.statusBarAvoidHeight,
        bottomInset: this.navigationAvoidHeight,
        scroller: this.pageScrollers[2]
      })
    } else {
      MorePage({
        topInset: this.statusBarAvoidHeight,
        bottomInset: this.navigationAvoidHeight,
        scroller: this.pageScrollers[MORE_TAB_INDEX],
        openDestination: (routeId: string) => {
          this.openMoreDestination(routeId);
        }
      })
    }
  }

  @Builder
  private LibraryManagementContent() {
    LibraryManagementPage({
      store: this.libraryStore,
      topInset: this.statusBarAvoidHeight,
      bottomInset: this.navigationAvoidHeight,
      scroller: this.libraryManagementScroller
    })
  }

  @Builder
  private MoreRootPage(routeId: string) {
    if (routeId === MoreRoute.LIBRARY_MANAGEMENT) {
      this.LibraryManagementContent()
    }
  }

  @Builder
  private DestinationBuilder(name: string, _param: Object) {
    if (name === MoreRoute.LIBRARY_MANAGEMENT) {
      HdsNavDestination() {
        this.LibraryManagementContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        MORE_NAVIGATION_ITEMS[this.moreNavigationIndex(name)].label
      ))
      .bindToScrollable([this.libraryManagementScroller])
    }
  }

  @Builder
  private TabNavigation(index: number) {
    HdsNavigation(this.tabPathStacks[index]) {
      this.LibraryPage(index)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(AppNavigationStyle.primaryTitleBar(
      this.navigationItems[index].label,
      this.sortTitleMenu(index),
      this.primaryTitleContents[index]
    ))
    .bindToScrollable([this.pageScrollers[index]])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private ExpandedMoreNavigation(item: MoreNavigationItem, index: number) {
    HdsNavigation(this.expandedMorePathStacks[index]) {
      this.MoreRootPage(item.routeId)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(AppNavigationStyle.primaryTitleBar(
      item.label,
      undefined,
      this.moreTitleContents[index]
    ))
    .bindToScrollable([this.libraryManagementScroller])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private AlbumCover(size: number, radius: number) {
    Image($r('app.media.default_album_cover'))
      .width(size)
      .height(size)
      .objectFit(ImageFit.Cover)
      .borderRadius(radius)
      .clip(true)
  }

  @Builder
  private PlaybackButton(size: number) {
    Stack() {
      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
        .fontSize(size * 0.42)
        .fontColor(['#FFFFFF'])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor($r('app.color.theme_accent'))
    .shadow({ radius: 12, color: $r('app.color.theme_accent_shadow'), offsetY: 5 })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(this.isPlaying ? '暂停' : '播放')
    .onClick(() => {
      this.isPlaying = !this.isPlaying;
    })
  }

  @Builder
  private MiniPlayerContent(showArtwork: boolean, followsSwipeOffset: boolean) {
    Row({ space: 10 }) {
      Stack() {
        if (showArtwork) {
          this.AlbumCover(PlayerLayoutSpec.MINI_ARTWORK_SIZE, PlayerLayoutSpec.MINI_ARTWORK_RADIUS)
        }
      }
      .width(48)
      .height(48)
      .zIndex(2)
      .onClick(() => {
        this.showFullPlayer();
      })

      if (this.miniBarExpanded) {
        Column({ space: 2 }) {
          Text('尚未播放')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)

          Text('选择一首音乐')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .translate({ x: followsSwipeOffset ? this.miniPlayerOffsetX : 0 })
        .onClick(() => {
          this.showFullPlayer();
        })

        this.PlaybackButton(40)
      }
    }
    .height(56)
    .width('100%')
    .padding({ left: 4, right: this.miniBarExpanded ? 8 : 4 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(28)
    .clip(true)
  }

  @Builder
  private MiniPlayer() {
    Stack() {
      this.MiniPlayerContent(true, true)
    }
    .height(56)
    .width('100%')
    .id('mini_player_surface')
    .borderRadius(28)
    .clip(true)
    .opacity(this.isMorphActive() ? 0 : 1)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.measuredMiniPlayerFrame = {
        x: this.lengthToNumber(newValue.globalPosition.x, this.measuredMiniPlayerFrame.x),
        y: this.lengthToNumber(newValue.globalPosition.y, this.measuredMiniPlayerFrame.y),
        width: this.lengthToNumber(newValue.width, this.measuredMiniPlayerFrame.width),
        height: this.lengthToNumber(newValue.height, this.measuredMiniPlayerFrame.height)
      };
    })
    .parallelGesture(
      PanGesture({ direction: PanDirection.All, distance: 3 })
        .onActionStart(() => {
          this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
          this.freezeMiniPlayerGeometry();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateMiniPlayerGesture(event);
        })
        .onActionEnd(() => {
          this.finishMiniPlayerGesture();
        })
        .onActionCancel(() => {
          this.finishMiniPlayerGesture();
        })
    )
  }

  @Builder
  private ExpandedTabBar(item: NavigationItem | MoreNavigationItem, tabIndex: number) {
    if (this.usesPortraitSideNavigation()) {
      Column({ space: AppShellLayoutSpec.EXPANDED_TAB_ITEM_VERTICAL_GAP }) {
        SymbolGlyph(item.symbol)
          .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_ICON_SIZE)
          .fontColor([
            this.expandedTabIndex() === tabIndex ?
              $r('app.color.theme_accent') : $r('app.color.text_tertiary')
          ])
        Text(item.label)
          .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LABEL_SIZE)
          .fontWeight(this.expandedTabIndex() === tabIndex ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(
            this.expandedTabIndex() === tabIndex ?
              $r('app.color.theme_accent') : $r('app.color.text_secondary')
          )
          .maxLines(1)
      }
      .width('100%')
      .height(AppShellLayoutSpec.EXPANDED_TAB_ITEM_PORTRAIT_HEIGHT)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    } else {
      Row({ space: AppShellLayoutSpec.EXPANDED_TAB_ITEM_HORIZONTAL_GAP }) {
        SymbolGlyph(item.symbol)
          .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_ICON_SIZE)
          .fontColor([
            this.expandedTabIndex() === tabIndex ?
              $r('app.color.theme_accent') : $r('app.color.text_tertiary')
          ])
        Text(item.label)
          .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LABEL_SIZE)
          .fontWeight(this.expandedTabIndex() === tabIndex ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(
            this.expandedTabIndex() === tabIndex ?
              $r('app.color.theme_accent') : $r('app.color.text_secondary')
          )
          .maxLines(1)
      }
      .width('100%')
      .height(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LANDSCAPE_HEIGHT)
      .padding({ left: AppShellLayoutSpec.EXPANDED_TAB_ITEM_LEADING_PADDING })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
  }

  @Builder
  private CompactTabsContent() {
    HdsTabs({ controller: this.compactTabsController, index: this.selectedTabIndex }) {
      ForEach(this.navigationItems, (item: NavigationItem, index: number) => {
        TabContent() {
          this.TabNavigation(index)
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(item.symbol)
        }, item.label))
      }, (item: NavigationItem) => item.label)
    }
    .width('100%')
    .height('100%')
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .onChange((index: number) => {
      this.handleCompactTabChange(index);
    })
    .onTabBarClick((index: number) => {
      this.handleCompactTabBarClick(index);
    })
    .barFloatingStyle(this.compactTabsFloatingStyle())
  }

  @Builder
  private ExpandedTabsContent() {
    HdsTabs({ controller: this.expandedTabsController, index: this.expandedTabIndex() }) {
      ForEach(this.navigationItems.slice(0, MORE_TAB_INDEX), (item: NavigationItem, index: number) => {
        TabContent() {
          this.TabNavigation(index)
        }
        .tabBar(this.ExpandedTabBar(item, index))
      }, (item: NavigationItem) => item.label)

      ForEach(MORE_NAVIGATION_ITEMS, (item: MoreNavigationItem, index: number) => {
        TabContent() {
          this.ExpandedMoreNavigation(item, index)
        }
        .tabBar(this.ExpandedTabBar(item, MORE_TAB_INDEX + index))
      }, (item: MoreNavigationItem) => item.routeId)
    }
    .width('100%')
    .height('100%')
    .barPosition(BarPosition.Start)
    .barWidth(this.expandedTabBarWidth())
    .vertical(true)
    .barMode(BarMode.Scrollable)
    .scrollable(false)
    .animationDuration(0)
    .onChange((index: number) => {
      this.handleExpandedTabChange(index);
    })
    .onTabBarClick((index: number) => {
      this.handleExpandedTabBarClick(index);
    })
  }

  @Builder
  private WideMiniPlayerHost() {
    Stack() {
      HdsTabs({ index: 0 }) {
        TabContent() {
          Stack()
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier($r('sys.symbol.music_fill'))
        }, '播放器'))
      }
      .width('100%')
      .height('100%')
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .barFloatingStyle(this.wideMiniPlayerFloatingStyle())
    }
    .id('wide_mini_player_hds_host')
    .width(this.wideMiniPlayerWidth() + AppShellLayoutSpec.WIDE_SIDE_MARGIN * 2)
    .height(AppShellLayoutSpec.MINI_PLAYER_HEIGHT + AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN)
  }

  @Builder
  private PlayerTabs() {
    if (this.usesWideLayout()) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.ExpandedTabsContent()
        this.WideMiniPlayerHost()
      }
      .id('player_tabs_wide_content_host')
      .width('100%')
      .height('100%')
    } else {
      Stack() {
        this.CompactTabsContent()
      }
      .id('player_tabs_compact_content_host')
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private FullPlayerControl(icon: Resource, accessibilityText: string, size: number) {
    Stack() {
      Image(icon)
        .width(size * 0.45)
        .height(size * 0.45)
        .fillColor($r('app.color.control_foreground'))
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor($r('app.color.glass_surface_subtle'))
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(accessibilityText)
  }

  @Builder
  private FullPlayerContent(showArtwork: boolean, measuresArtworkTarget: boolean = false) {
    Column() {
      Row() {
        Stack() {
          Image($r('app.media.control_chevron_down'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.glass_surface_strong'))
        .backgroundBlurStyle(BlurStyle.Thin)
        .clickEffect({ level: ClickEffectLevel.MIDDLE })
        .accessibilityText('收起播放器')
        .onClick(() => {
          this.hideFullPlayer();
        })

        Text('正在播放')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(44)
      }
      .width('100%')

      Blank().layoutWeight(1)

      Stack() {
        if (showArtwork) {
          this.AlbumCover(PlayerLayoutSpec.FULL_ARTWORK_SIZE, PlayerLayoutSpec.FULL_ARTWORK_RADIUS)
        }
      }
      .width(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
      .height(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
      .borderRadius(PlayerLayoutSpec.FULL_ARTWORK_SIZE / 2)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        if (!measuresArtworkTarget) {
          return;
        }
        this.artworkTarget = {
          x: this.lengthToNumber(
            newValue.globalPosition.x,
            this.artworkTarget.x + this.rootFrame.x
          ) - this.rootFrame.x,
          y: this.lengthToNumber(
            newValue.globalPosition.y,
            this.artworkTarget.y + this.rootFrame.y
          ) - this.rootFrame.y
        };
      })

      Blank().layoutWeight(1)

      Column({ space: 7 }) {
        Text('尚未播放')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('选择一首音乐开始播放')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row() {
        this.FullPlayerControl($r('app.media.control_previous'), '上一首', 54)
        this.PlaybackButton(74)
        this.FullPlayerControl($r('app.media.control_next'), '下一首', 54)
      }
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .margin({ top: 30, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 28,
      right: 28,
      top: this.statusBarAvoidHeight + 18,
      bottom: this.navigationAvoidHeight + 10
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
          this.FullPlayerContent(false, false)
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
            this.MiniPlayerContent(false, false)
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
  private MorphArtwork() {
    Stack() {
      Image($r('app.media.default_album_cover'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(this.morphArtworkSourceRadius())
        .clip(true)
    }
    .width(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
    .height(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
    .borderRadius(this.morphArtworkSourceRadius())
    .position({ x: 0, y: 0 })
    .translate({
      x: this.morphValue(
        this.frozenMiniPlayerFrame.x + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.frozenArtworkTarget.x
      ),
      y: this.morphValue(
        this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.frozenArtworkTarget.y
      )
    })
    .scale({
      x: this.morphArtworkScale(),
      y: this.morphArtworkScale(),
      centerX: 0,
      centerY: 0
    })
    .shadow({
      radius: 38,
      color: this.morphArtworkShadowColor(),
      offsetY: 20
    })
  }

  @Builder
  private FullPlayerGeometryProbe() {
    Stack() {
      this.FullPlayerContent(false, true)
    }
    .width('100%')
    .height('100%')
    .opacity(0)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      this.FullPlayerGeometryProbe()

      this.PlayerTabs()

      if (this.isMorphActive()) {
        this.MorphPlayer()
        this.MorphArtwork()
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
