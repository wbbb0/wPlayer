export class PageLayoutSpec {
  static readonly HORIZONTAL_INSET: number = 20;
  static readonly PRIMARY_CONTENT_GAP: number = 8;
  static readonly SECONDARY_CONTENT_GAP: number = 8;
  static readonly FLOATING_CONTROLS_CLEARANCE: number = 112;
  static readonly ALBUM_MIN_COLUMN_WIDTH: number = 160;
  static readonly ALBUM_COLUMN_GAP: number = 16;
  static readonly ALBUM_ROW_GAP: number = 20;
  static readonly ALBUM_GRID_CACHE_COUNT: number = 3;
  static readonly VIRTUAL_LIST_CACHE_COUNT: number = 8;
  static readonly SONG_LIST_CACHE_COUNT: number = 6;
  static readonly DETAIL_TRACK_LIST_CACHE_COUNT: number = 6;
  static readonly PLAYER_QUEUE_CACHE_COUNT: number = 5;
  static readonly LYRIC_LIST_CACHE_COUNT: number = 8;
  static readonly DETAIL_PRIMARY_PLAY_MIN_WIDTH: number = 112;
  static readonly DETAIL_PRIMARY_PLAY_MAX_WIDTH: number = 180;

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

  static albumColumnCount(containerWidth: number, horizontalInset: number = 0): number {
    const availableWidth = Math.max(
      PageLayoutSpec.ALBUM_MIN_COLUMN_WIDTH,
      containerWidth - horizontalInset * 2
    );
    return Math.max(1, Math.floor(
      (availableWidth + PageLayoutSpec.ALBUM_COLUMN_GAP) /
      (PageLayoutSpec.ALBUM_MIN_COLUMN_WIDTH + PageLayoutSpec.ALBUM_COLUMN_GAP)
    ));
  }

  static albumItemWidth(containerWidth: number, horizontalInset: number = 0): number {
    const availableWidth = Math.max(
      PageLayoutSpec.ALBUM_MIN_COLUMN_WIDTH,
      containerWidth - horizontalInset * 2
    );
    const columnCount = PageLayoutSpec.albumColumnCount(containerWidth, horizontalInset);
    return (availableWidth - PageLayoutSpec.ALBUM_COLUMN_GAP * (columnCount - 1)) / columnCount;
  }

}
