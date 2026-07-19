import { LibraryPagingPolicy } from './LibraryPagingPolicy';

export interface LibrarySlot<T> {
  index: number;
  generation: number;
  revision: number;
  value?: T;
}

export interface LibraryPageLoader<T> {
  load(offset: number, limit: number): Promise<Array<T>>;
}

/**
 * Stable LazyForEach data source backed by bounded, asynchronously loaded pages.
 * The object identity stays stable across sort and library refreshes.
 */
export class PagedLibraryDataSource<T> implements IDataSource {
  private readonly pageSize: number;
  private readonly maxCachedPages: number;
  private readonly listeners: Array<DataChangeListener> = [];
  private readonly pages: Map<number, Array<T>> = new Map<number, Array<T>>();
  private readonly pageRevisions: Map<number, number> = new Map<number, number>();
  private readonly pageAccess: Map<number, number> = new Map<number, number>();
  private readonly inflightSerials: Map<number, number> = new Map<number, number>();
  private readonly failedPages: Map<number, boolean> = new Map<number, boolean>();
  private itemCount: number = 0;
  private loader?: LibraryPageLoader<T>;
  private generation: number = 0;
  private requestSerial: number = 0;
  private revisionSerial: number = 0;
  private accessSerial: number = 0;
  private protectedStart: number = 0;
  private protectedEnd: number = -1;

  constructor(pageSize: number, maxCachedPages: number = 6) {
    this.pageSize = Math.max(1, pageSize);
    this.maxCachedPages = Math.max(2, maxCachedPages);
  }

  totalCount(): number {
    return this.itemCount;
  }

  getData(index: number): LibrarySlot<T> {
    const normalizedIndex = Math.max(0, Math.min(index, Math.max(0, this.itemCount - 1)));
    const pageStart = LibraryPagingPolicy.pageStartForIndex(normalizedIndex, this.pageSize);
    const page = this.pages.get(pageStart);
    if (page !== undefined) {
      this.markAccessed(pageStart);
      const value = page[normalizedIndex - pageStart];
      if (value !== undefined) {
        return {
          index: normalizedIndex,
          generation: this.generation,
          revision: this.pageRevisions.get(pageStart) ?? 0,
          value: value
        };
      }
    } else if (!this.failedPages.has(pageStart)) {
      this.startPageRequest(pageStart, false);
    }
    return { index: normalizedIndex, generation: this.generation, revision: 0 };
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  reset(itemCount: number, loader: LibraryPageLoader<T>): void {
    this.generation += 1;
    this.itemCount = Math.max(0, itemCount);
    this.loader = loader;
    this.pages.clear();
    this.pageRevisions.clear();
    this.pageAccess.clear();
    this.inflightSerials.clear();
    this.failedPages.clear();
    this.protectedStart = 0;
    this.protectedEnd = -1;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange([
      { type: DataOperationType.RELOAD }
    ]));
  }

  async ensureRange(firstIndex: number, lastIndex: number): Promise<void> {
    if (this.itemCount === 0 || this.loader === undefined) {
      return;
    }
    const first = Math.max(0, Math.min(firstIndex, this.itemCount - 1));
    const last = Math.max(first, Math.min(lastIndex, this.itemCount - 1));
    this.protectedStart = LibraryPagingPolicy.pageStartForIndex(first, this.pageSize);
    this.protectedEnd = LibraryPagingPolicy.pageStartForIndex(last, this.pageSize);
    const requests: Array<Promise<void>> = [];
    let pageStart = this.protectedStart;
    while (pageStart <= this.protectedEnd) {
      requests.push(this.requestPage(pageStart, true));
      pageStart += this.pageSize;
    }
    await Promise.all(requests);
  }

  private startPageRequest(pageStart: number, retryFailed: boolean): void {
    this.requestPage(pageStart, retryFailed).catch((_error: Object) => {
      // A placeholder remains visible. ensureRange or a later explicit jump retries it.
    });
  }

  private async requestPage(pageStart: number, retryFailed: boolean): Promise<void> {
    if (this.pages.has(pageStart) || this.inflightSerials.has(pageStart) || this.loader === undefined) {
      return;
    }
    if (this.failedPages.has(pageStart) && !retryFailed) {
      return;
    }
    if (retryFailed) {
      this.failedPages.delete(pageStart);
    }
    const requestGeneration = this.generation;
    const serial = ++this.requestSerial;
    const loader = this.loader;
    this.inflightSerials.set(pageStart, serial);
    try {
      const items = await loader.load(pageStart, this.pageSize);
      if (requestGeneration !== this.generation || this.inflightSerials.get(pageStart) !== serial) {
        return;
      }
      this.pages.set(pageStart, items);
      this.pageRevisions.set(pageStart, ++this.revisionSerial);
      this.markAccessed(pageStart);
      const changedCount = Math.min(items.length, Math.max(0, this.itemCount - pageStart));
      const revision = this.pageRevisions.get(pageStart) ?? 0;
      const changes: Array<DataOperation> = [];
      for (let offset = 0; offset < changedCount; offset += 1) {
        const index = pageStart + offset;
        changes.push({
          type: DataOperationType.CHANGE,
          index: index,
          key: `${this.generation}:${index}:${revision}`
        });
      }
      if (changes.length > 0) {
        this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(changes));
      }
      this.evictUnusedPages();
    } catch (_error) {
      if (requestGeneration === this.generation && this.inflightSerials.get(pageStart) === serial) {
        this.failedPages.set(pageStart, true);
      }
    } finally {
      if (requestGeneration === this.generation && this.inflightSerials.get(pageStart) === serial) {
        this.inflightSerials.delete(pageStart);
      }
    }
  }

  private markAccessed(pageStart: number): void {
    this.pageAccess.set(pageStart, ++this.accessSerial);
  }

  private evictUnusedPages(): void {
    while (this.pages.size > this.maxCachedPages) {
      let oldestPage = -1;
      let oldestAccess = Number.MAX_SAFE_INTEGER;
      this.pageAccess.forEach((access: number, pageStart: number) => {
        const protectedPage = this.protectedEnd >= this.protectedStart &&
          pageStart >= this.protectedStart - this.pageSize && pageStart <= this.protectedEnd + this.pageSize;
        if (!protectedPage && access < oldestAccess) {
          oldestAccess = access;
          oldestPage = pageStart;
        }
      });
      if (oldestPage < 0) {
        return;
      }
      this.pages.delete(oldestPage);
      this.pageRevisions.delete(oldestPage);
      this.pageAccess.delete(oldestPage);
    }
  }
}
