import { LibrarySection } from '../model/LibraryModels';

/** Paging and index-location rules shared by the store, UI and tests. */
export class LibraryPagingPolicy {
  static readonly TRACK_PAGE_SIZE: number = 16;
  static readonly ALBUM_PAGE_SIZE: number = 16;

  static pageStartForIndex(index: number, pageSize: number): number {
    if (index <= 0 || pageSize <= 0) {
      return 0;
    }
    return Math.floor(index / pageSize) * pageSize;
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
