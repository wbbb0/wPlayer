import {
  PlaylistDetail,
  PlaylistItemInput,
  PlaylistItemSource,
  PlaylistMutationResult,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackItem,
  PlaylistTrackSortField,
  SortDirection,
  TrackListItem
} from '../../library/model/LibraryModels';
import { MusicRepository } from '../../library/data/MusicRepository';
import { LibraryListDataSource } from '../../library/store/LibraryListDataSource';

const PLAYLIST_PAGE_SIZE: number = 100;

@Observed
export class PlaylistStore {
  playlists: Array<PlaylistSummary> = [];
  detail?: PlaylistDetail;
  loading: boolean = false;
  detailLoading: boolean = false;
  mutating: boolean = false;
  errorMessage: string = '';
  lastMessage: string = '';
  sortField: PlaylistSortField = PlaylistSortField.UPDATED_AT;
  sortDirection: SortDirection = SortDirection.DESCENDING;
  readonly playlistDataSource: LibraryListDataSource<PlaylistSummary> =
    new LibraryListDataSource<PlaylistSummary>();
  readonly detailItemDataSource: LibraryListDataSource<PlaylistTrackItem> =
    new LibraryListDataSource<PlaylistTrackItem>();

  private readonly repository: MusicRepository;
  private refreshGeneration: number = 0;
  private detailGeneration: number = 0;

  constructor(repository: MusicRepository) {
    this.repository = repository;
  }

  async initialize(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      await this.repository.getCompletedPlaylist();
      await this.refresh();
    } catch (error) {
      this.errorMessage = PlaylistStore.messageOf(error);
    } finally {
      this.loading = false;
    }
  }

  async refresh(): Promise<void> {
    const generation = ++this.refreshGeneration;
    try {
      const playlists = await this.repository.getPlaylists(this.sortField, this.sortDirection);
      if (generation === this.refreshGeneration) {
        this.playlistDataSource.replace(playlists);
        this.playlists = playlists;
      }
    } catch (error) {
      if (generation === this.refreshGeneration) {
        this.errorMessage = PlaylistStore.messageOf(error);
      }
    }
  }

  async setSort(field: PlaylistSortField, direction: SortDirection): Promise<void> {
    this.sortField = field;
    this.sortDirection = direction;
    await this.refresh();
  }

  async loadDetail(playlistId: number): Promise<void> {
    const generation = ++this.detailGeneration;
    this.detailLoading = true;
    this.errorMessage = '';
    try {
      const detail = await this.repository.getPlaylistDetail(playlistId, 0, PLAYLIST_PAGE_SIZE);
      if (generation === this.detailGeneration) {
        this.detailItemDataSource.replace(detail?.items ?? []);
        this.detail = detail;
      }
    } catch (error) {
      if (generation === this.detailGeneration) {
        this.errorMessage = PlaylistStore.messageOf(error);
      }
    } finally {
      if (generation === this.detailGeneration) {
        this.detailLoading = false;
      }
    }
  }

  async loadMore(): Promise<void> {
    const current = this.detail;
    if (current === undefined || this.detailLoading || current.items.length >= current.totalCount) {
      return;
    }
    const generation = this.detailGeneration;
    this.detailLoading = true;
    try {
      const next = await this.repository.getPlaylistDetail(
        current.playlist.id,
        current.items.length,
        PLAYLIST_PAGE_SIZE,
        current.playlist.itemSortField,
        current.playlist.itemSortDirection
      );
      if (generation === this.detailGeneration && next !== undefined) {
        const items = current.items.concat(next.items);
        this.detailItemDataSource.replace(items);
        this.detail = {
          playlist: next.playlist,
          items: items,
          offset: 0,
          totalCount: next.totalCount
        };
      }
    } catch (error) {
      if (generation === this.detailGeneration) {
        this.errorMessage = PlaylistStore.messageOf(error);
      }
    } finally {
      if (generation === this.detailGeneration) {
        this.detailLoading = false;
      }
    }
  }

  async create(name: string): Promise<PlaylistSummary | undefined> {
    return this.runMutation(async (): Promise<PlaylistSummary> => {
      const playlist = await this.repository.createPlaylist(name);
      await this.refresh();
      this.lastMessage = `已创建“${playlist.name}”`;
      return playlist;
    });
  }

  async rename(playlistId: number, name: string): Promise<PlaylistSummary | undefined> {
    return this.runMutation(async (): Promise<PlaylistSummary> => {
      const playlist = await this.repository.renamePlaylist(playlistId, name);
      await this.refresh();
      if (this.detail?.playlist.id === playlistId) {
        await this.loadDetail(playlistId);
      }
      this.lastMessage = `已改名为“${playlist.name}”`;
      return playlist;
    });
  }

  async delete(playlistId: number): Promise<boolean> {
    const result = await this.runMutation(async (): Promise<boolean> => {
      await this.repository.deletePlaylist(playlistId);
      if (this.detail?.playlist.id === playlistId) {
        this.detailItemDataSource.clear();
        this.detail = undefined;
      }
      await this.refresh();
      this.lastMessage = '播放列表已删除';
      return true;
    });
    return result ?? false;
  }

  async addTracks(playlistId: number, tracks: Array<TrackListItem>): Promise<PlaylistMutationResult | undefined> {
    const items: Array<PlaylistItemInput> = tracks.map((track: TrackListItem): PlaylistItemInput => {
      return { trackId: track.id, source: PlaylistItemSource.MANUAL };
    });
    return this.runItemMutation(playlistId, (): Promise<PlaylistMutationResult> =>
      this.repository.addPlaylistItems(playlistId, items));
  }

  async addTrackIds(playlistId: number, trackIds: Array<number>,
    source: PlaylistItemSource = PlaylistItemSource.MANUAL): Promise<PlaylistMutationResult | undefined> {
    const items = trackIds.map((trackId: number): PlaylistItemInput => {
      return { trackId: trackId, source: source };
    });
    return this.runItemMutation(playlistId, (): Promise<PlaylistMutationResult> =>
      this.repository.addPlaylistItems(playlistId, items));
  }

  async mergeItems(playlistId: number,
    items: Array<PlaylistItemInput>): Promise<PlaylistMutationResult | undefined> {
    return this.runItemMutation(playlistId, (): Promise<PlaylistMutationResult> =>
      this.repository.mergePlaylistItems(playlistId, items));
  }

  async replaceItems(playlistId: number,
    items: Array<PlaylistItemInput>): Promise<PlaylistMutationResult | undefined> {
    return this.runItemMutation(playlistId, (): Promise<PlaylistMutationResult> =>
      this.repository.replacePlaylistItems(playlistId, items));
  }

  async removeTrack(playlistId: number, trackId: number): Promise<boolean> {
    return this.removeTracks(playlistId, [trackId]);
  }

  async removeTracks(playlistId: number, trackIds: Array<number>): Promise<boolean> {
    if (trackIds.length === 0) {
      return false;
    }
    const removed = await this.runMutation(async (): Promise<number> => {
      const count = await this.repository.removePlaylistItems(playlistId, trackIds);
      await this.refreshAfterItemMutation(playlistId);
      if (count > 0) {
        this.lastMessage = count === 1 ? '已从播放列表移除' : `已从播放列表移除 ${count} 首`;
      }
      return count;
    });
    return (removed ?? 0) > 0;
  }

  async reorder(playlistId: number, items: Array<PlaylistTrackItem>): Promise<boolean> {
    const result = await this.runMutation(async (): Promise<boolean> => {
      await this.repository.reorderPlaylistItems(
        playlistId,
        items.map((item: PlaylistTrackItem): number => item.id)
      );
      await this.refreshAfterItemMutation(playlistId);
      return true;
    });
    return result ?? false;
  }

  async updateItemSort(playlistId: number, field: PlaylistTrackSortField,
    direction: SortDirection): Promise<void> {
    await this.runMutation(async (): Promise<boolean> => {
      await this.repository.updatePlaylistItemSort(playlistId, field, direction);
      await this.refreshAfterItemMutation(playlistId);
      return true;
    });
  }

  async markPlayed(playlistId: number): Promise<void> {
    try {
      await this.repository.markPlaylistPlayed(playlistId);
      await this.refresh();
    } catch (error) {
      this.errorMessage = PlaylistStore.messageOf(error);
    }
  }

  async getAllTracks(playlistId: number): Promise<Array<PlaylistTrackItem>> {
    const items: Array<PlaylistTrackItem> = [];
    let totalCount = 0;
    do {
      const detail = await this.repository.getPlaylistDetail(
        playlistId,
        items.length,
        PLAYLIST_PAGE_SIZE
      );
      if (detail === undefined) {
        return items;
      }
      totalCount = detail.totalCount;
      items.push(...detail.items);
    } while (items.length < totalCount);
    return items;
  }

  private async runItemMutation(playlistId: number,
    operation: () => Promise<PlaylistMutationResult>): Promise<PlaylistMutationResult | undefined> {
    return this.runMutation(async (): Promise<PlaylistMutationResult> => {
      const result = await operation();
      await this.refreshAfterItemMutation(playlistId);
      this.lastMessage = result.inserted > 0 ?
        `已添加 ${result.inserted} 首` :
        (result.alreadyPresent > 0 ? '歌曲已在播放列表中' : '没有可添加的歌曲');
      return result;
    });
  }

  private async refreshAfterItemMutation(playlistId: number): Promise<void> {
    await this.refresh();
    if (this.detail?.playlist.id === playlistId) {
      await this.loadDetail(playlistId);
    }
  }

  private async runMutation<T>(operation: () => Promise<T>): Promise<T | undefined> {
    if (this.mutating) {
      return undefined;
    }
    this.mutating = true;
    this.errorMessage = '';
    this.lastMessage = '';
    try {
      return await operation();
    } catch (error) {
      this.errorMessage = PlaylistStore.messageOf(error);
      return undefined;
    } finally {
      this.mutating = false;
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
