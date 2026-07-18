import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  AlbumSortField,
  AlbumDetail,
  ArtistReference,
  ArtistDetail,
  AvailabilityState,
  AlbumListItem,
  LibraryCatalog,
  LibraryPage,
  PlaylistDetail,
  PlaylistItemInput,
  PlaylistMutationResult,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackSortField,
  PlaylistTransferTrack,
  LibrarySnapshot,
  LibraryStatistics,
  SortDirection,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField
} from '../model/LibraryModels';
import { PlaybackTrack, QueueTrack, ResumeState } from '../../playback/model/PlaybackModels';
import { LibraryDatabase } from './LibraryDatabase';
import { MusicLibraryImporter } from './MusicLibraryImporter';
import { MusicLibraryQueries } from './MusicLibraryQueries';
import {
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate,
  ImportTrackResult,
  TrackImportInput
} from './MusicRepositoryTypes';
import { ArtworkPaletteUpdate, PaletteRefreshAsset } from './MusicRepositoryTypes';
import { ARTWORK_PALETTE_VERSION } from '../artwork/ArtworkPaletteExtractor';
import { PlaylistRepository } from '../../playlist/data/PlaylistRepository';

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

  initialize(context: common.Context): Promise<boolean> {
    return this.database.initialize(context);
  }

  close(): Promise<void> {
    return this.database.close();
  }

  clearLibrary(): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
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
  }

  rebuildSortIndexes(): Promise<void> {
    return this.database.rebuildSortIndexes();
  }

  getStatistics(): Promise<LibraryStatistics> {
    return this.queries.getStatistics();
  }

  getTracks(
    field: TrackSortField,
    direction: SortDirection
  ): Promise<LibrarySnapshot<TrackListItem>> {
    return this.queries.getTracks(field, direction);
  }

  getTrackCatalog(field: TrackSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.queries.getTrackCatalog(field, direction);
  }

  getTrackPage(field: TrackSortField, direction: SortDirection,
    offset: number, limit: number): Promise<LibraryPage<TrackListItem>> {
    return this.queries.getTrackPage(field, direction, offset, limit);
  }

  getPlaybackTrack(trackId: number): Promise<PlaybackTrack | undefined> {
    return this.queries.getPlaybackTrack(trackId);
  }

  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>> {
    return this.queries.getPlaybackQueueTracks(trackIds);
  }

  getResumeState(trackId: number): Promise<ResumeState> {
    return this.queries.getResumeState(trackId);
  }

  savePlaybackState(trackId: number, positionMs: number, durationMs: number, completed: boolean): Promise<void> {
    return this.queries.savePlaybackState(trackId, positionMs, durationMs, completed);
  }

  setTrackAvailability(
    trackId: number,
    state: AvailabilityState
  ): Promise<void> {
    return this.queries.setTrackAvailability(trackId, state);
  }

  getAlbums(
    field: AlbumSortField,
    direction: SortDirection
  ): Promise<LibrarySnapshot<AlbumListItem>> {
    return this.queries.getAlbums(field, direction);
  }

  getAlbumCatalog(field: AlbumSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.queries.getAlbumCatalog(field, direction);
  }

  getAlbumPage(field: AlbumSortField, direction: SortDirection,
    offset: number, limit: number): Promise<LibraryPage<AlbumListItem>> {
    return this.queries.getAlbumPage(field, direction, offset, limit);
  }

  getAlbumDetail(albumId: number): Promise<AlbumDetail | undefined> {
    return this.queries.getAlbumDetail(albumId);
  }

  getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    return this.queries.getAlbumArtists(albumId);
  }

  getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    return this.queries.getArtistDetail(artistId);
  }

  getTrackNavigationTargets(trackId: number): Promise<TrackNavigationTargets | undefined> {
    return this.queries.getTrackNavigationTargets(trackId);
  }

  getPlaylists(field: PlaylistSortField, direction: SortDirection): Promise<Array<PlaylistSummary>> {
    return this.playlists.getPlaylists(field, direction);
  }

  getPlaylist(playlistId: number): Promise<PlaylistSummary | undefined> {
    return this.playlists.getPlaylist(playlistId);
  }

  getCompletedPlaylist(): Promise<PlaylistSummary> {
    return this.playlists.getCompletedPlaylist();
  }

  createPlaylist(name: string): Promise<PlaylistSummary> {
    return this.playlists.createPlaylist(name);
  }

  renamePlaylist(playlistId: number, name: string): Promise<PlaylistSummary> {
    return this.playlists.renamePlaylist(playlistId, name);
  }

  deletePlaylist(playlistId: number): Promise<void> {
    return this.playlists.deletePlaylist(playlistId);
  }

  updatePlaylistItemSort(
    playlistId: number,
    field: PlaylistTrackSortField,
    direction: SortDirection
  ): Promise<void> {
    return this.playlists.updateItemSort(playlistId, field, direction);
  }

  markPlaylistPlayed(playlistId: number, playedAt: number = Date.now()): Promise<void> {
    return this.playlists.markPlayed(playlistId, playedAt);
  }

  getPlaylistDetail(
    playlistId: number,
    offset: number = 0,
    limit: number = 100,
    field?: PlaylistTrackSortField,
    direction?: SortDirection
  ): Promise<PlaylistDetail | undefined> {
    return this.playlists.getPlaylistDetail(playlistId, offset, limit, field, direction);
  }

  getPlaylistTrackIds(
    playlistId: number,
    field?: PlaylistTrackSortField,
    direction?: SortDirection
  ): Promise<Array<number>> {
    return this.playlists.getPlaylistTrackIds(playlistId, field, direction);
  }

  getPlaylistTransferCatalog(): Promise<Array<PlaylistTransferTrack>> {
    return this.playlists.getTransferCatalog();
  }

  getPlaylistTransferTracks(playlistId: number): Promise<Array<PlaylistTransferTrack>> {
    return this.playlists.getPlaylistTransferTracks(playlistId);
  }

  addPlaylistItems(
    playlistId: number,
    items: Array<PlaylistItemInput>
  ): Promise<PlaylistMutationResult> {
    return this.playlists.addItems(playlistId, items);
  }

  mergePlaylistItems(
    playlistId: number,
    items: Array<PlaylistItemInput>
  ): Promise<PlaylistMutationResult> {
    return this.playlists.mergeItems(playlistId, items);
  }

  replacePlaylistItems(
    playlistId: number,
    items: Array<PlaylistItemInput>
  ): Promise<PlaylistMutationResult> {
    return this.playlists.replaceItems(playlistId, items);
  }

  removePlaylistItems(playlistId: number, trackIds: Array<number>): Promise<number> {
    return this.playlists.removeItems(playlistId, trackIds);
  }

  reorderPlaylistItems(playlistId: number, reorderedTrackIds: Array<number>): Promise<void> {
    return this.playlists.reorderItems(playlistId, reorderedTrackIds);
  }

  recordCompletedPlayback(
    trackId: number,
    completedAt: number = Date.now(),
    collectInPlaylist: boolean = true
  ): Promise<void> {
    return this.playlists.recordCompletedPlayback(trackId, completedAt, collectInPlaylist);
  }

  hasUri(uri: string): Promise<boolean> {
    return this.queries.hasUri(uri);
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
    return this.queries.getUnreferencedArtworkAssets();
  }

  getReferencedArtworkPaths(): Promise<Array<string>> {
    return this.queries.getReferencedArtworkPaths();
  }

  getPaletteRefreshAssets(): Promise<Array<PaletteRefreshAsset>> {
    return this.queries.getPaletteRefreshAssets();
  }

  updateArtworkPalettes(updates: Array<ArtworkPaletteUpdate>): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
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
  }

  removeUnreferencedArtwork(assetId: number): Promise<void> {
    return this.queries.removeUnreferencedArtwork(assetId);
  }

  importTrack(input: TrackImportInput): Promise<ImportTrackResult> {
    return this.importer.importTrack(input);
  }

  importTracks(inputs: Array<TrackImportInput>): Promise<Array<ImportTrackResult>> {
    return this.importer.importTracks(inputs);
  }
}
