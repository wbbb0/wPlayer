import { LibrarySection } from '../model/LibraryModels';

/** Virtual-list cache sizing and index-location rules shared by pages and tests. */
export class LibraryPagingPolicy {
  static readonly TRACK_PAGE_SIZE: number = 4;
  static readonly ALBUM_PAGE_SIZE: number = 2;

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
