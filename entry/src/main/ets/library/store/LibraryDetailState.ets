import {
  AlbumDetail,
  ArtistDetail,
  EmbeddedArtwork,
  TrackDetail
} from '../model/LibraryModels';
import { image } from '@kit.ImageKit';
import { EmbeddedArtworkService } from '../artwork/EmbeddedArtworkService';
import { LibraryStore } from './LibraryStore';
import { TrackListItem } from '../model/LibraryModels';
import { LibraryListDataSource } from './LibraryListDataSource';

@Observed
export class AlbumDetailState {
  readonly albumId: number;
  detail?: AlbumDetail;
  loading: boolean = false;
  error: string = '';
  readonly trackDataSource: LibraryListDataSource<TrackListItem> =
    new LibraryListDataSource<TrackListItem>();
  private loadEpoch: number = 0;
  private loaded: boolean = false;

  constructor(albumId: number) {
    this.albumId = albumId;
  }

  async load(store: LibraryStore): Promise<void> {
    if (this.loaded || this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    this.loading = true;
    this.error = '';
    try {
      const detail = await store.getAlbumDetail(this.albumId);
      if (epoch !== this.loadEpoch) {
        return;
      }
      this.trackDataSource.replace(detail?.tracks ?? []);
      this.detail = detail;
      this.loaded = detail !== undefined;
      if (detail === undefined) {
        this.error = '专辑不存在或已从音乐库移除';
      }
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.error = AlbumDetailState.messageOf(error);
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
      }
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}

@Observed
export class ArtistDetailState {
  readonly artistId: number;
  detail?: ArtistDetail;
  loading: boolean = false;
  error: string = '';
  readonly trackDataSource: LibraryListDataSource<TrackListItem> =
    new LibraryListDataSource<TrackListItem>();
  private loadEpoch: number = 0;
  private loaded: boolean = false;

  constructor(artistId: number) {
    this.artistId = artistId;
  }

  async load(store: LibraryStore): Promise<void> {
    if (this.loaded || this.loading) {
      return;
    }
    const epoch = ++this.loadEpoch;
    this.loading = true;
    this.error = '';
    try {
      const detail = await store.getArtistDetail(this.artistId);
      if (epoch !== this.loadEpoch) {
        return;
      }
      this.trackDataSource.replace(detail?.tracks ?? []);
      this.detail = detail;
      this.loaded = detail !== undefined;
      if (detail === undefined) {
        this.error = '艺术家不存在或已从音乐库移除';
      }
    } catch (error) {
      if (epoch === this.loadEpoch) {
        this.error = ArtistDetailState.messageOf(error);
      }
    } finally {
      if (epoch === this.loadEpoch) {
        this.loading = false;
      }
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
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
