import { ComponentContent, window } from '@kit.ArkUI';
import { HdsTabsController } from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import {
  PlayerFrame,
  PlayerMorphPhase,
  PlayerMotionSpec,
  PlayerPoint
} from '../components/player/PlayerMotion';
import { LibraryStore } from '../library/store/LibraryStore';
import {
  LibraryNavigationTarget,
  PlaylistSummary,
  TrackListItem
} from '../library/model/LibraryModels';
import { PlaylistStore } from '../playlist/store/PlaylistStore';
import { playbackRuntime } from '../playback/PlaybackRuntime';
import { PlayerStore } from '../playback/model/PlaybackModels';
import { SettingsRepository } from '../settings/SettingsRepository';
import { AppSettingsStore, appSettings } from '../settings/AppSettingsStore';
import { WindowAvoidAreaController } from '../components/layout/WindowAvoidAreaController';
import {
  MiniPlayerHost,
  MiniPlayerHostParams
} from '../components/player/MiniPlayerSurface';
import {
  IndexPlaylistSheet,
  IndexPlaylistSheetKind
} from '../components/library/IndexPlaylistSheet';
import { IndexPlaylistController } from '../components/library/IndexPlaylistController';
import { PlayerGeometryProbe } from '../components/player/FullPlayerGeometryProbe';
import { PlayerMorphController } from '../components/player/PlayerMorphController';
import { PlayerMorphOverlay } from '../components/player/PlayerMorphOverlay';
import { PlayerDynamicBackgroundLayer } from '../components/player/PlayerDynamicBackground';
import {
  IndexNavigationController
} from '../components/navigation/IndexNavigationController';
import {
  NavigationChromeController
} from '../components/navigation/NavigationChromeController';
import { ResponsiveNavigationShell } from '../components/navigation/ResponsiveNavigationShell';
import { TrackDetailSheetBridge } from '../components/navigation/TrackDetailSheetBridge';
import { TrackActionMenuPresenter } from '../components/library/TrackActionMenu';
import {
  AppAppearanceListener,
  AppAppearancePalette,
  appAppearanceController
} from '../appearance/AppAppearance';
import { PaletteMotionSpec } from '../appearance/PaletteMotionSpec';
import { DynamicColor } from '../appearance/DynamicColor';
import { LibraryMaintenanceSheet } from '../components/library/LibraryMaintenanceSheet';
import {
  LibraryMaintenanceStatus
} from '../library/data/MusicRepositoryTypes';
import { NavigationRoute } from '../components/navigation/MoreNavigation';

@Entry
@Component
struct Index {
  private readonly compactTabsController: HdsTabsController = new HdsTabsController();
  private readonly condensedCompactTabsController: HdsTabsController = new HdsTabsController();
  private readonly expandedTabsController: HdsTabsController = new HdsTabsController();
  private readonly trackDetailSheetBridge: TrackDetailSheetBridge = new TrackDetailSheetBridge();
  private compactMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  private condensedCompactMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  private wideMiniPlayerContent?: ComponentContent<MiniPlayerHostParams>;
  @State statusBarAvoidHeight: number = 0;
  @State navigationAvoidHeight: number = 0;
  @State appearancePalette: AppAppearancePalette = AppAppearancePalette.fallback();
  @State navigationController: IndexNavigationController = new IndexNavigationController();
  @State navigationChromeController: NavigationChromeController = new NavigationChromeController();
  @State playerMorphController: PlayerMorphController =
    new PlayerMorphController(
      playbackRuntime.playerStore,
      this.compactTabsController,
      this.condensedCompactTabsController
    );
  @State libraryStore: LibraryStore = new LibraryStore(playbackRuntime.repository, playbackRuntime);
  @State playlistStore: PlaylistStore = new PlaylistStore(playbackRuntime.repository);
  @State playlistController: IndexPlaylistController = new IndexPlaylistController(this.playlistStore);
  @State playerStore: PlayerStore = playbackRuntime.playerStore;
  // The invisible geometry probe must not react to playback position or lyric updates.
  @State geometryPlayerStore: PlayerStore = new PlayerStore();
  @State settingsStore: AppSettingsStore = appSettings;
  @State playlistSheetVisible: boolean = false;
  @State maintenanceSheetVisible: boolean = false;
  @State maintenanceStatus: LibraryMaintenanceStatus = { items: [], total: 0 };
  @State animatedThemePrimary: string = this.playerStore.themePrimary();
  @State animatedThemeOnPrimary: string = this.playerStore.themeOnPrimary();
  private readonly appearanceListener: AppAppearanceListener = (_epoch: number): void => {
    this.refreshAppearance();
  };
  private readonly avoidAreaController: WindowAvoidAreaController =
    new WindowAvoidAreaController((type: window.AvoidAreaType, area: window.AvoidArea): void => {
      this.applyAvoidArea(type, area);
    });

  private settingsRepository?: SettingsRepository;

  aboutToAppear(): void {
    this.navigationController.bindChromeController(this.navigationChromeController);
    this.navigationChromeController.attach();
    this.playerMorphController.attach(this.getUIContext());
    const miniPlayerParams = new MiniPlayerHostParams(
      this.playerStore,
      this.playerMorphController.miniPlayerBinding,
      (): void => this.playerMorphController.showFullPlayer(),
      (localX: number): void => this.playerMorphController.beginMiniPlayerTouch(localX),
      (): void => this.playerMorphController.beginMiniPlayerGesture(),
      (event: GestureEvent): void => this.playerMorphController.updateMiniPlayerGesture(event),
      (): void => this.playerMorphController.finishMiniPlayerGesture()
    );
    this.compactMiniPlayerContent = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(MiniPlayerHost),
      miniPlayerParams
    );
    this.condensedCompactMiniPlayerContent = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(MiniPlayerHost),
      miniPlayerParams
    );
    this.wideMiniPlayerContent = new ComponentContent(
      this.getUIContext(),
      wrapBuilder(MiniPlayerHost),
      miniPlayerParams
    );
    playbackRuntime.setPaletteChangeListener((_primary: string, _secondary: string, _accent: string): void => {
      this.animatePlayerTheme();
      this.syncSystemBarContentColor();
    });
    appAppearanceController.addListener(this.appearanceListener);
    this.refreshAppearance();
    this.navigationController.initializeTitleContents(this.getUIContext());
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      const abilityContext = context as common.UIAbilityContext;
      this.avoidAreaController.start(abilityContext);
      this.playlistController.bindVisibility((visible: boolean): void => {
        this.playlistSheetVisible = visible;
      });
      this.playlistController.bindSuccessMessage((message: string): void => {
        this.showPlaylistSuccessDialog(message);
      });
      try {
        this.settingsRepository = new SettingsRepository(abilityContext);
        this.settingsStore.initialize(this.settingsRepository);
        playbackRuntime.bindPictureInPictureContext(this.getUIContext());
        this.playlistController.bindSettings(this.settingsRepository);
        this.navigationController.bindSettings(this.settingsRepository, this.settingsStore);
      } catch (error) {
        const businessError = error as BusinessError;
        console.warn(`Unable to initialize settings: ${businessError.code}, ${businessError.message}`);
      }
      this.initializeApplicationData(abilityContext, this.settingsRepository);
    }
  }

  private async initializeApplicationData(context: common.UIAbilityContext,
    settings?: SettingsRepository): Promise<void> {
    try {
      await playbackRuntime.repository.initialize(context);
      await Promise.all([
        this.libraryStore.initialize(context, settings),
        this.playlistStore.initialize(),
        playbackRuntime.initialize(context)
      ]);
      const maintenanceStatus = await this.libraryStore.checkLibraryMaintenance();
      if (maintenanceStatus.total > 0) {
        this.maintenanceStatus = maintenanceStatus;
        this.maintenanceSheetVisible = true;
      }
    } catch (error) {
      console.warn(`Unable to initialize application data: ${error instanceof Error ? error.message : error}`);
    }
  }

  aboutToDisappear(): void {
    this.playerMorphController.dispose();
    this.compactMiniPlayerContent?.dispose();
    this.compactMiniPlayerContent = undefined;
    this.condensedCompactMiniPlayerContent?.dispose();
    this.condensedCompactMiniPlayerContent = undefined;
    this.wideMiniPlayerContent?.dispose();
    this.wideMiniPlayerContent = undefined;
    this.playlistController.dispose();
    this.libraryStore.dispose();
    this.playlistStore.dispose();
    playbackRuntime.unbindPictureInPictureContext();
    playbackRuntime.setPaletteChangeListener(undefined);
    this.navigationChromeController.dispose();
    appAppearanceController.removeListener(this.appearanceListener);
    this.avoidAreaController.stop();
    this.navigationController.dispose();
  }

  private animatePlayerTheme(): void {
    const targetColor = this.playerStore.themePrimary();
    const targetContentColor = this.playerStore.themeOnPrimary();
    if (this.animatedThemePrimary === targetColor &&
      this.animatedThemeOnPrimary === targetContentColor) {
      return;
    }
    this.getUIContext().animateTo({
      duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
      curve: Curve.EaseInOut
    }, () => {
      this.animatedThemePrimary = targetColor;
      this.animatedThemeOnPrimary = targetContentColor;
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
    this.syncSystemBarContentColor();
  }

  private syncSystemBarContentColor(): void {
    this.playerMorphController.syncSystemBarContentColor();
  }

  private applyAvoidArea(type: window.AvoidAreaType, area: window.AvoidArea): void {
    const uiContext = this.getUIContext();
    if (type === window.AvoidAreaType.TYPE_SYSTEM) {
      this.statusBarAvoidHeight = uiContext.px2vp(area.topRect.height);
    } else if (type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.navigationAvoidHeight = uiContext.px2vp(area.bottomRect.height);
    }
  }

  private usesWideLayout(width: number = this.playerMorphController.rootFrame.width): boolean {
    return this.playerMorphController.usesWideLayout(width);
  }

  private fullPlayerPaneCount(width: number = this.playerMorphController.rootFrame.width,
    height: number = this.playerMorphController.rootFrame.height): number {
    return this.playerMorphController.fullPlayerPaneCount(width, height);
  }

  private navigateLibrary(target: LibraryNavigationTarget): void {
    this.navigationController.navigateLibrary(target, this.usesWideLayout());
    if (this.isMorphActive()) {
      this.playerMorphController.hideFullPlayer();
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

  private startLibraryMaintenance(): void {
    this.maintenanceSheetVisible = false;
    const routeId = NavigationRoute.LIBRARY_MANAGEMENT;
    if (!this.usesWideLayout() &&
      this.navigationController.moreItems().some((item): boolean => item.routeId === routeId)) {
      this.navigationController.morePathStack.clear(false);
      this.navigationController.openMoreDestination(routeId);
    } else {
      this.navigationController.selectRoute(routeId);
    }
    this.libraryStore.checkMusicFiles().catch((error: Object): void => {
      console.warn(`Unable to start library check: ${error instanceof Error ? error.message : error}`);
    });
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

  private playbackChromeBackground(): string {
    if (!this.settingsStore.followPlaybackTheme ||
      this.animatedThemePrimary.length === 0 || !this.playerStore.hasCurrentTrack()) {
      return '';
    }
    return this.animatedPageBackground();
  }

  private playerThemeBackground(): string {
    return this.animatedThemePrimary.length > 0 ?
      this.animatedThemePrimary : this.playerStore.themePrimary();
  }

  private playerContentColor(): string {
    return this.animatedThemeOnPrimary.length > 0 ?
      this.animatedThemeOnPrimary : this.playerStore.themeOnPrimary();
  }

  private morphCollapsedSurfaceColor(): string {
    return this.appearancePalette.windowBackground.toUpperCase() === '#FF000000' ?
      PlayerMotionSpec.COLLAPSED_SURFACE_DARK : PlayerMotionSpec.COLLAPSED_SURFACE_LIGHT;
  }

  onBackPress(): boolean {
    return this.playerMorphController.handleBackPress();
  }

  private isMorphActive(): boolean {
    return this.playerMorphController.isMorphActive();
  }

  @Builder
  private PlaylistSheet() {
    IndexPlaylistSheet({
      store: this.playlistStore,
      kind: this.playlistController.kind,
      createName: this.playlistController.createName,
      renameName: this.playlistController.renameName,
      pickerTrackIds: this.playlistController.pickerTrackIds,
      recentPlaylistTargetIds: this.playlistController.recentPlaylistTargetIds,
      onCreateNameChange: (value: string): void => {
        this.playlistController.createName = value;
      },
      onRenameNameChange: (value: string): void => {
        this.playlistController.renameName = value;
      },
      onSaveCreate: (): void => this.playlistController.saveNewPlaylist(),
      onSaveRename: (): void => this.playlistController.saveRename(),
      onAddedToPlaylist: (playlistId: number, message: string): void => {
        this.playlistController.recordRecentPlaylistTarget(playlistId);
        this.playlistController.showAddedToPlaylistMessage(message);
      },
      onClose: (): void => this.playlistController.close()
    })
  }

  @Builder
  private MaintenanceSheet() {
    LibraryMaintenanceSheet({
      status: this.maintenanceStatus,
      onStart: (): void => this.startLibraryMaintenance(),
      onLater: (): void => {
        this.maintenanceSheetVisible = false;
      }
    })
  }

  @Builder
  private SheetHosts() {
    Stack()
      .width(1)
      .height(1)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .bindSheet($$this.maintenanceSheetVisible, this.MaintenanceSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: true
      })
  }

  @Builder
  private NavigationShell() {
    ResponsiveNavigationShell({
      libraryStore: this.libraryStore,
      playlistStore: this.playlistStore,
      playerStore: this.playerStore,
      settingsStore: this.settingsStore,
      miniPlayerBinding: this.playerMorphController.miniPlayerBinding,
      navigationChromeController: this.navigationChromeController,
      compactMiniPlayerContent: this.compactMiniPlayerContent,
      condensedCompactMiniPlayerContent: this.condensedCompactMiniPlayerContent,
      wideMiniPlayerContent: this.wideMiniPlayerContent,
      topInset: this.statusBarAvoidHeight,
      bottomInset: this.navigationAvoidHeight,
      rootWidth: this.playerMorphController.rootFrame.width,
      rootHeight: this.playerMorphController.rootFrame.height,
      navigationOrder: this.navigationController.navigationOrder,
      selectedRouteId: this.navigationController.selectedRouteId,
      appearancePalette: this.appearancePalette,
      themePageBackground: this.animatedPageBackground(),
      playbackChromeBackground: this.playbackChromeBackground(),
      onShowFullPlayer: (): void => this.playerMorphController.showFullPlayer(),
      onMiniPlayerGestureStart: (): void => this.playerMorphController.beginMiniPlayerGesture(),
      onMiniPlayerGestureUpdate: (event: GestureEvent): void =>
        this.playerMorphController.updateMiniPlayerGesture(event),
      onMiniPlayerGestureFinish: (): void => this.playerMorphController.finishMiniPlayerGesture(),
      compactTabsController: this.compactTabsController,
      condensedCompactTabsController: this.condensedCompactTabsController,
      expandedTabsController: this.expandedTabsController,
      rootTitleContents: this.navigationController.rootTitleContents,
      moreTitleContent: this.navigationController.moreTitleContent,
      rootPathStacks: this.navigationController.rootPathStacks,
      rootScrollers: this.navigationController.rootScrollers,
      morePathStack: this.navigationController.morePathStack,
      moreScroller: this.navigationController.moreScroller,
      customizationScroller: this.navigationController.customizationScroller,
      trackDetailSheetBridge: this.trackDetailSheetBridge,
      onCompactTabChange: (index: number): void =>
        this.navigationController.handleCompactTabChange(index),
      onCompactTabClick: (index: number): void =>
        this.navigationController.handleCompactTabBarClick(index),
      onCondensedOutsideTouch: (): void =>
        this.playerMorphController.collapseCondensedMiniBar(),
      onExpandedTabChange: (index: number): void =>
        this.navigationController.handleExpandedTabChange(index),
      onExpandedTabClick: (index: number): void =>
        this.navigationController.handleExpandedTabBarClick(index),
      onOpenMoreDestination: (routeId: string): void =>
        this.navigationController.openMoreDestination(routeId),
      onOpenNavigationCustomization: (): void =>
        this.navigationController.openNavigationCustomization(this.usesWideLayout()),
      onRememberLastTabChange: (value: boolean): void =>
        this.navigationController.setRememberLastTab(value),
      onRememberSortChange: (value: boolean): void => this.libraryStore.setRememberSort(value),
      onPictureInPictureSettingsChange: (): void =>
        playbackRuntime.refreshPictureInPicturePreferences(),
      onDemoLibraryChange: (value: boolean): void => {
        this.setDemoLibraryEnabled(value);
      },
      onNavigationItemMove: (from: number, to: number): void =>
        this.navigationController.moveNavigationItem(from, to),
      onRequestCreatePlaylist: (): void => this.playlistController.openCreator(),
      onRequestRenamePlaylist: (playlist: PlaylistSummary): void =>
        this.playlistController.openRenamer(playlist),
      onRequestAddToPlaylist: (items: Array<TrackListItem>): void =>
        this.playlistController.requestAddToPlaylist(items),
      onNavigateLibrary: (target: LibraryNavigationTarget): void => this.navigateLibrary(target)
    })
  }

  private async setDemoLibraryEnabled(enabled: boolean): Promise<void> {
    if (this.settingsStore.demoLibraryEnabled === enabled) {
      return;
    }
    try {
      await playbackRuntime.setDemoLibraryEnabled(enabled);
      this.settingsStore.setDemoLibraryEnabled(enabled);
      await Promise.all([
        this.libraryStore.refresh(),
        this.libraryStore.loadUnavailableTracks(),
        this.playlistStore.refresh()
      ]);
    } catch (error) {
      console.warn(`Unable to switch demo library: ${error instanceof Error ? error.message : error}`);
    }
  }

  @Builder
  private FullPlayerDynamicBackground() {
    PlayerDynamicBackgroundLayer({
      controller: this.playerMorphController,
      playerStore: this.playerStore,
      binding: this.playerMorphController.dynamicBackgroundBinding,
      collapsedSurfaceColor: this.morphCollapsedSurfaceColor(),
      playerThemeBackground: this.playerThemeBackground()
    })
  }

  @Builder
  private FullPlayerOverlay() {
    PlayerMorphOverlay({
      controller: this.playerMorphController,
      playerStore: this.playerStore,
      settingsStore: this.settingsStore,
      libraryStore: this.libraryStore,
      topInset: this.statusBarAvoidHeight,
      bottomInset: this.navigationAvoidHeight,
      primaryContentColor: this.playerContentColor(),
      onRequestAddToPlaylist: (trackIds: Array<number>): void =>
        this.playlistController.requestTrackIdsAddToPlaylist(trackIds),
      onOpenTrackActions: (trackId: number, anchorId: string): void =>
        this.openFullPlayerTrackActions(trackId, anchorId),
      onOpenTrackDetails: (track: TrackListItem): void => {
        this.playerMorphController.hideFullPlayer();
        this.trackDetailSheetBridge.open(track);
      },
      onNavigateLibrary: (target: LibraryNavigationTarget): void => this.navigateLibrary(target)
    })
  }

  @Builder
  private FullPlayerGeometryProbe() {
    PlayerGeometryProbe({
      playerStore: this.geometryPlayerStore,
      settingsStore: this.settingsStore,
      libraryStore: this.libraryStore,
      topInset: this.statusBarAvoidHeight,
      bottomInset: this.navigationAvoidHeight,
      rootFrame: this.playerMorphController.rootFrame,
      paneCount: this.fullPlayerPaneCount(),
      primaryContentColor: this.playerContentColor(),
      previousArtworkTarget: this.playerMorphController.artworkTarget,
      previousCenteredArtworkTarget: this.playerMorphController.centeredArtworkTarget,
      onArtworkTarget: (target: PlayerPoint): void => {
        this.playerMorphController.artworkTarget = target;
      },
      onCenteredArtworkTarget: (target: PlayerPoint): void => {
        this.playerMorphController.centeredArtworkTarget = target;
      },
      onPlaybackButtonTarget: (target: PlayerFrame): void => {
        this.playerMorphController.playbackButtonTarget = target;
      }
    })
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

      this.SheetHosts()

      this.FullPlayerDynamicBackground()

      // Read the observable phase directly so ArkUI reliably removes the
      // full-screen hit-test layer after the closing handoff completes.
      if (this.playerMorphController.playerMorphPhase !== PlayerMorphPhase.IDLE) {
        this.FullPlayerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .id('player_page_root')
    .backgroundColor(this.animatedPageBackground())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.playlistSheetVisible, this.PlaylistSheet(), {
      height: this.playlistController.sheetHeight(),
      dragBar: true,
      showClose: this.playlistController.kind === IndexPlaylistSheetKind.PICKER
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const layoutChange = this.playerMorphController.updateRootFrame(newValue);
      if (layoutChange.previousWideLayout !== layoutChange.nextWideLayout) {
        this.navigationController.reconcileResponsiveNavigation(
          layoutChange.previousWideLayout,
          layoutChange.nextWideLayout
        );
      }
    })
  }
}
