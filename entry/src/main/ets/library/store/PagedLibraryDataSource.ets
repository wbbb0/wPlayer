import { LibraryPagingPolicy } from './LibraryPagingPolicy';

export interface LibrarySlot<T> {
  index: number;
  generation: number;
  key: string;
  value?: T;
}

export interface LibraryPageLoader<T> {
  load(offset: number, limit: number): Promise<Array<T>>;
}

export type LibraryItemKey<T> = (item: T) => string;

/**
 * Stable LazyForEach data source backed by bounded, asynchronously loaded pages.
 * Reset invalidates all outstanding completions and emits one logical reload.
 */
export class PagedLibraryDataSource<T> implements IDataSource {
  private static readonly EXPLICIT_LOAD_ATTEMPTS: number = 2;
  private readonly pageSize: number;
  private readonly maxCachedPages: number;
  private readonly itemKey: LibraryItemKey<T>;
  private readonly listeners: Array<DataChangeListener> = [];
  private readonly pages: Map<number, Array<T>> = new Map<number, Array<T>>();
  private readonly pageAccess: Map<number, number> = new Map<number, number>();
  private readonly inflight: Map<number, Promise<void>> = new Map<number, Promise<void>>();
  private readonly pageRequestSerials: Map<number, number> = new Map<number, number>();
  private readonly failedPages: Set<number> = new Set<number>();
  private itemCount: number = 0;
  private loader?: LibraryPageLoader<T>;
  private generation: number = 0;
  private requestSerial: number = 0;
  private accessSerial: number = 0;
  private protectedStart: number = 0;
  private protectedEnd: number = -1;

  constructor(pageSize: number, maxCachedPages: number, itemKey: LibraryItemKey<T>) {
    this.pageSize = Math.max(1, Math.floor(pageSize));
    this.maxCachedPages = Math.max(3, Math.floor(maxCachedPages));
    this.itemKey = itemKey;
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
          key: `${this.generation}:item:${this.itemKey(value)}`,
          value: value
        };
      }
    } else if (!this.failedPages.has(pageStart)) {
      this.startPageRequest(pageStart);
    }
    return {
      index: normalizedIndex,
      generation: this.generation,
      key: `${this.generation}:slot:${normalizedIndex}`
    };
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
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
    this.itemCount = Math.max(0, Math.floor(itemCount));
    this.loader = loader;
    this.pages.clear();
    this.pageAccess.clear();
    this.inflight.clear();
    this.pageRequestSerials.clear();
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
    for (let pageStart = this.protectedStart; pageStart <= this.protectedEnd; pageStart += this.pageSize) {
      requests.push(this.requestPageWithRetry(pageStart));
    }
    await Promise.all(requests);
  }

  cachedPageCount(): number {
    return this.pages.size;
  }

  private startPageRequest(pageStart: number): void {
    this.requestPage(pageStart, false).catch((error: Object): void => {
      console.warn(`Unable to load library page at ${pageStart}: ${PagedLibraryDataSource.messageOf(error)}`);
    });
  }

  private async requestPageWithRetry(pageStart: number): Promise<void> {
    let lastError: Error | undefined;
    for (let attempt = 0; attempt < PagedLibraryDataSource.EXPLICIT_LOAD_ATTEMPTS; attempt += 1) {
      try {
        await this.requestPage(pageStart, true);
        return;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(`${error}`);
      }
    }
    throw lastError ?? new Error(`Unable to load library page at ${pageStart}`);
  }

  private async requestPage(pageStart: number, retryFailed: boolean): Promise<void> {
    if (this.pages.has(pageStart) || this.loader === undefined) {
      return;
    }
    const existing = this.inflight.get(pageStart);
    if (existing !== undefined) {
      await existing;
      return;
    }
    if (this.failedPages.has(pageStart) && !retryFailed) {
      return;
    }
    if (retryFailed) {
      this.failedPages.delete(pageStart);
    }
    const requestGeneration = this.generation;
    const requestSerial = ++this.requestSerial;
    this.pageRequestSerials.set(pageStart, requestSerial);
    const request = this.loadPage(pageStart, requestGeneration, requestSerial);
    this.inflight.set(pageStart, request);
    try {
      await request;
    } finally {
      if (this.inflight.get(pageStart) === request) {
        this.inflight.delete(pageStart);
      }
    }
  }

  private async loadPage(pageStart: number, requestGeneration: number,
    requestSerial: number): Promise<void> {
    const loader = this.loader;
    if (loader === undefined) {
      return;
    }
    try {
      const items = await loader.load(pageStart, this.pageSize);
      if (requestGeneration !== this.generation ||
        this.pageRequestSerials.get(pageStart) !== requestSerial) {
        return;
      }
      this.pages.set(pageStart, items);
      this.markAccessed(pageStart);
      const changedCount = Math.min(items.length, Math.max(0, this.itemCount - pageStart));
      const changes: Array<DataOperation> = [];
      for (let offset = 0; offset < changedCount; offset += 1) {
        const item = items[offset];
        changes.push({
          type: DataOperationType.CHANGE,
          index: pageStart + offset,
          key: `${this.generation}:item:${this.itemKey(item)}`
        });
      }
      if (changes.length > 0) {
        this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(changes));
      }
      this.evictUnusedPages();
    } catch (error) {
      if (requestGeneration !== this.generation ||
        this.pageRequestSerials.get(pageStart) !== requestSerial) {
        return;
      }
      this.failedPages.add(pageStart);
      throw error instanceof Error ? error : new Error(`${error}`);
    }
  }

  private markAccessed(pageStart: number): void {
    this.pageAccess.set(pageStart, ++this.accessSerial);
  }

  private evictUnusedPages(): void {
    while (this.pages.size > this.maxCachedPages) {
      let oldestPage = -1;
      let oldestAccess = Number.MAX_SAFE_INTEGER;
      this.pageAccess.forEach((access: number, pageStart: number): void => {
        const protectedPage = this.protectedEnd >= this.protectedStart &&
          pageStart >= this.protectedStart - this.pageSize &&
          pageStart <= this.protectedEnd + this.pageSize;
        if (!protectedPage && access < oldestAccess) {
          oldestAccess = access;
          oldestPage = pageStart;
        }
      });
      if (oldestPage < 0) {
        this.pageAccess.forEach((access: number, pageStart: number): void => {
          if (access < oldestAccess) {
            oldestAccess = access;
            oldestPage = pageStart;
          }
        });
      }
      if (oldestPage < 0) {
        return;
      }
      this.pages.delete(oldestPage);
      this.pageAccess.delete(oldestPage);
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
