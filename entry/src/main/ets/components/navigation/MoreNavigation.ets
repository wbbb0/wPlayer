export class MoreRoute {
  static readonly LIBRARY_MANAGEMENT: string = 'libraryManagement';
}

export interface MoreNavigationItem {
  routeId: string;
  label: string;
  description: string;
  symbol: Resource;
}

export const MORE_NAVIGATION_ITEMS: Array<MoreNavigationItem> = [
  {
    routeId: MoreRoute.LIBRARY_MANAGEMENT,
    label: '音乐库',
    description: '添加 MP3 / FLAC，查看统计或清空测试数据',
    symbol: $r('sys.symbol.externaldrive_fill')
  }
];
