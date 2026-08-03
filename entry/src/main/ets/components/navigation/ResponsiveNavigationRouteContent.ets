import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigationMenuContentOptions
} from '@kit.UIDesignKit';
import { PageBottomGradient } from '../layout/PageBottomGradient';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import { AppNavigationStyle } from './AppNavigationStyle';
import {
  NavigationPageItem,
  NavigationPageKind,
  NavigationRoute,
  navigationItem,
  navigationPageKind
} from './MoreNavigation';
import {
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  PlaylistSummary,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { MultiSelectController } from '../library/MultiSelectController';
import { AlbumAction } from '../library/AlbumGridItem';
import { PlaylistsPage } from '../../pages/library/PlaylistsPage';
import { SongsPage } from '../../pages/library/SongsPage';
import { AlbumsPage } from '../../pages/library/AlbumsPage';
import { LibraryManagementPage } from '../../pages/library/LibraryManagementPage';
import { SettingsPage } from '../../pages/settings/SettingsPage';
import { DebugPage } from '../../pages/settings/DebugPage';
import { PlaylistDetailPage } from '../../pages/library/PlaylistDetailPage';
import {
  AlbumDetailColorPolicy,
  AlbumDetailPage
} from '../../pages/library/AlbumDetailPage';
import { ArtistDetailPage } from '../../pages/library/ArtistDetailPage';
import { ArtistTrackCollectionPage } from '../../pages/library/ArtistTrackCollectionPage';
import { AlbumCollectionPage } from '../../pages/library/AlbumCollectionPage';
import { AlbumCollectionScope } from '../../library/store/LibraryCollectionState';
import { FloatingWindowSettingsPage } from '../../pages/settings/FloatingWindowSettingsPage';
import { PlayerPageSettingsPage } from '../../pages/settings/PlayerPageSettingsPage';
import { DynamicBackgroundDebugPage } from '../../pages/settings/DynamicBackgroundDebugPage';
import { DynamicBackgroundV2DebugPage } from '../../pages/settings/DynamicBackgroundV2DebugPage';
import { DynamicBackgroundV3DebugPage } from '../../pages/settings/DynamicBackgroundV3DebugPage';
import { NavigationCustomizationPage } from '../../pages/settings/NavigationCustomizationPage';
import { AboutPage } from '../../pages/settings/AboutPage';
import { PrivacyPolicyPage } from '../../pages/settings/PrivacyPolicyPage';
import { DataAndPermissionsPage } from '../../pages/settings/DataAndPermissionsPage';
import { OpenSourceLicensesPage } from '../../pages/settings/OpenSourceLicensesPage';
import {
  AlbumDetailRouteParams,
  AlbumCollectionRouteParams,
  ArtistDetailRouteParams,
  ArtistTrackCollectionRouteParams,
  LibraryCollectionSelectionParams,
  LibraryDetailRoute,
  albumTarget,
  artistTarget
} from './LibraryNavigation';
import { NavigationChromeController } from './NavigationChromeController';
import { systemBarStyleController } from '../../appearance/SystemBarStyleController';
import {
  DynamicColor,
  DynamicContainerRole
} from '../../appearance/DynamicColor';

export const PLAYLIST_DETAIL_ROUTE: string = 'playlist_detail';
let playlistRouteInstanceId: number = 0;

class EmptyRouteParam {
}

export class PlaylistDetailRouteParams {
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
export struct ResponsiveNavigationRouteContent {
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink playlistStore: PlaylistStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @ObjectLink playlistsSelection: MultiSelectController;
  @ObjectLink songsSelection: MultiSelectController;
  @ObjectLink albumsSelection: MultiSelectController;
  @Prop routeId: string = NavigationRoute.PLAYLISTS;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onOpenPlaylist: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  onRequestRenamePlaylist: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  onExportPlaylist: (playlistId: number) => void = (_playlistId: number): void => {};
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onOpenTrackActions: (item: TrackListItem, anchorId: string) => void =
    (_item: TrackListItem, _anchorId: string): void => {};
  onOpenTrackDetails: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onOpenArtistTracks: (artistId: number, artistName: string) => void =
    (_artistId: number, _artistName: string): void => {};
  onOpenAlbumCollection: (scope: AlbumCollectionScope, ownerId: number, title: string) => void =
    (_scope: AlbumCollectionScope, _ownerId: number, _title: string): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onAlbumAction: (albumId: number, action: AlbumAction) => void =
    (_albumId: number, _action: AlbumAction): void => {};
  onOpenNavigationCustomization: () => void = (): void => {};
  onOpenFloatingWindowSettings: () => void = (): void => {};
  onOpenPlayerPageSettings: () => void = (): void => {};
  onOpenAbout: () => void = (): void => {};
  onOpenPrivacyPolicy: () => void = (): void => {};
  onOpenDataAndPermissions: () => void = (): void => {};
  onOpenOpenSourceLicenses: () => void = (): void => {};
  onRememberLastTabChange: (value: boolean) => void = (_value: boolean): void => {};
  onRememberSortChange: (value: boolean) => void = (_value: boolean): void => {};
  onOpenDynamicBackgroundV1: () => void = (): void => {};
  onOpenDynamicBackgroundV2: () => void = (): void => {};
  onOpenDynamicBackgroundV3: () => void = (): void => {};
  onDemoLibraryChange: (value: boolean) => void = (_value: boolean): void => {};

  build() {
    if (navigationPageKind(this.routeId) === NavigationPageKind.PLAYLISTS) {
      PlaylistsPage({
        store: this.playlistStore,
        selection: this.playlistsSelection,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller,
        onOpenPlaylist: this.onOpenPlaylist,
        onRequestRename: this.onRequestRenamePlaylist,
        onExportPlaylist: this.onExportPlaylist,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist
      })
    } else if (navigationPageKind(this.routeId) === NavigationPageKind.SONGS) {
      SongsPage({
        store: this.libraryStore,
        selection: this.songsSelection,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller,
        onPlayTrack: this.onPlayTrack,
        onOpenTrackActions: this.onOpenTrackActions,
        onOpenTrackDetails: this.onOpenTrackDetails,
        onShareTrackFile: this.onShareTrackFile,
        onNavigateTrackAction: this.onNavigateLibrary,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist
      })
    } else if (navigationPageKind(this.routeId) === NavigationPageKind.ALBUMS) {
      AlbumsPage({
        store: this.libraryStore,
        selection: this.albumsSelection,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller,
        onOpenAlbum: (item): void => {
          this.onNavigateLibrary(albumTarget({
            id: item.id,
            title: item.title,
            palettePrimary: item.palettePrimary
          }));
        },
        onAlbumAction: (item, action): void => this.onAlbumAction(item.id, action),
        onNavigateAlbumAction: this.onNavigateLibrary,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist
      })
    } else if (navigationPageKind(this.routeId) === NavigationPageKind.LIBRARY_MANAGEMENT) {
      LibraryManagementPage({
        store: this.libraryStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller
      })
    } else if (navigationPageKind(this.routeId) === NavigationPageKind.SETTINGS) {
      SettingsPage({
        settingsStore: this.settingsStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller,
        openNavigationCustomization: this.onOpenNavigationCustomization,
        openFloatingWindowSettings: this.onOpenFloatingWindowSettings,
        openPlayerPageSettings: this.onOpenPlayerPageSettings,
        openAbout: this.onOpenAbout,
        openPrivacyPolicy: this.onOpenPrivacyPolicy,
        openDataAndPermissions: this.onOpenDataAndPermissions,
        openOpenSourceLicenses: this.onOpenOpenSourceLicenses,
        onRememberLastTabChange: this.onRememberLastTabChange,
        onRememberSortChange: this.onRememberSortChange
      })
    } else if (navigationPageKind(this.routeId) === NavigationPageKind.DEBUG) {
      DebugPage({
        settingsStore: this.settingsStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller,
        openDynamicBackgroundV1: this.onOpenDynamicBackgroundV1,
        openDynamicBackgroundV2: this.onOpenDynamicBackgroundV2,
        openDynamicBackgroundV3: this.onOpenDynamicBackgroundV3,
        onDemoLibraryChange: this.onDemoLibraryChange
      })
    }
  }
}

@Component
export struct ResponsiveNavigationDestinationContent {
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink playlistStore: PlaylistStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @ObjectLink navigationChromeController: NavigationChromeController;
  @ObjectLink playlistsSelection: MultiSelectController;
  @ObjectLink songsSelection: MultiSelectController;
  @ObjectLink albumsSelection: MultiSelectController;
  @Prop name: string = '';
  param: Object = new EmptyRouteParam();
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop @Watch('onRootWidthChanged') rootWidth: number = 0;
  @Prop themePageBackground: string = '#FF000000';
  @Prop detailSelectionRevision: number = 0;
  @Prop orderedItems: Array<NavigationPageItem> = [];
  customizationScroller: Scroller = new Scroller();
  floatingWindowSettingsScroller: Scroller = new Scroller();
  playerPageSettingsScroller: Scroller = new Scroller();
  aboutScroller: Scroller = new Scroller();
  privacyPolicyScroller: Scroller = new Scroller();
  dataAndPermissionsScroller: Scroller = new Scroller();
  openSourceLicensesScroller: Scroller = new Scroller();
  routeScroller: (routeId: string) => Scroller = (_routeId: string): Scroller => new Scroller();
  onOpenPlaylist: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  onRequestRenamePlaylist: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  onExportPlaylist: (playlistId: number) => void = (_playlistId: number): void => {};
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onOpenNavigationCustomization: () => void = (): void => {};
  onOpenFloatingWindowSettings: () => void = (): void => {};
  onOpenPlayerPageSettings: () => void = (): void => {};
  onOpenAbout: () => void = (): void => {};
  onOpenPrivacyPolicy: () => void = (): void => {};
  onOpenDataAndPermissions: () => void = (): void => {};
  onOpenOpenSourceLicenses: () => void = (): void => {};
  onRememberLastTabChange: (value: boolean) => void = (_value: boolean): void => {};
  onRememberSortChange: (value: boolean) => void = (_value: boolean): void => {};
  onOpenDynamicBackgroundV1: () => void = (): void => {};
  onOpenDynamicBackgroundV2: () => void = (): void => {};
  onOpenDynamicBackgroundV3: () => void = (): void => {};
  onDemoLibraryChange: (value: boolean) => void = (_value: boolean): void => {};
  playlistDetailTitleMenu: (
    params: PlaylistDetailRouteParams,
    revision: number,
    playlist?: PlaylistSummary
  ) => HdsNavigationMenuContentOptions =
    (
      _params: PlaylistDetailRouteParams,
      _revision: number,
      _playlist?: PlaylistSummary
    ): HdsNavigationMenuContentOptions =>
      ({ maxCount: 0, value: [] });
  albumDetailTitleMenu: (
    params: AlbumDetailRouteParams,
    revision: number
  ) => HdsNavigationMenuContentOptions =
    (
      _params: AlbumDetailRouteParams,
      _revision: number
    ): HdsNavigationMenuContentOptions => ({ maxCount: 0, value: [] });
  artistDetailTitleMenu: (
    params: ArtistDetailRouteParams,
    revision: number
  ) => HdsNavigationMenuContentOptions =
    (
      _params: ArtistDetailRouteParams,
      _revision: number
    ): HdsNavigationMenuContentOptions => ({ maxCount: 0, value: [] });
  collectionTitleMenu: (
    params: LibraryCollectionSelectionParams,
    revision: number,
    totalCount: number
  ) => HdsNavigationMenuContentOptions =
    (
      _params: LibraryCollectionSelectionParams,
      _revision: number,
      _totalCount: number
    ): HdsNavigationMenuContentOptions => ({ maxCount: 0, value: [] });
  albumDetailBackground: (params: AlbumDetailRouteParams) => string =
    (_params: AlbumDetailRouteParams): string => '#FF000000';
  albumDetailContentColor: (params: AlbumDetailRouteParams) => string =
    (_params: AlbumDetailRouteParams): string => '#FFFFFFFF';
  albumDetailControlBackgroundColor: (params: AlbumDetailRouteParams) => ResourceColor | undefined =
    (_params: AlbumDetailRouteParams): ResourceColor | undefined => undefined;
  playbackChromeBackgroundColor: () => ResourceColor | undefined =
    (): ResourceColor | undefined => undefined;
  gradientMaskColor: (color: string) => string = (color: string): string => color;
  onDestinationBackPressed: () => boolean = (): boolean => false;
  onNavigationItemMove: (from: number, to: number) => void =
    (_from: number, _to: number): void => {};
  onPictureInPictureSettingsChange: () => void = (): void => {};
  onPlayerPageKeepScreenOnChange: () => void = (): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onOpenArtistTracks: (artistId: number, artistName: string) => void =
    (_artistId: number, _artistName: string): void => {};
  onOpenAlbumCollection: (scope: AlbumCollectionScope, ownerId: number, title: string) => void =
    (_scope: AlbumCollectionScope, _ownerId: number, _title: string): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenTrackActions: (
    item: TrackListItem,
    anchorId: string,
    current?: LibraryEntityIdentity
  ) => void = (_item: TrackListItem, _anchorId: string, _current?: LibraryEntityIdentity): void => {};
  onOpenTrackDetails: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  onAlbumAction: (albumId: number, action: AlbumAction) => void =
    (_albumId: number, _action: AlbumAction): void => {};

  private currentPlaylistSummary(playlistId: number): PlaylistSummary | undefined {
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

  private onRootWidthChanged(): void {
    if (AppShellLayoutSpec.supportsTitleSearchAndSelection(this.rootWidth)) {
      return;
    }
    if (this.name === PLAYLIST_DETAIL_ROUTE) {
      (this.param as PlaylistDetailRouteParams).selection.cancel();
    } else if (this.name === LibraryDetailRoute.ALBUM) {
      (this.param as AlbumDetailRouteParams).selection.cancel();
    } else if (this.name === LibraryDetailRoute.ARTIST) {
      (this.param as ArtistDetailRouteParams).selection.cancel();
    } else if (this.name === LibraryDetailRoute.ARTIST_TRACKS) {
      (this.param as ArtistTrackCollectionRouteParams).selection.cancel();
    } else if (this.name === LibraryDetailRoute.ALBUM_COLLECTION) {
      (this.param as AlbumCollectionRouteParams).selection.cancel();
    }
  }


  private activateAlbumChrome(params: AlbumDetailRouteParams): void {
    params.setPaletteChangeListener((primary: string): void => {
      this.navigationChromeController.updateAlbum(
        params.ownerRouteId,
        params.instanceId,
        DynamicColor.foreground(
          AlbumDetailColorPolicy.background(primary),
          DynamicContainerRole.PRIMARY
        )
      );
    });
    this.navigationChromeController.registerAlbum(
      params.ownerRouteId,
      params.instanceId,
      this.albumDetailContentColor(params)
    );
  }

  private deactivateAlbumChrome(params: AlbumDetailRouteParams): void {
    params.setPaletteChangeListener(undefined);
    this.navigationChromeController.unregisterAlbum(params.ownerRouteId, params.instanceId);
  }

  build() {
    if (this.name === PLAYLIST_DETAIL_ROUTE) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          PlaylistDetailPage({
            store: this.playlistStore,
            libraryStore: this.libraryStore,
            selection: (this.param as PlaylistDetailRouteParams).selection,
            playlistId: (this.param as PlaylistDetailRouteParams).playlistId,
            rootWidth: this.rootWidth,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: (this.param as PlaylistDetailRouteParams).scroller,
            onResolveArtwork: (relativePath: string): string =>
              this.libraryStore.resolveArtworkPath(relativePath),
            onRequestAddToPlaylist: this.onRequestAddToPlaylist,
            onNavigateLibrary: this.onNavigateLibrary,
            onOpenTrackDetails: this.onOpenTrackDetails,
            onShareTrackFile: this.onShareTrackFile
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        this.currentPlaylistSummary((this.param as PlaylistDetailRouteParams).playlistId)?.name ??
          (this.param as PlaylistDetailRouteParams).initialTitle,
        this.playlistDetailTitleMenu(
          this.param as PlaylistDetailRouteParams,
          this.detailSelectionRevision,
          this.currentPlaylistSummary((this.param as PlaylistDetailRouteParams).playlistId)
        ),
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([(this.param as PlaylistDetailRouteParams).scroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === LibraryDetailRoute.ALBUM) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          AlbumDetailPage({
            store: this.libraryStore,
            state: (this.param as AlbumDetailRouteParams).state,
            selection: (this.param as AlbumDetailRouteParams).selection,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            rootWidth: this.rootWidth,
            currentIdentity: (this.param as AlbumDetailRouteParams).identity(),
            themeBackground: this.albumDetailBackground(this.param as AlbumDetailRouteParams),
            scroller: (this.param as AlbumDetailRouteParams).scroller,
            actionAnchorPrefix: (this.param as AlbumDetailRouteParams).anchorPrefix(),
            onOpenArtist: (artist): void => this.onNavigateLibrary(artistTarget(artist)),
            onOpenAlbum: (album): void => this.onNavigateLibrary(albumTarget({
              id: album.id,
              title: album.title,
              palettePrimary: album.palettePrimary
            })),
            onOpenAllRelatedAlbums: (): void => this.onOpenAlbumCollection(
              AlbumCollectionScope.RELATED,
              (this.param as AlbumDetailRouteParams).albumId,
              `${(this.param as AlbumDetailRouteParams).title}的相关专辑`
            ),
            onAlbumAction: (album, action): void => this.onAlbumAction(album.id, action),
            onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
              this.onOpenTrackActions(item, anchorId, (this.param as AlbumDetailRouteParams).identity()),
            onOpenTrackDetails: this.onOpenTrackDetails,
            onShareTrackFile: this.onShareTrackFile,
            onNavigateTrackAction: this.onNavigateLibrary,
            onRequestAddToPlaylist: this.onRequestAddToPlaylist
          })
          PageBottomGradient({
            maskColor: this.albumDetailBackground(this.param as AlbumDetailRouteParams)
          })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.albumDetailBackground(this.param as AlbumDetailRouteParams))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryBackOnlyTitleBar(
        this.albumDetailTitleMenu(
          this.param as AlbumDetailRouteParams,
          this.detailSelectionRevision
        ),
        {
          backgroundColor: this.gradientMaskColor(
            this.albumDetailBackground(this.param as AlbumDetailRouteParams)
          ),
          contentColor: this.albumDetailContentColor(this.param as AlbumDetailRouteParams),
          controlBackgroundColor:
            this.albumDetailControlBackgroundColor(this.param as AlbumDetailRouteParams)
        }
      ))
      .onShown((): void => this.activateAlbumChrome(this.param as AlbumDetailRouteParams))
      .onHidden((): void => this.deactivateAlbumChrome(this.param as AlbumDetailRouteParams))
      .bindToScrollable([(this.param as AlbumDetailRouteParams).scroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === LibraryDetailRoute.ARTIST) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          ArtistDetailPage({
            store: this.libraryStore,
            state: (this.param as ArtistDetailRouteParams).state,
            selection: (this.param as ArtistDetailRouteParams).selection,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            rootWidth: this.rootWidth,
            currentIdentity: (this.param as ArtistDetailRouteParams).identity(),
            scroller: (this.param as ArtistDetailRouteParams).scroller,
            actionAnchorPrefix: (this.param as ArtistDetailRouteParams).anchorPrefix(),
            onOpenAlbum: (album): void => this.onNavigateLibrary(albumTarget({
              id: album.id,
              title: album.title,
              palettePrimary: album.palettePrimary
            })),
            onOpenAllTracks: (): void => this.onOpenArtistTracks(
              (this.param as ArtistDetailRouteParams).artistId,
              (this.param as ArtistDetailRouteParams).name
            ),
            onOpenAllAlbums: (): void => this.onOpenAlbumCollection(
              AlbumCollectionScope.ARTIST,
              (this.param as ArtistDetailRouteParams).artistId,
              `${(this.param as ArtistDetailRouteParams).name}的专辑`
            ),
            onAlbumAction: (album, action): void => this.onAlbumAction(album.id, action),
            onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
              this.onOpenTrackActions(item, anchorId, (this.param as ArtistDetailRouteParams).identity()),
            onOpenTrackDetails: this.onOpenTrackDetails,
            onShareTrackFile: this.onShareTrackFile,
            onNavigateTrackAction: this.onNavigateLibrary,
            onRequestAddToPlaylist: this.onRequestAddToPlaylist
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        (this.param as ArtistDetailRouteParams).name,
        this.artistDetailTitleMenu(
          this.param as ArtistDetailRouteParams,
          this.detailSelectionRevision
        ),
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([(this.param as ArtistDetailRouteParams).scroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === LibraryDetailRoute.ARTIST_TRACKS) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          ArtistTrackCollectionPage({
            store: this.libraryStore,
            state: (this.param as ArtistTrackCollectionRouteParams).state,
            selection: (this.param as ArtistTrackCollectionRouteParams).selection,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: (this.param as ArtistTrackCollectionRouteParams).scroller,
            actionAnchorPrefix: (this.param as ArtistTrackCollectionRouteParams).anchorPrefix(),
            onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
              this.onOpenTrackActions(item, anchorId),
            onOpenTrackDetails: this.onOpenTrackDetails,
            onShareTrackFile: this.onShareTrackFile,
            onNavigateTrackAction: this.onNavigateLibrary,
            onRequestAddToPlaylist: this.onRequestAddToPlaylist
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }.width('100%').height('100%')
      }
      .width('100%').height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        (this.param as ArtistTrackCollectionRouteParams).title,
        this.collectionTitleMenu(
          this.param as ArtistTrackCollectionRouteParams,
          this.detailSelectionRevision,
          (this.param as ArtistTrackCollectionRouteParams).state.totalCount
        ),
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([(this.param as ArtistTrackCollectionRouteParams).scroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === LibraryDetailRoute.ALBUM_COLLECTION) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          AlbumCollectionPage({
            store: this.libraryStore,
            state: (this.param as AlbumCollectionRouteParams).state,
            selection: (this.param as AlbumCollectionRouteParams).selection,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: (this.param as AlbumCollectionRouteParams).scroller,
            onOpenAlbum: (album): void => this.onNavigateLibrary(albumTarget({ id: album.id,
              title: album.title, palettePrimary: album.palettePrimary })),
            onAlbumAction: (album, action): void => this.onAlbumAction(album.id, action),
            onNavigate: this.onNavigateLibrary,
            onRequestAddToPlaylist: this.onRequestAddToPlaylist
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }.width('100%').height('100%')
      }
      .width('100%').height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        (this.param as AlbumCollectionRouteParams).title,
        this.collectionTitleMenu(
          this.param as AlbumCollectionRouteParams,
          this.detailSelectionRevision,
          (this.param as AlbumCollectionRouteParams).state.totalCount
        ),
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([(this.param as AlbumCollectionRouteParams).scroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.NAVIGATION_CUSTOMIZATION) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          NavigationCustomizationPage({
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            items: this.orderedItems,
            scroller: this.customizationScroller,
            onMove: this.onNavigationItemMove
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '自定义页面',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.customizationScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.FLOATING_WINDOW_SETTINGS) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          FloatingWindowSettingsPage({
            settingsStore: this.settingsStore,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.floatingWindowSettingsScroller,
            onSettingsChange: this.onPictureInPictureSettingsChange
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '浮窗',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.floatingWindowSettingsScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.PLAYER_PAGE_SETTINGS) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          PlayerPageSettingsPage({
            settingsStore: this.settingsStore,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.playerPageSettingsScroller,
            onKeepScreenOnChange: this.onPlayerPageKeepScreenOnChange
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '播放页面',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.playerPageSettingsScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.DYNAMIC_BACKGROUND_DEBUG) {
      HdsNavDestination() {
        DynamicBackgroundDebugPage({
          playerStore: playbackRuntime.playerStore,
          bottomInset: this.bottomInset
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FF000000')
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '动态背景',
        undefined,
        '#FF000000',
        {
          backgroundColor: '#FF000000',
          contentColor: '#FFFFFFFF',
          controlBackgroundColor: '#24FFFFFF'
        }
      ))
      .onShown((): void => {
        systemBarStyleController.submitContentColor(
          NavigationRoute.DYNAMIC_BACKGROUND_DEBUG,
          '#FFFFFFFF'
        );
      })
      .onHidden((): void => {
        systemBarStyleController.removeContentColor(NavigationRoute.DYNAMIC_BACKGROUND_DEBUG);
      })
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.DYNAMIC_BACKGROUND_V2_DEBUG) {
      HdsNavDestination() {
        DynamicBackgroundV2DebugPage({
          playerStore: playbackRuntime.playerStore,
          bottomInset: this.bottomInset
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FF000000')
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '动态背景 v2',
        undefined,
        '#FF000000',
        {
          backgroundColor: '#FF000000',
          contentColor: '#FFFFFFFF',
          controlBackgroundColor: '#24FFFFFF'
        }
      ))
      .onShown((): void => {
        systemBarStyleController.submitContentColor(
          NavigationRoute.DYNAMIC_BACKGROUND_V2_DEBUG,
          '#FFFFFFFF'
        );
      })
      .onHidden((): void => {
        systemBarStyleController.removeContentColor(NavigationRoute.DYNAMIC_BACKGROUND_V2_DEBUG);
      })
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.DYNAMIC_BACKGROUND_V3_DEBUG) {
      HdsNavDestination() {
        DynamicBackgroundV3DebugPage({
          playerStore: playbackRuntime.playerStore,
          bottomInset: this.bottomInset
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '动态背景 v3',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.ABOUT) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          AboutPage({
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.aboutScroller
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '关于 wPlayer',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.aboutScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.PRIVACY_POLICY) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          PrivacyPolicyPage({
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.privacyPolicyScroller
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '隐私政策',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.privacyPolicyScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.DATA_AND_PERMISSIONS) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          DataAndPermissionsPage({
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.dataAndPermissionsScroller
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '数据与权限',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.dataAndPermissionsScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else if (this.name === NavigationRoute.OPEN_SOURCE_LICENSES) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          OpenSourceLicensesPage({
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.openSourceLicensesScroller
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        '开源软件许可',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.openSourceLicensesScroller])
      .onBackPressed(this.onDestinationBackPressed)
    } else {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Bottom }) {
          ResponsiveNavigationRouteContent({
            libraryStore: this.libraryStore,
            playlistStore: this.playlistStore,
            settingsStore: this.settingsStore,
            playlistsSelection: this.playlistsSelection,
            songsSelection: this.songsSelection,
            albumsSelection: this.albumsSelection,
            routeId: this.name,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            scroller: this.routeScroller(this.name),
            onOpenPlaylist: this.onOpenPlaylist,
            onRequestRenamePlaylist: this.onRequestRenamePlaylist,
            onExportPlaylist: this.onExportPlaylist,
            onPlayTrack: this.onPlayTrack,
            onOpenTrackActions: (item: TrackListItem, anchorId: string): void =>
              this.onOpenTrackActions(item, anchorId),
            onOpenTrackDetails: this.onOpenTrackDetails,
            onShareTrackFile: this.onShareTrackFile,
            onNavigateLibrary: this.onNavigateLibrary,
            onOpenArtistTracks: this.onOpenArtistTracks,
            onOpenAlbumCollection: this.onOpenAlbumCollection,
            onRequestAddToPlaylist: this.onRequestAddToPlaylist,
            onAlbumAction: this.onAlbumAction,
            onOpenNavigationCustomization: this.onOpenNavigationCustomization,
            onOpenFloatingWindowSettings: this.onOpenFloatingWindowSettings,
            onOpenPlayerPageSettings: this.onOpenPlayerPageSettings,
            onOpenAbout: this.onOpenAbout,
            onOpenPrivacyPolicy: this.onOpenPrivacyPolicy,
            onOpenDataAndPermissions: this.onOpenDataAndPermissions,
            onOpenOpenSourceLicenses: this.onOpenOpenSourceLicenses,
            onRememberLastTabChange: this.onRememberLastTabChange,
            onRememberSortChange: this.onRememberSortChange,
            onOpenDynamicBackgroundV1: this.onOpenDynamicBackgroundV1,
            onOpenDynamicBackgroundV2: this.onOpenDynamicBackgroundV2,
            onOpenDynamicBackgroundV3: this.onOpenDynamicBackgroundV3,
            onDemoLibraryChange: this.onDemoLibraryChange
          })
          PageBottomGradient({ maskColor: this.themePageBackground })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themePageBackground)
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(AppNavigationStyle.secondaryTitleBar(
        navigationItem(this.name)?.label ?? '',
        undefined,
        this.playbackChromeBackgroundColor()
      ))
      .bindToScrollable([this.routeScroller(this.name)])
      .onBackPressed(this.onDestinationBackPressed)
    }
  }

}
