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
import { ComponentContent, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppAppearancePalette } from '../../appearance/AppAppearance';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { DynamicColor } from '../../appearance/DynamicColor';
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
import {
  PlaylistCreateMenu,
  PlaylistCreateMenuParams,
  PlaylistTransferMenu,
  PlaylistTransferMenuParams
} from '../library/PlaylistNavigationMenus';
import { MiniPlayerHostParams, MiniPlayerSurface } from '../player/MiniPlayerSurface';
import { MiniPlayerBinding } from '../player/MiniPlayerBinding';
import { QueueActionMenu, QueueActionMenuParams } from '../library/QueueActionMenu';
import { TrackActionMenuPresenter } from '../library/TrackActionMenu';
import {
  TaskResultDetailItem,
  TaskResultDetailSection,
  TaskResultDetails,
  TaskResultTone
} from '../library/TaskResultDetails';
import {
  AlbumSortField,
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  PlaylistKind,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackSortField,
  SortDirection,
  TrackListItem,
  TrackSortField
} from
  '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { AlbumsPage } from '../../pages/library/AlbumsPage';
import { AlbumDetailPage } from '../../pages/library/AlbumDetailPage';
import { ArtistDetailPage } from '../../pages/library/ArtistDetailPage';
import { TrackDetailPage } from '../../pages/library/TrackDetailPage';
import { TrackArtworkViewerPage } from '../../pages/library/TrackArtworkViewerPage';
import { LibraryManagementPage } from '../../pages/library/LibraryManagementPage';
import { MorePage } from '../../pages/library/MorePage';
import { PlaylistsPage } from '../../pages/library/PlaylistsPage';
import { PlaylistDetailPage } from '../../pages/library/PlaylistDetailPage';
import { SongsPage } from '../../pages/library/SongsPage';
import { SettingsPage } from '../../pages/settings/SettingsPage';
import { NavigationCustomizationPage } from '../../pages/settings/NavigationCustomizationPage';
import { AboutPage } from '../../pages/settings/AboutPage';
import { PrivacyPolicyPage } from '../../pages/settings/PrivacyPolicyPage';
import { DataAndPermissionsPage } from '../../pages/settings/DataAndPermissionsPage';
import { OpenSourceLicensesPage } from '../../pages/settings/OpenSourceLicensesPage';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import {
  AlbumDetailRouteParams,
  ArtistDetailRouteParams,
  LibraryDetailRoute,
  TrackArtworkViewerRouteParams,
  TrackDetailRouteParams,
  albumTarget,
  artistTarget
} from './LibraryNavigation';
import {
  M3uImportNameConflictAction,
  M3uImportContext,
  M3uImportDetail,
  M3uImportMode,
  M3uImportStage,
  M3uImportReport,
  M3uImportSource,
  M3uTransferService
} from '../../playlist/m3u/M3uTransferService';
import { AlbumAction } from '../library/AlbumGridItem';
import {
  MultiSelectActionMenu,
  MultiSelectActionMenuParams,
  MultiSelectController
} from '../library/MultiSelectController';

const TRACK_SORT_LABELS: Array<string> = ['名称', '专辑', '艺术家', '发行日期', '添加时间'];
const ALBUM_SORT_LABELS: Array<string> = ['名称', '艺术家', '发行日期', '添加时间'];
const PLAYLIST_SORT_LABELS: Array<string> =
  ['名称', '最后播放', '最近修改', '创建时间', '歌曲数量', '总时长'];
const PLAYLIST_TRACK_SORT_LABELS: Array<string> =
  ['手动顺序', '添加顺序', '名称', '艺术家', '专辑', '发行日期', '时长', '最后播放', '最近完整听完'];
const TRACK_SORT_MENU_ID: string = 'track_sort_menu';
const ALBUM_SORT_MENU_ID: string = 'album_sort_menu';
const PLAYLIST_SORT_MENU_ID: string = 'playlist_sort_menu';
const PLAYLIST_CREATE_MENU_ID: string = 'playlist_create_menu';
const PLAYLIST_DETAIL_ROUTE: string = 'playlist_detail';
const MORE_TAB_INDEX: number = PRIMARY_NAVIGATION_COUNT;
let playlistRouteInstanceId: number = 0;

enum PlaylistImportSheetKind {
  PROGRESS = 'progress',
  REPORT = 'report'
}

class PlaylistDetailRouteParams {
  readonly instanceId: number;
  readonly playlistId: number;
  readonly initialTitle: string;
  readonly scroller: Scroller = new Scroller();
  readonly selection: MultiSelectController = new MultiSelectController();

  constructor(playlistId: number, initialTitle: string) {
    this.instanceId = ++playlistRouteInstanceId;
    this.playlistId = playlistId;
    this.initialTitle = initialTitle;
  }
}

@Component
export struct ResponsiveNavigationShell {
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink playlistStore: PlaylistStore;
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @ObjectLink miniPlayerBinding: MiniPlayerBinding;
  compactMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  condensedCompactMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  wideMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop rootHeight: number = 0;
  @Prop navigationOrder: Array<string> = [];
  @Prop selectedRouteId: string = NavigationRoute.PLAYLISTS;
  @Prop appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();
  @Prop themePageBackground: string = '#FF000000';
  onShowFullPlayer: () => void = (): void => {};
  onMiniPlayerGestureStart: () => void = (): void => {};
  onMiniPlayerGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onMiniPlayerGestureFinish: () => void = (): void => {};
  onDemoLibraryChange: (value: boolean) => void = (_value: boolean): void => {};

  compactTabsController: HdsTabsController = new HdsTabsController();
  condensedCompactTabsController: HdsTabsController = new HdsTabsController();
  expandedTabsController: HdsTabsController = new HdsTabsController();
  rootTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> = [];
  @Prop moreTitleContent: ComponentContent<AppPrimaryTitleParams> | undefined = undefined;
  rootPathStacks: Array<NavPathStack> = [];
  rootScrollers: Array<Scroller> = [];
  morePathStack: NavPathStack = new NavPathStack();
  moreScroller: Scroller = new Scroller();
  customizationScroller: Scroller = new Scroller();
  aboutScroller: Scroller = new Scroller();
  privacyPolicyScroller: Scroller = new Scroller();
  dataAndPermissionsScroller: Scroller = new Scroller();
  openSourceLicensesScroller: Scroller = new Scroller();

  onCompactTabChange: (index: number) => void = (_index: number): void => {};
  onCompactTabClick: (index: number) => void = (_index: number): void => {};
  onCondensedOutsideTouch: () => void = (): void => {};
  onExpandedTabChange: (index: number) => void = (_index: number): void => {};
  onExpandedTabClick: (index: number) => void = (_index: number): void => {};
  onOpenMoreDestination: (routeId: string) => void = (_routeId: string): void => {};
  onOpenNavigationCustomization: () => void = (): void => {};
  onRememberLastTabChange: (value: boolean) => void = (_value: boolean): void => {};
  onRememberSortChange: (value: boolean) => void = (_value: boolean): void => {};
  onNavigationItemMove: (from: number, to: number) => void = (_from: number, _to: number): void => {};
  onRequestCreatePlaylist: () => void = (): void => {};
  onRequestRenamePlaylist: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  private readonly miniPlayerBuilder: () => void = (): void => this.MiniPlayer();
  private readonly playlistTransferService: M3uTransferService =
    new M3uTransferService(playbackRuntime.repository);
  private playlistTransferBusy: boolean = false;
  @State private playlistImportSheetVisible: boolean = false;
  @State private playlistImportSheetKind: PlaylistImportSheetKind = PlaylistImportSheetKind.PROGRESS;
  @State private playlistImportStage: M3uImportStage = M3uImportStage.READING;
  @State private playlistImportSourceName: string = '';
  @State private playlistImportReports: Array<M3uImportReport> = [];
  @State private songsSelection: MultiSelectController = new MultiSelectController();
  @State private albumsSelection: MultiSelectController = new MultiSelectController();
  @State private playlistsSelection: MultiSelectController = new MultiSelectController();
  @State private detailSelectionRevision: number = 0;
  private readonly onDetailSelectionChange: () => void = (): void => {
    this.detailSelectionRevision += 1;
  };

  private rootSelection(routeId: string): MultiSelectController | undefined {
    if (routeId === NavigationRoute.SONGS) {
      return this.songsSelection;
    }
    if (routeId === NavigationRoute.ALBUMS) {
      return this.albumsSelection;
    }
    if (routeId === NavigationRoute.PLAYLISTS) {
      return this.playlistsSelection;
    }
    return undefined;
  }

  private openMultiSelectActionMenu(controller: MultiSelectController, targetId: string): void {
    const content = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(MultiSelectActionMenu),
      new MultiSelectActionMenuParams(controller)
    );
    this.getUIContext().getPromptAction().openMenu(
      content,
      { id: targetId },
      { enableArrow: true }
    ).catch((error: BusinessError): void => {
      console.warn(`Unable to open multi-select menu: ${error.code}, ${error.message}`);
    });
  }

  private selectionTitleMenu(
    controller: MultiSelectController,
    targetId: string,
    normalItems: Array<HdsNavigationMenuItemOptions> = []
  ): HdsNavigationMenuContentOptions {
    const effectiveTargetId = `${targetId}_${this.detailSelectionRevision}`;
    controller.onStateChange = this.onDetailSelectionChange;
    if (controller.active) {
      const activeItems: Array<HdsNavigationMenuItemOptions> = [{
        content: {
          label: controller.selectedCount() > 0 ? `操作 ${controller.selectedCount()}` : '操作',
          type: TextStyleMode.NORMAL,
          componentId: effectiveTargetId,
          isEnabled: controller.selectedCount() > 0 && !controller.busy,
          action: (): void => this.openMultiSelectActionMenu(controller, effectiveTargetId)
        }
      }, {
        content: {
          label: '取消',
          type: TextStyleMode.NORMAL,
          action: (): void => controller.cancel()
        }
      }];
      return { maxCount: activeItems.length, value: activeItems };
    }
    const items = normalItems.concat([{
      content: {
        icon: $r('sys.symbol.checkmark_square_on_square'),
        label: '多选',
        type: IconStyleMode.NORMAL,
        action: (): void => controller.activate()
      }
    }]);
    return { maxCount: items.length, value: items };
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

  private routePathStack(routeId: string): NavPathStack {
    if (!this.usesWideLayout() && this.compactTabIndex() === MORE_TAB_INDEX) {
      return this.morePathStack;
    }
    return this.rootPathStacks[navigationItemIndex(routeId)];
  }

  private compactTabsFloatingStyle(
    miniPlayerContent: ComponentContent<MiniPlayerHostParams> | undefined =
      this.compactMiniPlayerContent,
    smallWidth: number = AppShellLayoutSpec.COMPACT_TAB_SMALL_WIDTH,
    mediumWidth: number = AppShellLayoutSpec.COMPACT_TAB_MEDIUM_WIDTH,
    largeWidth: number = AppShellLayoutSpec.COMPACT_TAB_LARGE_WIDTH,
    barOpacity: number = 1
  ): HdsTabsFloatingStyle {
    return {
      barWidth: {
        smallWidth: smallWidth,
        mediumWidth: mediumWidth,
        largeWidth: largeWidth
      },
      barBottomMargin: AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN,
      gradientMask: {
        maskColor: $r('app.color.float_bar_gradient_mask'),
        maskHeight: AppShellLayoutSpec.FLOATING_BAR_GRADIENT_MASK_HEIGHT
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      barOpacity: barOpacity,
      miniBar: {
        miniBarBuilder: miniPlayerContent ?? this.miniPlayerBuilder,
        miniBarWidth: {
          smallWidth: AppShellLayoutSpec.MINI_PLAYER_SMALL_WIDTH,
          mediumWidth: AppShellLayoutSpec.MINI_PLAYER_MEDIUM_WIDTH,
          largeWidth: AppShellLayoutSpec.MINI_PLAYER_LARGE_WIDTH
        },
        miniBarStyle: this.miniPlayerBinding.expanded ?
          HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE,
        barLayoutMode: HdsBarLayoutMode.HORIZONTAL,
        onBarStyleChange: (style: HdsBarStyle) => {
          this.miniPlayerBinding.expanded = style === HdsBarStyle.EXPAND;
        },
        enableMiniBarBackground: true,
        enableMiniBarClip: true
      }
    };
  }

  private condensedCompactTabsFloatingStyle(): HdsTabsFloatingStyle {
    return this.compactTabsFloatingStyle(
      this.condensedCompactMiniPlayerContent,
      AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH,
      AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH,
      AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH,
      0
    );
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
      gradientMask: {
        maskColor: $r('app.color.float_bar_gradient_mask'),
        maskHeight: AppShellLayoutSpec.FLOATING_BAR_GRADIENT_MASK_HEIGHT
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      barOpacity: 0,
      miniBar: {
        miniBarBuilder: this.wideMiniPlayerContent ?? this.miniPlayerBuilder,
        miniBarWidth: { smallWidth: miniPlayerWidth, mediumWidth: miniPlayerWidth, largeWidth: miniPlayerWidth },
        miniBarStyle: HdsBarStyle.EXPAND,
        barLayoutMode: HdsBarLayoutMode.HORIZONTAL,
        onBarStyleChange: (style: HdsBarStyle) => {
          this.miniPlayerBinding.expanded = style === HdsBarStyle.EXPAND;
        },
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

  private applyPlaylistSort(field: PlaylistSortField, direction: SortDirection): void {
    this.playlistStore.setSort(field, direction).then(() => {
      if (this.playlistStore.playlists.length > 0) {
        this.routeScroller(NavigationRoute.PLAYLISTS).scrollToIndex(0, false, ScrollAlign.START);
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

  private openPlaylistSortMenu(): void {
    const content = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(LibrarySortMenu),
      new LibrarySortMenuParams(
        PLAYLIST_SORT_LABELS,
        this.playlistStore.sortField,
        this.playlistStore.sortDirection === SortDirection.DESCENDING,
        (index: number): void => {
          this.applyPlaylistSort(index as PlaylistSortField, this.playlistStore.sortDirection);
        },
        (descending: boolean): void => {
          this.applyPlaylistSort(
            this.playlistStore.sortField,
            descending ? SortDirection.DESCENDING : SortDirection.ASCENDING
          );
        }
      )
    );
    this.getUIContext().getPromptAction().openMenu(
      content,
      { id: PLAYLIST_SORT_MENU_ID },
      { enableArrow: true }
    ).catch((error: BusinessError) => {
      console.warn(`Unable to open playlist sort menu: ${error.code}, ${error.message}`);
    });
  }

  private importPlaylistAsNew(): void {
    if (this.playlistTransferBusy) {
      return;
    }
    this.playlistTransferBusy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.importSelectedPlaylistSourcesAsNew(context)
      .then((reports: Array<M3uImportReport>): void => {
        if (reports.length > 0) {
          this.showPlaylistImportReports(reports);
        }
      }).catch((error: Object): void => {
        this.playlistStore.errorMessage = error instanceof Error ? error.message : `${error}`;
      }).finally((): void => {
        this.playlistTransferBusy = false;
      });
  }

  private async importSelectedPlaylistSourcesAsNew(
    context: common.UIAbilityContext
  ): Promise<Array<M3uImportReport>> {
    const sources = await this.playlistTransferService.selectImportSources(context);
    if (sources.length === 0) {
      return [];
    }
    const reports: Array<M3uImportReport> = [];
    const importContext = await this.playlistTransferService.createImportContext();
    for (let index = 0; index < sources.length; index += 1) {
      const source = sources[index];
      await this.playlistStore.synchronizeRepositoryChanges();
      const conflict = this.playlistTransferService.findNameConflict(source, this.playlistStore.playlists);
      if (conflict === undefined) {
        reports.push(await this.importPlaylistSourceAsNewForBatch(source, importContext));
        await this.playlistStore.synchronizeCommittedRepositoryChanges();
        continue;
      }
      const action = await this.choosePlaylistNameConflictAction(source, conflict);
      if (action === undefined) {
        continue;
      }
      if (action === M3uImportNameConflictAction.SAVE_AS_NEW) {
        reports.push(await this.importPlaylistSourceAsNewForBatch(source, importContext));
      } else {
        const mode = action === M3uImportNameConflictAction.REPLACE ? M3uImportMode.REPLACE : M3uImportMode.MERGE;
        reports.push(await this.importPlaylistSourceIntoForBatch(source, conflict.id, mode, importContext));
      }
      await this.playlistStore.synchronizeCommittedRepositoryChanges();
    }
    this.hidePlaylistImportProgress();
    return reports;
  }

  private importPlaylistSourceAsNewForBatch(
    source: M3uImportSource,
    importContext: M3uImportContext
  ): Promise<M3uImportReport> {
    this.playlistImportSourceName = source.suggestedName;
    return this.playlistTransferService.importSourceAsNew(
      source,
      (stage: M3uImportStage): void => this.showPlaylistImportProgress(stage),
      importContext
    );
  }

  private async choosePlaylistNameConflictAction(
    source: M3uImportSource,
    playlist: PlaylistSummary
  ): Promise<M3uImportNameConflictAction | undefined> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '播放列表已存在',
        message: `“${source.suggestedName}”与现有播放列表“${playlist.name}”重名。请选择导入方式。`,
        buttons: [
          { text: '合并', color: $r('app.color.text_primary') },
          { text: '另存', color: $r('app.color.text_primary') },
          { text: '替换', color: $r('sys.color.ohos_id_color_warning') },
          { text: '取消', color: $r('app.color.text_primary') }
        ]
      });
      if (result.index === 0) {
        return M3uImportNameConflictAction.MERGE;
      }
      if (result.index === 1) {
        return M3uImportNameConflictAction.SAVE_AS_NEW;
      }
      if (result.index === 2) {
        return M3uImportNameConflictAction.REPLACE;
      }
    } catch (_error) {
      // Closing the dialog is equivalent to cancelling this file.
    }
    return undefined;
  }

  private openPlaylistCreateMenu(): void {
    const content = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(PlaylistCreateMenu),
      new PlaylistCreateMenuParams(
        this.onRequestCreatePlaylist,
        (): void => this.importPlaylistAsNew()
      )
    );
    this.getUIContext().getPromptAction().openMenu(
      content,
      { id: PLAYLIST_CREATE_MENU_ID },
      { enableArrow: true }
    ).catch((error: BusinessError) => {
      console.warn(`Unable to open playlist create menu: ${error.code}, ${error.message}`);
    });
  }

  private playlistRootTitleMenu(): HdsNavigationMenuContentOptions {
    const values: Array<HdsNavigationMenuItemOptions> = [{
      content: {
        icon: $r('sys.symbol.plus'),
        label: '新建或导入播放列表',
        type: IconStyleMode.NORMAL,
        componentId: PLAYLIST_CREATE_MENU_ID,
        action: (): void => this.openPlaylistCreateMenu()
      }
    }, {
      content: {
        label: `${this.playlistStore.playlists.length} 个`,
        type: TextStyleMode.NORMAL,
        componentId: PLAYLIST_SORT_MENU_ID,
        action: (): void => this.openPlaylistSortMenu()
      }
    }];
    return this.selectionTitleMenu(
      this.playlistsSelection,
      'playlists_selection_actions',
      values
    );
  }

  private shuffleAllTracks(): void {
    this.libraryStore.loadTrackSnapshot()
      .then((items: Array<TrackListItem>) => playbackRuntime.shuffleAll(items))
      .catch((error: Object) => console.warn(`Unable to load shuffle queue: ${error}`));
  }

  private playLibraryTrack(item: TrackListItem): void {
    this.libraryStore.loadTrackSnapshot()
      .then((items: Array<TrackListItem>) => playbackRuntime.playFromLibrary(item, items))
      .catch((error: Object) => console.warn(`Unable to load playback queue: ${error}`));
  }

  private rootTitleMenu(routeId: string): HdsNavigationMenuContentOptions | undefined {
    if (routeId === NavigationRoute.PLAYLISTS) {
      return this.playlistRootTitleMenu();
    }
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
        action: () => this.shuffleAllTracks()
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
    const selection = this.rootSelection(routeId);
    return selection === undefined ?
      { maxCount: values.length, value: values } :
      this.selectionTitleMenu(selection, `${routeId}_selection_actions`, values);
  }

  private albumDetailBackground(params: AlbumDetailRouteParams): string {
    const darkMode = this.appearancePalette.windowBackground.toUpperCase() === '#FF000000';
    return DynamicColor.blendOpaque(
      this.appearancePalette.windowBackground,
      params.palettePrimary,
      darkMode ? 0.50 : 0.36
    );
  }

  private albumDetailTitleMenu(params: AlbumDetailRouteParams): HdsNavigationMenuContentOptions {
    const targetId = `album_detail_more_${params.instanceId}`;
    const values: Array<HdsNavigationMenuItemOptions> = [{
        content: {
          icon: $r('app.media.control_more'),
          label: '更多',
          type: IconStyleMode.NORMAL,
          componentId: targetId,
          action: () => {
            const detail = params.state.detail;
            if (detail === undefined) {
              return;
            }
            const content = new ComponentContent(
              this.getUIContext(),
              wrapBuilder(QueueActionMenu),
              new QueueActionMenuParams(detail.tracks, this.onRequestAddToPlaylist)
            );
            this.getUIContext().getPromptAction().openMenu(
              content, { id: targetId }, { enableArrow: true }
            ).catch((error: BusinessError) => {
              console.warn(`Unable to open album queue menu: ${error.code}, ${error.message}`);
            });
          }
        }
      }];
    return this.selectionTitleMenu(
      params.selection,
      `album_detail_selection_${params.instanceId}`,
      values
    );
  }

  private openTrackActions(
    item: TrackListItem,
    anchorId: string,
    current?: LibraryEntityIdentity
  ): void {
    TrackActionMenuPresenter.open(
      this.getUIContext(),
      this.libraryStore,
      item.id,
      anchorId,
      [item],
      current,
      this.onNavigateLibrary,
      this.onRequestAddToPlaylist,
      '',
      undefined,
      (track: TrackListItem): void => this.openTrackDetails(track)
    );
  }

  private openTrackDetails(item: TrackListItem): void {
    this.routePathStack(this.selectedRouteId).pushPath({
      name: LibraryDetailRoute.TRACK,
      param: new TrackDetailRouteParams(item.id, item.title)
    });
  }

  private performAlbumAction(albumId: number, action: AlbumAction): void {
    this.libraryStore.getAlbumDetail(albumId)
      .then((detail): void => {
        if (detail === undefined || detail.tracks.length === 0) {
          return;
        }
        if (action === AlbumAction.INSERT_NEXT) {
          playbackRuntime.insertNext(detail.tracks);
        } else if (action === AlbumAction.APPEND_QUEUE) {
          playbackRuntime.appendToQueue(detail.tracks);
        } else {
          this.onRequestAddToPlaylist(detail.tracks);
        }
      })
      .catch((error: Object): void => {
        console.warn(`Unable to load album actions: ${error}`);
      });
  }

  private playlistSummary(playlistId: number): PlaylistSummary | undefined {
    const detail = this.playlistStore.detail;
    if (detail !== undefined && detail.playlist.id === playlistId) {
      return detail.playlist;
    }
    for (let index = 0; index < this.playlistStore.playlists.length; index += 1) {
      if (this.playlistStore.playlists[index].id === playlistId) {
        return this.playlistStore.playlists[index];
      }
    }
    return undefined;
  }

  private openPlaylistTrackSortMenu(playlistId: number, targetId: string): void {
    const playlist = this.playlistSummary(playlistId);
    if (playlist === undefined) {
      return;
    }
    const content = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(LibrarySortMenu),
      new LibrarySortMenuParams(
        PLAYLIST_TRACK_SORT_LABELS,
        playlist.itemSortField,
        playlist.itemSortDirection === SortDirection.DESCENDING,
        (index: number): void => {
          this.playlistStore.updateItemSort(
            playlistId,
            index as PlaylistTrackSortField,
            playlist.itemSortDirection
          );
        },
        (descending: boolean): void => {
          this.playlistStore.updateItemSort(
            playlistId,
            playlist.itemSortField,
            descending ? SortDirection.DESCENDING : SortDirection.ASCENDING
          );
        }
      )
    );
    this.getUIContext().getPromptAction().openMenu(content, { id: targetId }, { enableArrow: true })
      .catch((error: BusinessError) => {
        console.warn(`Unable to open playlist item sort menu: ${error.code}, ${error.message}`);
      });
  }

  private importIntoPlaylist(playlistId: number, mode: M3uImportMode): void {
    if (this.playlistTransferBusy) {
      return;
    }
    this.playlistTransferBusy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.playlistTransferService.importInto(
      context,
      playlistId,
      mode,
      (stage: M3uImportStage): void => this.showPlaylistImportProgress(stage)
    )
      .then((report: M3uImportReport | undefined): void => {
        if (report === undefined) {
          this.hidePlaylistImportProgress();
          return;
        }
        this.showPlaylistImportReport(report);
        this.playlistStore.synchronizeCommittedRepositoryChanges();
      }).catch((error: Object): void => {
        this.finishPlaylistImportWithError(error);
      }).finally((): void => {
        this.playlistTransferBusy = false;
      });
  }

  private importPlaylistSourceIntoForBatch(
    source: M3uImportSource,
    playlistId: number,
    mode: M3uImportMode,
    importContext: M3uImportContext
  ): Promise<M3uImportReport> {
    this.playlistImportSourceName = source.suggestedName;
    return this.playlistTransferService.importSource(
      source,
      playlistId,
      mode,
      (stage: M3uImportStage): void => this.showPlaylistImportProgress(stage),
      importContext
    );
  }

  private promptPlaylistImportMode(playlistId: number): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '导入 M3U',
      message: '请选择导入到当前播放列表的方式。',
      buttons: [
        { text: '合并', color: $r('app.color.text_primary') },
        { text: '替换', color: $r('sys.color.ohos_id_color_warning') },
        { text: '取消', color: $r('app.color.text_primary') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 0) {
        this.importIntoPlaylist(playlistId, M3uImportMode.MERGE);
      } else if (result.index === 1) {
        this.importIntoPlaylist(playlistId, M3uImportMode.REPLACE);
      }
    }).catch((_error: Object): void => {
      // Closing the dialog is equivalent to cancelling the import.
    });
  }

  private showPlaylistImportProgress(stage: M3uImportStage): void {
    this.playlistImportStage = stage;
    this.playlistImportReports = [];
    this.playlistImportSheetKind = PlaylistImportSheetKind.PROGRESS;
    this.playlistImportSheetVisible = true;
  }

  private hidePlaylistImportProgress(): void {
    if (this.playlistImportSheetKind === PlaylistImportSheetKind.PROGRESS) {
      this.playlistImportSheetVisible = false;
    }
  }

  private finishPlaylistImportWithError(error: Object): void {
    this.hidePlaylistImportProgress();
    this.playlistStore.errorMessage = error instanceof Error ? error.message : `${error}`;
  }

  private showPlaylistSuccessDialog(message: string): void {
    if (message.length === 0) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '操作完成',
      message: message,
      buttons: [
        { text: '确定', color: $r('app.color.text_primary') }
      ]
    }).catch((_error: Object): void => {
      // The message is informational; dismissing it needs no recovery.
    });
  }

  private showPlaylistImportReport(report: M3uImportReport): void {
    this.showPlaylistImportReports([report]);
  }

  private showPlaylistImportReports(reports: Array<M3uImportReport>): void {
    this.playlistImportReports = reports;
    this.playlistImportSheetKind = PlaylistImportSheetKind.REPORT;
    this.playlistImportSheetVisible = true;
  }

  private exportPlaylist(playlistId: number): void {
    if (this.playlistTransferBusy) {
      return;
    }
    const playlist = this.playlistSummary(playlistId);
    if (playlist === undefined) {
      return;
    }
    this.playlistTransferBusy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.playlistTransferService.exportPlaylist(context, playlist)
      .then((exported: boolean): void => {
        if (exported) {
          this.showPlaylistSuccessDialog('M3U8 播放列表已导出');
        }
      }).catch((error: Object): void => {
        this.playlistStore.errorMessage = error instanceof Error ? error.message : `${error}`;
      }).finally((): void => {
        this.playlistTransferBusy = false;
      });
  }

  private confirmDeletePlaylist(playlistId: number): void {
    const playlist = this.playlistSummary(playlistId);
    if (playlist === undefined || playlist.kind !== PlaylistKind.USER) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除播放列表',
      message: `确定删除“${playlist.name}”吗？音乐文件不会被删除。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_primary') },
        { text: '删除', color: $r('sys.color.ohos_id_color_warning') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      this.playlistStore.delete(playlistId).then((deleted: boolean): void => {
        if (deleted) {
          this.showPlaylistSuccessDialog(this.playlistStore.lastMessage);
          this.routePathStack(NavigationRoute.PLAYLISTS).pop(true);
        }
      });
    }).catch((_error: Object): void => {
      // Closing the dialog is equivalent to cancelling the destructive action.
    });
  }

  private openPlaylistTransferMenu(playlistId: number, targetId: string): void {
    const playlist = this.playlistSummary(playlistId);
    const content = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(PlaylistTransferMenu),
      new PlaylistTransferMenuParams(
        (): void => this.exportPlaylist(playlistId),
        (): void => this.promptPlaylistImportMode(playlistId),
        playlist?.kind === PlaylistKind.USER && playlist !== undefined ?
          (): void => this.onRequestRenamePlaylist(playlist) : undefined,
        playlist?.kind === PlaylistKind.USER ?
          (): void => this.confirmDeletePlaylist(playlistId) : undefined
      )
    );
    this.getUIContext().getPromptAction().openMenu(content, { id: targetId }, { enableArrow: true })
      .catch((error: BusinessError) => {
        console.warn(`Unable to open playlist transfer menu: ${error.code}, ${error.message}`);
      });
  }

  private playlistDetailTitleMenu(params: PlaylistDetailRouteParams): HdsNavigationMenuContentOptions {
    const sortTargetId = `playlist_detail_sort_${params.instanceId}`;
    const moreTargetId = `playlist_detail_more_${params.instanceId}`;
    const playlist = this.playlistSummary(params.playlistId);
    const values: Array<HdsNavigationMenuItemOptions> = [{
      content: {
        label: `${playlist?.trackCount ?? 0} 首`,
        type: TextStyleMode.NORMAL,
        componentId: sortTargetId,
        action: (): void => this.openPlaylistTrackSortMenu(params.playlistId, sortTargetId)
      }
    }, {
      content: {
        icon: $r('app.media.control_more'),
        label: '更多',
        type: IconStyleMode.NORMAL,
        componentId: moreTargetId,
        action: (): void => this.openPlaylistTransferMenu(params.playlistId, moreTargetId)
      }
    }];
    return this.selectionTitleMenu(
      params.selection,
      `playlist_detail_selection_${params.instanceId}`,
      values
    );
  }

  @Builder
  private PageContent(routeId: string) {
    if (navigationPageKind(routeId) === NavigationPageKind.PLAYLISTS) {
      PlaylistsPage({
        store: this.playlistStore,
        selection: this.playlistsSelection,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        onOpenPlaylist: (playlist: PlaylistSummary): void => {
          this.routePathStack(routeId).pushPath({
            name: PLAYLIST_DETAIL_ROUTE,
            param: new PlaylistDetailRouteParams(playlist.id, playlist.name)
          });
        },
        onRequestRename: this.onRequestRenamePlaylist,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist
      })
    } else if (navigationPageKind(routeId) === NavigationPageKind.SONGS) {
      SongsPage({
        store: this.libraryStore,
        selection: this.songsSelection,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        onPlayTrack: (item) => this.playLibraryTrack(item),
        onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
          this.openTrackActions(item, anchorId),
        onOpenTrackDetails: (item: TrackListItem): void => this.openTrackDetails(item),
        onNavigateTrackAction: this.onNavigateLibrary,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist
      })
    } else if (navigationPageKind(routeId) === NavigationPageKind.ALBUMS) {
      AlbumsPage({ store: this.libraryStore, selection: this.albumsSelection,
        topInset: this.topInset, bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        onOpenAlbum: (item) => {
          this.onNavigateLibrary(albumTarget({
            id: item.id,
            title: item.title,
            palettePrimary: item.palettePrimary
          }));
        },
        onAlbumAction: (item, action): void => this.performAlbumAction(item.id, action),
        onNavigateAlbumAction: this.onNavigateLibrary,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist
      })
    } else if (navigationPageKind(routeId) === NavigationPageKind.LIBRARY_MANAGEMENT) {
      LibraryManagementPage({ store: this.libraryStore, topInset: this.topInset, bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId) })
    } else if (navigationPageKind(routeId) === NavigationPageKind.SETTINGS) {
      SettingsPage({
        settingsStore: this.settingsStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.routeScroller(routeId),
        openNavigationCustomization: this.onOpenNavigationCustomization,
        openAbout: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
          name: NavigationRoute.ABOUT
        }),
        openPrivacyPolicy: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
          name: NavigationRoute.PRIVACY_POLICY
        }),
        openDataAndPermissions: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
          name: NavigationRoute.DATA_AND_PERMISSIONS
        }),
        openOpenSourceLicenses: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
          name: NavigationRoute.OPEN_SOURCE_LICENSES
        }),
        onRememberLastTabChange: this.onRememberLastTabChange,
        onRememberSortChange: this.onRememberSortChange,
        onDemoLibraryChange: this.onDemoLibraryChange
      })
    }
  }

  @Builder
  private DestinationBuilder(name: string, _param: Object) {
    if (name === PLAYLIST_DETAIL_ROUTE) {
      HdsNavDestination() {
        PlaylistDetailPage({
          store: this.playlistStore,
          libraryStore: this.libraryStore,
          selection: (_param as PlaylistDetailRouteParams).selection,
          playlistId: (_param as PlaylistDetailRouteParams).playlistId,
          rootWidth: this.rootWidth,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          scroller: (_param as PlaylistDetailRouteParams).scroller,
          onResolveArtwork: (relativePath: string): string =>
            this.libraryStore.resolveArtworkPath(relativePath),
          onRequestAddToPlaylist: this.onRequestAddToPlaylist,
          onNavigateLibrary: this.onNavigateLibrary,
          onOpenTrackDetails: (item: TrackListItem): void => this.openTrackDetails(item)
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        this.playlistSummary((_param as PlaylistDetailRouteParams).playlistId)?.name ??
          (_param as PlaylistDetailRouteParams).initialTitle,
        this.appearancePalette,
        this.playlistDetailTitleMenu(_param as PlaylistDetailRouteParams)
      ))
      .bindToScrollable([(_param as PlaylistDetailRouteParams).scroller])
    } else if (name === LibraryDetailRoute.ALBUM) {
      HdsNavDestination() {
        AlbumDetailPage({
          store: this.libraryStore,
          state: (_param as AlbumDetailRouteParams).state,
          selection: (_param as AlbumDetailRouteParams).selection,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          rootWidth: this.rootWidth,
          currentIdentity: (_param as AlbumDetailRouteParams).identity(),
          themeBackground: this.albumDetailBackground(_param as AlbumDetailRouteParams),
          scroller: (_param as AlbumDetailRouteParams).scroller,
          actionAnchorPrefix: (_param as AlbumDetailRouteParams).anchorPrefix(),
          onOpenArtist: (artist): void => this.onNavigateLibrary(artistTarget(artist)),
          onOpenAlbum: (album): void => this.onNavigateLibrary(albumTarget({
            id: album.id,
            title: album.title,
            palettePrimary: album.palettePrimary
          })),
          onAlbumAction: (album, action): void => this.performAlbumAction(album.id, action),
          onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
            this.openTrackActions(item, anchorId, (_param as AlbumDetailRouteParams).identity()),
          onOpenTrackDetails: (item: TrackListItem): void => this.openTrackDetails(item),
          onNavigateTrackAction: this.onNavigateLibrary,
          onRequestAddToPlaylist: this.onRequestAddToPlaylist
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.albumDetailBackground(_param as AlbumDetailRouteParams))
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryBackOnlyTitleBar(
        this.appearancePalette,
        this.albumDetailTitleMenu(_param as AlbumDetailRouteParams)
      ))
      .bindToScrollable([(_param as AlbumDetailRouteParams).scroller])
    } else if (name === LibraryDetailRoute.ARTIST) {
      HdsNavDestination() {
        ArtistDetailPage({
          store: this.libraryStore,
          state: (_param as ArtistDetailRouteParams).state,
          selection: (_param as ArtistDetailRouteParams).selection,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          rootWidth: this.rootWidth,
          currentIdentity: (_param as ArtistDetailRouteParams).identity(),
          scroller: (_param as ArtistDetailRouteParams).scroller,
          actionAnchorPrefix: (_param as ArtistDetailRouteParams).anchorPrefix(),
          onOpenAlbum: (album): void => this.onNavigateLibrary(albumTarget({
            id: album.id,
            title: album.title,
            palettePrimary: album.palettePrimary
          })),
          onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
            this.openTrackActions(item, anchorId, (_param as ArtistDetailRouteParams).identity()),
          onOpenTrackDetails: (item: TrackListItem): void => this.openTrackDetails(item),
          onNavigateTrackAction: this.onNavigateLibrary,
          onRequestAddToPlaylist: this.onRequestAddToPlaylist
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        (_param as ArtistDetailRouteParams).name,
        this.appearancePalette,
        this.selectionTitleMenu(
          (_param as ArtistDetailRouteParams).selection,
          `artist_detail_selection_${(_param as ArtistDetailRouteParams).instanceId}`
        )
      ))
      .bindToScrollable([(_param as ArtistDetailRouteParams).scroller])
    } else if (name === LibraryDetailRoute.TRACK) {
      HdsNavDestination() {
        TrackDetailPage({
          store: this.libraryStore,
          state: (_param as TrackDetailRouteParams).state,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          rootWidth: this.rootWidth,
          themeBackground: this.themePageBackground,
          scroller: (_param as TrackDetailRouteParams).scroller,
          onOpenArtwork: (detail, index: number): void => {
            this.routePathStack(this.selectedRouteId).pushPath({
              name: LibraryDetailRoute.ARTWORK_VIEWER,
              param: new TrackArtworkViewerRouteParams(detail, index)
            });
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '歌曲信息',
        this.appearancePalette
      ))
      .bindToScrollable([(_param as TrackDetailRouteParams).scroller])
    } else if (name === LibraryDetailRoute.ARTWORK_VIEWER) {
      HdsNavDestination() {
        TrackArtworkViewerPage({
          state: (_param as TrackArtworkViewerRouteParams).state,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          rootWidth: this.rootWidth
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FF000000')
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryBackOnlyTitleBar(this.appearancePalette))
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
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar('自定义页面', this.appearancePalette))
      .bindToScrollable([this.customizationScroller])
    } else if (name === NavigationRoute.ABOUT) {
      HdsNavDestination() {
        AboutPage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          scroller: this.aboutScroller
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar('关于 w音乐', this.appearancePalette))
      .bindToScrollable([this.aboutScroller])
    } else if (name === NavigationRoute.PRIVACY_POLICY) {
      HdsNavDestination() {
        PrivacyPolicyPage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          scroller: this.privacyPolicyScroller
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar('隐私政策', this.appearancePalette))
      .bindToScrollable([this.privacyPolicyScroller])
    } else if (name === NavigationRoute.DATA_AND_PERMISSIONS) {
      HdsNavDestination() {
        DataAndPermissionsPage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          scroller: this.dataAndPermissionsScroller
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar('数据与权限', this.appearancePalette))
      .bindToScrollable([this.dataAndPermissionsScroller])
    } else if (name === NavigationRoute.OPEN_SOURCE_LICENSES) {
      HdsNavDestination() {
        OpenSourceLicensesPage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          scroller: this.openSourceLicensesScroller
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar('开源软件许可', this.appearancePalette))
      .bindToScrollable([this.openSourceLicensesScroller])
    } else {
      HdsNavDestination() {
        this.PageContent(name)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
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
    .backgroundColor(this.themePageBackground)
    .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(AppNavigationStyle.primaryTitleBar(
      item.label,
      this.appearancePalette,
      this.rootTitleMenu(item.routeId),
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
    .backgroundColor(this.themePageBackground)
    .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(AppNavigationStyle.primaryTitleBar(
      '更多',
      this.appearancePalette,
      undefined,
      this.moreTitleContent
    ))
    .bindToScrollable([this.moreScroller])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private MiniPlayer() {
    MiniPlayerSurface({
      playerStore: this.playerStore,
      binding: this.miniPlayerBinding,
      onShowFullPlayer: this.onShowFullPlayer,
      onTouchDown: (_localX: number): void => {},
      onGestureStart: this.onMiniPlayerGestureStart,
      onGestureUpdate: this.onMiniPlayerGestureUpdate,
      onGestureFinish: this.onMiniPlayerGestureFinish
    })
  }

  private playlistImportSheetHeight(): SheetSize {
    return this.playlistImportSheetKind === PlaylistImportSheetKind.REPORT ?
      SheetSize.LARGE : SheetSize.FIT_CONTENT;
  }

  private playlistImportStageText(): string {
    const prefix = this.playlistImportSourceName.length > 0 ? `${this.playlistImportSourceName}：` : '';
    if (this.playlistImportStage === M3uImportStage.READING) {
      return `${prefix}正在读取 M3U 文件`;
    }
    if (this.playlistImportStage === M3uImportStage.MATCHING) {
      return `${prefix}正在匹配音乐库歌曲`;
    }
    return `${prefix}正在写入播放列表`;
  }

  private playlistImportReportTitle(reports: Array<M3uImportReport>): string {
    if (reports.length === 1) {
      const report = reports[0];
      return report.playlistName.length > 0 ? `已导入“${report.playlistName}”` : '播放列表导入完成';
    }
    return `已导入 ${reports.length} 个播放列表`;
  }

  private playlistImportReportSummary(reports: Array<M3uImportReport>): string {
    let parsed = 0;
    let matched = 0;
    let inserted = 0;
    let alreadyPresent = 0;
    let unmatched = 0;
    let issues = 0;
    for (let index = 0; index < reports.length; index += 1) {
      parsed += reports[index].parsed;
      matched += reports[index].matched;
      inserted += reports[index].inserted;
      alreadyPresent += reports[index].alreadyPresent;
      unmatched += reports[index].unmatched;
      issues += reports[index].issues;
    }
    const modeLabel = reports.length === 1 ?
      (reports[0].mode === M3uImportMode.REPLACE ? '替换' : '合并') : '导入';
    return `${modeLabel}完成：匹配 ${matched}/${parsed} 项，` +
      `写入 ${inserted} 首，已存在 ${alreadyPresent} 首，` +
      `未匹配 ${unmatched} 项，解析问题 ${issues} 项`;
  }

  private playlistImportDetailItem(
    detail: M3uImportDetail,
    tone: TaskResultTone,
    keyPrefix: string,
    playlistName: string
  ): TaskResultDetailItem {
    const item: TaskResultDetailItem = {
      key: `${keyPrefix}_${detail.key}`,
      status: detail.status,
      title: detail.title,
      reason: playlistName.length > 0 ? `${playlistName} · ${detail.reason}` : detail.reason,
      uri: detail.uri,
      tone: tone
    };
    if (detail.secondaryUri !== undefined) {
      item.secondaryUri = detail.secondaryUri;
    }
    return item;
  }

  private playlistImportDetailItems(
    reports: Array<M3uImportReport>,
    selector: (report: M3uImportReport) => Array<M3uImportDetail>,
    tone: TaskResultTone
  ): Array<TaskResultDetailItem> {
    const items: Array<TaskResultDetailItem> = [];
    for (let reportIndex = 0; reportIndex < reports.length; reportIndex += 1) {
      const details = selector(reports[reportIndex]);
      for (let detailIndex = 0; detailIndex < details.length; detailIndex += 1) {
        items.push(this.playlistImportDetailItem(
          details[detailIndex],
          tone,
          `report_${reportIndex}`,
          reports.length > 1 ? reports[reportIndex].playlistName : ''
        ));
      }
    }
    return items;
  }

  private playlistImportDetailSections(reports: Array<M3uImportReport>): Array<TaskResultDetailSection> {
    return [{
      key: 'matched',
      title: '已匹配歌曲',
      emptyText: '没有匹配到音乐库中的歌曲',
      items: this.playlistImportDetailItems(
        reports,
        (report: M3uImportReport): Array<M3uImportDetail> => report.matchedDetails,
        TaskResultTone.SUCCESS
      ),
      tone: TaskResultTone.SUCCESS
    }, {
      key: 'unmatched',
      title: '未匹配项目',
      emptyText: '所有项目均已匹配',
      items: this.playlistImportDetailItems(
        reports,
        (report: M3uImportReport): Array<M3uImportDetail> => report.unmatchedDetails,
        TaskResultTone.ERROR
      ),
      tone: TaskResultTone.ERROR
    }, {
      key: 'issues',
      title: '解析问题',
      emptyText: '没有解析问题',
      items: this.playlistImportDetailItems(
        reports,
        (report: M3uImportReport): Array<M3uImportDetail> => report.issueDetails,
        TaskResultTone.ERROR
      ),
      tone: TaskResultTone.ERROR
    }];
  }

  private clearPlaylistImportReportIfClosed(): void {
    if (!this.playlistImportSheetVisible && this.playlistImportSheetKind === PlaylistImportSheetKind.REPORT) {
      this.playlistImportReports = [];
      this.playlistImportSheetKind = PlaylistImportSheetKind.PROGRESS;
      this.playlistImportStage = M3uImportStage.READING;
      this.playlistImportSourceName = '';
    }
  }

  @Builder
  private PlaylistImportProgressSheet() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        LoadingProgress()
          .width(28)
          .height(28)
        Column({ space: 4 }) {
          Text('正在导入播放列表')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(this.playlistImportStageText())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26, bottom: 28 })
  }

  @Builder
  private PlaylistImportReportSheet(reports: Array<M3uImportReport>) {
    Column({ space: 16 }) {
      Text(this.playlistImportReportTitle(reports))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(this.playlistImportReportSummary(reports))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TaskResultDetails({
        title: '导入明细',
        emptyText: '没有可显示的明细',
        sections: this.playlistImportDetailSections(reports)
      })
      Button('完成')
        .width('100%')
        .height(48)
        .onClick((): void => {
          this.playlistImportSheetVisible = false;
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 24 })
    .onDisAppear((): void => this.clearPlaylistImportReportIfClosed())
  }

  @Builder
  private PlaylistImportSheet() {
    if (this.playlistImportSheetKind === PlaylistImportSheetKind.REPORT &&
      this.playlistImportReports.length > 0) {
      this.PlaylistImportReportSheet(this.playlistImportReports)
    } else {
      this.PlaylistImportProgressSheet()
    }
  }

  private NativeCompactTabBar(symbol: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(symbol)
    }, label).labelStyle({
      maxLines: 1,
      font: { size: 10 }
    });
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
              $r('app.color.theme_accent') : $r('app.color.text_tertiary')])
            .animation({ duration: AppShellLayoutSpec.TAB_SELECTION_COLOR_DURATION, curve: Curve.EaseInOut })
          Text(item.label)
            .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LABEL_SIZE)
            .fontWeight(this.expandedTabIndex() === tabIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.expandedTabIndex() === tabIndex ?
              $r('app.color.theme_accent') : $r('app.color.text_secondary'))
            .animation({ duration: AppShellLayoutSpec.TAB_SELECTION_COLOR_DURATION, curve: Curve.EaseInOut })
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
              $r('app.color.theme_accent') : $r('app.color.text_tertiary')])
            .animation({ duration: AppShellLayoutSpec.TAB_SELECTION_COLOR_DURATION, curve: Curve.EaseInOut })
          Text(item.label)
            .fontSize(AppShellLayoutSpec.EXPANDED_TAB_ITEM_LABEL_SIZE)
            .fontWeight(this.expandedTabIndex() === tabIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.expandedTabIndex() === tabIndex ?
              $r('app.color.theme_accent') : $r('app.color.text_secondary'))
            .animation({ duration: AppShellLayoutSpec.TAB_SELECTION_COLOR_DURATION, curve: Curve.EaseInOut })
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
  private RegularCompactTabsContent() {
    HdsTabs({ controller: this.compactTabsController,
      index: this.compactTabIndex() }) {
      ForEach(this.primaryItems(),
        (item: NavigationPageItem, index: number) => {
        TabContent() {
          this.RootNavigation(item)
        }
        .tabBar(this.NativeCompactTabBar(item.symbol, item.label))
      }, (item: NavigationPageItem) => item.routeId)
      TabContent() {
        this.MoreNavigation()
      }
      .tabBar(this.NativeCompactTabBar(
        $r('sys.symbol.square_fill_grid_2x2'),
        '更多'
      ))
    }
    .width('100%')
    .height('100%')
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .onSelected(this.onCompactTabChange)
    .onTabBarClick(this.onCompactTabClick)
    .barFloatingStyle(this.compactTabsFloatingStyle())
  }

  @Builder
  private CondensedCompactTabsContent() {
    HdsTabs({ controller: this.condensedCompactTabsController,
      index: this.compactTabIndex() }) {
      ForEach(this.primaryItems(),
        (item: NavigationPageItem, index: number) => {
        TabContent() {
          this.RootNavigation(item)
        }
        .tabBar(this.NativeCompactTabBar(item.symbol, item.label))
      }, (item: NavigationPageItem) => item.routeId)
      TabContent() {
        this.MoreNavigation()
      }
      .tabBar(this.NativeCompactTabBar(
        $r('sys.symbol.square_fill_grid_2x2'),
        '更多'
      ))
    }
    .width('100%')
    .height('100%')
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barMode(BarMode.Fixed)
    .scrollable(true)
    .onSelected(this.onCompactTabChange)
    .onTabBarClick(this.onCompactTabClick)
    .barFloatingStyle(this.condensedCompactTabsFloatingStyle())
  }

  @Builder
  private ExpandedTabsContent() {
    HdsTabs({ controller: this.expandedTabsController, index: this.expandedTabIndex() }) {
      ForEach(this.expandedItems(), (item: NavigationPageItem, index: number) => {
        TabContent() {
          Stack({ alignContent: Alignment.Bottom }) {
            this.RootNavigation(item)
            if (this.expandedTabIndex() === index) {
              this.WideMiniPlayerHost()
            }
          }
          .width('100%')
          .height('100%')
        }
        .tabBar(this.ExpandedTabBar(item, index))
      }, (item: NavigationPageItem) => item.routeId)
    }
    .width('100%')
    .height('100%')
    .barPosition(BarPosition.Start)
    .barWidth(this.expandedTabBarWidth())
    .vertical(true)
    .barMode(BarMode.Scrollable)
    .scrollable(false)
    .animationDuration(0)
    .onSelected(this.onExpandedTabChange)
    .onTabBarClick(this.onExpandedTabClick)
  }

  @Builder
  private WideMiniPlayerHost() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      HdsTabs({ index: 0 }) {
        TabContent() { Stack() }
          .tabBar(new BottomTabBarStyle({
            normal: new SymbolGlyphModifier($r('sys.symbol.music_fill'))
          }, '播放器'))
      }
      .width(this.rootWidth)
      .height('100%')
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .barFloatingStyle(this.wideMiniPlayerFloatingStyle())
    }
    .id(AppShellLayoutSpec.WIDE_MINI_PLAYER_HOST_ID)
    .width('100%')
    .height(AppShellLayoutSpec.WIDE_MINI_PLAYER_HOST_HEIGHT)
    .clip(true)
  }

  build() {
    Stack() {
      if (!AppShellLayoutSpec.hasResolvedRootSize(this.rootWidth, this.rootHeight)) {
        Stack()
          .id('player_tabs_layout_pending')
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      } else if (this.usesWideLayout()) {
        Stack() { this.ExpandedTabsContent() }
        .id(AppShellLayoutSpec.WIDE_TABS_HOST_ID)
        .width('100%')
        .height('100%')
      } else if (AppShellLayoutSpec.usesCondensedCompactNavigation(this.rootWidth)) {
        Stack() { this.CondensedCompactTabsContent() }
        .id(AppShellLayoutSpec.CONDENSED_COMPACT_TABS_HOST_ID)
        .width('100%')
        .height('100%')
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.onCondensedOutsideTouch();
          }
        })
      } else {
        Stack() { this.RegularCompactTabsContent() }
        .id(AppShellLayoutSpec.COMPACT_TABS_HOST_ID)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.playlistImportSheetVisible, this.PlaylistImportSheet(), {
      height: this.playlistImportSheetHeight(),
      dragBar: true,
      showClose: !this.playlistTransferBusy
    })
    }
}
