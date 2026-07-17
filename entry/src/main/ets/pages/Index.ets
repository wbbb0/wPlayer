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
  FullPlayerPage,
  FullPlayerPagerSpec,
  FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID,
  FULL_PLAYER_VERTICAL_GESTURE_HOST_ID,
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
import {
  LibraryEntityKind,
  LibraryNavigationTarget
} from '../library/model/LibraryModels';
import { playbackRuntime } from '../playback/PlaybackRuntime';
import { PlayerStore } from '../playback/model/PlaybackModels';
import { SettingsRepository } from '../settings/SettingsRepository';
import { AppSettingsStore, appSettings } from '../settings/AppSettingsStore';
import { AppShellLayoutSpec } from '../components/layout/AppShellLayoutSpec';
import { WindowAvoidAreaController } from '../components/layout/WindowAvoidAreaController';
import { LayoutLength } from '../components/layout/LayoutLength';
import { FullPlayerContent } from '../components/player/FullPlayerContent';
import {
  MiniPlayerContent,
  MiniPlayerSurface
} from '../components/player/MiniPlayerSurface';
import { ArtworkLayout } from '../components/artwork/ArtworkLayout';
import { ArtworkFitMode, ArtworkView } from '../components/artwork/ArtworkView';
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
import { TrackActionMenuPresenter } from '../components/library/TrackActionMenu';
import {
  AlbumDetailRouteParams,
  ArtistDetailRouteParams,
  LibraryDetailRoute
} from '../components/navigation/LibraryNavigation';
import {
  AppAppearanceListener,
  AppAppearancePalette,
  appAppearanceController
} from '../appearance/AppAppearance';
import { PaletteMotionSpec } from '../appearance/PaletteMotionSpec';
import { DynamicColor } from '../appearance/DynamicColor';
import { systemBarStyleController } from '../appearance/SystemBarStyleController';

const MORE_TAB_INDEX: number = PRIMARY_NAVIGATION_COUNT;

@Entry
@Component
struct Index {
  @State statusBarAvoidHeight: number = 0;
  @State navigationAvoidHeight: number = 0;
  @State appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();
  @State navigationOrder: Array<string> = DEFAULT_NAVIGATION_ORDER;
  @State selectedRouteId: string = NavigationRoute.PLAYLISTS;
  @State libraryStore: LibraryStore = new LibraryStore(playbackRuntime.repository, playbackRuntime);
  @State playerStore: PlayerStore = playbackRuntime.playerStore;
  // The invisible geometry probe must not react to playback position or lyric updates.
  @State geometryPlayerStore: PlayerStore = new PlayerStore();
  @State settingsStore: AppSettingsStore = appSettings;
  @State animatedThemePrimary: string = '';
  @State miniBarExpanded: boolean = false;
  @State miniPlayerOffsetX: number = 0;
  @State playerExpandProgress: number = 0;
  @State playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  @State swipeHapticTriggered: boolean = false;
  @State playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @State playerMorphBackgroundOpacity: number = 1;
  @State fullPlayerPage: FullPlayerPage = FullPlayerPage.COVER;
  @State fullPlayerPagePosition: number = FullPlayerPage.COVER;
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
  @State centeredArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @State frozenArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  private returnToExpandedMiniBar: boolean = false;
  private fullPlayerGestureStartPosition: number = FullPlayerPage.COVER;
  private morphTransitionEpoch: number = 0;
  private compactTabIndexBeforeSelection: number = 0;
  private expandedTabIndexBeforeSelection: number = 0;
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
    playbackRuntime.setPaletteChangeListener((primary: string, _secondary: string, _accent: string): void => {
      this.animateThemePrimary(primary);
      this.syncSystemBarContentColor();
    });
    appAppearanceController.addListener(this.appearanceListener);
    this.refreshAppearance();
    this.initializePrimaryTitleContents();
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      const abilityContext = context as common.UIAbilityContext;
      this.avoidAreaController.start(abilityContext);
      try {
        this.settingsRepository = new SettingsRepository(abilityContext);
        this.settingsStore.initialize(this.settingsRepository);
        this.navigationOrder = normalizeNavigationOrder(
          this.settingsRepository.getNavigationOrder(DEFAULT_NAVIGATION_ORDER)
        );
        if (this.settingsStore.rememberLastTab) {
          const oldTabIndex = this.normalizeTabIndex(this.settingsRepository.getLastTabIndex());
          const fallbackRoute = oldTabIndex < PRIMARY_NAVIGATION_COUNT ?
            this.navigationOrder[oldTabIndex] : this.navigationOrder[PRIMARY_NAVIGATION_COUNT];
          const storedRoute = this.settingsRepository.getLastNavigationRoute(fallbackRoute);
          this.selectedRouteId = navigationItem(storedRoute) === undefined ?
            NavigationRoute.PLAYLISTS : storedRoute;
        } else {
          this.selectedRouteId = this.navigationOrder[0] ?? NavigationRoute.PLAYLISTS;
        }
      } catch (error) {
        const businessError = error as BusinessError;
        console.warn(`Unable to initialize settings: ${businessError.code}, ${businessError.message}`);
      }
      this.libraryStore.initialize(abilityContext, this.settingsRepository);
    }
  }

  aboutToDisappear(): void {
    this.releaseMorphArtworkSource();
    playbackRuntime.setPaletteChangeListener(undefined);
    systemBarStyleController.setPlayerContentColor(false, '');
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

  private animateThemePrimary(targetColor: string): void {
    if (this.animatedThemePrimary === targetColor) {
      return;
    }
    this.getUIContext().animateTo({
      duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
      curve: Curve.EaseInOut
    }, () => {
      this.animatedThemePrimary = targetColor;
    });
  }

  private refreshAppearance(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const palette = AppAppearancePalette.resolve(context as common.UIAbilityContext);
    this.appearancePalette = palette;
    this.playerStore.themeBaseBackground = palette.windowBackground;
    systemBarStyleController.setAppearanceContentColor(palette.systemBarContent);
    this.syncSystemBarContentColor();
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

  private fullPlayerPaneCount(width: number = this.rootFrame.width,
    height: number = this.rootFrame.height): number {
    return FullPlayerPagerSpec.paneCount(width, height);
  }

  private fullPlayerPageSpan(): number {
    return FullPlayerPagerSpec.pageSpan(this.fullPlayerFrame().width, this.renderedFullPlayerPaneCount());
  }

  private reconcileFullPlayerPager(previousPaneCount: number, nextPaneCount: number): void {
    if (previousPaneCount === nextPaneCount) {
      return;
    }
    this.fullPlayerPagePosition = FullPlayerPagerSpec.positionForPage(
      this.fullPlayerPage,
      nextPaneCount
    );
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
    if (this.settingsStore.rememberLastTab) {
      this.settingsRepository?.setLastNavigationRoute(routeId);
      this.settingsRepository?.setLastTabIndex(this.compactTabIndex());
    }
  }

  private handleCompactTabChange(index: number): void {
    this.compactTabIndexBeforeSelection = this.compactTabIndex();
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
    if (index !== this.compactTabIndexBeforeSelection) {
      return;
    }
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
    this.expandedTabIndexBeforeSelection = this.expandedTabIndex();
    const items = this.expandedItems();
    if (index < 0 || index >= items.length) {
      return;
    }
    this.selectRoute(items[index].routeId);
    this.morePathStack.clear(false);
  }

  private handleExpandedTabBarClick(index: number): void {
    if (index !== this.expandedTabIndexBeforeSelection) {
      return;
    }
    if (index !== this.expandedTabIndex()) {
      return;
    }
    this.rootPathStacks[navigationItemIndex(this.selectedRouteId)].clear(true);
  }

  private activeNavigationStack(): NavPathStack {
    if (!this.usesWideLayout() && this.compactTabIndex() === MORE_TAB_INDEX) {
      return this.morePathStack;
    }
    return this.rootPathStacks[navigationItemIndex(this.selectedRouteId)];
  }

  private navigateLibrary(target: LibraryNavigationTarget): void {
    if (target.identity.kind === LibraryEntityKind.ARTIST) {
      this.activeNavigationStack().pushPath({
        name: LibraryDetailRoute.ARTIST,
        param: new ArtistDetailRouteParams(target.identity.id, target.title)
      });
    } else if (target.identity.kind === LibraryEntityKind.ALBUM) {
      this.activeNavigationStack().pushPath({
        name: LibraryDetailRoute.ALBUM,
        param: new AlbumDetailRouteParams(
          target.identity.id,
          target.title,
          target.palettePrimary
        )
      });
    }
    if (this.isMorphActive()) {
      this.hideFullPlayer();
    }
  }

  private openFullPlayerTrackActions(trackId: number, anchorId: string): void {
    TrackActionMenuPresenter.open(
      this.getUIContext(),
      this.libraryStore,
      trackId,
      anchorId,
      [],
      undefined,
      (target: LibraryNavigationTarget): void => this.navigateLibrary(target)
    );
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

  private setRememberLastTab(value: boolean): void {
    this.settingsStore.setRememberLastTab(value);
    if (value) {
      this.settingsRepository?.setLastNavigationRoute(this.selectedRouteId);
      this.settingsRepository?.setLastTabIndex(this.compactTabIndex());
      return;
    }
    this.settingsRepository?.setLastNavigationRoute(this.navigationOrder[0] ?? NavigationRoute.PLAYLISTS);
    this.settingsRepository?.setLastTabIndex(0);
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
    const rootStack = this.rootPathStacks[navigationItemIndex(this.selectedRouteId)];
    if (nextWideLayout) {
      rootStack.clear(false);
      const names = this.morePathStack.getAllPathName();
      const firstDetailIndex = names.length > 0 && names[0] === this.selectedRouteId ? 1 : 0;
      for (let index = firstDetailIndex; index < names.length; index += 1) {
        rootStack.pushPath({
          name: names[index],
          param: this.morePathStack.getParamByIndex(index)
        }, false);
      }
      this.morePathStack.clear(false);
      return;
    }
    this.morePathStack.clear(false);
    this.morePathStack.pushPath({ name: this.selectedRouteId }, false);
    const names = rootStack.getAllPathName();
    for (let index = 0; index < names.length; index += 1) {
      this.morePathStack.pushPath({
        name: names[index],
        param: rootStack.getParamByIndex(index)
      }, false);
    }
    rootStack.clear(false);
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

  private syncSystemBarContentColor(): void {
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

  private morphArtworkSourceWidth(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkWidth :
      (this.playerStore.currentTrack?.artworkWidth ?? 0);
  }

  private morphArtworkSourceHeight(): number {
    return this.morphArtworkSourceFrozen ? this.frozenMorphArtworkHeight :
      (this.playerStore.currentTrack?.artworkHeight ?? 0);
  }

  private morphArtworkAspectRatio(): number {
    const height = this.morphArtworkHeight();
    return height > 0 ? this.morphArtworkWidth() / height : 1;
  }

  private morphValue(start: number, end: number): number {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private pageThemeTintOpacity(): number {
    return this.appearancePalette.windowBackground.toUpperCase() === '#FF000000' ? 0.24 : 0.16;
  }

  private animatedPageBackground(): string {
    if (!this.settingsStore.followPlaybackTheme ||
      this.animatedThemePrimary.length === 0 || !this.playerStore.hasCurrentTrack()) {
      return this.appearancePalette.windowBackground;
    }
    return DynamicColor.blendOpaque(
      this.appearancePalette.windowBackground,
      this.animatedThemePrimary,
      this.pageThemeTintOpacity()
    );
  }

  private playerThemeBackground(): string {
    return this.animatedThemePrimary.length > 0 ?
      this.animatedThemePrimary : this.appearancePalette.windowBackground;
  }

  private heroArtworkInterpolation(): ImageInterpolation {
    return this.settingsStore.highQualityHeroArtwork ?
      ImageInterpolation.High : ImageInterpolation.Medium;
  }

  private morphCollapsedSurfaceColor(): string {
    return this.appearancePalette.windowBackground.toUpperCase() === '#FF000000' ?
      PlayerMotionSpec.COLLAPSED_SURFACE_DARK : PlayerMotionSpec.COLLAPSED_SURFACE_LIGHT;
  }

  private fullPlayerFrame(): PlayerFrame {
    return this.playerMorphPhase === PlayerMorphPhase.OPEN ? this.rootFrame : this.frozenRootFrame;
  }

  private renderedFullPlayerPaneCount(): number {
    const frame = this.fullPlayerFrame();
    return FullPlayerPagerSpec.paneCount(frame.width, frame.height);
  }

  private fullPlayerArtworkTarget(): PlayerPoint {
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
      FullPlayerPagerSpec.pageSpan(fullPlayerFrame.width,
        FullPlayerPagerSpec.paneCount(fullPlayerFrame.width, fullPlayerFrame.height)),
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

  private morphArtworkPlaybackScale(): number {
    const fullPlayerScale = this.playerStore.isPlaying() ? 1 : PlayerMotionSpec.PAUSED_ARTWORK_SCALE;
    return 1 - (1 - fullPlayerScale) * this.clamp(this.playerExpandProgress, 0, 1);
  }

  private isMorphActive(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.IDLE;
  }

  private beginMorphPhase(phase: PlayerMorphPhase): number {
    this.morphTransitionEpoch += 1;
    this.playerMorphPhase = phase;
    this.syncSystemBarContentColor();
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

  private updateMiniPlayerGesture(event: GestureEvent): void {
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

  private beginFullPlayerHorizontalGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    this.fullPlayerGestureStartPosition = this.fullPlayerPagePosition;
  }

  private updateFullPlayerHorizontalGesture(event: GestureEvent): void {
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

  private finishFullPlayerHorizontalGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    this.finishFullPlayerPageGesture();
  }

  private beginFullPlayerVerticalGesture(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      return;
    }
    this.freezeMiniPlayerGeometry(false);
    this.freezeMorphArtworkSource();
    this.beginMorphPhase(PlayerMorphPhase.CLOSE_DRAGGING);
    this.playerMorphBackgroundOpacity = 1;
  }

  private updateFullPlayerVerticalGesture(event: GestureEvent): void {
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

  private finishFullPlayerVerticalGesture(): void {
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

  private finishFullPlayerPageGesture(): void {
    const paneCount = this.fullPlayerPaneCount();
    const movement = this.fullPlayerPagePosition - this.fullPlayerGestureStartPosition;
    let targetPosition = Math.round(this.fullPlayerGestureStartPosition);
    if (Math.abs(movement) >= FullPlayerPagerSpec.SWIPE_COMPLETION_FRACTION) {
      targetPosition += movement > 0 ? 1 : -1;
    }
    targetPosition = FullPlayerPagerSpec.clampPosition(targetPosition, paneCount);
    this.fullPlayerPage = FullPlayerPagerSpec.nearestPage(targetPosition, paneCount);
    this.getUIContext().animateTo({
      duration: FullPlayerPagerSpec.PAGE_SETTLE_DURATION,
      curve: Curve.EaseOut
    }, () => {
      this.fullPlayerPagePosition = targetPosition;
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
      settingsStore: this.settingsStore,
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
      themePageBackground: this.animatedPageBackground(),
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
      onRememberLastTabChange: (value: boolean): void => this.setRememberLastTab(value),
      onRememberSortChange: (value: boolean): void => this.libraryStore.setRememberSort(value),
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
      onMiniPlayerGestureFinish: (): void => this.finishMiniPlayerGesture(),
      onNavigateLibrary: (target: LibraryNavigationTarget): void => this.navigateLibrary(target)
    })
  }

  @Builder
  private MorphPlayer() {
    Stack() {
      Stack() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DynamicColor.blendOpaque(
        this.morphCollapsedSurfaceColor(),
        this.playerThemeBackground(),
        this.clamp(this.playerExpandProgress, 0, 1)
      ))
      .opacity(this.playerMorphBackgroundOpacity)

      Stack() {
        Stack() {
          FullPlayerContent({
            playerStore: this.playerStore,
            topInset: this.statusBarAvoidHeight,
            bottomInset: this.navigationAvoidHeight,
            showArtwork: false,
            heroArtworkInterpolation: this.heroArtworkInterpolation(),
            rootFrame: this.fullPlayerFrame(),
            pagePosition: this.fullPlayerPagePosition,
            paneCount: this.renderedFullPlayerPaneCount(),
            previousArtworkTarget: this.artworkTarget,
            previousCenteredArtworkTarget: this.centeredArtworkTarget,
            onClose: () => this.hideFullPlayer(),
            onPlayQueueTrack: (trackId: number): void => playbackRuntime.playQueueTrack(trackId),
            onSeek: (positionMs: number): void => playbackRuntime.seek(positionMs),
            onResolveQueueArtwork: (relativePath: string): string =>
              playbackRuntime.queueArtworkUri(relativePath),
            onOpenTrackActions: (trackId: number, anchorId: string): void =>
              this.openFullPlayerTrackActions(trackId, anchorId)
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
    .borderRadius(PlayerLayoutSpec.MORPH_SURFACE_RADIUS *
      (1 - this.clamp(this.playerExpandProgress, 0, 1)))
    .clip(true)
  }

  @Builder
  private FullPlayerOverlay() {
    Stack() {
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
      .id(FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID)
      .parallelGesture(
        PanGesture({
          direction: PanDirection.Horizontal,
          distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE
        })
          .onActionStart(() => {
            this.beginFullPlayerHorizontalGesture();
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateFullPlayerHorizontalGesture(event);
          })
          .onActionEnd(() => {
            this.finishFullPlayerHorizontalGesture();
          })
          .onActionCancel(() => {
            this.finishFullPlayerHorizontalGesture();
          })
      )
    }
    .width('100%')
    .height('100%')
    .id(FULL_PLAYER_VERTICAL_GESTURE_HOST_ID)
    .parallelGesture(
      PanGesture({
        direction: PanDirection.Vertical,
        distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE
      })
        .onActionStart(() => {
          this.beginFullPlayerVerticalGesture();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateFullPlayerVerticalGesture(event);
        })
        .onActionEnd(() => {
          this.finishFullPlayerVerticalGesture();
        })
        .onActionCancel(() => {
          this.finishFullPlayerVerticalGesture();
        })
    )
  }

  @Builder
  private MorphArtwork() {
    Stack() {
      ArtworkView({
        sourceProvider: (): image.PixelMap | ResourceStr => this.morphArtworkSource(),
        sourceRevision: this.playerStore.heroArtworkRevision,
        sourceWidth: this.morphArtworkSourceWidth(),
        sourceHeight: this.morphArtworkSourceHeight(),
        slotWidth: this.morphArtworkWidth(),
        slotAspectRatio: this.morphArtworkAspectRatio(),
        fitMode: ArtworkFitMode.COVER,
        resolvedCornerRadius: this.morphArtworkSourceRadius(),
        shadowEnabled: true,
        shadowRadius: PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS *
          this.clamp(this.playerExpandProgress, 0, 1),
        shadowOffsetY: PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y *
          this.clamp(this.playerExpandProgress, 0, 1),
        interpolation: this.heroArtworkInterpolation()
      })
        .scale({
          x: this.morphArtworkPlaybackScale(),
          y: this.morphArtworkPlaybackScale()
        })
        .animation(this.playerMorphPhase === PlayerMorphPhase.OPEN ? {
          curve: curves.springMotion(
            PlayerMotionSpec.ARTWORK_STATE_SPRING_RESPONSE,
            PlayerMotionSpec.ARTWORK_STATE_SPRING_DAMPING
          )
        } : { duration: 0 })
    }
    .width(this.morphArtworkWidth())
    .height(this.morphArtworkHeight())
    .opacity(this.morphArtworkOpacity())
    .position({ x: 0, y: 0 })
    .translate({ x: this.morphArtworkX(), y: this.morphArtworkY() })
  }

  private morphArtworkX(): number {
    return this.morphValue(
      this.frozenMiniPlayerFrame.x + PlayerLayoutSpec.MINI_ARTWORK_INSET,
      this.fullPlayerArtworkTarget().x +
        (this.fullArtworkSlotSize() - this.morphTargetArtworkWidth()) / 2
    );
  }

  private morphArtworkY(): number {
    return this.morphValue(
      this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
      this.fullPlayerArtworkTarget().y +
        (this.fullArtworkSlotSize() - this.morphTargetArtworkHeight()) / 2
    );
  }

  private morphArtworkOpacity(): number {
    if (this.renderedFullPlayerPaneCount() > 1) {
      return 1;
    }
    if (this.playerMorphPhase === PlayerMorphPhase.OPEN) {
      return this.clamp(1 - Math.abs(this.fullPlayerPagePosition - FullPlayerPage.COVER), 0, 1);
    }
    if (this.fullPlayerPage === FullPlayerPage.COVER) {
      return 1;
    }
    return FullPlayerPagerSpec.sidePageArtworkOpacity(this.playerExpandProgress);
  }

  @Builder
  private FullPlayerGeometryProbe() {
    Stack() {
      FullPlayerContent({
        playerStore: this.geometryPlayerStore,
        topInset: this.statusBarAvoidHeight,
        bottomInset: this.navigationAvoidHeight,
        showArtwork: false,
        heroArtworkInterpolation: this.heroArtworkInterpolation(),
        measuresArtworkTarget: true,
        rootFrame: this.rootFrame,
        pagePosition: FullPlayerPage.COVER,
        paneCount: this.fullPlayerPaneCount(),
        previousArtworkTarget: this.artworkTarget,
        previousCenteredArtworkTarget: this.centeredArtworkTarget,
        onClose: () => this.hideFullPlayer(),
        onArtworkTarget: (target: PlayerPoint): void => {
          this.artworkTarget = target;
        },
        onCenteredArtworkTarget: (target: PlayerPoint): void => {
          this.centeredArtworkTarget = target;
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
        .backgroundColor(this.appearancePalette.windowBackground)
        .hitTestBehavior(HitTestMode.None)

      if (this.settingsStore.followPlaybackTheme && this.playerStore.hasCurrentTrack()) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.playerThemeBackground())
          .opacity(this.pageThemeTintOpacity())
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
    .backgroundColor(this.animatedPageBackground())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
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
        this.reconcileResponsiveNavigation(previousWideLayout, nextWideLayout);
      }
    })
  }
}
