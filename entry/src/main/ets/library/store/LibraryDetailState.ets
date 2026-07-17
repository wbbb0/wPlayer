import {
  AlbumDetail,
  ArtistDetail
} from '../model/LibraryModels';
import { LibraryStore } from './LibraryStore';

@Observed
export class AlbumDetailState {
  readonly albumId: number;
  detail?: AlbumDetail;
  loading: boolean = false;
  error: string = '';
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
