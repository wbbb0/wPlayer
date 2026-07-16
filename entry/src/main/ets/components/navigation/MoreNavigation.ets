export class NavigationRoute {
  static readonly PLAYLISTS: string = 'playlists';
  static readonly SONGS: string = 'songs';
  static readonly ALBUMS: string = 'albums';
  static readonly LIBRARY_MANAGEMENT: string = 'libraryManagement';
  static readonly MATERIAL_DEBUG: string = 'materialDebug';
  static readonly SETTINGS: string = 'settings';
  static readonly NAVIGATION_CUSTOMIZATION: string = 'navigationCustomization';
}

export enum NavigationPageKind {
  PLAYLISTS = 0,
  SONGS = 1,
  ALBUMS = 2,
  LIBRARY_MANAGEMENT = 3,
  MATERIAL_DEBUG = 4,
  SETTINGS = 5
}

export interface NavigationPageItem {
  routeId: string;
  kind: NavigationPageKind;
  label: string;
  description: string;
  symbol: Resource;
}

export const PRIMARY_NAVIGATION_COUNT: number = 3;

export const DYNAMIC_NAVIGATION_ITEMS: Array<NavigationPageItem> = [
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
    routeId: NavigationRoute.LIBRARY_MANAGEMENT,
    kind: NavigationPageKind.LIBRARY_MANAGEMENT,
    label: '音乐库',
    description: '添加音乐、查看统计或清空测试数据',
    symbol: $r('sys.symbol.externaldrive_fill')
  },
  {
    routeId: NavigationRoute.MATERIAL_DEBUG,
    kind: NavigationPageKind.MATERIAL_DEBUG,
    label: '材质调试',
    description: '比较 HDS、模糊背板与各类弹出组件',
    symbol: $r('sys.symbol.square_fill_grid_2x2')
  }
];

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
