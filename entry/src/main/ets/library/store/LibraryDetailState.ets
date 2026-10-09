import {
  AlbumDetail,
  ArtistDetailOverview,
  EmbeddedArtwork,
  TrackDetail
} from '../model/LibraryModels';
import { image } from '@kit.ImageKit';
import { EmbeddedArtworkService } from '../artwork/EmbeddedArtworkService';
import { LibraryStore } from './LibraryStore';
import { TrackListItem } from '../model/LibraryModels';
import { LibraryListDataSource } from './LibraryListDataSource';
import { LibraryDetailRefreshCoordinator, LibraryDetailRefreshTarget } from './LibraryDetailRefreshCoordinator';

@Observed
export class AlbumDetailState implements LibraryDetailRefreshTarget<AlbumDetail | undefined> {
  readonly albumId: number;
  detail?: AlbumDetail;
  loading: boolean = false;
  error: string = '';
  readonly trackDataSource: LibraryListDataSource<TrackListItem> = new LibraryListDataSource<TrackListItem>();
  private readonly refreshCoordinator: LibraryDetailRefreshCoordinator<AlbumDetail | undefined> =
    new LibraryDetailRefreshCoordinator<AlbumDetail | undefined>();
  private readonly onPaletteChanged: (primary: string) => void;

  constructor(albumId: number, onPaletteChanged: (primary: string) => void = (_primary: string): void => {}) {
    this.albumId = albumId;
    this.onPaletteChanged = onPaletteChanged;
  }

  commitDetail(detail: AlbumDetail | undefined): void {
    this.trackDataSource.replace(detail?.tracks ?? []);
    this.detail = detail;
    this.error = detail === undefined ? '专辑不存在或已从音乐库移除' : '';
    if (detail !== undefined) {
      this.onPaletteChanged(detail.album.palettePrimary);
    }
  }

  load(store: LibraryStore): Promise<void> {
    return this.activate(store);
  }

  activate(store: LibraryStore): Promise<void> {
    return this.refreshCoordinator.activate(store, (): Promise<AlbumDetail | undefined> =>
      store.getAlbumDetail(this.albumId), this);
  }

  refresh(store: LibraryStore): Promise<void> {
    return this.refreshCoordinator.refresh(store, (): Promise<AlbumDetail | undefined> =>
      store.getAlbumDetail(this.albumId), this);
  }

  deactivate(store: LibraryStore): void {
    this.refreshCoordinator.deactivate(store);
  }
}

@Observed
export class ArtistDetailState implements LibraryDetailRefreshTarget<ArtistDetailOverview | undefined> {
  readonly artistId: number;
  detail?: ArtistDetailOverview;
  loading: boolean = false;
  error: string = '';
  private readonly refreshCoordinator: LibraryDetailRefreshCoordinator<ArtistDetailOverview | undefined> =
    new LibraryDetailRefreshCoordinator<ArtistDetailOverview | undefined>();

  constructor(artistId: number) {
    this.artistId = artistId;
  }

  commitDetail(detail: ArtistDetailOverview | undefined): void {
    this.detail = detail;
    this.error = detail === undefined ? '艺术家不存在或已从音乐库移除' : '';
  }

  load(store: LibraryStore): Promise<void> {
    return this.activate(store);
  }

  activate(store: LibraryStore): Promise<void> {
    return this.refreshCoordinator.activate(store, (): Promise<ArtistDetailOverview | undefined> =>
      store.getArtistOverview(this.artistId), this);
  }

  refresh(store: LibraryStore): Promise<void> {
    return this.refreshCoordinator.refresh(store, (): Promise<ArtistDetailOverview | undefined> =>
      store.getArtistOverview(this.artistId), this);
  }

  deactivate(store: LibraryStore): void {
    this.refreshCoordinator.deactivate(store);
  }

  async loadTrackSnapshot(store: LibraryStore): Promise<Array<TrackListItem>> {
    const epoch = this.refreshCoordinator.currentEpoch();
    const revision = store.libraryContentRevision;
    const expectedCount = this.detail?.trackCount ?? 0;
    const tracks = await store.loadArtistTrackPlaybackOrder(this.artistId, expectedCount);
    if (!this.refreshCoordinator.isCurrent(store, epoch) || revision !== store.libraryContentRevision ||
      this.detail === undefined) {
      throw new Error('艺术家内容已更新，请重试');
    }
    return tracks;
  }
}

@Observed
export class TrackArtworkPreviewState {
  readonly artwork: EmbeddedArtwork;
  pixelMap: image.PixelMap | undefined = undefined;
  loading: boolean = false;
  error: string = '';
  private loadEpoch: number = 0;
  private readonly onChanged: () => void;

  constructor(artwork: EmbeddedArtwork, onChanged: () => void = (): void => {}) {
    this.artwork = artwork;
    this.onChanged = onChanged;
  }

  async load(
    service: EmbeddedArtworkService,
    detail: TrackDetail,
    maxEdge: number = 720
  ): Promise<void> {
    if (this.pixelMap !== undefined || this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    this.loading = true;
    this.error = '';
    try {
      const pixelMap = await service.decode(detail, this.artwork, maxEdge);
      if (epoch !== this.loadEpoch) {
        await pixelMap.release();
        return;
      }
      this.pixelMap = pixelMap;
      this.onChanged();
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.error = TrackDetailState.messageOf(error);
        console.warn(`Unable to load embedded artwork ${this.artwork.ordinal}: ${this.error}`);
        this.onChanged();
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
        this.onChanged();
      }
    }
  }

  release(): void {
    this.loadEpoch += 1;
    const pixelMap = this.pixelMap;
    this.pixelMap = undefined;
    if (pixelMap !== undefined) {
      pixelMap.release().catch((error: Object): void =>
        console.warn(`Unable to release embedded artwork preview: ${error}`));
    }
  }
}

@Observed
export class TrackDetailState {
  readonly trackId: number;
  detail?: TrackDetail;
  previews: Array<TrackArtworkPreviewState> = [];
  previewRevision: number = 0;
  loading: boolean = false;
  error: string = '';
  private loadEpoch: number = 0;
  private loaded: boolean = false;

  constructor(trackId: number) {
    this.trackId = trackId;
  }

  async load(store: LibraryStore): Promise<void> {
    if (this.loaded || this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    this.loading = true;
    this.error = '';
    try {
      const detail = await store.getTrackDetail(this.trackId);
      if (epoch !== this.loadEpoch) {
        return;
      }
      this.detail = detail;
      this.previews = detail?.artworks.map(
        (artwork: EmbeddedArtwork): TrackArtworkPreviewState =>
          new TrackArtworkPreviewState(artwork, (): void => {
            this.previewRevision += 1;
          })
      ) ?? [];
      this.previewRevision += 1;
      this.loaded = detail !== undefined;
      if (detail === undefined) {
        this.error = '歌曲不存在或已从音乐库移除';
      }
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.error = TrackDetailState.messageOf(error);
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
      }
    }
  }

  releasePreviews(): void {
    this.previews.forEach((preview: TrackArtworkPreviewState): void => preview.release());
  }

  static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}

@Observed
export class TrackArtworkViewerState {
  readonly detail: TrackDetail;
  currentIndex: number;
  pixelMap: image.PixelMap | undefined = undefined;
  loading: boolean = false;
  error: string = '';
  revision: number = 0;
  private loadEpoch: number = 0;

  constructor(detail: TrackDetail, initialIndex: number) {
    this.detail = detail;
    this.currentIndex = Math.max(0, Math.min(initialIndex, detail.artworks.length - 1));
  }

  currentArtwork(): EmbeddedArtwork | undefined {
    return this.detail.artworks[this.currentIndex];
  }

  async load(service: EmbeddedArtworkService): Promise<void> {
    const artwork = this.currentArtwork();
    if (artwork === undefined || this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    this.loading = true;
    this.error = '';
    try {
      const next = await service.decode(this.detail, artwork, 4096);
      if (epoch !== this.loadEpoch) {
        await next.release();
        return;
      }
      const previous = this.pixelMap;
      this.pixelMap = next;
      this.revision += 1;
      if (previous !== undefined) {
        await previous.release();
      }
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.error = TrackDetailState.messageOf(error);
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
      }
    }
  }

  async move(service: EmbeddedArtworkService, offset: number): Promise<void> {
    const nextIndex = Math.max(
      0,
      Math.min(this.currentIndex + offset, this.detail.artworks.length - 1)
    );
    if (nextIndex === this.currentIndex) {
      return;
    }
    this.loadEpoch += 1;
    this.currentIndex = nextIndex;
    await this.load(service);
  }

  release(): void {
    this.loadEpoch += 1;
    const pixelMap = this.pixelMap;
    this.pixelMap = undefined;
    if (pixelMap !== undefined) {
      pixelMap.release().catch((error: Object): void =>
        console.warn(`Unable to release full embedded artwork: ${error}`));
    }
  }
}
