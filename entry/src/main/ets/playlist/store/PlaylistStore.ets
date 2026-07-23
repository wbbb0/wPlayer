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
import {
  PlaylistDetailTarget,
  RepositoryInvalidation,
  RepositoryInvalidationListener,
  RepositoryProjection
} from '../../library/data/RepositoryInvalidation';

const PLAYLIST_QUERY_BATCH_SIZE: number = 500;

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
  private initialized: boolean = false;
  private active: boolean = false;
  private needsActivationRefresh: boolean = false;
  private initializationPromise?: Promise<void>;
  private observingInvalidations: boolean = false;
  private lastSeenInvalidationRevision: number = 0;
  private pendingSummaryRefresh: boolean = false;
  private pendingAllDetails: boolean = false;
  private pendingPlaylistIds: Array<number> = [];
  private invalidationRefreshPromise?: Promise<void>;
  private readonly invalidationListener: RepositoryInvalidationListener =
    (invalidation: RepositoryInvalidation): void => {
      this.lastSeenInvalidationRevision = invalidation.revision;
      this.queueInvalidation(invalidation);
    };

  constructor(repository: MusicRepository) {
    this.repository = repository;
  }

  async initialize(): Promise<void> {
    this.active = true;
    if (this.initialized) {
      await this.reactivateIfNeeded();
      return;
    }
    if (this.initializationPromise !== undefined) {
      await this.initializationPromise;
      await this.reactivateIfNeeded();
      return;
    }
    const running = this.initializeInternal();
    this.initializationPromise = running;
    try {
      await running;
    } finally {
      if (this.initializationPromise === running) {
        this.initializationPromise = undefined;
      }
    }
  }

  private async initializeInternal(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      this.lastSeenInvalidationRevision = this.repository.currentInvalidationRevision();
      await this.repository.getCompletedPlaylist();
      if (!await this.refresh()) {
        throw new Error(this.errorMessage || 'Unable to initialize playlists');
      }
      this.initialized = true;
      if (this.active && !this.needsActivationRefresh) {
        await this.startObservingInvalidations();
      }
    } catch (error) {
      this.errorMessage = PlaylistStore.messageOf(error);
    } finally {
      this.loading = false;
    }
  }

  dispose(): void {
    this.active = false;
    this.needsActivationRefresh = true;
    this.refreshGeneration++;
    this.detailGeneration++;
    this.pendingSummaryRefresh = false;
    this.pendingAllDetails = false;
    this.pendingPlaylistIds = [];
    if (this.observingInvalidations) {
      this.repository.removeInvalidationListener(this.invalidationListener);
      this.observingInvalidations = false;
    }
  }

  synchronizeRepositoryChanges(): Promise<void> {
    return this.synchronizeInvalidations();
  }

  synchronizeCommittedRepositoryChanges(): Promise<void> {
    return this.synchronizeCommittedChanges();
  }

  async refresh(): Promise<boolean> {
    const generation = ++this.refreshGeneration;
    try {
      const playlists = await this.repository.getPlaylists(this.sortField, this.sortDirection);
      if (generation === this.refreshGeneration) {
        this.playlistDataSource.replace(playlists);
        this.playlists = playlists;
        return true;
      }
    } catch (error) {
      if (generation === this.refreshGeneration) {
        this.errorMessage = PlaylistStore.messageOf(error);
      }
    }
    return false;
  }

  private startObservingInvalidations(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    if (!this.observingInvalidations) {
      this.attachInvalidationListener();
      const currentRevision = this.repository.currentInvalidationRevision();
      if (currentRevision > this.lastSeenInvalidationRevision) {
        this.lastSeenInvalidationRevision = currentRevision;
        this.pendingSummaryRefresh = true;
        this.pendingAllDetails = true;
        return this.synchronizeInvalidations();
      }
    }
    return Promise.resolve();
  }

  private attachInvalidationListener(): void {
    if (!this.observingInvalidations) {
      this.repository.addInvalidationListener(this.invalidationListener);
      this.observingInvalidations = true;
    }
  }

  private queueInvalidation(invalidation: RepositoryInvalidation): void {
    if (!this.active || !this.initialized) {
      return;
    }
    if (invalidation.hasProjection(RepositoryProjection.PLAYLIST_SUMMARIES)) {
      this.pendingSummaryRefresh = true;
    }
    if (invalidation.hasProjection(RepositoryProjection.PLAYLIST_DETAILS)) {
      if (invalidation.playlistDetailTarget === PlaylistDetailTarget.ALL) {
        this.pendingAllDetails = true;
        this.pendingPlaylistIds = [];
      } else if (!this.pendingAllDetails && invalidation.playlistDetailTarget === PlaylistDetailTarget.IDS) {
        invalidation.playlistIds.forEach((playlistId: number): void => {
          if (!this.pendingPlaylistIds.includes(playlistId)) {
            this.pendingPlaylistIds.push(playlistId);
          }
        });
      }
    }
    if (invalidation.hasProjection(RepositoryProjection.PLAYLIST_PLAYBACK_ORDER)) {
      const current = this.detail;
      if (current !== undefined &&
        (current.playlist.itemSortField === PlaylistTrackSortField.LAST_PLAYED ||
          current.playlist.itemSortField === PlaylistTrackSortField.LAST_COMPLETED) &&
        !this.pendingAllDetails && !this.pendingPlaylistIds.includes(current.playlist.id)) {
        this.pendingPlaylistIds.push(current.playlist.id);
      }
    }
    if (!this.hasPendingInvalidation()) {
      return;
    }
    this.synchronizeInvalidations().catch((error: Object): void => {
      console.warn(`Unable to refresh invalidated playlists: ${PlaylistStore.messageOf(error)}`);
    });
  }

  private hasPendingInvalidation(): boolean {
    return this.pendingSummaryRefresh || this.pendingAllDetails || this.pendingPlaylistIds.length > 0;
  }

  private synchronizeInvalidations(): Promise<void> {
    if (this.invalidationRefreshPromise !== undefined) {
      return this.invalidationRefreshPromise;
    }
    if (!this.hasPendingInvalidation()) {
      return Promise.resolve();
    }
    const running = this.drainInvalidations();
    this.invalidationRefreshPromise = running;
    const completeSuccess = (): void => {
      if (this.invalidationRefreshPromise === running) {
        this.invalidationRefreshPromise = undefined;
      }
      if (this.hasPendingInvalidation()) {
        this.synchronizeInvalidations().catch((error: Object): void => {
          console.warn(`Unable to continue invalidated playlist refresh: ${PlaylistStore.messageOf(error)}`);
        });
      }
    };
    const completeFailure = (): void => {
      if (this.invalidationRefreshPromise === running) {
        this.invalidationRefreshPromise = undefined;
      }
    };
    running.then(completeSuccess, completeFailure);
    return running;
  }

  private async reactivateIfNeeded(): Promise<void> {
    if (!this.active || !this.initialized) {
      return;
    }
    if (this.needsActivationRefresh) {
      const baselineRevision = this.repository.currentInvalidationRevision();
      const summaryRefreshed = await this.refresh();
      const currentPlaylistId = this.detail?.playlist.id;
      let detailRefreshed = true;
      if (currentPlaylistId !== undefined) {
        detailRefreshed = await this.loadDetail(currentPlaylistId);
      }
      if (!this.active) {
        return;
      }
      if (!summaryRefreshed || !detailRefreshed) {
        this.pendingSummaryRefresh = true;
        this.pendingAllDetails = true;
        this.attachInvalidationListener();
        return;
      }
      this.lastSeenInvalidationRevision = baselineRevision;
      this.needsActivationRefresh = false;
    }
    await this.startObservingInvalidations();
  }

  private async drainInvalidations(): Promise<void> {
    while (this.hasPendingInvalidation()) {
      const refreshSummaries = this.pendingSummaryRefresh;
      const refreshAllDetails = this.pendingAllDetails;
      const refreshPlaylistIds = this.pendingPlaylistIds.slice();
      this.pendingSummaryRefresh = false;
      this.pendingAllDetails = false;
      this.pendingPlaylistIds = [];
      if (refreshSummaries) {
        const refreshed = await this.refresh();
        if (!refreshed) {
          this.restorePendingInvalidation(refreshSummaries, refreshAllDetails, refreshPlaylistIds);
          throw new Error(this.errorMessage || 'Unable to refresh playlist summaries');
        }
      }
      const currentPlaylistId = this.detail?.playlist.id;
      if (currentPlaylistId !== undefined &&
        (refreshAllDetails || refreshPlaylistIds.includes(currentPlaylistId))) {
        const refreshed = await this.loadDetail(currentPlaylistId);
        if (!refreshed) {
          this.restorePendingInvalidation(false, refreshAllDetails, refreshPlaylistIds);
          throw new Error(this.errorMessage || 'Unable to refresh playlist detail');
        }
      }
    }
  }

  private restorePendingInvalidation(refreshSummaries: boolean, refreshAllDetails: boolean,
    refreshPlaylistIds: Array<number>): void {
    if (!this.active) {
      return;
    }
    this.pendingSummaryRefresh = this.pendingSummaryRefresh || refreshSummaries;
    if (refreshAllDetails) {
      this.pendingAllDetails = true;
      this.pendingPlaylistIds = [];
      return;
    }
    if (!this.pendingAllDetails) {
      refreshPlaylistIds.forEach((playlistId: number): void => {
        if (!this.pendingPlaylistIds.includes(playlistId)) {
          this.pendingPlaylistIds.push(playlistId);
        }
      });
    }
  }

  async setSort(field: PlaylistSortField, direction: SortDirection): Promise<void> {
    this.sortField = field;
    this.sortDirection = direction;
    await this.refresh();
  }

  async loadDetail(playlistId: number): Promise<boolean> {
    const generation = ++this.detailGeneration;
    this.detailLoading = true;
    this.errorMessage = '';
    try {
      const detail = await this.getCompleteDetail(playlistId);
      if (generation === this.detailGeneration) {
        this.detailItemDataSource.replace(detail?.items ?? []);
        this.detail = detail;
        return true;
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
    return false;
  }

  async create(name: string): Promise<PlaylistSummary | undefined> {
    return this.runMutation(async (): Promise<PlaylistSummary> => {
      const playlist = await this.repository.createPlaylist(name);
      await this.synchronizeCommittedChanges();
      this.lastMessage = `已创建“${playlist.name}”`;
      return playlist;
    });
  }

  async rename(playlistId: number, name: string): Promise<PlaylistSummary | undefined> {
    return this.runMutation(async (): Promise<PlaylistSummary> => {
      const playlist = await this.repository.renamePlaylist(playlistId, name);
      await this.synchronizeCommittedChanges();
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
      await this.synchronizeCommittedChanges();
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
      await this.refreshAfterItemMutation();
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
      await this.refreshAfterItemMutation();
      return true;
    });
    return result ?? false;
  }

  async updateItemSort(playlistId: number, field: PlaylistTrackSortField,
    direction: SortDirection): Promise<void> {
    await this.runMutation(async (): Promise<boolean> => {
      await this.repository.updatePlaylistItemSort(playlistId, field, direction);
      await this.refreshAfterItemMutation();
      return true;
    });
  }

  async markPlayed(playlistId: number): Promise<void> {
    try {
      await this.repository.markPlaylistPlayed(playlistId);
      await this.synchronizeCommittedChanges();
    } catch (error) {
      this.errorMessage = PlaylistStore.messageOf(error);
    }
  }

  async getAllTracks(playlistId: number): Promise<Array<PlaylistTrackItem>> {
    return (await this.getCompleteDetail(playlistId))?.items ?? [];
  }

  private async getCompleteDetail(playlistId: number): Promise<PlaylistDetail | undefined> {
    const first = await this.repository.getPlaylistDetail(
      playlistId,
      0,
      PLAYLIST_QUERY_BATCH_SIZE
    );
    if (first === undefined) {
      return undefined;
    }
    const items = first.items.slice();
    let latest = first;
    while (items.length < latest.totalCount) {
      const next = await this.repository.getPlaylistDetail(
        playlistId,
        items.length,
        PLAYLIST_QUERY_BATCH_SIZE,
        first.playlist.itemSortField,
        first.playlist.itemSortDirection
      );
      if (next === undefined || next.items.length === 0) {
        throw new Error(`Unable to load complete playlist ${playlistId}`);
      }
      items.push(...next.items);
      latest = next;
    }
    return {
      playlist: latest.playlist,
      items: items,
      offset: 0,
      totalCount: latest.totalCount
    };
  }

  private async runItemMutation(playlistId: number,
    operation: () => Promise<PlaylistMutationResult>): Promise<PlaylistMutationResult | undefined> {
    return this.runMutation(async (): Promise<PlaylistMutationResult> => {
      const result = await operation();
      await this.refreshAfterItemMutation();
      this.lastMessage = result.inserted > 0 ?
        `已添加 ${result.inserted} 首` :
        (result.alreadyPresent > 0 ? '歌曲已在播放列表中' : '没有可添加的歌曲');
      return result;
    });
  }

  private async refreshAfterItemMutation(): Promise<void> {
    await this.synchronizeCommittedChanges();
  }

  private async synchronizeCommittedChanges(): Promise<void> {
    try {
      await this.synchronizeInvalidations();
    } catch (error) {
      this.errorMessage = PlaylistStore.messageOf(error);
      console.warn(`Playlist change committed but projection refresh is pending: ${this.errorMessage}`);
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
