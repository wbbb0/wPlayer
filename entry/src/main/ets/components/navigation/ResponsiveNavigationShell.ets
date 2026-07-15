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
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { AppNavigationStyle } from './AppNavigationStyle';
import { AppPrimaryTitleParams } from './AppPrimaryTitleContent';
import { MORE_NAVIGATION_ITEMS, MoreNavigationItem, MoreRoute } from './MoreNavigation';
import { LibrarySortMenu, LibrarySortMenuParams } from '../library/LibrarySortMenu';
import { MiniPlayerSurface } from '../player/MiniPlayerSurface';
import { PlayerFrame } from '../player/PlayerMotion';
import {
  AlbumSortField,
  SortDirection,
  TrackSortField
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { AlbumsPage } from '../../pages/library/AlbumsPage';
import { LibraryManagementPage } from '../../pages/library/LibraryManagementPage';
import { MorePage } from '../../pages/library/MorePage';
import { PlaylistsPage } from '../../pages/library/PlaylistsPage';
import { SongsPage } from '../../pages/library/SongsPage';

interface NavigationItem {
  label: string;
  symbol: Resource;
}

const TRACK_SORT_LABELS: Array<string> = ['名称', '专辑', '艺术家', '发行日期', '添加时间'];
const ALBUM_SORT_LABELS: Array<string> = ['名称', '艺术家', '发行日期', '添加时间'];
const TRACK_SORT_MENU_ID: string = 'track_sort_menu';
const ALBUM_SORT_MENU_ID: string = 'album_sort_menu';
const MORE_TAB_INDEX: number = 3;

@Component
export struct ResponsiveNavigationShell {
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink playerStore: PlayerStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop rootHeight: number = 0;
  @Prop selectedTabIndex: number = 0;
  @Prop selectedMoreRouteId: string = MoreRoute.LIBRARY_MANAGEMENT;
  @Prop miniBarExpanded: boolean = false;
  @Prop miniPlayerOffsetX: number = 0;
  @Prop morphActive: boolean = false;
  @Prop measuredMiniPlayerFrame: PlayerFrame = { x: 0, y: 0, width: 56, height: 56 };
  @Prop appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();

  compactTabsController: HdsTabsController = new HdsTabsController();
  expandedTabsController: HdsTabsController = new HdsTabsController();
  primaryTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> = [];
  moreTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> = [];
  tabPathStacks: Array<NavPathStack> = [];
  expandedMorePathStacks: Array<NavPathStack> = [];
  pageScrollers: Array<Scroller> = [];
  libraryManagementScroller: Scroller = new Scroller();

  onCompactTabChange: (index: number) => void = (_index: number): void => {};
  onCompactTabClick: (index: number) => void = (_index: number): void => {};
  onExpandedTabChange: (index: number) => void = (_index: number): void => {};
  onExpandedTabClick: (index: number) => void = (_index: number): void => {};
  onOpenMoreDestination: (routeId: string) => void = (_routeId: string): void => {};
  onMiniBarStyleChange: (expanded: boolean) => void = (_expanded: boolean): void => {};
  onShowFullPlayer: () => void = (): void => {};
  onMeasuredMiniPlayerFrame: (frame: PlayerFrame) => void = (_frame: PlayerFrame): void => {};
  onMiniPlayerGestureStart: () => void = (): void => {};
  onMiniPlayerGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onMiniPlayerGestureFinish: () => void = (): void => {};

  private readonly navigationItems: Array<NavigationItem> = [
    { label: '播放列表', symbol: $r('sys.symbol.music_note_list_fill') },
    { label: '音乐', symbol: $r('sys.symbol.music_fill') },
    { label: '专辑', symbol: $r('sys.symbol.opticaldisc') },
    { label: '更多', symbol: $r('sys.symbol.square_fill_grid_2x2') }
  ];

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
        onBarStyleChange: (style: HdsBarStyle) => {
          this.onMiniBarStyleChange(style === HdsBarStyle.EXPAND);
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
        onBarStyleChange: (style: HdsBarStyle) => {
          this.onMiniBarStyleChange(style === HdsBarStyle.EXPAND);
        },
        enableMiniBarBackground: true,
        enableMiniBarClip: true
      }
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

  private expandedTabIndex(): number {
    return this.selectedTabIndex < MORE_TAB_INDEX ?
      this.selectedTabIndex : MORE_TAB_INDEX + this.moreNavigationIndex();
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
    const content = new ComponentContent(this.getUIContext(), wrapBuilder(LibrarySortMenu), params);
    this.getUIContext().getPromptAction().openMenu(content, { id: targetId }, { enableArrow: true })
      .catch((error: BusinessError) => {
        console.warn(`Unable to open sort menu: ${error.code}, ${error.message}`);
      });
  }

  private libraryTitleMenu(index: number): HdsNavigationMenuContentOptions | undefined {
    if (index !== 1 && index !== 2) {
      return undefined;
    }
    const targetId = index === 1 ? TRACK_SORT_MENU_ID : ALBUM_SORT_MENU_ID;
    const countLabel = index === 1 ?
      `${this.libraryStore.statistics.trackCount} 首` :
      `${this.libraryStore.statistics.albumCount} 张`;
    const values: Array<HdsNavigationMenuItemOptions> = index === 1 ? [{
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
        action: () => this.openSortMenu(index, targetId)
      }
    }] : [{
      content: {
        label: countLabel,
        type: TextStyleMode.NORMAL,
        componentId: targetId,
        action: () => this.openSortMenu(index, targetId)
      }
    }];
    return { maxCount: values.length, value: values };
  }

  @Builder
  private LibraryPage(index: number) {
    if (index === 0) {
      PlaylistsPage({
        store: this.libraryStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.pageScrollers[0]
      })
    } else if (index === 1) {
      SongsPage({
        store: this.libraryStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.pageScrollers[1],
        onPlayTrack: (item) => playbackRuntime.playFromLibrary(item, this.libraryStore.trackSnapshot())
      })
    } else if (index === 2) {
      AlbumsPage({
        store: this.libraryStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.pageScrollers[2]
      })
    } else {
      MorePage({
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.pageScrollers[MORE_TAB_INDEX],
        openDestination: this.onOpenMoreDestination
      })
    }
  }

  @Builder
  private LibraryManagementContent() {
    LibraryManagementPage({
      store: this.libraryStore,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.libraryManagementScroller
    })
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
        MORE_NAVIGATION_ITEMS[this.moreNavigationIndex(name)].label,
        this.appearancePalette
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
      this.appearancePalette,
      this.libraryTitleMenu(index),
      this.primaryTitleContents[index]
    ))
    .bindToScrollable([this.pageScrollers[index]])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private ExpandedMoreNavigation(item: MoreNavigationItem, index: number) {
    HdsNavigation(this.expandedMorePathStacks[index]) {
      if (item.routeId === MoreRoute.LIBRARY_MANAGEMENT) {
        this.LibraryManagementContent()
      }
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
      undefined,
      this.moreTitleContents[index]
    ))
    .bindToScrollable([this.libraryManagementScroller])
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
          .fontColor(this.expandedTabIndex() === tabIndex ?
            $r('app.color.theme_accent') : $r('app.color.text_secondary'))
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
          .fontColor(this.expandedTabIndex() === tabIndex ?
            $r('app.color.theme_accent') : $r('app.color.text_secondary'))
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
        .tabBar(new BottomTabBarStyle({ normal: new SymbolGlyphModifier(item.symbol) }, item.label))
      }, (item: NavigationItem) => item.label)
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
    .onChange(this.onExpandedTabChange)
    .onTabBarClick(this.onExpandedTabClick)
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
      Stack() {
        this.CompactTabsContent()
      }
      .id('player_tabs_compact_content_host')
      .width('100%')
      .height('100%')
    }
  }
}
