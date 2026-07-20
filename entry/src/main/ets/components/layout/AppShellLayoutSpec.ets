export class AppShellLayoutSpec {
  static readonly SIDE_NAVIGATION_BREAKPOINT: number = 600;
  static readonly COMPACT_TABS_HOST_ID: string = 'player_tabs_compact_content_host';
  static readonly CONDENSED_COMPACT_TABS_HOST_ID: string =
    'player_tabs_condensed_compact_content_host';
  static readonly WIDE_TABS_HOST_ID: string = 'player_tabs_wide_content_host';
  static readonly WIDE_MINI_PLAYER_HOST_ID: string = 'wide_mini_player_hds_host';

  static readonly FLOATING_BAR_BOTTOM_MARGIN: number = 18;
  static readonly FLOATING_BAR_GRADIENT_MASK_HEIGHT: number = 84;
  static readonly WIDE_MINI_PLAYER_HOST_HEIGHT: number =
    AppShellLayoutSpec.FLOATING_BAR_GRADIENT_MASK_HEIGHT +
      AppShellLayoutSpec.FLOATING_BAR_BOTTOM_MARGIN;
  static readonly COMPACT_SIDE_MARGIN: number = 16;
  static readonly WIDE_SIDE_MARGIN: number = 32;
  static readonly EXPANDED_TAB_BAR_PORTRAIT_WIDTH: number = 88;
  static readonly EXPANDED_TAB_BAR_LANDSCAPE_WIDTH: number = 128;
  static readonly EXPANDED_TAB_ITEM_LEADING_PADDING: number = 20;
  static readonly EXPANDED_TAB_ITEM_ICON_SIZE: number = 24;
  static readonly EXPANDED_TAB_ITEM_LABEL_SIZE: number = 12;
  static readonly EXPANDED_TAB_ITEM_HORIZONTAL_GAP: number = 8;
  static readonly EXPANDED_TAB_ITEM_VERTICAL_GAP: number = 2;
  static readonly EXPANDED_TAB_ITEM_PORTRAIT_HEIGHT: number = 56;
  static readonly EXPANDED_TAB_ITEM_LANDSCAPE_HEIGHT: number = 48;
  static readonly EXPANDED_TAB_SECTION_DIVIDER_WIDTH: number = 36;
  static readonly EXPANDED_TAB_SECTION_DIVIDER_THICKNESS: number = 1;
  static readonly EXPANDED_TAB_SECTION_DIVIDER_MARGIN: number = 8;
  static readonly EXPANDED_TAB_SECTION_DIVIDER_OPACITY: number = 0.24;
  static readonly TAB_SELECTION_COLOR_DURATION: number = 100;
  static readonly HIDDEN_TAB_BAR_WIDTH: number = 56;

  static readonly COMPACT_TAB_SMALL_WIDTH: number = 272;
  static readonly COMPACT_TAB_MEDIUM_WIDTH: number = 292;
  static readonly COMPACT_TAB_LARGE_WIDTH: number = 320;
  static readonly MINI_PLAYER_SMALL_WIDTH: number = 260;
  static readonly MINI_PLAYER_MEDIUM_WIDTH: number = 288;
  static readonly MINI_PLAYER_LARGE_WIDTH: number = 328;
  static readonly MINI_PLAYER_HEIGHT: number = 56;

  static usesCondensedCompactNavigation(hostWidth: number): boolean {
    if (hostWidth <= 0 || hostWidth >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT) {
      return false;
    }
    const requiredWidth = AppShellLayoutSpec.COMPACT_TAB_SMALL_WIDTH +
      AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH +
      AppShellLayoutSpec.COMPACT_SIDE_MARGIN * 2;
    return hostWidth < requiredWidth;
  }

  static hasResolvedRootSize(hostWidth: number, hostHeight: number): boolean {
    return hostWidth > 0 && hostHeight > 0;
  }

  static compactTabsHostId(hostWidth: number): string {
    return AppShellLayoutSpec.usesCondensedCompactNavigation(hostWidth) ?
      AppShellLayoutSpec.CONDENSED_COMPACT_TABS_HOST_ID :
      AppShellLayoutSpec.COMPACT_TABS_HOST_ID;
  }

  static compactExpandedMiniPlayerStart(hostWidth: number, miniPlayerWidth: number): number {
    const centeredStart = (hostWidth - miniPlayerWidth) / 2;
    const collapsedNavigationEnd =
      AppShellLayoutSpec.COMPACT_SIDE_MARGIN + AppShellLayoutSpec.HIDDEN_TAB_BAR_WIDTH;
    if (centeredStart >= collapsedNavigationEnd) {
      return centeredStart;
    }
    return Math.max(
      AppShellLayoutSpec.COMPACT_SIDE_MARGIN,
      hostWidth - miniPlayerWidth - AppShellLayoutSpec.COMPACT_SIDE_MARGIN
    );
  }
}
