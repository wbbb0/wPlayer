import { LibrarySection } from '../model/LibraryModels';

/** Virtual-list cache, query-window and index-location rules shared by pages and tests. */
export class LibraryPagingPolicy {
  static readonly TRACK_UI_CACHE_COUNT: number = 4;
  static readonly ALBUM_UI_CACHE_COUNT: number = 2;
  static readonly TRACK_QUERY_PAGE_SIZE: number = 32;
  static readonly ALBUM_QUERY_PAGE_SIZE: number = 24;
  static readonly INITIAL_PREFETCH_PAGES: number = 2;
  static readonly VISIBLE_RANGE_PREFETCH_PAGES: number = 1;
  static readonly MAX_CACHED_PAGES: number = 7;

  static pageStartForIndex(index: number, pageSize: number): number {
    if (index <= 0 || pageSize <= 0) {
      return 0;
    }
    return Math.floor(index / pageSize) * pageSize;
  }

  static initialPrefetchLastIndex(pageSize: number): number {
    return Math.max(0, pageSize * LibraryPagingPolicy.INITIAL_PREFETCH_PAGES - 1);
  }

  static prefetchStartForVisibleRange(firstIndex: number, pageSize: number): number {
    const firstPage = LibraryPagingPolicy.pageStartForIndex(firstIndex, pageSize);
    return Math.max(0, firstPage - pageSize * LibraryPagingPolicy.VISIBLE_RANGE_PREFETCH_PAGES);
  }

  static prefetchEndForVisibleRange(lastIndex: number, pageSize: number): number {
    const lastPage = LibraryPagingPolicy.pageStartForIndex(lastIndex, pageSize);
    return lastPage + pageSize * (LibraryPagingPolicy.VISIBLE_RANGE_PREFETCH_PAGES + 1) - 1;
  }

  static selectedSectionIndex(sections: Array<LibrarySection>, itemIndex: number): number {
    if (sections.length === 0) {
      return -1;
    }
    const target = Math.max(0, itemIndex);
    let low = 0;
    let high = sections.length - 1;
    while (low <= high) {
      const middle = low + Math.floor((high - low) / 2);
      if (sections[middle].startIndex <= target) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return Math.max(0, high);
  }
}
