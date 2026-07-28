import { ArtworkLayout, ArtworkSize } from '../artwork/ArtworkLayout';

export class PageLayoutSpec {
  static readonly HORIZONTAL_INSET: number = 20;
  static readonly PRIMARY_CONTENT_GAP: number = 8;
  static readonly SECONDARY_CONTENT_GAP: number = 8;
  static readonly FLOATING_CONTROLS_CLEARANCE: number = 112;
  static readonly ALBUM_MIN_COLUMN_WIDTH: number = 160;
  static readonly ALBUM_MIN_COLUMN_COUNT: number = 2;
  static readonly ALBUM_COLUMN_GAP: number = 16;
  static readonly ALBUM_ROW_GAP: number = 20;
  static readonly DETAIL_PRIMARY_PLAY_MIN_WIDTH: number = 112;
  static readonly DETAIL_PRIMARY_PLAY_MAX_WIDTH: number = 180;
  static readonly DETAIL_COMPACT_ARTWORK_MAX_HEIGHT: number = 220;
  static readonly DETAIL_WIDE_ARTWORK_MAX_HEIGHT: number = 184;
  static readonly DETAIL_WIDE_HEADER_GAP: number = 28;
  static readonly DETAIL_WIDE_TEXT_MIN_WIDTH: number = 280;

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

  static albumDetailArtworkSize(sourceWidth: number, sourceHeight: number,
    containerWidth: number, wideHeader: boolean): ArtworkSize {
    const maximumHeight = wideHeader ?
      PageLayoutSpec.DETAIL_WIDE_ARTWORK_MAX_HEIGHT :
      PageLayoutSpec.DETAIL_COMPACT_ARTWORK_MAX_HEIGHT;
    const maximumWidth = wideHeader ?
      Math.max(
        maximumHeight,
        containerWidth - PageLayoutSpec.HORIZONTAL_INSET * 2 -
          PageLayoutSpec.DETAIL_WIDE_HEADER_GAP -
          PageLayoutSpec.DETAIL_WIDE_TEXT_MIN_WIDTH
      ) :
      Math.max(0, containerWidth);
    return ArtworkLayout.containedSizeWithSquareFallback(
      sourceWidth,
      sourceHeight,
      maximumWidth,
      maximumHeight
    );
  }

  static albumColumnsTemplate(containerWidth: number, horizontalInset: number = 0): string {
    const columnCount = PageLayoutSpec.albumColumnCount(containerWidth, horizontalInset);
    let template = '1fr';
    for (let index = 1; index < columnCount; index += 1) {
      template += ' 1fr';
    }
    return template;
  }

  static albumColumnCount(containerWidth: number, horizontalInset: number = 0): number {
    const availableWidth = Math.max(
      PageLayoutSpec.ALBUM_MIN_COLUMN_WIDTH,
      containerWidth - horizontalInset * 2
    );
    return Math.max(PageLayoutSpec.ALBUM_MIN_COLUMN_COUNT, Math.floor(
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
