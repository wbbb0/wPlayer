import BuildProfile from 'entry/BuildProfile';

export class NavigationRoute {
  static readonly PLAYLISTS: string = 'playlists';
  static readonly SONGS: string = 'songs';
  static readonly ALBUMS: string = 'albums';
  static readonly ARTISTS: string = 'artists';
  static readonly GENRES: string = 'genres';
  static readonly LIBRARY_MANAGEMENT: string = 'libraryManagement';
  static readonly SETTINGS: string = 'settings';
  static readonly FLOATING_WINDOW_SETTINGS: string = 'floatingWindowSettings';
  static readonly PLAYER_PAGE_SETTINGS: string = 'playerPageSettings';
  static readonly NAVIGATION_CUSTOMIZATION: string = 'navigationCustomization';
  static readonly DEBUG: string = 'debug';
  static readonly DYNAMIC_BACKGROUND_DEBUG: string = 'dynamicBackgroundDebug';
  static readonly DYNAMIC_BACKGROUND_V2_DEBUG: string = 'dynamicBackgroundV2Debug';
  static readonly DYNAMIC_BACKGROUND_V3_DEBUG: string = 'dynamicBackgroundV3Debug';
  static readonly ABOUT: string = 'about';
  static readonly PRIVACY_POLICY: string = 'privacyPolicy';
  static readonly DATA_AND_PERMISSIONS: string = 'dataAndPermissions';
  static readonly OPEN_SOURCE_LICENSES: string = 'openSourceLicenses';
}

export enum NavigationPageKind {
  PLAYLISTS = 0,
  SONGS = 1,
  ALBUMS = 2,
  ARTISTS = 3,
  GENRES = 4,
  LIBRARY_MANAGEMENT = 5,
  SETTINGS = 6,
  DEBUG = 7
}

export interface NavigationPageItem {
  routeId: string;
  kind: NavigationPageKind;
  label: string;
  description: string;
  symbol: Resource;
}

export const PRIMARY_NAVIGATION_COUNT: number = 3;

const DEFAULT_DYNAMIC_NAVIGATION_ITEMS: Array<NavigationPageItem> = [
  {
    routeId: NavigationRoute.PLAYLISTS,
    kind: NavigationPageKind.PLAYLISTS,
    label: '播放列表',
    description: '查看和管理播放列表',
    symbol: $r('sys.symbol.music_note_list_fill')
  },
  {
    routeId: NavigationRoute.SONGS,
    kind: NavigationPageKind.SONGS,
    label: '音乐',
    description: '浏览本地音乐',
    symbol: $r('sys.symbol.music_fill')
  },
  {
    routeId: NavigationRoute.ALBUMS,
    kind: NavigationPageKind.ALBUMS,
    label: '专辑',
    description: '按专辑浏览音乐',
    symbol: $r('sys.symbol.opticaldisc')
  },
  {
    routeId: NavigationRoute.ARTISTS,
    kind: NavigationPageKind.ARTISTS,
    label: '艺人',
    description: '按艺人浏览音乐',
    symbol: $r('sys.symbol.person_2_fill')
  },
  {
    routeId: NavigationRoute.GENRES,
    kind: NavigationPageKind.GENRES,
    label: '流派',
    description: '按流派浏览音乐',
    symbol: $r('sys.symbol.music_note_list_fill')
  },
  {
    routeId: NavigationRoute.LIBRARY_MANAGEMENT,
    kind: NavigationPageKind.LIBRARY_MANAGEMENT,
    label: '音乐库',
    description: '添加音乐、检查文件并管理本地音乐库',
    symbol: $r('sys.symbol.externaldrive_fill')
  }
];

const DEBUG_NAVIGATION_ITEM: NavigationPageItem = {
  routeId: NavigationRoute.DEBUG,
  kind: NavigationPageKind.DEBUG,
  label: '调试工具',
  description: '演示数据、动态背景与开发阶段视觉测试',
  symbol: $r('sys.symbol.gearshape_fill')
};

export const DYNAMIC_NAVIGATION_ITEMS: Array<NavigationPageItem> = BuildProfile.DEBUG ?
  DEFAULT_DYNAMIC_NAVIGATION_ITEMS.concat([DEBUG_NAVIGATION_ITEM]) :
  DEFAULT_DYNAMIC_NAVIGATION_ITEMS;

export const SETTINGS_NAVIGATION_ITEM: NavigationPageItem = {
  routeId: NavigationRoute.SETTINGS,
  kind: NavigationPageKind.SETTINGS,
  label: '设置',
  description: '自定义页面和应用偏好',
  symbol: $r('sys.symbol.gearshape_fill')
};

export const DEFAULT_NAVIGATION_ORDER: Array<string> = DYNAMIC_NAVIGATION_ITEMS.map(
  (item: NavigationPageItem): string => item.routeId
);

export const ALL_ROOT_NAVIGATION_ITEMS: Array<NavigationPageItem> =
  DYNAMIC_NAVIGATION_ITEMS.concat([SETTINGS_NAVIGATION_ITEM]);

export function navigationItem(routeId: string): NavigationPageItem | undefined {
  for (let index = 0; index < ALL_ROOT_NAVIGATION_ITEMS.length; index += 1) {
    if (ALL_ROOT_NAVIGATION_ITEMS[index].routeId === routeId) {
      return ALL_ROOT_NAVIGATION_ITEMS[index];
    }
  }
  return undefined;
}

export function navigationItemIndex(routeId: string): number {
  for (let index = 0; index < ALL_ROOT_NAVIGATION_ITEMS.length; index += 1) {
    if (ALL_ROOT_NAVIGATION_ITEMS[index].routeId === routeId) {
      return index;
    }
  }
  return 0;
}

export function navigationPageKind(routeId: string): NavigationPageKind {
  return navigationItem(routeId)?.kind ?? NavigationPageKind.PLAYLISTS;
}

export function normalizeNavigationOrder(order: Array<string>): Array<string> {
  const normalized: Array<string> = [];
  for (let index = 0; index < order.length; index += 1) {
    const routeId = order[index];
    if (routeId !== NavigationRoute.SETTINGS && navigationItem(routeId) !== undefined &&
      normalized.indexOf(routeId) < 0) {
      normalized.push(routeId);
    }
  }
  for (let index = 0; index < DEFAULT_NAVIGATION_ORDER.length; index += 1) {
    const routeId = DEFAULT_NAVIGATION_ORDER[index];
    if (normalized.indexOf(routeId) < 0) {
      normalized.push(routeId);
    }
  }
  return normalized;
}

export function orderedNavigationItems(order: Array<string>): Array<NavigationPageItem> {
  const normalized = normalizeNavigationOrder(order);
  const items: Array<NavigationPageItem> = [];
  for (let index = 0; index < normalized.length; index += 1) {
    const item = navigationItem(normalized[index]);
    if (item !== undefined) {
      items.push(item);
    }
  }
  return items;
}
