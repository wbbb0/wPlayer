export interface DetailTrackVisibleRange {
  firstIndex: number;
  lastIndex: number;
}

/**
 * Maps whole-detail List indexes to the track-only data source.
 * Album grids occupy one List item regardless of the number of albums they render.
 */
export class DetailTrackListPagingPolicy {
  static artistTrackDataStartIndex(hasAlbums: boolean): number {
    const headerItems = 1;
    const albumSectionItems = hasAlbums ? 2 : 0;
    const trackSectionTitleItems = 1;
    return headerItems + albumSectionItems + trackSectionTitleItems;
  }

  static playlistTrackDataStartIndex(): number {
    return 1;
  }

  static visibleDataRange(firstListIndex: number, lastListIndex: number,
    dataStartIndex: number, totalCount: number): DetailTrackVisibleRange | undefined {
    const count = Math.max(0, Math.floor(totalCount));
    if (count === 0 || lastListIndex < dataStartIndex) {
      return undefined;
    }
    const first = Math.min(
      count - 1,
      Math.max(0, Math.floor(firstListIndex) - dataStartIndex)
    );
    const last = Math.min(count - 1, Math.max(first, Math.floor(lastListIndex) - dataStartIndex));
    return { firstIndex: first, lastIndex: last };
  }
}
