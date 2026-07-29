import { describe, it, expect } from '@ohos/hypium';
import {
  AlbumSortField,
  LibraryCatalog,
  LibraryIndexPresentation,
  LibrarySection,
  SortDirection,
  TrackSortField
} from '../main/ets/library/model/LibraryModels';
import { LibrarySortPlan } from '../main/ets/library/data/LibrarySortPlan';
import { LibraryQueryPagingPolicy } from '../main/ets/library/data/LibraryQueryPagingPolicy';
import {
  LibrarySectionPagePlanner,
  LibrarySectionPageSegment
} from '../main/ets/library/data/LibrarySectionPagePlanner';
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
import {
  DetailTrackListPagingPolicy,
  DetailTrackVisibleRange
} from '../main/ets/library/store/DetailTrackListPagingPolicy';

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

class ControlledPagingTestLoader implements LibraryPageLoader<PagingTestItem> {
  startedOffsets: Array<number> = [];
  activeLoads: number = 0;
  maxActiveLoads: number = 0;
  private readonly releases: Map<number, () => void> = new Map<number, () => void>();

  load(offset: number, limit: number): Promise<Array<PagingTestItem>> {
    this.startedOffsets.push(offset);
    this.activeLoads += 1;
    this.maxActiveLoads = Math.max(this.maxActiveLoads, this.activeLoads);
    return new Promise<Array<PagingTestItem>>((resolve) => {
      this.releases.set(offset, (): void => {
        this.activeLoads -= 1;
        const items: Array<PagingTestItem> = [];
        for (let index = offset; index < offset + limit; index += 1) {
          const item = new PagingTestItem();
          item.id = index;
          items.push(item);
        }
        resolve(items);
      });
    });
  }

  release(offset: number): void {
    const release = this.releases.get(offset);
    if (release !== undefined) {
      this.releases.delete(offset);
      release();
    }
  }
}

class UpgradableFailurePagingTestLoader implements LibraryPageLoader<PagingTestItem> {
  loadCount: number = 0;
  private failFirstLoad?: () => void;

  load(offset: number, limit: number): Promise<Array<PagingTestItem>> {
    this.loadCount += 1;
    if (this.loadCount === 1) {
      return new Promise<Array<PagingTestItem>>((_resolve, reject) => {
        this.failFirstLoad = (): void => reject(new Error('expected first failure'));
      });
    }
    const items: Array<PagingTestItem> = [];
    for (let index = offset; index < offset + limit; index += 1) {
      const item = new PagingTestItem();
      item.id = index;
      items.push(item);
    }
    return Promise.resolve(items);
  }

  failFirst(): void {
    this.failFirstLoad?.();
    this.failFirstLoad = undefined;
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
  { label: 'A', startIndex: 0 },
  { label: 'B', startIndex: 2 },
  { label: 'Z', startIndex: 5 },
  { label: '#', startIndex: 8 }
];

const DESCENDING_SECTIONS: Array<LibrarySection> = [
  { label: 'Z', startIndex: 0 },
  { label: 'B', startIndex: 3 },
  { label: 'A', startIndex: 6 },
  { label: '#', startIndex: 9 }
];

function source(pageSize: number = 8, maxCachedPages: number = 5):
  PagedLibraryDataSource<PagingTestItem> {
  return new PagedLibraryDataSource<PagingTestItem>(
    pageSize,
    maxCachedPages,
    (item: PagingTestItem): string => `${item.id}`
  );
}

function expectInvalidSectionCatalog(sections: Array<LibrarySection>, totalCount: number): void {
  let rejected = false;
  try {
    LibrarySectionPagePlanner.plan({
      totalCount: totalCount,
      sections: sections,
      indexPresentation: LibraryIndexPresentation.ALPHABET
    }, 0, 8);
  } catch (_error) {
    rejected = true;
  }
  expect(rejected).assertTrue();
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

    it('maps detail List indexes after structural header sections', 0, () => {
      expect(DetailTrackListPagingPolicy.artistTrackDataStartIndex(false)).assertEqual(2);
      expect(DetailTrackListPagingPolicy.artistTrackDataStartIndex(true)).assertEqual(4);
      expect(DetailTrackListPagingPolicy.playlistTrackDataStartIndex()).assertEqual(1);

      expect(DetailTrackListPagingPolicy.visibleDataRange(0, 3, 4, 20) === undefined).assertTrue();
      const artistRange: DetailTrackVisibleRange =
        DetailTrackListPagingPolicy.visibleDataRange(2, 7, 4, 20)!;
      expect(artistRange.firstIndex).assertEqual(0);
      expect(artistRange.lastIndex).assertEqual(3);
      const tailRange: DetailTrackVisibleRange =
        DetailTrackListPagingPolicy.visibleDataRange(20, 40, 4, 22)!;
      expect(tailRange.firstIndex).assertEqual(16);
      expect(tailRange.lastIndex).assertEqual(21);
      const overscrollRange: DetailTrackVisibleRange =
        DetailTrackListPagingPolicy.visibleDataRange(40, 50, 4, 22)!;
      expect(overscrollRange.firstIndex).assertEqual(21);
      expect(overscrollRange.lastIndex).assertEqual(21);
      expect(DetailTrackListPagingPolicy.visibleDataRange(1, 5, 1, 0) === undefined).assertTrue();
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
      expect(ascending.sectionLocalOrderClause)
        .assertEqual('t.title_natural_key ASC, t.id ASC');

      const descending = LibrarySortPlan.album(AlbumSortField.ALBUM_ARTIST, SortDirection.DESCENDING);
      expect(descending.orderClause)
        .assertEqual("al.artist_section = '#' ASC, al.artist_natural_key DESC, al.id DESC");
      expect(descending.sectionOrderClause)
        .assertEqual("al.artist_section = '#' ASC, al.artist_section DESC");
      expect(descending.sectionLocalOrderClause)
        .assertEqual('al.artist_natural_key DESC, al.id DESC');
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

    it('plans a global page across ordered alphabet sections', 0, () => {
      const segments: Array<LibrarySectionPageSegment> = LibrarySectionPagePlanner.plan({
        totalCount: 12,
        sections: CHARACTERIZED_SECTIONS,
        indexPresentation: LibraryIndexPresentation.ALPHABET
      }, 1, 8);

      expect(segments.length).assertEqual(4);
      expect(segments[0].label).assertEqual('A');
      expect(segments[0].localOffset).assertEqual(1);
      expect(segments[0].limit).assertEqual(1);
      expect(segments[1].label).assertEqual('B');
      expect(segments[1].localOffset).assertEqual(0);
      expect(segments[1].limit).assertEqual(3);
      expect(segments[2].label).assertEqual('Z');
      expect(segments[2].localOffset).assertEqual(0);
      expect(segments[2].limit).assertEqual(3);
      expect(segments[3].label).assertEqual('#');
      expect(segments[3].localOffset).assertEqual(0);
      expect(segments[3].limit).assertEqual(1);
    });

    it('keeps the unknown section last for ascending and descending page plans', 0, () => {
      const ascending = LibrarySectionPagePlanner.plan({
        totalCount: 12,
        sections: CHARACTERIZED_SECTIONS,
        indexPresentation: LibraryIndexPresentation.ALPHABET
      }, 7, 4);
      expect(ascending.length).assertEqual(2);
      expect(ascending[0].label).assertEqual('Z');
      expect(ascending[0].localOffset).assertEqual(2);
      expect(ascending[0].limit).assertEqual(1);
      expect(ascending[1].label).assertEqual('#');
      expect(ascending[1].limit).assertEqual(3);

      const descending = LibrarySectionPagePlanner.plan({
        totalCount: 12,
        sections: DESCENDING_SECTIONS,
        indexPresentation: LibraryIndexPresentation.ALPHABET
      }, 8, 4);
      expect(descending.length).assertEqual(2);
      expect(descending[0].label).assertEqual('A');
      expect(descending[0].localOffset).assertEqual(2);
      expect(descending[0].limit).assertEqual(1);
      expect(descending[1].label).assertEqual('#');
      expect(descending[1].limit).assertEqual(3);
    });

    it('bounds section page plans at exact boundaries and the catalog end', 0, () => {
      const catalog: LibraryCatalog = {
        totalCount: 12,
        sections: CHARACTERIZED_SECTIONS,
        indexPresentation: LibraryIndexPresentation.ALPHABET
      };
      const exact: Array<LibrarySectionPageSegment> =
        LibrarySectionPagePlanner.plan(catalog, 5, 3);
      expect(exact.length).assertEqual(1);
      expect(exact[0].label).assertEqual('Z');
      expect(exact[0].localOffset).assertEqual(0);
      expect(exact[0].limit).assertEqual(3);

      const tail: Array<LibrarySectionPageSegment> =
        LibrarySectionPagePlanner.plan(catalog, 10, 8);
      expect(tail.length).assertEqual(1);
      expect(tail[0].label).assertEqual('#');
      expect(tail[0].localOffset).assertEqual(2);
      expect(tail[0].limit).assertEqual(2);
      expect(LibrarySectionPagePlanner.plan(catalog, 12, 8).length).assertEqual(0);
    });

    it('rejects inconsistent alphabet section catalogs', 0, () => {
      expectInvalidSectionCatalog([], -1);
      expectInvalidSectionCatalog([], 1.5);
      expectInvalidSectionCatalog([], Number.POSITIVE_INFINITY);
      expectInvalidSectionCatalog([], Number.NaN);
      expectInvalidSectionCatalog([], 3);
      expectInvalidSectionCatalog([{ label: 'A', startIndex: 1 }], 3);
      expectInvalidSectionCatalog([
        { label: 'A', startIndex: 0 },
        { label: 'B', startIndex: 2 },
        { label: 'C', startIndex: 2 }
      ], 4);
      expectInvalidSectionCatalog([
        { label: 'A', startIndex: 0 },
        { label: 'B', startIndex: 3 },
        { label: 'C', startIndex: 2 }
      ], 4);
      expectInvalidSectionCatalog([
        { label: 'A', startIndex: 0 },
        { label: 'B', startIndex: 4 }
      ], 4);
      expectInvalidSectionCatalog([
        { label: 'A', startIndex: 0 },
        { label: 'B', startIndex: 1.5 }
      ], 4);
      expectInvalidSectionCatalog([
        { label: 'A', startIndex: 0 },
        { label: 'B', startIndex: Number.POSITIVE_INFINITY }
      ], 4);
      expectInvalidSectionCatalog([
        { label: 'A', startIndex: 0 },
        { label: 'B', startIndex: Number.NaN }
      ], 4);
      expectInvalidSectionCatalog([{ label: '#', startIndex: 0 }], 0);
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

    it('bounds concurrency and starts the latest visible window before stale queued pages', 0, async () => {
      const loader = new ControlledPagingTestLoader();
      const dataSource = source(4, 5);
      dataSource.reset(100, loader);

      const staleRange = dataSource.ensureRange(0, 15, 0);
      expect(loader.startedOffsets.length).assertEqual(2);
      expect(loader.startedOffsets[0]).assertEqual(0);
      expect(loader.startedOffsets[1]).assertEqual(4);

      const latestRange = dataSource.ensureRange(40, 47, 40);
      loader.release(0);
      await new Promise<void>((resolve) => setTimeout(resolve, 0));
      expect(loader.startedOffsets[2]).assertEqual(40);

      loader.release(4);
      await new Promise<void>((resolve) => setTimeout(resolve, 0));
      expect(loader.startedOffsets[3]).assertEqual(44);
      expect(loader.startedOffsets.includes(8)).assertFalse();
      expect(loader.startedOffsets.includes(12)).assertFalse();
      expect(loader.maxActiveLoads).assertEqual(2);

      loader.release(40);
      loader.release(44);
      await Promise.all([staleRange, latestRange]);
      expect(dataSource.getData(40).value !== undefined).assertTrue();
    });

    it('retries an opportunistic request after the latest visible range upgrades it', 0, async () => {
      const loader = new UpgradableFailurePagingTestLoader();
      const dataSource = source();
      dataSource.reset(20, loader);

      dataSource.getData(0);
      const visibleLoad = dataSource.ensureRange(0, 0);
      loader.failFirst();
      await visibleLoad;

      expect(loader.loadCount).assertEqual(2);
      expect(dataSource.getData(0).value !== undefined).assertTrue();
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

    it('clears the loader and discards page completion after detail disposal', 0, async () => {
      const slowLoader = new PagingTestLoader();
      slowLoader.delayMs = 10;
      const dataSource = source();
      const listener = new RecordingDataChangeListener();
      dataSource.registerDataChangeListener(listener);
      dataSource.reset(100, slowLoader);
      const staleLoad = dataSource.ensureRange(0, 0);

      dataSource.clear();
      await staleLoad;

      expect(dataSource.totalCount()).assertEqual(0);
      expect(dataSource.cachedPageCount()).assertEqual(0);
      expect(listener.notifications).assertEqual(2);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);
    });

    it('invalidates cached detail pages immediately while retaining virtual slots', 0, async () => {
      const staleLoader = new PagingTestLoader();
      staleLoader.delayMs = 10;
      const dataSource = source();
      dataSource.reset(100, staleLoader);
      const staleLoad = dataSource.ensureRange(0, 0);

      dataSource.invalidatePages();
      await staleLoad;

      expect(dataSource.totalCount()).assertEqual(100);
      expect(dataSource.cachedPageCount()).assertEqual(0);
      expect(dataSource.getData(0).value === undefined).assertTrue();
      await dataSource.ensureRange(0, 0);
      expect(dataSource.getData(0).value !== undefined).assertTrue();
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
