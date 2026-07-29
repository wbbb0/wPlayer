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

class LibraryQueuedPageRequest {
  readonly pageStart: number;
  readonly generation: number;
  readonly completion: Promise<void>;
  demandSerial: number;
  priority: number;
  retryFailed: boolean;
  private resolveCompletion?: () => void;
  private rejectCompletion?: (error: Error) => void;
  private settled: boolean = false;

  constructor(pageStart: number, generation: number, demandSerial: number,
    priority: number, retryFailed: boolean) {
    this.pageStart = pageStart;
    this.generation = generation;
    this.demandSerial = demandSerial;
    this.priority = priority;
    this.retryFailed = retryFailed;
    this.completion = new Promise<void>((resolve, reject) => {
      this.resolveCompletion = resolve;
      this.rejectCompletion = reject;
    });
  }

  resolve(): void {
    if (!this.settled) {
      this.settled = true;
      this.resolveCompletion?.();
    }
  }

  reject(error: Error): void {
    if (!this.settled) {
      this.settled = true;
      this.rejectCompletion?.(error);
    }
  }
}

/**
 * Stable LazyForEach data source backed by bounded, asynchronously loaded pages.
 * Reset invalidates all outstanding completions and emits one logical reload.
 */
export class PagedLibraryDataSource<T> implements IDataSource {
  private static readonly EXPLICIT_LOAD_ATTEMPTS: number = 2;
  private static readonly MAX_CONCURRENT_PAGE_LOADS: number = 2;
  private static readonly OPPORTUNISTIC_PRIORITY: number = 1000000;
  private readonly pageSize: number;
  private readonly maxCachedPages: number;
  private readonly itemKey: LibraryItemKey<T>;
  private readonly listeners: Array<DataChangeListener> = [];
  private readonly pages: Map<number, Array<T>> = new Map<number, Array<T>>();
  private readonly pageAccess: Map<number, number> = new Map<number, number>();
  private readonly inflight: Map<number, LibraryQueuedPageRequest> =
    new Map<number, LibraryQueuedPageRequest>();
  private readonly queued: Map<number, LibraryQueuedPageRequest> =
    new Map<number, LibraryQueuedPageRequest>();
  private readonly failedPages: Set<number> = new Set<number>();
  private readonly latestDemandPages: Set<number> = new Set<number>();
  private itemCount: number = 0;
  private loader?: LibraryPageLoader<T>;
  private generation: number = 0;
  private demandSerial: number = 0;
  private accessSerial: number = 0;
  private activeLoads: number = 0;
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
    this.resolveQueuedRequests();
    this.inflight.clear();
    this.failedPages.clear();
    this.latestDemandPages.clear();
    this.demandSerial += 1;
    this.protectedStart = 0;
    this.protectedEnd = -1;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange([
      { type: DataOperationType.RELOAD }
    ]));
  }

  clear(): void {
    this.generation += 1;
    this.itemCount = 0;
    this.loader = undefined;
    this.pages.clear();
    this.pageAccess.clear();
    this.resolveQueuedRequests();
    this.inflight.clear();
    this.failedPages.clear();
    this.latestDemandPages.clear();
    this.demandSerial += 1;
    this.protectedStart = 0;
    this.protectedEnd = -1;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange([
      { type: DataOperationType.RELOAD }
    ]));
  }

  invalidatePages(): void {
    if (this.loader === undefined) {
      this.clear();
      return;
    }
    this.generation += 1;
    this.pages.clear();
    this.pageAccess.clear();
    this.resolveQueuedRequests();
    this.inflight.clear();
    this.failedPages.clear();
    this.latestDemandPages.clear();
    this.demandSerial += 1;
    this.protectedStart = 0;
    this.protectedEnd = -1;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange([
      { type: DataOperationType.RELOAD }
    ]));
  }

  async ensureRange(firstIndex: number, lastIndex: number,
    preferredIndex: number = firstIndex): Promise<void> {
    if (this.itemCount === 0 || this.loader === undefined) {
      return;
    }
    const first = Math.max(0, Math.min(firstIndex, this.itemCount - 1));
    const last = Math.max(first, Math.min(lastIndex, this.itemCount - 1));
    this.protectedStart = LibraryPagingPolicy.pageStartForIndex(first, this.pageSize);
    this.protectedEnd = LibraryPagingPolicy.pageStartForIndex(last, this.pageSize);
    const preferred = Math.max(first, Math.min(preferredIndex, last));
    const preferredPage = LibraryPagingPolicy.pageStartForIndex(preferred, this.pageSize);
    const currentDemandSerial = ++this.demandSerial;
    this.latestDemandPages.clear();
    for (let pageStart = this.protectedStart;
      pageStart <= this.protectedEnd; pageStart += this.pageSize) {
      this.latestDemandPages.add(pageStart);
    }
    this.discardSupersededQueuedRequests();
    const requests: Array<Promise<void>> = [];
    const orderedPages: Array<number> = Array.from(this.latestDemandPages);
    orderedPages.sort((left: number, right: number): number => {
      const distance = Math.abs(left - preferredPage) - Math.abs(right - preferredPage);
      return distance !== 0 ? distance : left - right;
    });
    for (let index = 0; index < orderedPages.length; index += 1) {
      requests.push(this.enqueuePageRequest(
        orderedPages[index],
        currentDemandSerial,
        index,
        true
      ));
    }
    await Promise.all(requests);
  }

  cachedPageCount(): number {
    return this.pages.size;
  }

  private startPageRequest(pageStart: number): void {
    this.enqueuePageRequest(
      pageStart,
      0,
      PagedLibraryDataSource.OPPORTUNISTIC_PRIORITY,
      false
    ).catch((error: Object): void => {
      console.warn(`Unable to load library page at ${pageStart}: ${PagedLibraryDataSource.messageOf(error)}`);
    });
  }

  private enqueuePageRequest(pageStart: number, demandSerial: number,
    priority: number, retryFailed: boolean): Promise<void> {
    if (this.pages.has(pageStart) || this.loader === undefined) {
      return Promise.resolve();
    }
    const existing = this.inflight.get(pageStart);
    if (existing !== undefined) {
      if (demandSerial > existing.demandSerial) {
        existing.demandSerial = demandSerial;
      }
      existing.priority = Math.min(existing.priority, priority);
      existing.retryFailed = existing.retryFailed || retryFailed;
      if (retryFailed) {
        this.failedPages.delete(pageStart);
      }
      return existing.completion;
    }
    const queued = this.queued.get(pageStart);
    if (queued !== undefined) {
      if (demandSerial > queued.demandSerial) {
        queued.demandSerial = demandSerial;
      }
      queued.priority = Math.min(queued.priority, priority);
      queued.retryFailed = queued.retryFailed || retryFailed;
      if (retryFailed) {
        this.failedPages.delete(pageStart);
      }
      this.pumpQueue();
      return queued.completion;
    }
    if (this.failedPages.has(pageStart) && !retryFailed) {
      return Promise.resolve();
    }
    if (retryFailed) {
      this.failedPages.delete(pageStart);
    }
    const request = new LibraryQueuedPageRequest(
      pageStart,
      this.generation,
      demandSerial,
      priority,
      retryFailed
    );
    this.queued.set(pageStart, request);
    this.pumpQueue();
    return request.completion;
  }

  private pumpQueue(): void {
    while (this.activeLoads < PagedLibraryDataSource.MAX_CONCURRENT_PAGE_LOADS &&
      this.queued.size > 0) {
      const request = this.takeNextQueuedRequest();
      if (request === undefined) {
        return;
      }
      this.queued.delete(request.pageStart);
      this.activeLoads += 1;
      this.inflight.set(request.pageStart, request);
      this.runQueuedRequest(request);
    }
  }

  private takeNextQueuedRequest(): LibraryQueuedPageRequest | undefined {
    let selected: LibraryQueuedPageRequest | undefined;
    this.queued.forEach((request: LibraryQueuedPageRequest): void => {
      if (selected === undefined || request.demandSerial > selected.demandSerial ||
        (request.demandSerial === selected.demandSerial && request.priority < selected.priority)) {
        selected = request;
      }
    });
    return selected;
  }

  private async runQueuedRequest(request: LibraryQueuedPageRequest): Promise<void> {
    let lastError: Error | undefined;
    try {
      for (let attempt = 0;
        attempt < PagedLibraryDataSource.EXPLICIT_LOAD_ATTEMPTS; attempt += 1) {
        try {
          await this.loadPage(request.pageStart, request.generation);
          request.resolve();
          return;
        } catch (error) {
          lastError = error instanceof Error ? error : new Error(`${error}`);
          const stillLatest = request.generation === this.generation &&
            request.demandSerial === this.demandSerial &&
            this.latestDemandPages.has(request.pageStart);
          if (attempt + 1 >= PagedLibraryDataSource.EXPLICIT_LOAD_ATTEMPTS ||
            !request.retryFailed || !stillLatest) {
            break;
          }
        }
      }
      const supersededDemand = request.retryFailed &&
        (request.demandSerial !== this.demandSerial ||
          !this.latestDemandPages.has(request.pageStart));
      if (supersededDemand) {
        request.resolve();
        return;
      }
      if (request.generation === this.generation) {
        this.failedPages.add(request.pageStart);
      }
      request.reject(lastError ?? new Error(`Unable to load library page at ${request.pageStart}`));
    } finally {
      if (this.inflight.get(request.pageStart) === request) {
        this.inflight.delete(request.pageStart);
      }
      this.activeLoads = Math.max(0, this.activeLoads - 1);
      this.pumpQueue();
    }
  }

  private async loadPage(pageStart: number, requestGeneration: number): Promise<void> {
    const loader = this.loader;
    if (loader === undefined) {
      return;
    }
    try {
      const items = await loader.load(pageStart, this.pageSize);
      if (requestGeneration !== this.generation) {
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
      if (requestGeneration !== this.generation) {
        return;
      }
      throw error instanceof Error ? error : new Error(`${error}`);
    }
  }

  private discardSupersededQueuedRequests(): void {
    const discarded: Array<number> = [];
    this.queued.forEach((request: LibraryQueuedPageRequest, pageStart: number): void => {
      if (!this.latestDemandPages.has(pageStart)) {
        request.resolve();
        discarded.push(pageStart);
      }
    });
    discarded.forEach((pageStart: number): void => {
      this.queued.delete(pageStart);
    });
  }

  private resolveQueuedRequests(): void {
    this.queued.forEach((request: LibraryQueuedPageRequest): void => request.resolve());
    this.queued.clear();
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
