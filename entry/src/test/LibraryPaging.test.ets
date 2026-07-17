import { describe, it, expect } from '@ohos/hypium';
import {
  AlbumSortField,
  LibrarySection,
  SortDirection,
  TrackSortField
} from '../main/ets/library/model/LibraryModels';
import { LibrarySortPlan } from '../main/ets/library/data/LibrarySortPlan';
import { LibraryPagingPolicy } from '../main/ets/library/store/LibraryPagingPolicy';
import {
  LibraryPageLoader,
  LibrarySlot,
  PagedLibraryDataSource
} from '../main/ets/library/store/PagedLibraryDataSource';

class PagingTestItem {
  id: number = 0;
}

class PagingTestLoader implements LibraryPageLoader<PagingTestItem> {
  loadCount: number = 0;

  async load(offset: number, limit: number): Promise<Array<PagingTestItem>> {
    this.loadCount += 1;
    const items: Array<PagingTestItem> = [];
    for (let index = offset; index < offset + limit; index += 1) {
      const item = new PagingTestItem();
      item.id = index;
      items.push(item);
    }
    return items;
  }
}

const CHARACTERIZED_SECTIONS: Array<LibrarySection> = [
  { label: '#', startIndex: 0 },
  { label: 'A', startIndex: 2 },
  { label: 'B', startIndex: 5 },
  { label: 'Z', startIndex: 8 }
];

export default function libraryPagingTest() {
  describe('Library paging and alphabet index', () => {
    it('uses a bounded initial page for songs and albums', 0, () => {
      expect(LibraryPagingPolicy.TRACK_PAGE_SIZE).assertEqual(16);
      expect(LibraryPagingPolicy.ALBUM_PAGE_SIZE).assertEqual(16);
      expect(LibraryPagingPolicy.TRACK_PAGE_SIZE)
        .assertEqual(LibraryPagingPolicy.ALBUM_PAGE_SIZE);
    });

    it('maps global item indexes to stable page starts', 0, () => {
      const pageSize = LibraryPagingPolicy.TRACK_PAGE_SIZE;
      expect(LibraryPagingPolicy.pageStartForIndex(-1, pageSize)).assertEqual(0);
      expect(LibraryPagingPolicy.pageStartForIndex(0, pageSize)).assertEqual(0);
      expect(LibraryPagingPolicy.pageStartForIndex(pageSize - 1, pageSize)).assertEqual(0);
      expect(LibraryPagingPolicy.pageStartForIndex(pageSize, pageSize)).assertEqual(pageSize);
      expect(LibraryPagingPolicy.pageStartForIndex(pageSize * 2 + 5, pageSize))
        .assertEqual(pageSize * 2);
    });

    it('shares exact alphabet ordering between pages and global sections', 0, () => {
      const ascending = LibrarySortPlan.track(TrackSortField.TITLE, SortDirection.ASCENDING);
      expect(ascending.orderClause)
        .assertEqual("t.title_section = '#' ASC, t.title_natural_key ASC, t.id ASC");
      expect(ascending.sectionOrderClause)
        .assertEqual("t.title_section = '#' ASC, t.title_section ASC");

      const descending = LibrarySortPlan.album(AlbumSortField.ALBUM_ARTIST, SortDirection.DESCENDING);
      expect(descending.orderClause)
        .assertEqual("al.artist_section = '#' ASC, al.artist_natural_key DESC, al.id DESC");
      expect(descending.sectionOrderClause)
        .assertEqual("al.artist_section = '#' ASC, al.artist_section DESC");
    });

    it('keeps unknown release dates last in both directions', 0, () => {
      const ascending = LibrarySortPlan.track(TrackSortField.RELEASE_DATE, SortDirection.ASCENDING);
      const descending = LibrarySortPlan.track(TrackSortField.RELEASE_DATE, SortDirection.DESCENDING);
      expect(ascending.orderClause)
        .assertEqual('t.release_date_sort = 0 ASC, t.release_date_sort ASC, t.id ASC');
      expect(descending.orderClause)
        .assertEqual('t.release_date_sort = 0 ASC, t.release_date_sort DESC, t.id DESC');
    });

    it('selects no alphabet section when the section index is empty', 0, () => {
      expect(LibraryPagingPolicy.selectedSectionIndex([], 0)).assertEqual(-1);
      expect(LibraryPagingPolicy.selectedSectionIndex([], 999)).assertEqual(-1);
    });

    it('selects the section whose global start index contains the first visible item', 0, () => {
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, -1)).assertEqual(0);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 0)).assertEqual(0);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 1)).assertEqual(0);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 2)).assertEqual(1);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 4)).assertEqual(1);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 5)).assertEqual(2);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 7)).assertEqual(2);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 8)).assertEqual(3);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 999)).assertEqual(3);
    });

    it('moves the alphabet selection backward when the user scrolls upward', 0, () => {
      const visibleIndexes: Array<number> = [8, 7, 5, 4, 2, 1];
      const expectedSections: Array<number> = [3, 2, 2, 1, 1, 0];
      for (let index = 0; index < visibleIndexes.length; index += 1) {
        expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, visibleIndexes[index]))
          .assertEqual(expectedSections[index]);
      }
    });

    it('keeps logical slots stable while loading one requested page', 0, async () => {
      const loader = new PagingTestLoader();
      const source = new PagedLibraryDataSource<PagingTestItem>(24, 3);
      source.reset(60, loader);
      const placeholder = source.getData(25);
      expect(placeholder.index).assertEqual(25);
      expect(placeholder.value === undefined).assertTrue();

      await source.ensureRange(25, 25);
      const loaded: LibrarySlot<PagingTestItem> = source.getData(25);
      expect(loaded.value !== undefined).assertTrue();
      if (loaded.value !== undefined) {
        expect(loaded.value.id).assertEqual(25);
      }
      expect(loaded.revision > placeholder.revision).assertTrue();
      expect(loader.loadCount).assertEqual(1);
    });

    it('invalidates loaded slots when the logical result set resets', 0, async () => {
      const loader = new PagingTestLoader();
      const source = new PagedLibraryDataSource<PagingTestItem>(24, 3);
      source.reset(30, loader);
      await source.ensureRange(0, 0);
      const loaded = source.getData(0);
      source.reset(12, loader);
      const resetSlot = source.getData(0);
      expect(resetSlot.generation > loaded.generation).assertTrue();
      expect(resetSlot.value === undefined).assertTrue();
      expect(source.totalCount()).assertEqual(12);
    });
  });
}
