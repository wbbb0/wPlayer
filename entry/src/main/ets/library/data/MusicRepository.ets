import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  AlbumSortField,
  AlbumDetail,
  ArtistReference,
  ArtistDetail,
  AvailabilityState,
  AlbumListItem,
  PlaylistDetail,
  PlaylistItemInput,
  PlaylistMutationResult,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackSortField,
  PlaylistTransferTrack,
  LibrarySnapshot,
  LibraryStatistics,
  MediaFileCheckCandidate,
  SortDirection,
  TrackDetail,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField,
  TrackAvailabilityUpdate,
  UnavailableTrackItem
} from '../model/LibraryModels';
import { PlaybackTrack, QueueTrack, ResumeState } from '../../playback/model/PlaybackModels';
import { LibraryDatabase } from './LibraryDatabase';
import { MusicLibraryImporter } from './MusicLibraryImporter';
import { MusicLibraryQueries } from './MusicLibraryQueries';
import {
  ArtworkImportInput,
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate,
  ImportTrackResult,
  TrackImportInput
} from './MusicRepositoryTypes';
import { ArtworkPaletteUpdate, PaletteRefreshAsset } from './MusicRepositoryTypes';
import { ARTWORK_PALETTE_VERSION } from '../artwork/ArtworkPaletteExtractor';
import { PlaylistRepository } from '../../playlist/data/PlaylistRepository';
import { DemoLibraryMode } from '../../demo/DemoLibraryMode';
import { DemoMusicLibrary } from '../../demo/DemoMusicLibrary';
import {
  PlaylistDetailTarget,
  RepositoryContentChangeKind,
  RepositoryInvalidationHub,
  RepositoryInvalidationListener,
  RepositoryInvalidationReason,
  RepositoryProjection
} from './RepositoryInvalidation';

export {
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate,
  ArtworkImportInput,
  ImportTrackResult,
  TrackImportInput
} from './MusicRepositoryTypes';

/**
 * Application-facing library persistence facade.
 *
 * Lifecycle and destructive maintenance remain here; query and import workflows are
 * delegated to dedicated collaborators so their transactional boundaries are explicit.
 */
export class MusicRepository {
  private readonly database: LibraryDatabase = new LibraryDatabase();
  private readonly queries: MusicLibraryQueries = new MusicLibraryQueries(this.database);
  private readonly importer: MusicLibraryImporter = new MusicLibraryImporter(this.database);
  private readonly playlists: PlaylistRepository = new PlaylistRepository(this.database);
  private readonly invalidations: RepositoryInvalidationHub = new RepositoryInvalidationHub();

  addInvalidationListener(listener: RepositoryInvalidationListener): void {
    this.invalidations.addListener(listener);
  }

  removeInvalidationListener(listener: RepositoryInvalidationListener): void {
    this.invalidations.removeListener(listener);
  }

  currentInvalidationRevision(): number {
    return this.invalidations.currentRevision();
  }

  notifyContentChanged(kind: RepositoryContentChangeKind): void {
    if (kind === RepositoryContentChangeKind.METADATA) {
      this.invalidations.publish(
        [
          RepositoryProjection.LIBRARY_SUMMARY,
          RepositoryProjection.LIBRARY_TRACKS,
          RepositoryProjection.LIBRARY_ALBUMS,
          RepositoryProjection.UNAVAILABLE_TRACKS,
          RepositoryProjection.PLAYLIST_SUMMARIES,
          RepositoryProjection.PLAYLIST_DETAILS
        ],
        RepositoryInvalidationReason.LIBRARY_METADATA_CHANGED,
        PlaylistDetailTarget.ALL
      );
      return;
    }
    this.invalidations.publish(
      [
        RepositoryProjection.LIBRARY_SUMMARY,
        RepositoryProjection.LIBRARY_TRACKS,
        RepositoryProjection.LIBRARY_ALBUMS,
        RepositoryProjection.PLAYLIST_DETAILS
      ],
      RepositoryInvalidationReason.LIBRARY_ARTWORK_CHANGED,
      PlaylistDetailTarget.ALL
    );
  }

  initialize(context: common.Context): Promise<boolean> {
    return this.database.initialize(context);
  }

  close(): Promise<void> {
    return this.database.close();
  }

  async clearLibrary(): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    await this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      const now = Date.now();
      await transaction.execute('DELETE FROM track_artwork');
      await transaction.execute('DELETE FROM track_credit');
      await transaction.execute('DELETE FROM track_genre');
      await transaction.execute('DELETE FROM track_tag_extra');
      await transaction.execute('DELETE FROM album_credit');
      await transaction.execute('DELETE FROM track');
      await transaction.execute('DELETE FROM media_file');
      await transaction.execute('DELETE FROM album');
      await transaction.execute('DELETE FROM person');
      await transaction.execute('DELETE FROM genre');
      await transaction.execute('DELETE FROM artwork_source');
      await transaction.execute(
        'UPDATE artwork_asset SET ref_count = 0, unreferenced_at = ? WHERE ref_count <> 0 OR unreferenced_at IS NULL',
        [now]
      );
    });
    this.invalidations.publish(
      MusicRepository.allLibraryAndPlaylistProjections(),
      RepositoryInvalidationReason.LIBRARY_CLEARED,
      PlaylistDetailTarget.ALL
    );
  }

  async rebuildSortIndexes(): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    await this.database.rebuildSortIndexes();
    this.invalidations.publish(
      [
        RepositoryProjection.LIBRARY_TRACKS,
        RepositoryProjection.LIBRARY_ALBUMS,
        RepositoryProjection.PLAYLIST_DETAILS
      ],
      RepositoryInvalidationReason.SORT_INDEXES_REBUILT,
      PlaylistDetailTarget.ALL
    );
  }

  getStatistics(): Promise<LibraryStatistics> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.statistics());
    }
    return this.queries.getStatistics();
  }

  getTracks(
    field: TrackSortField,
    direction: SortDirection
  ): Promise<LibrarySnapshot<TrackListItem>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.trackSnapshot(field, direction));
    }
    return this.queries.getTracks(field, direction);
  }

  getPlaybackTrack(trackId: number): Promise<PlaybackTrack | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.playbackTrack(trackId));
    }
    return this.queries.getPlaybackTrack(trackId);
  }

  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.playbackQueueTracks(trackIds));
    }
    return this.queries.getPlaybackQueueTracks(trackIds);
  }

  getResumeState(trackId: number): Promise<ResumeState> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.resumeState(trackId));
    }
    return this.queries.getResumeState(trackId);
  }

  savePlaybackState(trackId: number, positionMs: number, durationMs: number, completed: boolean): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve();
    }
    return this.queries.savePlaybackState(trackId, positionMs, durationMs, completed);
  }

  async setTrackAvailability(
    trackId: number,
    state: AvailabilityState
  ): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    await this.queries.setTrackAvailability(trackId, state);
    this.publishAvailabilityChanged();
  }

  async setTrackAvailabilities(updates: Array<TrackAvailabilityUpdate>): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    if (updates.length === 0) {
      return;
    }
    await this.queries.setTrackAvailabilities(updates);
  }

  getMediaFileCheckCandidates(): Promise<Array<MediaFileCheckCandidate>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.queries.getMediaFileCheckCandidates();
  }

  getUnavailableTracks(): Promise<Array<UnavailableTrackItem>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.queries.getUnavailableTracks();
  }

  async removeTracks(trackIds: Array<number>): Promise<number> {
    if (DemoLibraryMode.isEnabled()) {
      return 0;
    }
    const uniqueIds = Array.from(new Set<number>(trackIds.filter((id: number) => id >= 0)));
    if (uniqueIds.length === 0) {
      return 0;
    }
    const removed = await this.database.enqueueWrite(
      async (transaction: relationalStore.Transaction): Promise<number> => {
      const now = Date.now();
      let removed = 0;
      const affectedAlbums: Set<number> = new Set<number>();
      for (let offset = 0; offset < uniqueIds.length; offset += 300) {
        const batch = uniqueIds.slice(offset, Math.min(offset + 300, uniqueIds.length));
        const placeholders = batch.map((_id: number) => '?').join(', ');
        const albumResult = await transaction.querySql(
          `SELECT DISTINCT album_id FROM track
           WHERE id IN (${placeholders}) AND album_id IS NOT NULL`,
          batch
        );
        while (albumResult.goToNextRow()) {
          affectedAlbums.add(albumResult.getLong(0));
        }
        albumResult.close();
        const artworkResult = await transaction.querySql(
          `SELECT asset_id, COUNT(*) FROM track_artwork
           WHERE track_id IN (${placeholders}) AND asset_id IS NOT NULL GROUP BY asset_id`,
          batch
        );
        while (artworkResult.goToNextRow()) {
          const assetId = artworkResult.getLong(0);
          const count = artworkResult.getLong(1);
          await transaction.execute(
            `UPDATE artwork_asset SET ref_count = MAX(0, ref_count - ?),
              unreferenced_at = CASE WHEN ref_count - ? <= 0 THEN ? ELSE unreferenced_at END
             WHERE id = ?`,
            [count, count, now, assetId]
          );
        }
        artworkResult.close();
        const countResult = await transaction.querySql(
          `SELECT COUNT(*) FROM track WHERE id IN (${placeholders})`,
          batch
        );
        if (countResult.goToNextRow()) {
          removed += countResult.getLong(0);
        }
        countResult.close();
        await transaction.execute(
          `DELETE FROM media_file WHERE id IN (
             SELECT media_file_id FROM track WHERE id IN (${placeholders})
           )`,
          batch
        );
      }
      for (const albumId of affectedAlbums) {
        await transaction.execute(
          `UPDATE album SET
            track_count = (SELECT COUNT(*) FROM track WHERE album_id = ?),
            total_duration_ms = COALESCE((SELECT SUM(duration_ms) FROM track WHERE album_id = ?), 0),
            primary_artwork_id = (
              SELECT primary_artwork_id FROM track
              WHERE album_id = ? AND primary_artwork_id IS NOT NULL ORDER BY id LIMIT 1
            ),
            updated_at = ? WHERE id = ?`,
          [albumId, albumId, albumId, now, albumId]
        );
      }
      await transaction.execute('DELETE FROM album WHERE track_count = 0');
      await transaction.execute(
        `DELETE FROM person WHERE id NOT IN (
          SELECT person_id FROM track_credit UNION SELECT person_id FROM album_credit
        )`
      );
      await transaction.execute('DELETE FROM genre WHERE id NOT IN (SELECT genre_id FROM track_genre)');
      return removed;
      }
    );
    if (removed > 0) {
      this.invalidations.publish(
        MusicRepository.allLibraryAndPlaylistProjections(),
        RepositoryInvalidationReason.TRACKS_REMOVED,
        PlaylistDetailTarget.ALL
      );
    }
    return removed;
  }

  getAlbums(
    field: AlbumSortField,
    direction: SortDirection
  ): Promise<LibrarySnapshot<AlbumListItem>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.albumSnapshot(field, direction));
    }
    return this.queries.getAlbums(field, direction);
  }

  getAlbumDetail(albumId: number): Promise<AlbumDetail | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.albumDetail(albumId));
    }
    return this.queries.getAlbumDetail(albumId);
  }

  getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.albumArtists(albumId));
    }
    return this.queries.getAlbumArtists(albumId);
  }

  getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.artistDetail(artistId));
    }
    return this.queries.getArtistDetail(artistId);
  }

  getTrackNavigationTargets(trackId: number): Promise<TrackNavigationTargets | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.navigationTargets(trackId));
    }
    return this.queries.getTrackNavigationTargets(trackId);
  }

  getTrackDetail(trackId: number): Promise<TrackDetail | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.trackDetail(trackId));
    }
    return this.queries.getTrackDetail(trackId);
  }

  getPlaylists(field: PlaylistSortField, direction: SortDirection): Promise<Array<PlaylistSummary>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.playlists(field, direction));
    }
    return this.playlists.getPlaylists(field, direction);
  }

  getPlaylist(playlistId: number): Promise<PlaylistSummary | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.playlist(playlistId));
    }
    return this.playlists.getPlaylist(playlistId);
  }

  getCompletedPlaylist(): Promise<PlaylistSummary> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.completedPlaylist());
    }
    return this.playlists.getCompletedPlaylist();
  }

  async createPlaylist(name: string): Promise<PlaylistSummary> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.reject(new Error('演示音乐库为只读模式'));
    }
    const playlist = await this.playlists.createPlaylist(name);
    this.invalidations.publish(
      [RepositoryProjection.PLAYLIST_SUMMARIES],
      RepositoryInvalidationReason.PLAYLIST_CREATED
    );
    return playlist;
  }

  async renamePlaylist(playlistId: number, name: string): Promise<PlaylistSummary> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.reject(new Error('演示音乐库为只读模式'));
    }
    const playlist = await this.playlists.renamePlaylist(playlistId, name);
    this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_RENAMED, playlistId);
    return playlist;
  }

  async deletePlaylist(playlistId: number): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.reject(new Error('演示音乐库为只读模式'));
    }
    await this.playlists.deletePlaylist(playlistId);
    this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_DELETED, playlistId);
  }

  async updatePlaylistItemSort(
    playlistId: number,
    field: PlaylistTrackSortField,
    direction: SortDirection
  ): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    await this.playlists.updateItemSort(playlistId, field, direction);
    this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_ORDER_CHANGED, playlistId);
  }

  async markPlaylistPlayed(playlistId: number, playedAt: number = Date.now()): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    await this.playlists.markPlayed(playlistId, playedAt);
    this.invalidations.publish(
      [RepositoryProjection.PLAYLIST_SUMMARIES],
      RepositoryInvalidationReason.PLAYLIST_PLAYED
    );
  }

  getPlaylistDetail(
    playlistId: number,
    offset: number = 0,
    limit: number = 100,
    field?: PlaylistTrackSortField,
    direction?: SortDirection
  ): Promise<PlaylistDetail | undefined> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.playlistDetail(playlistId, offset, limit));
    }
    return this.playlists.getPlaylistDetail(playlistId, offset, limit, field, direction);
  }

  getPlaylistTrackIds(
    playlistId: number,
    field?: PlaylistTrackSortField,
    direction?: SortDirection
  ): Promise<Array<number>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve(DemoMusicLibrary.playlistTrackIds(playlistId));
    }
    return this.playlists.getPlaylistTrackIds(playlistId, field, direction);
  }

  getPlaylistTransferCatalog(): Promise<Array<PlaylistTransferTrack>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.playlists.getTransferCatalog();
  }

  getPlaylistTransferTracks(playlistId: number): Promise<Array<PlaylistTransferTrack>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.playlists.getPlaylistTransferTracks(playlistId);
  }

  async addPlaylistItems(
    playlistId: number,
    items: Array<PlaylistItemInput>
  ): Promise<PlaylistMutationResult> {
    if (DemoLibraryMode.isEnabled()) {
      const result: PlaylistMutationResult =
        { requested: items.length, inserted: 0, alreadyPresent: 0, unavailable: 0 };
      return result;
    }
    const result = await this.playlists.addItems(playlistId, items);
    if (result.inserted > 0) {
      this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_ITEMS_CHANGED, playlistId);
    }
    return result;
  }

  async mergePlaylistItems(
    playlistId: number,
    items: Array<PlaylistItemInput>
  ): Promise<PlaylistMutationResult> {
    if (DemoLibraryMode.isEnabled()) {
      const result: PlaylistMutationResult =
        { requested: items.length, inserted: 0, alreadyPresent: 0, unavailable: 0 };
      return result;
    }
    const result = await this.playlists.mergeItems(playlistId, items);
    if (result.inserted > 0) {
      this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_ITEMS_CHANGED, playlistId);
    }
    return result;
  }

  async replacePlaylistItems(
    playlistId: number,
    items: Array<PlaylistItemInput>
  ): Promise<PlaylistMutationResult> {
    if (DemoLibraryMode.isEnabled()) {
      const result: PlaylistMutationResult =
        { requested: items.length, inserted: 0, alreadyPresent: 0, unavailable: 0 };
      return result;
    }
    const result = await this.playlists.replaceItems(playlistId, items);
    this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_ITEMS_CHANGED, playlistId);
    return result;
  }

  async removePlaylistItems(playlistId: number, trackIds: Array<number>): Promise<number> {
    if (DemoLibraryMode.isEnabled()) {
      return 0;
    }
    const removed = await this.playlists.removeItems(playlistId, trackIds);
    if (removed > 0) {
      this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_ITEMS_CHANGED, playlistId);
    }
    return removed;
  }

  async reorderPlaylistItems(playlistId: number, reorderedTrackIds: Array<number>): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    await this.playlists.reorderItems(playlistId, reorderedTrackIds);
    this.publishPlaylistChanged(RepositoryInvalidationReason.PLAYLIST_ORDER_CHANGED, playlistId);
  }

  async recordCompletedPlayback(
    trackId: number,
    completedAt: number = Date.now(),
    collectInPlaylist: boolean = true
  ): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return;
    }
    const completedPlaylistId = await this.playlists.recordCompletedPlayback(
      trackId,
      completedAt,
      collectInPlaylist
    );
    const projections = completedPlaylistId === undefined ?
      [RepositoryProjection.PLAYLIST_PLAYBACK_ORDER] :
      [
        RepositoryProjection.PLAYLIST_SUMMARIES,
        RepositoryProjection.PLAYLIST_DETAILS,
        RepositoryProjection.PLAYLIST_PLAYBACK_ORDER
      ];
    this.invalidations.publish(
      projections,
      RepositoryInvalidationReason.PLAYBACK_COMPLETED,
      completedPlaylistId === undefined ? PlaylistDetailTarget.NONE : PlaylistDetailTarget.IDS,
      completedPlaylistId === undefined ? [] : [completedPlaylistId]
    );
  }

  hasUri(uri: string): Promise<boolean> {
    return this.queries.hasUri(uri);
  }

  getPersistedMediaUris(): Promise<Array<string>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.queries.getPersistedMediaUris();
  }

  hasUris(uris: Array<string>): Promise<Array<string>> {
    return this.queries.hasUris(uris);
  }

  findDuplicateCandidates(fileSize: number, quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    return this.queries.findDuplicateCandidates(fileSize, quickFingerprint);
  }

  updateFullFingerprint(trackId: number, fullFingerprint: string): Promise<void> {
    return this.queries.updateFullFingerprint(trackId, fullFingerprint);
  }

  findArtworkBySourceHash(sourceHash: string): Promise<ArtworkAssetLookup | undefined> {
    return this.queries.findArtworkBySourceHash(sourceHash);
  }

  getUnreferencedArtworkAssets(): Promise<Array<ArtworkCleanupCandidate>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.queries.getUnreferencedArtworkAssets();
  }

  getReferencedArtworkPaths(): Promise<Array<string>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.queries.getReferencedArtworkPaths();
  }

  getPaletteRefreshAssets(): Promise<Array<PaletteRefreshAsset>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve([]);
    }
    return this.queries.getPaletteRefreshAssets();
  }

  async updateArtworkPalettes(updates: Array<ArtworkPaletteUpdate>): Promise<void> {
    if (updates.length === 0) {
      return;
    }
    await this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      for (let index = 0; index < updates.length; index += 1) {
        const update = updates[index];
        await transaction.execute(
          `UPDATE artwork_asset SET palette_primary = ?, palette_secondary = ?,
            palette_accent = ?, palette_version = ? WHERE id = ?`,
          [update.palette.primary, update.palette.secondary, update.palette.accent,
            ARTWORK_PALETTE_VERSION, update.id]
        );
      }
    });
    this.notifyContentChanged(RepositoryContentChangeKind.ARTWORK);
  }

  removeUnreferencedArtwork(assetId: number): Promise<void> {
    return this.queries.removeUnreferencedArtwork(assetId);
  }

  importTrack(input: TrackImportInput): Promise<ImportTrackResult> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.reject(new Error('演示音乐库开启时不能导入音乐'));
    }
    return this.importer.importTrack(input);
  }

  importTracks(inputs: Array<TrackImportInput>): Promise<Array<ImportTrackResult>> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.reject(new Error('演示音乐库开启时不能导入音乐'));
    }
    return this.importer.importTracks(inputs);
  }

  refreshTrack(trackId: number, input: TrackImportInput): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      return Promise.resolve();
    }
    return this.importer.refreshTrack(trackId, input);
  }

  markArtworkProcessing(trackId: number, fileSize: number, modifiedAt: number): Promise<boolean> {
    return this.importer.markArtworkProcessing(trackId, fileSize, modifiedAt);
  }

  completeArtwork(trackId: number, fileSize: number, modifiedAt: number,
    artworks: Array<ArtworkImportInput>): Promise<boolean> {
    return this.importer.completeArtwork(trackId, fileSize, modifiedAt, artworks);
  }

  failArtwork(trackId: number, fileSize: number, modifiedAt: number, message: string): Promise<void> {
    return this.importer.failArtwork(trackId, fileSize, modifiedAt, message);
  }

  deferArtwork(trackId: number, fileSize: number, modifiedAt: number): Promise<void> {
    return this.importer.deferArtwork(trackId, fileSize, modifiedAt);
  }

  private publishAvailabilityChanged(): void {
    this.invalidations.publish(
      [
        RepositoryProjection.LIBRARY_SUMMARY,
        RepositoryProjection.LIBRARY_TRACKS,
        RepositoryProjection.LIBRARY_ALBUMS,
        RepositoryProjection.UNAVAILABLE_TRACKS,
        RepositoryProjection.PLAYLIST_DETAILS
      ],
      RepositoryInvalidationReason.TRACK_AVAILABILITY_CHANGED,
      PlaylistDetailTarget.ALL
    );
  }

  private publishPlaylistChanged(reason: RepositoryInvalidationReason, playlistId: number): void {
    this.invalidations.publish(
      [RepositoryProjection.PLAYLIST_SUMMARIES, RepositoryProjection.PLAYLIST_DETAILS],
      reason,
      PlaylistDetailTarget.IDS,
      [playlistId]
    );
  }

  private static allLibraryAndPlaylistProjections(): Array<RepositoryProjection> {
    return [
      RepositoryProjection.LIBRARY_SUMMARY,
      RepositoryProjection.LIBRARY_TRACKS,
      RepositoryProjection.LIBRARY_ALBUMS,
      RepositoryProjection.UNAVAILABLE_TRACKS,
      RepositoryProjection.PLAYLIST_SUMMARIES,
      RepositoryProjection.PLAYLIST_DETAILS
    ];
  }
}
