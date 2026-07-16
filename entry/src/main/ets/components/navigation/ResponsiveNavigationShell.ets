import {
  HdsBarLayoutMode,
  HdsBarStyle,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigation,
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  IconStyleMode,
  TextStyleMode,
  hdsMaterial
} from '@kit.UIDesignKit';
import { ComponentContent, SymbolGlyphModifier } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppAppearancePalette } from '../../appearance/AppAppearance';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { AppNavigationStyle } from './AppNavigationStyle';
import { AppPrimaryTitleParams } from './AppPrimaryTitleContent';
import {
  NavigationPageItem,
  NavigationPageKind,
  NavigationRoute,
  PRIMARY_NAVIGATION_COUNT,
  SETTINGS_NAVIGATION_ITEM,
  navigationItem,
  navigationItemIndex,
  navigationPageKind,
  orderedNavigationItems
} from './MoreNavigation';
import { LibrarySortMenu, LibrarySortMenuParams } from '../library/LibrarySortMenu';
import { MiniPlayerSurface } from '../player/MiniPlayerSurface';
import { QueueActionMenu } from '../library/QueueActionMenu';
import { PlayerFrame } from '../player/PlayerMotion';
import { AlbumSortField, SortDirection, TrackSortField } from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { AlbumsPage } from '../../pages/library/AlbumsPage';
import { AlbumDetailPage } from '../../pages/library/AlbumDetailPage';
import { MaterialDebugPage } from '../../pages/debug/MaterialDebugPage';
import { LibraryManagementPage } from '../../pages/library/LibraryManagementPage';
import { MorePage } from '../../pages/library/MorePage';
import { PlaylistsPage } from '../../pages/library/PlaylistsPage';
import { SongsPage } from '../../pages/library/SongsPage';
import { SettingsPage } from '../../pages/settings/SettingsPage';
import { NavigationCustomizationPage } from '../../pages/settings/NavigationCustomizationPage';

const TRACK_SORT_LABELS: Array<string> = ['名称', '专辑', '艺术家', '发行日期', '添加时间'];
const ALBUM_SORT_LABELS: Array<string> = ['名称', '艺术家', '发行日期', '添加时间'];
const TRACK_SORT_MENU_ID: string = 'track_sort_menu';
const ALBUM_SORT_MENU_ID: string = 'album_sort_menu';
const MORE_TAB_INDEX: number = PRIMARY_NAVIGATION_COUNT;
const ALBUM_DETAIL_ROUTE: string = 'album_detail';

class AlbumDetailRouteParams {
  albumId: number;
  title: string;
  palettePrimary: string;

  constructor(albumId: number, title: string, palettePrimary: string) {
    this.albumId = albumId;
    this.title = title;
    this.palettePrimary = palettePrimary;
  }
}

@Component
export struct ResponsiveNavigationShell {
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink playerStore: PlayerStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop rootHeight: number = 0;
  @Prop navigationOrder: Array<string> = [];
  @Prop selectedRouteId: string = NavigationRoute.PLAYLISTS;
  @Prop miniBarExpanded: boolean = false;
  @Prop miniPlayerOffsetX: number = 0;
  @Prop morphActive: boolean = false;
  @Prop measuredMiniPlayerFrame: PlayerFrame = { x: 0, y: 0, width: 56, height: 56 };
  @Prop appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();

  compactTabsController: HdsTabsController = new HdsTabsController();
  expandedTabsController: HdsTabsController = new HdsTabsController();
  rootTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> = [];
  rootPathStacks: Array<NavPathStack> = [];
  rootScrollers: Array<Scroller> = [];
  morePathStack: NavPathStack = new NavPathStack();
  moreScroller: Scroller = new Scroller();
  customizationScroller: Scroller = new Scroller();
  albumDetailScroller: Scroller = new Scroller();

  onCompactTabChange: (index: number) => void = (_index: number): void => {};
  onCompactTabClick: (index: number) => void = (_index: number): void => {};
  onExpandedTabChange: (index: number) => void = (_index: number): void => {};
  onExpandedTabClick: (index: number) => void = (_index: number): void => {};
  onOpenMoreDestination: (routeId: string) => void = (_routeId: string): void => {};
  onOpenNavigationCustomization: () => void = (): void => {};
  onNavigationItemMove: (from: number, to: number) => void = (_from: number, _to: number): void => {};
  onMiniBarStyleChange: (expanded: boolean) => void = (_expanded: boolean): void => {};
  onShowFullPlayer: () => void = (): void => {};
  onMeasuredMiniPlayerFrame: (frame: PlayerFrame) => void = (_frame: PlayerFrame): void => {};
  onMiniPlayerGestureStart: () => void = (): void => {};
  onMiniPlayerGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onMiniPlayerGestureFinish: () => void = (): void => {};

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

  private expandedTabIndex(): number {
    const expanded = this.expandedItems();
    for (let index = 0; index < expanded.length; index += 1) {
      if (expanded[index].routeId === this.selectedRouteId) {
        return index;
      }
    }
    return 0;
  }

  private usesWideLayout(): boolean {
    return this.rootWidth >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT;
  }

  private usesPortraitSideNavigation(): boolean {
    return this.usesWideLayout() && this.rootWidth < this.rootHeight;
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

  private routeScroller(routeId: string): Scroller {
    return this.rootScrollers[navigationItemIndex(routeId)];
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
        onBarStyleChange: (style: HdsBarStyle) => this.onMiniBarStyleChange(style === HdsBarStyle.EXPAND),
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
        miniBarWidth: { smallWidth: miniPlayerWidth, mediumWidth: miniPlayerWidth, largeWidth: miniPlayerWidth },
        miniBarStyle: HdsBarStyle.EXPAND,
        barLayoutMode: HdsBarLayoutMode.HORIZONTAL,
        onBarStyleChange: (style: HdsBarStyle) => this.onMiniBarStyleChange(style === HdsBarStyle.EXPAND),
        enableMiniBarBackground: true,
        enableMiniBarClip: true
      }
    };
  }

  private applyTrackSort(field: TrackSortField, direction: SortDirection): void {
    this.libraryStore.setTrackSort(field, direction).then(() => {
      if (this.libraryStore.trackDataSource.totalCount() > 0) {
        this.routeScroller(NavigationRoute.SONGS).scrollToIndex(0, false, ScrollAlign.START);
      }
    });
  }

  private applyAlbumSort(field: AlbumSortField, direction: SortDirection): void {
    this.libraryStore.setAlbumSort(field, direction).then(() => {
      if (this.libraryStore.albumDataSource.totalCount() > 0) {
        this.routeScroller(NavigationRoute.ALBUMS).scrollToIndex(0, false, ScrollAlign.START);
      }
    });
  }

  private openSortMenu(routeId: string, targetId: string): void {
    const isTracks = routeId === NavigationRoute.SONGS;
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
    const content = new ComponentContent(this.getUIContext(), wrapBuilder(LibrarySortMenu), params);
    this.getUIContext().getPromptAction().openMenu(content, { id: targetId }, { enableArrow: true })
      .catch((error: BusinessError) => {
        console.warn(`Unable to open sort menu: ${error.code}, ${error.message}`);
      });
  }

  private libraryTitleMenu(routeId: string): HdsNavigationMenuContentOptions | undefined {
    if (routeId !== NavigationRoute.SONGS && routeId !== NavigationRoute.ALBUMS) {
      return undefined;
    }
    const isTracks = routeId === NavigationRoute.SONGS;
    const targetId = isTracks ? TRACK_SORT_MENU_ID : ALBUM_SORT_MENU_ID;
    const countLabel = isTracks ? `${this.libraryStore.statistics.trackCount} 首` :
      `${this.libraryStore.statistics.albumCount} 张`;
    const values: Array<HdsNavigationMenuItemOptions> = isTracks ? [{
      content: {
        icon: $r('sys.symbol.shuffle'),
        label: '随机播放全部音乐',
        type: IconStyleMode.NORMAL,
        isEnabled: this.libraryStore.statistics.trackCount > 0,
        action: () => playbackRuntime.shuffleAll(this.libraryStore.trackSnapshot())
      }
    }, {
      content: {
        label: countLabel,
        type: TextStyleMode.NORMAL,
        componentId: targetId,
        action: () => this.openSortMenu(routeId, targetId)
      }
    }] : [{
      content: {
        label: countLabel,
        type: TextStyleMode.NORMAL,
        componentId: targetId,
        action: () => this.openSortMenu(routeId, targetId)
      }
    }];
    return { maxCount: values.length, value: values };
  }

  private albumDetailBackground(params: AlbumDetailRouteParams): string {
    return this.blendOpaque(this.appearancePalette.windowBackground, params.palettePrimary, 0.12);
  }

  private blendOpaque(base: string, tint: string, opacity: number): string {
    if (base.length !== 9 || tint.length !== 9 || !base.startsWith('#') || !tint.startsWith('#')) {
      return base;
    }
    let result = '#FF';
    for (let channel = 0; channel < 3; channel += 1) {
      const offset = 3 + channel * 2;
      const baseValue = Number.parseInt(base.substring(offset, offset + 2), 16);
      const tintValue = Number.parseInt(tint.substring(offset, offset + 2), 16);
      const mixed = Math.round(baseValue * (1 - opacity) + tintValue * opacity);
      result += mixed.toString(16).padStart(2, '0').toUpperCase();
    }
    return result;
  }

  private albumDetailTitleMenu(albumId: number): HdsNavigationMenuContentOptions {
    const targetId = `album_detail_more_${albumId}`;
    return {
      maxCount: 1,
      value: [{
        content: {
          icon: $r('app.media.control_more'),
          label: '更多',
          type: IconStyleMode.NORMAL,
          componentId: targetId,
          action: () => {
            const detail = this.libraryStore.albumDetail;
            if (detail === undefined || detail.album.id !== albumId) {
              return;
            }
            const content = new ComponentContent(
              this.getUIContext(), wrapBuilder(QueueActionMenu), detail.tracks
            );
            this.getUIContext().getPromptAction().openMenu(
              content, { id: targetId }, { enableArrow: true }
            ).catch((error: BusinessError) => {
              console.warn(`Unable to open album queue menu: ${error.code}, ${error.message}`);
            });
          }
        }
      }]
    };
  }

  @Builder
  private PageContent(routeId: string) {
    if (navigationPageKind(routeId) === NavigationPageKind.PLAYLISTS) {
      PlaylistsPage({ store: this.libraryStore, topInset: this.topInset, bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId) })
    } else if (navigationPageKind(routeId) === NavigationPageKind.SONGS) {
      SongsPage({
        store: this.libraryStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        onPlayTrack: (item) => playbackRuntime.playFromLibrary(item, this.libraryStore.trackSnapshot())
      })
    } else if (navigationPageKind(routeId) === NavigationPageKind.ALBUMS) {
      AlbumsPage({ store: this.libraryStore, topInset: this.topInset, bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        onOpenAlbum: (item) => {
          this.rootPathStacks[navigationItemIndex(routeId)].pushPath({
            name: ALBUM_DETAIL_ROUTE,
            param: new AlbumDetailRouteParams(item.id, item.title, item.palettePrimary)
          });
        } })
    } else if (navigationPageKind(routeId) === NavigationPageKind.LIBRARY_MANAGEMENT) {
      LibraryManagementPage({ store: this.libraryStore, topInset: this.topInset, bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId) })
    } else if (navigationPageKind(routeId) === NavigationPageKind.MATERIAL_DEBUG) {
      MaterialDebugPage({ topInset: this.topInset, bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId) })
    } else if (navigationPageKind(routeId) === NavigationPageKind.SETTINGS) {
      SettingsPage({
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        openNavigationCustomization: this.onOpenNavigationCustomization
      })
    }
  }

  @Builder
  private DestinationBuilder(name: string, _param: Object) {
    if (name === ALBUM_DETAIL_ROUTE) {
      HdsNavDestination() {
        AlbumDetailPage({
          store: this.libraryStore,
          albumId: (_param as AlbumDetailRouteParams).albumId,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          rootWidth: this.rootWidth,
          themeBackground: this.albumDetailBackground(_param as AlbumDetailRouteParams),
          scroller: this.albumDetailScroller
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.albumDetailBackground(_param as AlbumDetailRouteParams))
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryBackOnlyTitleBar(
        this.appearancePalette,
        this.albumDetailTitleMenu((_param as AlbumDetailRouteParams).albumId)
      ))
      .bindToScrollable([this.albumDetailScroller])
    } else if (name === NavigationRoute.NAVIGATION_CUSTOMIZATION) {
      HdsNavDestination() {
        NavigationCustomizationPage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          items: this.orderedItems(),
          scroller: this.customizationScroller,
          onMove: this.onNavigationItemMove
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar('自定义页面', this.appearancePalette))
      .bindToScrollable([this.customizationScroller])
    } else {
      HdsNavDestination() {
        this.PageContent(name)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        navigationItem(name)?.label ?? '',
        this.appearancePalette
      ))
      .bindToScrollable([this.routeScroller(name)])
    }
  }

  @Builder
  private RootNavigation(item: NavigationPageItem) {
    HdsNavigation(this.rootPathStacks[navigationItemIndex(item.routeId)]) {
      this.PageContent(item.routeId)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(AppNavigationStyle.primaryTitleBar(
      item.label,
      this.appearancePalette,
      this.libraryTitleMenu(item.routeId),
      this.rootTitleContents[navigationItemIndex(item.routeId)]
    ))
    .bindToScrollable([this.routeScroller(item.routeId)])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private MoreNavigation() {
    HdsNavigation(this.morePathStack) {
      MorePage({
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.moreScroller,
        items: this.moreItems(),
        openDestination: this.onOpenMoreDestination
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .backgroundColor($r('app.color.page_background'))
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(AppNavigationStyle.primaryTitleBar('更多', this.appearancePalette))
    .bindToScrollable([this.moreScroller])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private MiniPlayer() {
    MiniPlayerSurface({
      playerStore: this.playerStore,
      expanded: this.miniBarExpanded,
      swipeOffsetX: this.miniPlayerOffsetX,
      morphActive: this.morphActive,
      measuredFrame: this.measuredMiniPlayerFrame,
      onShowFullPlayer: this.onShowFullPlayer,
      onMeasuredFrame: this.onMeasuredMiniPlayerFrame,
      onGestureStart: this.onMiniPlayerGestureStart,
      onGestureUpdate: this.onMiniPlayerGestureUpdate,
      onGestureFinish: this.onMiniPlayerGestureFinish
    })
  }

  @Builder
  private ExpandedTabBar(item: NavigationPageItem, tabIndex: number) {
    Column() {
      if (tabIndex === PRIMARY_NAVIGATION_COUNT) {
        Divider()
          .width(AppShellLayoutSpec.EXPANDED_TAB_SECTION_DIVIDER_WIDTH)
          .strokeWidth(AppShellLayoutSpec.EXPANDED_TAB_SECTION_DIVIDER_THICKNESS)
          .color($r('app.color.text_tertiary'))
          .opacity(AppShellLayoutSpec.EXPANDED_TAB_SECTION_DIVIDER_OPACITY)
          .margin({ bottom: AppShellLayoutSpec.EXPANDED_TAB_SECTION_DIVIDER_MARGIN })
      }
      if (this.usesPortraitSideNavigation()) {
        Column({ space: AppShellLayoutSpec.EXPANDED_TAB_ITEM_VERTICAL_GAP }) {
          SymbolGlyph(item.symbol)
            .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_ICON_SIZE)
            .fontColor([this.expandedTabIndex() === tabIndex ?
              this.playerStore.paletteAccent : $r('app.color.text_tertiary')])
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          Text(item.label)
            .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LABEL_SIZE)
            .fontWeight(this.expandedTabIndex() === tabIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.expandedTabIndex() === tabIndex ?
              this.playerStore.paletteAccent : $r('app.color.text_secondary'))
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
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
            .fontColor([this.expandedTabIndex() === tabIndex ?
              this.playerStore.paletteAccent : $r('app.color.text_tertiary')])
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          Text(item.label)
            .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LABEL_SIZE)
            .fontWeight(this.expandedTabIndex() === tabIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.expandedTabIndex() === tabIndex ?
              this.playerStore.paletteAccent : $r('app.color.text_secondary'))
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
            .maxLines(1)
        }
        .width('100%')
        .height(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LANDSCAPE_HEIGHT)
        .padding({ left: AppShellLayoutSpec.EXPANDED_TAB_ITEM_LEADING_PADDING })
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
  }

  @Builder
  private CompactTabsContent() {
    HdsTabs({ controller: this.compactTabsController, index: this.compactTabIndex() }) {
      ForEach(this.primaryItems(), (item: NavigationPageItem) => {
        TabContent() {
          this.RootNavigation(item)
        }
        .tabBar(new BottomTabBarStyle({ normal: new SymbolGlyphModifier(item.symbol) }, item.label))
      }, (_item: NavigationPageItem, index: number) => index.toString())
      TabContent() {
        this.MoreNavigation()
      }
      .tabBar(new BottomTabBarStyle({
        normal: new SymbolGlyphModifier($r('sys.symbol.square_fill_grid_2x2'))
      }, '更多'))
    }
    .width('100%')
    .height('100%')
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .onChange(this.onCompactTabChange)
    .onTabBarClick(this.onCompactTabClick)
    .barFloatingStyle(this.compactTabsFloatingStyle())
  }

  @Builder
  private ExpandedTabsContent() {
    HdsTabs({ controller: this.expandedTabsController, index: this.expandedTabIndex() }) {
      ForEach(this.expandedItems(), (item: NavigationPageItem, index: number) => {
        TabContent() {
          this.RootNavigation(item)
        }
        .tabBar(this.ExpandedTabBar(item, index))
      }, (_item: NavigationPageItem, index: number) => index.toString())
    }
    .width('100%')
    .height('100%')
    .barPosition(BarPosition.Start)
    .barWidth(this.expandedTabBarWidth())
    .vertical(true)
    .barMode(BarMode.Scrollable)
    .scrollable(false)
    .animationDuration(0)
    .onChange(this.onExpandedTabChange)
    .onTabBarClick(this.onExpandedTabClick)
  }

  @Builder
  private WideMiniPlayerHost() {
    Stack() {
      HdsTabs({ index: 0 }) {
        TabContent() { Stack() }
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

  build() {
    if (this.usesWideLayout()) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.ExpandedTabsContent()
        this.WideMiniPlayerHost()
      }
      .id('player_tabs_wide_content_host')
      .width('100%')
      .height('100%')
    } else {
      Stack() { this.CompactTabsContent() }
        .id('player_tabs_compact_content_host')
        .width('100%')
        .height('100%')
    }
  }
}
