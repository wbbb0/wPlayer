import {
  HdsBarStyle,
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
import {
  DynamicColor,
  DynamicContainerRole,
  ForegroundEmphasis
} from '../../appearance/DynamicColor';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { PageBottomGradient } from '../layout/PageBottomGradient';
import { AppNavigationStyle } from './AppNavigationStyle';
import { AppPrimaryTitleParams } from './AppPrimaryTitleContent';
import {
  NavigationPageItem,
  NavigationRoute,
  PRIMARY_NAVIGATION_COUNT,
  SETTINGS_NAVIGATION_ITEM,
  navigationItemIndex,
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
import { PlaylistImportSheetKind } from '../library/PlaylistImportSheetContent';
import {
  AlbumSortField,
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  PlaylistKind,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackSortField,
  SortDirection,
  TrackDetail,
  TrackListItem,
  TrackSortField
} from
  '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { TrackArtworkViewerState } from '../../library/store/LibraryDetailState';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { MorePage } from '../../pages/library/MorePage';
import { AlbumDetailColorPolicy } from '../../pages/library/AlbumDetailPage';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import {
  AlbumDetailRouteParams,
  ArtistDetailRouteParams
} from './LibraryNavigation';
import {
  M3uImportNameConflictAction,
  M3uImportContext,
  M3uImportMode,
  M3uImportStage,
  M3uImportReport,
  M3uImportSource,
  M3uTransferService
} from '../../playlist/m3u/M3uTransferService';
import { M3uImportReportBudget } from '../../playlist/m3u/M3uImportReportPolicy';
import { AlbumAction } from '../library/AlbumGridItem';
import {
  MultiSelectController
} from '../library/MultiSelectController';
import { TrackDetailSheetBridge } from './TrackDetailSheetBridge';
import { NavigationChromeController } from './NavigationChromeController';
import { SelectionNavigationTitleBar } from './SelectionNavigationTitleBar';
import { TitleBarMotionSpec } from './TitleBarMotionSpec';
import {
  ResponsiveNavigationModalHost,
  TrackDetailSheetPresentationState
} from './ResponsiveNavigationModalHost';
import {
  PLAYLIST_DETAIL_ROUTE,
  PlaylistDetailRouteParams,
  ResponsiveNavigationDestinationContent,
  ResponsiveNavigationRouteContent
} from './ResponsiveNavigationRouteContent';

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
const MORE_TAB_INDEX: number = PRIMARY_NAVIGATION_COUNT;

@Component
export struct ResponsiveNavigationShell {
  private static readonly GRADIENT_MASK_OPACITY: number = 0.40;

  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink playlistStore: PlaylistStore;
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @ObjectLink miniPlayerBinding: MiniPlayerBinding;
  @ObjectLink navigationChromeController: NavigationChromeController;
  compactMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  condensedCompactMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  wideMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop @Watch('onRootWidthChanged') rootWidth: number = 0;
  @Prop rootHeight: number = 0;
  @Prop navigationOrder: Array<string> = [];
  @Prop selectedRouteId: string = NavigationRoute.PLAYLISTS;
  @Prop appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();
  @Prop themePageBackground: string = '#FF000000';
  @Prop playbackChromeBackground: string = '';
  onDestinationBackPressed: () => boolean = (): boolean => false;
  onShowFullPlayer: () => void = (): void => {};
  onMiniPlayerGestureStart: () => void = (): void => {};
  onMiniPlayerGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onMiniPlayerGestureFinish: () => void = (): void => {};
  onDemoLibraryChange: (value: boolean) => void = (_value: boolean): void => {};

  compactTabsController: HdsTabsController = new HdsTabsController();
  condensedCompactTabsController: HdsTabsController = new HdsTabsController();
  expandedTabsController: HdsTabsController = new HdsTabsController();
  rootTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> = [];
  rootTitleParams: Array<AppPrimaryTitleParams | undefined> = [];
  @Prop moreTitleContent: ComponentContent<AppPrimaryTitleParams> | undefined = undefined;
  rootPathStacks: Array<NavPathStack> = [];
  rootScrollers: Array<Scroller> = [];
  morePathStack: NavPathStack = new NavPathStack();
  moreScroller: Scroller = new Scroller();
  customizationScroller: Scroller = new Scroller();
  floatingWindowSettingsScroller: Scroller = new Scroller();
  trackDetailSheetBridge: TrackDetailSheetBridge = new TrackDetailSheetBridge();
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
  onPictureInPictureSettingsChange: () => void = (): void => {};
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
  @State private playlistTransferBusy: boolean = false;
  @State private playlistImportSheetVisible: boolean = false;
  @State private playlistImportSheetKind: PlaylistImportSheetKind = PlaylistImportSheetKind.PROGRESS;
  @State private playlistImportStage: M3uImportStage = M3uImportStage.READING;
  @State private playlistImportSourceName: string = '';
  @State private playlistImportReports: Array<M3uImportReport> = [];
  @State private songsSelection: MultiSelectController = new MultiSelectController();
  @State private albumsSelection: MultiSelectController = new MultiSelectController();
  @State private playlistsSelection: MultiSelectController = new MultiSelectController();
  @State private detailSelectionRevision: number = 0;
  @State private rootSearchRouteId: string = '';
  @State private trackDetailSheetVisible: boolean = false;
  @State private artworkViewerVisible: boolean = false;
  @State private artworkViewerState: TrackArtworkViewerState | undefined = undefined;
  @State private trackDetailSheetState: TrackDetailSheetPresentationState =
    new TrackDetailSheetPresentationState();
  private readonly bridgedOpenTrackDetails: (track: TrackListItem) => void =
    (track: TrackListItem): void => this.openTrackDetails(track);
  private readonly onDetailSelectionChange: () => void = (): void => {
    this.detailSelectionRevision += 1;
    this.syncRootTitleContents();
  };

  aboutToAppear(): void {
    this.trackDetailSheetBridge.attach(this.bridgedOpenTrackDetails);
    this.syncRootTitleContents();
  }

  aboutToDisappear(): void {
    this.trackDetailSheetBridge.detach(this.bridgedOpenTrackDetails);
  }

  private onRootWidthChanged(): void {
    if (this.supportsTitleSearchAndSelection()) {
      return;
    }
    this.rootSearchRouteId = '';
    this.songsSelection.cancel();
    this.albumsSelection.cancel();
    this.playlistsSelection.cancel();
  }

  private toggleRootSearch(routeId: string): void {
    if (!this.supportsTitleSearchAndSelection()) {
      return;
    }
    this.getUIContext().animateTo({
      curve: TitleBarMotionSpec.transitionCurve()
    }, (): void => {
      this.rootSearchRouteId = this.rootSearchRouteId === routeId ? '' : routeId;
      this.syncRootTitleContents();
    });
  }

  private syncRootTitleContents(): void {
    const routes: Array<string> = [
      NavigationRoute.PLAYLISTS,
      NavigationRoute.SONGS,
      NavigationRoute.ALBUMS
    ];
    routes.forEach((routeId: string): void => {
      const index = navigationItemIndex(routeId);
      const params = this.rootTitleParams[index];
      if (params === undefined) {
        return;
      }
      params.searchExpanded = this.rootSearchRouteId === routeId;
      params.onCancelSearch = (): void => this.toggleRootSearch(routeId);
      this.rootTitleContents[index]?.update(params);
    });
  }

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

  private supportsTitleSearchAndSelection(): boolean {
    return AppShellLayoutSpec.supportsTitleSearchAndSelection(this.rootWidth);
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
        maskColor: '#00000000',
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
        maskColor: '#00000000',
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
        this.finishPlaylistImportWithError(error);
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
    const detailBudget = new M3uImportReportBudget();
    const importContext = await this.playlistTransferService.createImportContext();
    for (let index = 0; index < sources.length; index += 1) {
      const source = sources[index];
      try {
        await this.playlistStore.synchronizeRepositoryChanges();
        const conflict = this.playlistTransferService.findNameConflict(source, this.playlistStore.playlists);
        if (conflict === undefined) {
          this.appendPlaylistImportReport(
            reports,
            await this.importPlaylistSourceAsNewForBatch(source, importContext),
            detailBudget
          );
          await this.playlistStore.synchronizeCommittedRepositoryChanges();
          continue;
        }
        const action = await this.choosePlaylistNameConflictAction(source, conflict);
        if (action === undefined) {
          continue;
        }
        if (action === M3uImportNameConflictAction.SAVE_AS_NEW) {
          this.appendPlaylistImportReport(
            reports,
            await this.importPlaylistSourceAsNewForBatch(source, importContext),
            detailBudget
          );
        } else {
          const mode = action === M3uImportNameConflictAction.REPLACE ?
            M3uImportMode.REPLACE : M3uImportMode.MERGE;
          this.appendPlaylistImportReport(
            reports,
            await this.importPlaylistSourceIntoForBatch(source, conflict.id, mode, importContext),
            detailBudget
          );
        }
        await this.playlistStore.synchronizeCommittedRepositoryChanges();
      } catch (error) {
        this.appendPlaylistImportReport(
          reports,
          this.playlistTransferService.failedImportReport(source, error),
          detailBudget
        );
      }
    }
    return reports;
  }

  private appendPlaylistImportReport(
    reports: Array<M3uImportReport>,
    report: M3uImportReport,
    budget: M3uImportReportBudget
  ): void {
    const matched = budget.retainMatched(report.matchedDetails.length);
    const unmatched = budget.retainUnmatched(report.unmatchedDetails.length);
    const issues = budget.retainIssues(report.issueDetails.length);
    const failures = budget.retainFailures(report.failureDetails.length);
    const truncated = matched < report.matchedDetails.length ||
      unmatched < report.unmatchedDetails.length ||
      issues < report.issueDetails.length ||
      failures < report.failureDetails.length;
    report.matchedDetails = report.matchedDetails.slice(0, matched);
    report.unmatchedDetails = report.unmatchedDetails.slice(0, unmatched);
    report.issueDetails = report.issueDetails.slice(0, issues);
    report.failureDetails = report.failureDetails.slice(0, failures);
    report.detailsTruncated = report.detailsTruncated || truncated;
    reports.push(report);
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
    this.playlistsSelection.selectableCount = this.playlistStore.playlists.length;
    const sortContent: HdsNavigationMenuItemOptions = {
      content: AppShellLayoutSpec.usesSortIconOnly(this.rootWidth) ? {
        icon: $r('sys.symbol.line_3_horizontal'),
        label: '排序',
        type: IconStyleMode.NORMAL,
        componentId: PLAYLIST_SORT_MENU_ID,
        action: (): void => this.openPlaylistSortMenu()
      } : {
        label: `${this.playlistStore.playlists.length} 个`,
        type: TextStyleMode.NORMAL,
        componentId: PLAYLIST_SORT_MENU_ID,
        action: (): void => this.openPlaylistSortMenu()
      }
    };
    const values: Array<HdsNavigationMenuItemOptions> = [{
      content: {
        icon: $r('sys.symbol.plus'),
        label: '新建或导入播放列表',
        type: IconStyleMode.NORMAL,
        componentId: PLAYLIST_CREATE_MENU_ID,
        action: (): void => this.openPlaylistCreateMenu()
      }
    }, sortContent];
    return SelectionNavigationTitleBar.menu(
      this.getUIContext(),
      this.playlistsSelection,
      'playlists_selection_actions',
      this.detailSelectionRevision,
      this.onDetailSelectionChange,
      values,
      this.supportsTitleSearchAndSelection()
    );
  }

  private shuffleAllTracks(): void {
    this.libraryStore.loadTrackPlaybackOrder()
      .then((items: Array<TrackListItem>) => playbackRuntime.shuffleAll(items))
      .catch((error: Object) => console.warn(`Unable to load shuffle queue: ${error}`));
  }

  private playLibraryTrack(item: TrackListItem): void {
    this.libraryStore.loadTrackPlaybackOrder()
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
    if (this.rootSearchRouteId === routeId) {
      return { maxCount: 0, value: [] };
    }
    const isTracks = routeId === NavigationRoute.SONGS;
    const targetId = isTracks ? TRACK_SORT_MENU_ID : ALBUM_SORT_MENU_ID;
    const countLabel = isTracks ? `${this.libraryStore.statistics.trackCount} 首` :
      `${this.libraryStore.statistics.albumCount} 张`;
    const sortItem: HdsNavigationMenuItemOptions = {
      content: AppShellLayoutSpec.usesSortIconOnly(this.rootWidth) ? {
        icon: $r('sys.symbol.line_3_horizontal'),
        label: '排序',
        type: IconStyleMode.NORMAL,
        componentId: targetId,
        action: () => this.openSortMenu(routeId, targetId)
      } : {
        label: countLabel,
        type: TextStyleMode.NORMAL,
        componentId: targetId,
        action: () => this.openSortMenu(routeId, targetId)
      }
    };
    const searchItem: HdsNavigationMenuItemOptions = {
      content: {
        icon: $r('sys.symbol.magnifyingglass'),
        label: '搜索',
        type: IconStyleMode.NORMAL,
        action: (): void => this.toggleRootSearch(routeId)
      }
    };
    const values: Array<HdsNavigationMenuItemOptions> = isTracks ? [{
      content: {
        icon: $r('sys.symbol.shuffle'),
        label: '随机播放全部音乐',
        type: IconStyleMode.NORMAL,
        isEnabled: this.libraryStore.statistics.trackCount > 0,
        action: () => this.shuffleAllTracks()
      }
    }] : [];
    if (this.supportsTitleSearchAndSelection()) {
      values.push(searchItem);
    }
    values.push(sortItem);
    const selection = this.rootSelection(routeId);
    if (selection !== undefined) {
      selection.selectableCount = isTracks ?
        this.libraryStore.statistics.trackCount : this.libraryStore.statistics.albumCount;
    }
    return selection === undefined ?
      { maxCount: values.length, value: values } :
      SelectionNavigationTitleBar.menu(
        this.getUIContext(),
        selection,
        `${routeId}_selection_actions`,
        this.detailSelectionRevision,
        this.onDetailSelectionChange,
        values,
        this.supportsTitleSearchAndSelection(),
        (): void => {
          this.rootSearchRouteId = '';
        }
      );
  }

  private albumDetailBackground(params: AlbumDetailRouteParams): string {
    return AlbumDetailColorPolicy.background(
      params.state.detail?.album.palettePrimary ?? params.palettePrimary
    );
  }

  private albumDetailContentColor(params: AlbumDetailRouteParams): string {
    return DynamicColor.foreground(
      this.albumDetailBackground(params),
      DynamicContainerRole.PRIMARY
    );
  }

  private albumDetailControlBackgroundColor(params: AlbumDetailRouteParams): ResourceColor | undefined {
    const lightAppearance = this.appearancePalette.windowBackground.toUpperCase() !== '#FF000000';
    const darkContent = this.albumDetailContentColor(params).toUpperCase() === '#FF000000';
    if (lightAppearance && darkContent) {
      return undefined;
    }
    const inverseColor = this.albumDetailContentColor(params).toUpperCase() === '#FFFFFFFF' ?
      '#FF000000' : '#FFFFFFFF';
    return DynamicColor.withEmphasis(inverseColor, ForegroundEmphasis.DISABLED);
  }

  private playbackChromeBackgroundColor(): ResourceColor | undefined {
    return this.playbackChromeBackground.length > 0 ?
      this.gradientMaskColor(this.playbackChromeBackground) : undefined;
  }

  private gradientMaskColor(color: string): string {
    return DynamicColor.withOpacity(color, ResponsiveNavigationShell.GRADIENT_MASK_OPACITY);
  }

  private albumDetailTitleMenu(
    params: AlbumDetailRouteParams,
    revision: number
  ): HdsNavigationMenuContentOptions {
    params.selection.selectableCount = params.state.detail?.tracks.length ?? 0;
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
    return SelectionNavigationTitleBar.menu(
      this.getUIContext(),
      params.selection,
      `album_detail_selection_${params.instanceId}`,
      revision,
      this.onDetailSelectionChange,
      values,
      this.supportsTitleSearchAndSelection()
    );
  }

  private artistDetailTitleMenu(
    params: ArtistDetailRouteParams,
    revision: number
  ): HdsNavigationMenuContentOptions {
    params.selection.selectableCount = params.state.detail?.trackCount ?? 0;
    return SelectionNavigationTitleBar.menu(
      this.getUIContext(),
      params.selection,
      `artist_detail_selection_${params.instanceId}`,
      revision,
      this.onDetailSelectionChange,
      [],
      this.supportsTitleSearchAndSelection()
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
    this.trackDetailSheetState.present(item.id, item.title);
    this.trackDetailSheetVisible = true;
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
    const detail = this.playlistStore.detailOverview;
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
    this.playlistImportSourceName = '';
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
    this.playlistImportStage = M3uImportStage.READING;
    this.playlistImportSourceName = '';
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

  private playlistDetailTitleMenu(
    params: PlaylistDetailRouteParams,
    revision: number,
    playlist?: PlaylistSummary
  ): HdsNavigationMenuContentOptions {
    params.selection.selectableCount = playlist?.trackCount ?? 0;
    const sortTargetId = `playlist_detail_sort_${params.instanceId}`;
    const moreTargetId = `playlist_detail_more_${params.instanceId}`;
    const values: Array<HdsNavigationMenuItemOptions> = [{
      content: AppShellLayoutSpec.usesSortIconOnly(this.rootWidth) ? {
        icon: $r('sys.symbol.line_3_horizontal'),
        label: '排序',
        type: IconStyleMode.NORMAL,
        componentId: sortTargetId,
        action: (): void => this.openPlaylistTrackSortMenu(params.playlistId, sortTargetId)
      } : {
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
    return SelectionNavigationTitleBar.menu(
      this.getUIContext(),
      params.selection,
      `playlist_detail_selection_${params.instanceId}`,
      revision,
      this.onDetailSelectionChange,
      values,
      this.supportsTitleSearchAndSelection()
    );
  }

  @Builder
  private PageContent(routeId: string) {
    ResponsiveNavigationRouteContent({
      libraryStore: this.libraryStore,
      playlistStore: this.playlistStore,
      settingsStore: this.settingsStore,
      playlistsSelection: this.playlistsSelection,
      songsSelection: this.songsSelection,
      albumsSelection: this.albumsSelection,
      routeId: routeId,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.routeScroller(routeId),
      onOpenPlaylist: (playlist: PlaylistSummary): void => {
        this.routePathStack(routeId).pushPath({
          name: PLAYLIST_DETAIL_ROUTE,
          param: new PlaylistDetailRouteParams(playlist.id, playlist.name)
        });
      },
      onRequestRenamePlaylist: this.onRequestRenamePlaylist,
      onPlayTrack: (item: TrackListItem): void => this.playLibraryTrack(item),
      onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
        this.openTrackActions(item, anchorId),
      onOpenTrackDetails: (item: TrackListItem): void => this.openTrackDetails(item),
      onNavigateLibrary: this.onNavigateLibrary,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      onAlbumAction: (albumId: number, action: AlbumAction): void =>
        this.performAlbumAction(albumId, action),
      onOpenNavigationCustomization: this.onOpenNavigationCustomization,
      onOpenFloatingWindowSettings: (): void =>
        this.routePathStack(NavigationRoute.SETTINGS).pushPath({
          name: NavigationRoute.FLOATING_WINDOW_SETTINGS
        }),
      onOpenAbout: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.ABOUT
      }),
      onOpenPrivacyPolicy: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.PRIVACY_POLICY
      }),
      onOpenDataAndPermissions: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.DATA_AND_PERMISSIONS
      }),
      onOpenOpenSourceLicenses: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.OPEN_SOURCE_LICENSES
      }),
      onRememberLastTabChange: this.onRememberLastTabChange,
      onRememberSortChange: this.onRememberSortChange,
      onOpenDynamicBackgroundV1: (): void =>
        this.routePathStack(NavigationRoute.DEBUG).pushPath({
          name: NavigationRoute.DYNAMIC_BACKGROUND_DEBUG
        }),
      onOpenDynamicBackgroundV2: (): void =>
        this.routePathStack(NavigationRoute.DEBUG).pushPath({
          name: NavigationRoute.DYNAMIC_BACKGROUND_V2_DEBUG
        }),
      onOpenDynamicBackgroundV3: (): void =>
        this.routePathStack(NavigationRoute.DEBUG).pushPath({
          name: NavigationRoute.DYNAMIC_BACKGROUND_V3_DEBUG
        }),
      onDemoLibraryChange: this.onDemoLibraryChange
    })
  }

  @Builder
  private DestinationBuilder(name: string, _param: Object) {
    ResponsiveNavigationDestinationContent({
      libraryStore: this.libraryStore,
      playlistStore: this.playlistStore,
      playerStore: this.playerStore,
      settingsStore: this.settingsStore,
      navigationChromeController: this.navigationChromeController,
      playlistsSelection: this.playlistsSelection,
      songsSelection: this.songsSelection,
      albumsSelection: this.albumsSelection,
      name: name,
      param: _param,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      rootWidth: this.rootWidth,
      themePageBackground: this.themePageBackground,
      detailSelectionRevision: this.detailSelectionRevision,
      orderedItems: this.orderedItems(),
      customizationScroller: this.customizationScroller,
      floatingWindowSettingsScroller: this.floatingWindowSettingsScroller,
      aboutScroller: this.aboutScroller,
      privacyPolicyScroller: this.privacyPolicyScroller,
      dataAndPermissionsScroller: this.dataAndPermissionsScroller,
      openSourceLicensesScroller: this.openSourceLicensesScroller,
      routeScroller: (routeId: string): Scroller => this.routeScroller(routeId),
      onOpenPlaylist: (playlist: PlaylistSummary): void => {
        this.routePathStack(name).pushPath({
          name: PLAYLIST_DETAIL_ROUTE,
          param: new PlaylistDetailRouteParams(playlist.id, playlist.name)
        });
      },
      onRequestRenamePlaylist: this.onRequestRenamePlaylist,
      onPlayTrack: (item: TrackListItem): void => this.playLibraryTrack(item),
      onOpenNavigationCustomization: this.onOpenNavigationCustomization,
      onOpenFloatingWindowSettings: (): void =>
        this.routePathStack(NavigationRoute.SETTINGS).pushPath({
          name: NavigationRoute.FLOATING_WINDOW_SETTINGS
        }),
      onOpenAbout: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.ABOUT
      }),
      onOpenPrivacyPolicy: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.PRIVACY_POLICY
      }),
      onOpenDataAndPermissions: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.DATA_AND_PERMISSIONS
      }),
      onOpenOpenSourceLicenses: (): void => this.routePathStack(NavigationRoute.SETTINGS).pushPath({
        name: NavigationRoute.OPEN_SOURCE_LICENSES
      }),
      onRememberLastTabChange: this.onRememberLastTabChange,
      onRememberSortChange: this.onRememberSortChange,
      onOpenDynamicBackgroundV1: (): void =>
        this.routePathStack(NavigationRoute.DEBUG).pushPath({
          name: NavigationRoute.DYNAMIC_BACKGROUND_DEBUG
        }),
      onOpenDynamicBackgroundV2: (): void =>
        this.routePathStack(NavigationRoute.DEBUG).pushPath({
          name: NavigationRoute.DYNAMIC_BACKGROUND_V2_DEBUG
        }),
      onOpenDynamicBackgroundV3: (): void =>
        this.routePathStack(NavigationRoute.DEBUG).pushPath({
          name: NavigationRoute.DYNAMIC_BACKGROUND_V3_DEBUG
        }),
      onDemoLibraryChange: this.onDemoLibraryChange,
      playlistDetailTitleMenu: (
        params: PlaylistDetailRouteParams,
        revision: number,
        playlist?: PlaylistSummary
      ): HdsNavigationMenuContentOptions =>
        this.playlistDetailTitleMenu(params, revision, playlist),
      albumDetailTitleMenu: (
        params: AlbumDetailRouteParams,
        revision: number
      ): HdsNavigationMenuContentOptions =>
        this.albumDetailTitleMenu(params, revision),
      artistDetailTitleMenu: (
        params: ArtistDetailRouteParams,
        revision: number
      ): HdsNavigationMenuContentOptions =>
        this.artistDetailTitleMenu(params, revision),
      albumDetailBackground: (params: AlbumDetailRouteParams): string =>
        this.albumDetailBackground(params),
      albumDetailContentColor: (params: AlbumDetailRouteParams): string =>
        this.albumDetailContentColor(params),
      albumDetailControlBackgroundColor: (params: AlbumDetailRouteParams): ResourceColor | undefined =>
        this.albumDetailControlBackgroundColor(params),
      playbackChromeBackgroundColor: (): ResourceColor | undefined =>
        this.playbackChromeBackgroundColor(),
      gradientMaskColor: (color: string): string => this.gradientMaskColor(color),
      onDestinationBackPressed: this.onDestinationBackPressed,
      onNavigationItemMove: this.onNavigationItemMove,
      onPictureInPictureSettingsChange: this.onPictureInPictureSettingsChange,
      onNavigateLibrary: this.onNavigateLibrary,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      onOpenTrackActions: (
        item: TrackListItem,
        anchorId: string,
        current?: LibraryEntityIdentity
      ): void => this.openTrackActions(item, anchorId, current),
      onOpenTrackDetails: (item: TrackListItem): void => this.openTrackDetails(item),
      onAlbumAction: (albumId: number, action: AlbumAction): void =>
        this.performAlbumAction(albumId, action)
    })
  }

  @Builder
  private RootNavigation(item: NavigationPageItem) {
    HdsNavigation(this.rootPathStacks[navigationItemIndex(item.routeId)]) {
      Stack({ alignContent: Alignment.Bottom }) {
        this.PageContent(item.routeId)
        PageBottomGradient({ maskColor: this.themePageBackground })
      }
      .width('100%')
      .height('100%')
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
      this.rootTitleMenu(item.routeId),
      this.rootTitleContents[navigationItemIndex(item.routeId)],
      this.playbackChromeBackgroundColor()
    ))
    .bindToScrollable([this.routeScroller(item.routeId)])
    .navDestination(this.DestinationBuilder)
  }

  @Builder
  private MoreNavigation() {
    HdsNavigation(this.morePathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        MorePage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          scroller: this.moreScroller,
          items: this.moreItems(),
          openDestination: this.onOpenMoreDestination
        })
        PageBottomGradient({ maskColor: this.themePageBackground })
      }
      .width('100%')
      .height('100%')
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
      undefined,
      this.moreTitleContent,
      this.playbackChromeBackgroundColor()
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

  private openArtworkViewer(detail: TrackDetail, index: number): void {
    this.artworkViewerState = new TrackArtworkViewerState(detail, index);
    this.artworkViewerVisible = true;
  }

  private closeArtworkViewer(): void {
    this.artworkViewerVisible = false;
  }

  private finishClosingArtworkViewer(): void {
    this.artworkViewerVisible = false;
    this.artworkViewerState = undefined;
  }

  private handleTrackDetailDisappear(): void {
    if (!this.trackDetailSheetVisible) {
      this.closeArtworkViewer();
      this.trackDetailSheetState.clear();
    }
  }

  @Builder
  private SheetHosts() {
    Stack() {
      ResponsiveNavigationModalHost({
        libraryStore: this.libraryStore,
        trackDetailVisible: $trackDetailSheetVisible,
        artworkViewerVisible: $artworkViewerVisible,
        playlistImportVisible: $playlistImportSheetVisible,
        trackDetailState: this.trackDetailSheetState,
        artworkViewerState: this.artworkViewerState,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        rootWidth: this.rootWidth,
        themePageBackground: this.themePageBackground,
        playlistImportBusy: this.playlistTransferBusy,
        playlistImportKind: this.playlistImportSheetKind,
        playlistImportStage: this.playlistImportStage,
        playlistImportSourceName: this.playlistImportSourceName,
        playlistImportReports: this.playlistImportReports,
        onOpenArtwork: (detail: TrackDetail, index: number): void =>
          this.openArtworkViewer(detail, index),
        onCloseArtwork: (): void => this.closeArtworkViewer(),
        onArtworkViewerDisappear: (): void => this.finishClosingArtworkViewer(),
        onTrackDetailDisappear: (): void => this.handleTrackDetailDisappear(),
        onPlaylistImportDisappear: (): void => this.clearPlaylistImportReportIfClosed()
      })
    }
    .width(1)
    .height(1)
  }

  private clearPlaylistImportReportIfClosed(): void {
    if (!this.playlistImportSheetVisible && this.playlistImportSheetKind === PlaylistImportSheetKind.REPORT) {
      this.playlistImportReports = [];
      this.playlistImportSheetKind = PlaylistImportSheetKind.PROGRESS;
      this.playlistImportStage = M3uImportStage.READING;
      this.playlistImportSourceName = '';
    }
  }

  private NativeCompactTabBar(symbol: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(symbol)
    }, label)
      .labelStyle({
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
    .hitTestBehavior(HitTestMode.Transparent)
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

      this.SheetHosts()
    }
    .width('100%')
    .height('100%')
    }
}
