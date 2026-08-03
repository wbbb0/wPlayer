import { AlbumListItem, TrackListItem } from '../model/LibraryModels';
import { LibraryStore } from './LibraryStore';
import { LibraryPageLoader, PagedLibraryDataSource } from './PagedLibraryDataSource';
import { LibraryPagingPolicy } from './LibraryPagingPolicy';

export enum TrackCollectionScope {
  ARTIST = 0,
  GENRE = 1
}

class TrackCollectionPageLoader implements LibraryPageLoader<TrackListItem> {
  private readonly store: LibraryStore;
  private readonly scope: TrackCollectionScope;
  private readonly ownerId: number;

  constructor(store: LibraryStore, scope: TrackCollectionScope, ownerId: number) {
    this.store = store;
    this.scope = scope;
    this.ownerId = ownerId;
  }

  load(offset: number, limit: number): Promise<Array<TrackListItem>> {
    return this.scope === TrackCollectionScope.ARTIST ?
      this.store.getArtistTrackPage(this.ownerId, offset, limit) :
      this.store.getGenreTrackPage(this.ownerId, offset, limit);
  }
}

export enum AlbumCollectionScope {
  ARTIST = 0,
  RELATED = 1
}

class AlbumCollectionPageLoader implements LibraryPageLoader<AlbumListItem> {
  private readonly store: LibraryStore;
  private readonly scope: AlbumCollectionScope;
  private readonly ownerId: number;

  constructor(store: LibraryStore, scope: AlbumCollectionScope, ownerId: number) {
    this.store = store;
    this.scope = scope;
    this.ownerId = ownerId;
  }

  load(offset: number, limit: number): Promise<Array<AlbumListItem>> {
    return this.scope === AlbumCollectionScope.ARTIST ?
      this.store.getArtistAlbumPage(this.ownerId, offset, limit) :
      this.store.getRelatedAlbumPage(this.ownerId, offset, limit);
  }
}

@Observed
export class LibraryTrackCollectionState {
  readonly scope: TrackCollectionScope;
  readonly ownerId: number;
  totalCount: number = 0;
  loading: boolean = false;
  error: string = '';
  readonly dataSource: PagedLibraryDataSource<TrackListItem> =
    new PagedLibraryDataSource<TrackListItem>(
      LibraryPagingPolicy.TRACK_QUERY_PAGE_SIZE,
      LibraryPagingPolicy.MAX_CACHED_PAGES,
      (item: TrackListItem): string => `${item.id}`
    );
  private loadEpoch: number = 0;
  private loadedContentRevision: number = -1;
  private loadingContentRevision: number = -1;
  private refreshPending: boolean = false;
  private activeStore?: LibraryStore;
  private readonly contentChangeListener: () => void = (): void => {
    const store = this.activeStore;
    if (store === undefined) {
      return;
    }
    if (this.loading) {
      this.refreshPending = true;
      return;
    }
    this.refresh(store).catch((error: Object): void => {
      console.warn(`Unable to refresh track collection ${this.ownerId}: ${this.messageOf(error)}`);
    });
  };

  constructor(scope: TrackCollectionScope, ownerId: number) {
    this.scope = scope;
    this.ownerId = ownerId;
  }

  async activate(store: LibraryStore): Promise<void> {
    if (this.activeStore !== store) {
      this.activeStore?.removeContentChangeListener(this.contentChangeListener);
      this.activeStore = store;
      store.addContentChangeListener(this.contentChangeListener);
    }
    if (this.loadedContentRevision === store.libraryContentRevision) {
      return;
    }
    if (this.loading) {
      if (this.loadingContentRevision !== store.libraryContentRevision) {
        this.refreshPending = true;
      }
      return;
    }
    await this.loadInternal(store);
  }

  deactivate(store: LibraryStore): void {
    if (this.activeStore === store) {
      store.removeContentChangeListener(this.contentChangeListener);
      this.activeStore = undefined;
      this.refreshPending = false;
    }
  }

  refresh(store: LibraryStore): Promise<void> {
    return this.loadInternal(store);
  }

  ensureRange(firstIndex: number, lastIndex: number): Promise<void> {
    const start = LibraryPagingPolicy.prefetchStartForVisibleRange(
      firstIndex, LibraryPagingPolicy.TRACK_QUERY_PAGE_SIZE
    );
    const end = LibraryPagingPolicy.prefetchEndForVisibleRange(
      lastIndex, LibraryPagingPolicy.TRACK_QUERY_PAGE_SIZE
    );
    return this.dataSource.ensureRange(start, end, firstIndex);
  }

  async loadSnapshot(store: LibraryStore): Promise<Array<TrackListItem>> {
    const epoch = this.loadEpoch;
    const expectedCount = this.totalCount;
    const items = this.scope === TrackCollectionScope.ARTIST ?
      await store.loadArtistTrackPlaybackOrder(this.ownerId, expectedCount) :
      await store.loadGenreTrackPlaybackOrder(this.ownerId, expectedCount);
    if (epoch !== this.loadEpoch || this.activeStore !== store ||
      this.loadedContentRevision !== store.libraryContentRevision) {
      throw new Error('歌曲集合已更新，请重试');
    }
    return items;
  }

  private async loadInternal(store: LibraryStore): Promise<void> {
    if (this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    const contentRevision = store.libraryContentRevision;
    this.loadingContentRevision = contentRevision;
    this.loading = true;
    this.error = '';
    try {
      const count = this.scope === TrackCollectionScope.ARTIST ?
        await store.getArtistTrackCount(this.ownerId) : await store.getGenreTrackCount(this.ownerId);
      if (epoch !== this.loadEpoch) {
        return;
      }
      this.totalCount = count;
      this.loadedContentRevision = contentRevision;
      this.dataSource.reset(count, new TrackCollectionPageLoader(store, this.scope, this.ownerId));
      await this.dataSource.ensureRange(
        0, LibraryPagingPolicy.initialPrefetchLastIndex(LibraryPagingPolicy.TRACK_QUERY_PAGE_SIZE)
      );
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.loadedContentRevision = -1;
        this.error = this.messageOf(error);
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
        this.loadingContentRevision = -1;
        this.continuePendingRefresh(store);
      }
    }
  }

  private continuePendingRefresh(store: LibraryStore): void {
    if (this.refreshPending && this.activeStore === store) {
      this.refreshPending = false;
      this.refresh(store).catch((error: Object): void => {
        console.warn(`Unable to continue track collection refresh: ${this.messageOf(error)}`);
      });
    }
  }

  private messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}

export class ArtistTrackCollectionState extends LibraryTrackCollectionState {
  constructor(artistId: number) {
    super(TrackCollectionScope.ARTIST, artistId);
  }
}

export class GenreTrackCollectionState extends LibraryTrackCollectionState {
  constructor(genreId: number) {
    super(TrackCollectionScope.GENRE, genreId);
  }
}

@Observed
export class AlbumCollectionState {
  readonly scope: AlbumCollectionScope;
  readonly ownerId: number;
  totalCount: number = 0;
  loading: boolean = false;
  error: string = '';
  readonly dataSource: PagedLibraryDataSource<AlbumListItem> =
    new PagedLibraryDataSource<AlbumListItem>(
      LibraryPagingPolicy.ALBUM_QUERY_PAGE_SIZE,
      LibraryPagingPolicy.MAX_CACHED_PAGES,
      (item: AlbumListItem): string => `${item.id}`
    );
  private loadEpoch: number = 0;
  private loadedContentRevision: number = -1;
  private loadingContentRevision: number = -1;
  private refreshPending: boolean = false;
  private activeStore?: LibraryStore;
  private readonly contentChangeListener: () => void = (): void => {
    const store = this.activeStore;
    if (store === undefined) {
      return;
    }
    if (this.loading) {
      this.refreshPending = true;
      return;
    }
    this.refresh(store).catch((error: Object): void => {
      console.warn(`Unable to refresh album collection ${this.ownerId}: ${this.messageOf(error)}`);
    });
  };

  constructor(scope: AlbumCollectionScope, ownerId: number) {
    this.scope = scope;
    this.ownerId = ownerId;
  }

  async activate(store: LibraryStore): Promise<void> {
    if (this.activeStore !== store) {
      this.activeStore?.removeContentChangeListener(this.contentChangeListener);
      this.activeStore = store;
      store.addContentChangeListener(this.contentChangeListener);
    }
    if (this.loadedContentRevision === store.libraryContentRevision) {
      return;
    }
    if (this.loading) {
      if (this.loadingContentRevision !== store.libraryContentRevision) {
        this.refreshPending = true;
      }
      return;
    }
    await this.loadInternal(store);
  }

  deactivate(store: LibraryStore): void {
    if (this.activeStore === store) {
      store.removeContentChangeListener(this.contentChangeListener);
      this.activeStore = undefined;
      this.refreshPending = false;
    }
  }

  refresh(store: LibraryStore): Promise<void> {
    return this.loadInternal(store);
  }

  ensureRange(firstIndex: number, lastIndex: number): Promise<void> {
    const start = LibraryPagingPolicy.prefetchStartForVisibleRange(
      firstIndex, LibraryPagingPolicy.ALBUM_QUERY_PAGE_SIZE
    );
    const end = LibraryPagingPolicy.prefetchEndForVisibleRange(
      lastIndex, LibraryPagingPolicy.ALBUM_QUERY_PAGE_SIZE
    );
    return this.dataSource.ensureRange(start, end, firstIndex);
  }

  async loadSnapshot(store: LibraryStore): Promise<Array<AlbumListItem>> {
    const epoch = this.loadEpoch;
    const expectedCount = this.totalCount;
    const items = this.scope === AlbumCollectionScope.ARTIST ?
      await store.loadArtistAlbumSelectionOrder(this.ownerId, expectedCount) :
      await store.loadRelatedAlbumSelectionOrder(this.ownerId, expectedCount);
    if (epoch !== this.loadEpoch || this.activeStore !== store ||
      this.loadedContentRevision !== store.libraryContentRevision) {
      throw new Error('专辑集合已更新，请重试');
    }
    return items;
  }

  private async loadInternal(store: LibraryStore): Promise<void> {
    if (this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    const contentRevision = store.libraryContentRevision;
    this.loadingContentRevision = contentRevision;
    this.loading = true;
    this.error = '';
    try {
      const count = this.scope === AlbumCollectionScope.ARTIST ?
        await store.getArtistAlbumCount(this.ownerId) : await store.getRelatedAlbumCount(this.ownerId);
      if (epoch !== this.loadEpoch) {
        return;
      }
      this.totalCount = count;
      this.loadedContentRevision = contentRevision;
      this.dataSource.reset(count, new AlbumCollectionPageLoader(store, this.scope, this.ownerId));
      await this.dataSource.ensureRange(
        0, LibraryPagingPolicy.initialPrefetchLastIndex(LibraryPagingPolicy.ALBUM_QUERY_PAGE_SIZE)
      );
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.loadedContentRevision = -1;
        this.error = this.messageOf(error);
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
        this.loadingContentRevision = -1;
        this.continuePendingRefresh(store);
      }
    }
  }

  private continuePendingRefresh(store: LibraryStore): void {
    if (this.refreshPending && this.activeStore === store) {
      this.refreshPending = false;
      this.refresh(store).catch((error: Object): void => {
        console.warn(`Unable to continue album collection refresh: ${this.messageOf(error)}`);
      });
    }
  }

  private messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
