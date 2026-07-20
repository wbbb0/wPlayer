import { ComponentContent } from '@kit.ArkUI';
import { AppAppearancePalette } from '../../appearance/AppAppearance';
import {
  LibraryEntityKind,
  LibraryNavigationTarget
} from '../../library/model/LibraryModels';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { SettingsRepository } from '../../settings/SettingsRepository';
import {
  AppPrimaryTitleContent,
  AppPrimaryTitleParams
} from './AppPrimaryTitleContent';
import {
  AlbumDetailRouteParams,
  ArtistDetailRouteParams,
  LibraryDetailRoute
} from './LibraryNavigation';
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
} from './MoreNavigation';

const MORE_TAB_INDEX: number = PRIMARY_NAVIGATION_COUNT;

@Observed
export class IndexNavigationController {
  navigationOrder: Array<string> = DEFAULT_NAVIGATION_ORDER;
  selectedRouteId: string = NavigationRoute.PLAYLISTS;
  readonly rootTitleContents: Array<ComponentContent<AppPrimaryTitleParams> | undefined> =
    new Array<ComponentContent<AppPrimaryTitleParams> | undefined>(ALL_ROOT_NAVIGATION_ITEMS.length);
  moreTitleContent?: ComponentContent<AppPrimaryTitleParams>;
  readonly rootPathStacks: Array<NavPathStack> = ALL_ROOT_NAVIGATION_ITEMS.map(() => new NavPathStack());
  readonly rootScrollers: Array<Scroller> = ALL_ROOT_NAVIGATION_ITEMS.map(() => new Scroller());
  readonly morePathStack: NavPathStack = new NavPathStack();
  readonly moreScroller: Scroller = new Scroller();
  readonly customizationScroller: Scroller = new Scroller();
  private compactTabIndexBeforeSelection: number = 0;
  private expandedTabIndexBeforeSelection: number = 0;
  private settingsRepository?: SettingsRepository;
  private settingsStore?: AppSettingsStore;

  initializeTitleContents(uiContext: UIContext, palette: AppAppearancePalette): void {
    for (let index = 0; index < ALL_ROOT_NAVIGATION_ITEMS.length; index += 1) {
      if (this.rootTitleContents[index] === undefined) {
        this.rootTitleContents[index] = new ComponentContent(
          uiContext,
          wrapBuilder(AppPrimaryTitleContent),
          new AppPrimaryTitleParams(ALL_ROOT_NAVIGATION_ITEMS[index].label, palette.titlePrimary)
        );
      }
    }
    if (this.moreTitleContent === undefined) {
      this.moreTitleContent = new ComponentContent(
        uiContext,
        wrapBuilder(AppPrimaryTitleContent),
        new AppPrimaryTitleParams('更多', palette.titlePrimary)
      );
    }
  }

  updateTitleColors(palette: AppAppearancePalette): void {
    for (let index = 0; index < this.rootTitleContents.length; index += 1) {
      this.rootTitleContents[index]?.update(
        new AppPrimaryTitleParams(ALL_ROOT_NAVIGATION_ITEMS[index].label, palette.titlePrimary)
      );
    }
    this.moreTitleContent?.update(new AppPrimaryTitleParams('更多', palette.titlePrimary));
  }

  dispose(): void {
    for (let index = 0; index < this.rootTitleContents.length; index += 1) {
      this.rootTitleContents[index]?.dispose();
      this.rootTitleContents[index] = undefined;
    }
    this.moreTitleContent?.dispose();
    this.moreTitleContent = undefined;
  }

  bindSettings(repository: SettingsRepository, store: AppSettingsStore): void {
    this.settingsRepository = repository;
    this.settingsStore = store;
    this.navigationOrder = normalizeNavigationOrder(
      repository.getNavigationOrder(DEFAULT_NAVIGATION_ORDER)
    );
    if (store.rememberLastTab) {
      const oldTabIndex = this.normalizeTabIndex(repository.getLastTabIndex());
      const fallbackRoute = oldTabIndex < PRIMARY_NAVIGATION_COUNT ?
        this.navigationOrder[oldTabIndex] : this.navigationOrder[PRIMARY_NAVIGATION_COUNT];
      const storedRoute = repository.getLastNavigationRoute(fallbackRoute);
      this.selectedRouteId = navigationItem(storedRoute) === undefined ?
        NavigationRoute.PLAYLISTS : storedRoute;
    } else {
      this.selectedRouteId = this.navigationOrder[0] ?? NavigationRoute.PLAYLISTS;
    }
  }

  private normalizeTabIndex(index: number): number {
    return Number.isInteger(index) && index >= 0 && index <= MORE_TAB_INDEX ? index : 0;
  }

  orderedItems(): Array<NavigationPageItem> {
    return orderedNavigationItems(this.navigationOrder);
  }

  primaryItems(): Array<NavigationPageItem> {
    return this.orderedItems().slice(0, PRIMARY_NAVIGATION_COUNT);
  }

  moreItems(): Array<NavigationPageItem> {
    return this.orderedItems().slice(PRIMARY_NAVIGATION_COUNT).concat([SETTINGS_NAVIGATION_ITEM]);
  }

  expandedItems(): Array<NavigationPageItem> {
    return this.orderedItems().concat([SETTINGS_NAVIGATION_ITEM]);
  }

  compactTabIndex(): number {
    const primary = this.primaryItems();
    for (let index = 0; index < primary.length; index += 1) {
      if (primary[index].routeId === this.selectedRouteId) {
        return index;
      }
    }
    return MORE_TAB_INDEX;
  }

  selectRoute(routeId: string): void {
    if (navigationItem(routeId) === undefined) {
      return;
    }
    this.selectedRouteId = routeId;
    if (this.settingsStore?.rememberLastTab) {
      this.settingsRepository?.setLastNavigationRoute(routeId);
      this.settingsRepository?.setLastTabIndex(this.compactTabIndex());
    }
  }

  handleCompactTabChange(index: number): void {
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

  handleCompactTabBarClick(index: number): void {
    if (index !== this.compactTabIndexBeforeSelection || index !== this.compactTabIndex()) {
      return;
    }
    if (index < PRIMARY_NAVIGATION_COUNT) {
      this.rootPathStacks[navigationItemIndex(this.selectedRouteId)].clear(true);
    } else {
      this.morePathStack.clear(true);
    }
  }

  expandedTabIndex(): number {
    const items = this.expandedItems();
    for (let index = 0; index < items.length; index += 1) {
      if (items[index].routeId === this.selectedRouteId) {
        return index;
      }
    }
    return 0;
  }

  handleExpandedTabChange(index: number): void {
    this.expandedTabIndexBeforeSelection = this.expandedTabIndex();
    const items = this.expandedItems();
    if (index < 0 || index >= items.length) {
      return;
    }
    this.selectRoute(items[index].routeId);
    this.morePathStack.clear(false);
  }

  handleExpandedTabBarClick(index: number): void {
    if (index !== this.expandedTabIndexBeforeSelection || index !== this.expandedTabIndex()) {
      return;
    }
    this.rootPathStacks[navigationItemIndex(this.selectedRouteId)].clear(true);
  }

  activeNavigationStack(wideLayout: boolean): NavPathStack {
    if (!wideLayout && this.compactTabIndex() === MORE_TAB_INDEX) {
      return this.morePathStack;
    }
    return this.rootPathStacks[navigationItemIndex(this.selectedRouteId)];
  }

  navigateLibrary(target: LibraryNavigationTarget, wideLayout: boolean): void {
    const stack = this.activeNavigationStack(wideLayout);
    if (target.identity.kind === LibraryEntityKind.ARTIST) {
      stack.pushPath({
        name: LibraryDetailRoute.ARTIST,
        param: new ArtistDetailRouteParams(target.identity.id, target.title)
      });
    } else if (target.identity.kind === LibraryEntityKind.ALBUM) {
      stack.pushPath({
        name: LibraryDetailRoute.ALBUM,
        param: new AlbumDetailRouteParams(
          target.identity.id,
          target.title,
          target.palettePrimary
        )
      });
    }
  }

  openMoreDestination(routeId: string): void {
    const items = this.moreItems();
    if (!items.some((item: NavigationPageItem): boolean => item.routeId === routeId)) {
      return;
    }
    this.selectRoute(routeId);
    this.morePathStack.pushPath({ name: routeId });
  }

  openNavigationCustomization(wideLayout: boolean): void {
    this.selectRoute(NavigationRoute.SETTINGS);
    const pathStack = wideLayout ?
      this.rootPathStacks[navigationItemIndex(NavigationRoute.SETTINGS)] : this.morePathStack;
    pathStack.pushPath({ name: NavigationRoute.NAVIGATION_CUSTOMIZATION });
  }

  setRememberLastTab(value: boolean): void {
    this.settingsStore?.setRememberLastTab(value);
    if (value) {
      this.settingsRepository?.setLastNavigationRoute(this.selectedRouteId);
      this.settingsRepository?.setLastTabIndex(this.compactTabIndex());
      return;
    }
    this.settingsRepository?.setLastNavigationRoute(
      this.navigationOrder[0] ?? NavigationRoute.PLAYLISTS
    );
    this.settingsRepository?.setLastTabIndex(0);
  }

  moveNavigationItem(from: number, to: number): void {
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

  reconcileResponsiveNavigation(previousWideLayout: boolean, nextWideLayout: boolean): void {
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
}
