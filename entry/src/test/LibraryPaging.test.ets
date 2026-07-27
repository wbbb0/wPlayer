import { describe, it, expect } from '@ohos/hypium';
import {
  AlbumSortField,
  LibrarySection,
  SortDirection,
  TrackSortField
} from '../main/ets/library/model/LibraryModels';
import { LibrarySortPlan } from '../main/ets/library/data/LibrarySortPlan';
import { LibraryQueryPagingPolicy } from '../main/ets/library/data/LibraryQueryPagingPolicy';
import { LibraryPagingPolicy } from '../main/ets/library/store/LibraryPagingPolicy';
import {
  LibraryPageLoader,
  LibrarySlot,
  PagedLibraryDataSource
} from '../main/ets/library/store/PagedLibraryDataSource';
import {
  LibraryTrackProjection,
  TrackProjectionSnapshot
} from '../main/ets/library/store/LibraryTrackProjection';

class PagingTestItem {
  id: number = 0;
}

class PagingTestLoader implements LibraryPageLoader<PagingTestItem> {
  loadCount: number = 0;
  failNext: boolean = false;
  delayMs: number = 0;

  async load(offset: number, limit: number): Promise<Array<PagingTestItem>> {
    this.loadCount += 1;
    if (this.delayMs > 0) {
      await new Promise<void>((resolve) => setTimeout(resolve, this.delayMs));
    }
    if (this.failNext) {
      this.failNext = false;
      throw new Error('expected page failure');
    }
    const items: Array<PagingTestItem> = [];
    for (let index = offset; index < offset + limit; index += 1) {
      const item = new PagingTestItem();
      item.id = index;
      items.push(item);
    }
    return items;
  }
}

class RecordingDataChangeListener implements DataChangeListener {
  operations: Array<DataOperation> = [];
  notifications: number = 0;

  onDataReloaded(): void {}
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}

  onDatasetChange(dataOperations: Array<DataOperation>): void {
    this.operations = dataOperations;
    this.notifications += 1;
  }
}

const CHARACTERIZED_SECTIONS: Array<LibrarySection> = [
  { label: '#', startIndex: 0 },
  { label: 'A', startIndex: 2 },
  { label: 'B', startIndex: 5 },
  { label: 'Z', startIndex: 8 }
];

function source(pageSize: number = 8, maxCachedPages: number = 5):
  PagedLibraryDataSource<PagingTestItem> {
  return new PagedLibraryDataSource<PagingTestItem>(
    pageSize,
    maxCachedPages,
    (item: PagingTestItem): string => `${item.id}`
  );
}

export default function libraryPagingTest() {
  describe('Library paging and alphabet index', () => {
    it('separates UI cache counts from bounded query pages', 0, () => {
      expect(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT).assertEqual(4);
      expect(LibraryPagingPolicy.ALBUM_UI_CACHE_COUNT).assertEqual(2);
      expect(LibraryPagingPolicy.TRACK_QUERY_PAGE_SIZE >
        LibraryPagingPolicy.TRACK_UI_CACHE_COUNT).assertTrue();
      expect(LibraryPagingPolicy.ALBUM_QUERY_PAGE_SIZE >
        LibraryPagingPolicy.ALBUM_UI_CACHE_COUNT).assertTrue();
    });

    it('maps visible ranges to adjacent query windows', 0, () => {
      const pageSize = 32;
      expect(LibraryPagingPolicy.pageStartForIndex(-1, pageSize)).assertEqual(0);
      expect(LibraryPagingPolicy.pageStartForIndex(31, pageSize)).assertEqual(0);
      expect(LibraryPagingPolicy.pageStartForIndex(32, pageSize)).assertEqual(32);
      expect(LibraryPagingPolicy.initialPrefetchLastIndex(pageSize)).assertEqual(63);
      expect(LibraryPagingPolicy.prefetchStartForVisibleRange(70, pageSize)).assertEqual(32);
      expect(LibraryPagingPolicy.prefetchEndForVisibleRange(75, pageSize)).assertEqual(127);
    });

    it('bounds random-access query parameters', 0, () => {
      expect(LibraryQueryPagingPolicy.offset(-1)).assertEqual(0);
      expect(LibraryQueryPagingPolicy.offset(12.8)).assertEqual(12);
      expect(LibraryQueryPagingPolicy.limit(0)).assertEqual(1);
      expect(LibraryQueryPagingPolicy.limit(0.5)).assertEqual(1);
      expect(LibraryQueryPagingPolicy.limit(16.9)).assertEqual(16);
      expect(LibraryQueryPagingPolicy.limit(1000))
        .assertEqual(LibraryQueryPagingPolicy.MAX_PAGE_SIZE);
    });

    it('shares exact alphabet ordering between pages and catalogs', 0, () => {
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

    it('invalidates a captured playback order when a new catalog is published', 0, () => {
      const projection = new LibraryTrackProjection();
      projection.publish(TrackSortField.TITLE, SortDirection.ASCENDING);
      const captured: TrackProjectionSnapshot = projection.snapshot();
      expect(projection.isCurrent(captured)).assertTrue();

      projection.publish(TrackSortField.ARTIST, SortDirection.DESCENDING);
      expect(projection.isCurrent(captured)).assertFalse();
      expect(projection.snapshot().field).assertEqual(TrackSortField.ARTIST);
    });

    it('selects the section whose global start index contains the visible item', 0, () => {
      expect(LibraryPagingPolicy.selectedSectionIndex([], 0)).assertEqual(-1);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 1)).assertEqual(0);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 2)).assertEqual(1);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 7)).assertEqual(2);
      expect(LibraryPagingPolicy.selectedSectionIndex(CHARACTERIZED_SECTIONS, 999)).assertEqual(3);
    });

    it('loads a deep page and bounds its change notification', 0, async () => {
      const loader = new PagingTestLoader();
      const dataSource = source();
      const listener = new RecordingDataChangeListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.reset(59000, loader);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);

      await dataSource.ensureRange(48000, 48000);
      const loaded: LibrarySlot<PagingTestItem> = dataSource.getData(48000);
      expect(loaded.value !== undefined).assertTrue();
      expect(listener.operations.length <= 8).assertTrue();
      expect(loader.loadCount).assertEqual(1);
    });

    it('deduplicates concurrent requests for the same page', 0, async () => {
      const loader = new PagingTestLoader();
      loader.delayMs = 5;
      const dataSource = source();
      dataSource.reset(100, loader);

      await Promise.all([
        dataSource.ensureRange(16, 16),
        dataSource.ensureRange(17, 17)
      ]);

      expect(loader.loadCount).assertEqual(1);
      expect(dataSource.getData(16).value !== undefined).assertTrue();
    });

    it('discards page completion after a reset', 0, async () => {
      const slowLoader = new PagingTestLoader();
      slowLoader.delayMs = 10;
      const replacementLoader = new PagingTestLoader();
      const dataSource = source();
      dataSource.reset(100, slowLoader);
      const staleLoad = dataSource.ensureRange(0, 0);
      dataSource.reset(20, replacementLoader);
      await staleLoad;

      const slot = dataSource.getData(0);
      expect(slot.value === undefined).assertTrue();
      expect(dataSource.totalCount()).assertEqual(20);
    });

    it('recovers a transient page failure without another scroll event', 0, async () => {
      const loader = new PagingTestLoader();
      loader.failNext = true;
      const dataSource = source();
      dataSource.reset(30, loader);

      await dataSource.ensureRange(0, 0);
      expect(loader.loadCount).assertEqual(2);
      expect(dataSource.getData(0).value !== undefined).assertTrue();
    });

    it('evicts old pages while retaining a bounded cache', 0, async () => {
      const loader = new PagingTestLoader();
      const dataSource = source(4, 3);
      dataSource.reset(80, loader);
      await dataSource.ensureRange(0, 3);
      await dataSource.ensureRange(16, 19);
      await dataSource.ensureRange(32, 35);
      await dataSource.ensureRange(48, 51);

      expect(dataSource.cachedPageCount() <= 3).assertTrue();
      expect(dataSource.getData(48).value !== undefined).assertTrue();
    });

    it('keeps the cache bounded when a caller protects an oversized range', 0, async () => {
      const loader = new PagingTestLoader();
      const dataSource = source(4, 3);
      dataSource.reset(80, loader);

      await dataSource.ensureRange(0, 31);

      expect(dataSource.cachedPageCount()).assertEqual(3);
    });
  });
}
