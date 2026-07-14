export class PageLayoutSpec {
  static readonly HORIZONTAL_INSET: number = 20;
  static readonly PRIMARY_CONTENT_GAP: number = 8;
  static readonly SECONDARY_CONTENT_GAP: number = 8;
  static readonly FLOATING_CONTROLS_CLEARANCE: number = 112;
  static readonly ALBUM_MIN_COLUMN_WIDTH: number = 160;
  static readonly ALBUM_GRID_CACHE_COUNT: number = 12;
  static readonly VIRTUAL_LIST_CACHE_COUNT: number = 16;

  static primaryContentStart(_topInset: number): number {
    // HdsNavigation owns the title bar safe area and its layout height.
    return PageLayoutSpec.PRIMARY_CONTENT_GAP;
  }

  static secondaryContentStart(_topInset: number): number {
    // HdsNavDestination applies the same safe-area contract to its title bar.
    return PageLayoutSpec.SECONDARY_CONTENT_GAP;
  }

  static contentEnd(bottomInset: number): number {
    return Math.max(0, bottomInset) + PageLayoutSpec.FLOATING_CONTROLS_CLEARANCE;
  }

  static albumColumnsTemplate(): string {
    return `repeat(auto-fit, ${PageLayoutSpec.ALBUM_MIN_COLUMN_WIDTH})`;
  }
}
