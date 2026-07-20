import { relationalStore } from '@kit.ArkData';
import {
  AlbumReference,
  AlbumListItem,
  AlbumDetail,
  AlbumSortField,
  ArtistDetail,
  ArtistReference,
  AvailabilityState,
  ArtworkState,
  ArtworkPictureType,
  CreditRole,
  LibraryCatalog,
  LibraryIndexPresentation,
  LibraryPage,
  LibrarySection,
  LibrarySnapshot,
  LibraryStatistics,
  MediaFormat,
  MediaFileCheckCandidate,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField,
  TrackAvailabilityUpdate,
  SortDirection,
  UnavailableTrackItem
} from '../model/LibraryModels';
import { PlaybackTrack, QueueTrack, ResumeState } from '../../playback/model/PlaybackModels';
import { LibraryDatabase } from './LibraryDatabase';
import {
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate
} from './MusicRepositoryTypes';
import { PaletteRefreshAsset } from './MusicRepositoryTypes';
import { LibrarySortDescriptor, LibrarySortPlan } from './LibrarySortPlan';
import { RelationalStoreSafety } from './RelationalStoreSafety';

const URI_QUERY_BATCH_SIZE = 128;
const PLAYBACK_QUEUE_QUERY_BATCH_SIZE = 128;

/**
 * Read-only and maintenance queries for the local library.
 * Transactional import work lives in MusicLibraryImporter.
 */
export class MusicLibraryQueries {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  async getStatistics(): Promise<LibraryStatistics> {
    const store = this.database.getStore();
    return {
      trackCount: await this.readCount(store, 'SELECT COUNT(*) FROM track'),
      albumCount: await this.readCount(store, 'SELECT COUNT(*) FROM album'),
      artworkCount: await this.readCount(store, 'SELECT COUNT(*) FROM artwork_asset WHERE ref_count > 0'),
      unavailableTrackCount: await this.readCount(
        store,
        `SELECT COUNT(*) FROM media_file WHERE availability_state <> ${AvailabilityState.AVAILABLE}`
      )
    };
  }

  async getTracks(field: TrackSortField, direction: SortDirection): Promise<LibrarySnapshot<TrackListItem>> {
    const descriptor = LibrarySortPlan.track(field, direction);
    const items = await this.queryTrackItems(descriptor);
    return {
      items: items,
      sections: descriptor.alphabetic ? this.buildSections(items) : [],
      indexPresentation: descriptor.indexPresentation()
    };
  }

  getTrackCatalog(field: TrackSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.queryCatalog('track t', LibrarySortPlan.track(field, direction));
  }

  async getTrackPage(field: TrackSortField, direction: SortDirection,
    offset: number, limit: number): Promise<LibraryPage<TrackListItem>> {
    const safeOffset = MusicLibraryQueries.pageOffset(offset);
    const safeLimit = MusicLibraryQueries.pageLimit(limit);
    return {
      offset: safeOffset,
      items: await this.queryTrackItems(LibrarySortPlan.track(field, direction), safeOffset, safeLimit)
    };
  }

  private async queryTrackItems(descriptor: LibrarySortDescriptor,
    offset?: number, limit?: number): Promise<Array<TrackListItem>> {
    const paged = offset !== undefined && limit !== undefined;
    const paginationClause = paged ? ' LIMIT ? OFFSET ?' : '';
    const bindArgs: Array<number> = paged ? [limit as number, offset as number] : [];
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<TrackListItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
          COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
          COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
          COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), ${descriptor.sectionExpression},
          m.availability_state
         FROM track t
         JOIN media_file m ON m.id = t.media_file_id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         ORDER BY ${descriptor.orderClause}${paginationClause}`,
        bindArgs
      );
      while (resultSet.goToNextRow()) {
        items.push({
          id: resultSet.getLong(0),
          title: resultSet.getString(1),
          artistDisplay: resultSet.getString(2),
          albumDisplay: resultSet.getString(3),
          durationMs: resultSet.getLong(4),
          trackNumber: resultSet.getLong(5),
          discNumber: resultSet.getLong(6),
          smallArtworkHash: resultSet.getString(7),
          smallArtworkPath: resultSet.getString(8),
          artworkHash: resultSet.getString(9),
          artworkPath: resultSet.getString(10),
          artworkWidth: resultSet.getLong(11),
          artworkHeight: resultSet.getLong(12),
          palettePrimary: resultSet.getString(13),
          paletteSecondary: resultSet.getString(14),
          paletteAccent: resultSet.getString(15),
          sectionKey: resultSet.getString(16),
          availability: resultSet.getLong(17) as AvailabilityState
        });
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query tracks', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track list');
    }
  }

  async getPlaybackTrack(trackId: number): Promise<PlaybackTrack | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
          m.uri, m.file_size, m.modified_at, m.format, m.availability_state,
          m.authorization_persisted, COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
          COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'),
          COALESCE(ta.picture_type, 0), COALESCE(ta.mime_type, ''), COALESCE(ta.description, ''),
          COALESCE(ta.width, 0), COALESCE(ta.height, 0), COALESCE(ta.color_depth, 0),
          COALESCE(ta.byte_offset, 0), COALESCE(ta.byte_length, 0), COALESCE(ta.payload_offset, 0),
          COALESCE(ta.ordinal, 0), COALESCE(ta.unsynchronized, 0)
         FROM track t
         JOIN media_file m ON m.id = t.media_file_id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         LEFT JOIN track_artwork ta ON ta.id = (
           SELECT selected.id FROM track_artwork selected
           WHERE selected.track_id = t.id AND selected.asset_id = t.primary_artwork_id
           ORDER BY selected.picture_type = 3 DESC, selected.ordinal ASC LIMIT 1
         )
         WHERE t.id = ? LIMIT 1`,
        [trackId]
      );
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      const byteLength = resultSet.getLong(27);
      const track: PlaybackTrack = {
        id: resultSet.getLong(0),
        title: resultSet.getString(1),
        artistDisplay: resultSet.getString(2),
        albumDisplay: resultSet.getString(3),
        durationMs: resultSet.getLong(4),
        uri: resultSet.getString(5),
        fileSize: resultSet.getLong(6),
        modifiedAt: resultSet.getLong(7),
        format: resultSet.getString(8) as MediaFormat,
        availability: resultSet.getLong(9) as AvailabilityState,
        authorizationPersisted: resultSet.getLong(10) === 1,
        smallArtworkHash: resultSet.getString(11),
        smallArtworkPath: resultSet.getString(12),
        largeArtworkHash: resultSet.getString(13),
        largeArtworkPath: resultSet.getString(14),
        artworkWidth: resultSet.getLong(15),
        artworkHeight: resultSet.getLong(16),
        palettePrimary: resultSet.getString(17),
        paletteSecondary: resultSet.getString(18),
        paletteAccent: resultSet.getString(19)
      };
      if (byteLength > 0) {
        track.artwork = {
          pictureType: resultSet.getLong(20) as ArtworkPictureType,
          mimeType: resultSet.getString(21),
          description: resultSet.getString(22),
          width: resultSet.getLong(23),
          height: resultSet.getLong(24),
          colorDepth: resultSet.getLong(25),
          byteOffset: resultSet.getLong(26),
          byteLength: byteLength,
          payloadOffset: resultSet.getLong(28),
          ordinal: resultSet.getLong(29),
          unsynchronized: resultSet.getLong(30) === 1
        };
      }
      return track;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read playback track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'playback track');
    }
  }

  async getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>> {
    if (trackIds.length === 0) {
      return [];
    }
    const uniqueTrackIds: Array<number> = [];
    const seenTrackIds: Set<number> = new Set<number>();
    trackIds.forEach((trackId: number) => {
      if (!seenTrackIds.has(trackId)) {
        seenTrackIds.add(trackId);
        uniqueTrackIds.push(trackId);
      }
    });
    const tracksById: Map<number, QueueTrack> = new Map<number, QueueTrack>();
    for (let offset = 0; offset < uniqueTrackIds.length; offset += PLAYBACK_QUEUE_QUERY_BATCH_SIZE) {
      const batch = uniqueTrackIds.slice(
        offset,
        Math.min(offset + PLAYBACK_QUEUE_QUERY_BATCH_SIZE, uniqueTrackIds.length)
      );
      await this.queryPlaybackQueueTrackBatch(batch, tracksById);
    }
    const tracks: Array<QueueTrack> = [];
    trackIds.forEach((trackId: number) => {
      const track = tracksById.get(trackId);
      if (track !== undefined) {
        tracks.push(track);
      }
    });
    return tracks;
  }

  private async queryPlaybackQueueTrackBatch(trackIds: Array<number>,
    tracksById: Map<number, QueueTrack>): Promise<void> {
    if (trackIds.length === 0) {
      return;
    }
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      const placeholders = trackIds.map((_trackId: number) => '?').join(', ');
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
          COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
          COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347')
         FROM track t
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         WHERE t.id IN (${placeholders})`,
        trackIds
      );
      while (resultSet.goToNextRow()) {
        const track: QueueTrack = {
          id: resultSet.getLong(0),
          title: resultSet.getString(1),
          artistDisplay: resultSet.getString(2),
          albumDisplay: resultSet.getString(3),
          durationMs: resultSet.getLong(4),
          smallArtworkHash: resultSet.getString(5),
          smallArtworkPath: resultSet.getString(6),
          largeArtworkHash: resultSet.getString(7),
          largeArtworkPath: resultSet.getString(8),
          artworkWidth: resultSet.getLong(9),
          artworkHeight: resultSet.getLong(10),
          palettePrimary: resultSet.getString(11),
          paletteSecondary: resultSet.getString(12),
          paletteAccent: resultSet.getString(13)
        };
        tracksById.set(track.id, track);
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to restore playback queue', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'playback queue');
    }
  }

  async getResumeState(trackId: number): Promise<ResumeState> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT resume_position_ms, duration_ms, completed
         FROM track_playback_state WHERE track_id = ? LIMIT 1`,
        [trackId]
      );
      if (!resultSet.goToNextRow() || resultSet.getLong(2) === 1) {
        return { positionMs: 0, durationMs: 0 };
      }
      return { positionMs: resultSet.getLong(0), durationMs: resultSet.getLong(1) };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read resume state for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'resume state');
    }
  }

  savePlaybackState(trackId: number, positionMs: number, durationMs: number,
    completed: boolean): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      const now = Date.now();
      await transaction.execute(
        `INSERT OR REPLACE INTO track_playback_state(
          track_id, resume_position_ms, duration_ms, completed, last_played_at, updated_at
        ) VALUES(?, ?, ?, ?, ?, ?)`,
        [trackId, positionMs, durationMs, completed ? 1 : 0, now, now]
      );
    });
  }

  setTrackAvailability(trackId: number, state: AvailabilityState): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(
        `UPDATE media_file SET availability_state = ?, last_checked_at = ?, updated_at = ?
         WHERE id = (SELECT media_file_id FROM track WHERE id = ?)`,
        [state, Date.now(), Date.now(), trackId]
      );
    });
  }

  setTrackAvailabilities(updates: Array<TrackAvailabilityUpdate>): Promise<void> {
    if (updates.length === 0) {
      return Promise.resolve();
    }
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction): Promise<void> => {
      const now = Date.now();
      for (let index = 0; index < updates.length; index += 1) {
        const update = updates[index];
        await transaction.execute(
          `UPDATE media_file SET availability_state = ?, last_checked_at = ?, updated_at = ?
           WHERE id = (SELECT media_file_id FROM track WHERE id = ?)`,
          [update.state, now, now, update.trackId]
        );
      }
    });
  }

  async getMediaFileCheckCandidates(): Promise<Array<MediaFileCheckCandidate>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<MediaFileCheckCandidate> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, f.uri, f.display_name, f.file_size, f.modified_at, f.availability_state,
           f.artwork_state, f.artwork_attempt_count, f.artwork_last_attempt_at,
           COALESCE(a.small_path, ''), COALESCE(a.large_path, '')
         FROM media_file f JOIN track t ON t.media_file_id = f.id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         ORDER BY t.id`
      );
      while (resultSet.goToNextRow()) {
        items.push({
          trackId: resultSet.getLong(0),
          uri: resultSet.getString(1),
          displayName: resultSet.getString(2),
          fileSize: resultSet.getLong(3),
          modifiedAt: resultSet.getLong(4),
          availability: resultSet.getLong(5) as AvailabilityState,
          artworkState: resultSet.getLong(6) as ArtworkState,
          artworkAttemptCount: resultSet.getLong(7),
          artworkLastAttemptAt: resultSet.getLong(8),
          artworkSmallPath: resultSet.getString(9),
          artworkLargePath: resultSet.getString(10)
        });
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query media file check candidates', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'media file check candidates');
    }
  }

  async getUnavailableTracks(): Promise<Array<UnavailableTrackItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<UnavailableTrackItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display,
          f.display_name, f.uri, f.availability_state
         FROM track t JOIN media_file f ON f.id = t.media_file_id
         WHERE f.availability_state <> ?
         ORDER BY t.title_natural_key, t.id`,
        [AvailabilityState.AVAILABLE]
      );
      while (resultSet.goToNextRow()) {
        items.push({
          trackId: resultSet.getLong(0),
          title: resultSet.getString(1),
          artistDisplay: resultSet.getString(2),
          albumDisplay: resultSet.getString(3),
          displayName: resultSet.getString(4),
          uri: resultSet.getString(5),
          availability: resultSet.getLong(6) as AvailabilityState
        });
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query unavailable tracks', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'unavailable tracks');
    }
  }

  async getAlbums(field: AlbumSortField, direction: SortDirection): Promise<LibrarySnapshot<AlbumListItem>> {
    const descriptor = LibrarySortPlan.album(field, direction);
    const items = await this.queryAlbumItems(descriptor);
    return {
      items: items,
      sections: descriptor.alphabetic ? this.buildSections(items) : [],
      indexPresentation: descriptor.indexPresentation()
    };
  }

  getAlbumCatalog(field: AlbumSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.queryCatalog('album al', LibrarySortPlan.album(field, direction));
  }

  async getAlbumPage(field: AlbumSortField, direction: SortDirection,
    offset: number, limit: number): Promise<LibraryPage<AlbumListItem>> {
    const safeOffset = MusicLibraryQueries.pageOffset(offset);
    const safeLimit = MusicLibraryQueries.pageLimit(limit);
    return {
      offset: safeOffset,
      items: await this.queryAlbumItems(LibrarySortPlan.album(field, direction), safeOffset, safeLimit)
    };
  }

  private async queryAlbumItems(descriptor: LibrarySortDescriptor,
    offset?: number, limit?: number): Promise<Array<AlbumListItem>> {
    const paged = offset !== undefined && limit !== undefined;
    const paginationClause = paged ? ' LIMIT ? OFFSET ?' : '';
    const bindArgs: Array<number> = paged ? [limit as number, offset as number] : [];
    try {
      const resultSet = await this.database.getStore().querySql(
        `SELECT al.id, al.title, al.album_artist_display, al.track_count,
          al.total_duration_ms, COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), ${descriptor.sectionExpression},
          (SELECT COUNT(*) FROM track unavailable_track
           JOIN media_file unavailable_file ON unavailable_file.id = unavailable_track.media_file_id
           WHERE unavailable_track.album_id = al.id
             AND unavailable_file.availability_state <> ${AvailabilityState.AVAILABLE})
         FROM album al LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
         ORDER BY ${descriptor.orderClause}${paginationClause}`,
        bindArgs
      );
      return this.readAlbumListItems(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query albums', error);
    }
  }

  async getAlbumDetail(albumId: number): Promise<AlbumDetail | undefined> {
    let albumResult: relationalStore.ResultSet | undefined;
    let album: AlbumListItem | undefined;
    let releaseYear: number = 0;
    let genreDisplay: string = '';
    try {
      albumResult = await this.database.getStore().querySql(
        `SELECT al.id, al.title, al.album_artist_display, al.track_count,
          al.total_duration_ms, COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), '#',
          (SELECT COUNT(*) FROM track unavailable_track
           JOIN media_file unavailable_file ON unavailable_file.id = unavailable_track.media_file_id
           WHERE unavailable_track.album_id = al.id
             AND unavailable_file.availability_state <> ${AvailabilityState.AVAILABLE}),
          COALESCE(al.release_year, 0),
          COALESCE((SELECT GROUP_CONCAT(g.name) FROM genre g WHERE g.id IN (
            SELECT tg.genre_id FROM track_genre tg JOIN track grouped_track ON grouped_track.id = tg.track_id
            WHERE grouped_track.album_id = al.id
          )), '')
         FROM album al LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
         WHERE al.id = ? LIMIT 1`,
        [albumId]
      );
      if (albumResult.goToNextRow()) {
        album = {
          id: albumResult.getLong(0),
          title: albumResult.getString(1),
          albumArtistDisplay: albumResult.getString(2),
          trackCount: albumResult.getLong(3),
          totalDurationMs: albumResult.getLong(4),
          artworkPath: albumResult.getString(5),
          artworkWidth: albumResult.getLong(6),
          artworkHeight: albumResult.getLong(7),
          palettePrimary: albumResult.getString(8),
          paletteSecondary: albumResult.getString(9),
          paletteAccent: albumResult.getString(10),
          sectionKey: albumResult.getString(11),
          unavailableTrackCount: albumResult.getLong(12)
        };
        releaseYear = albumResult.getLong(13);
        genreDisplay = albumResult.getString(14);
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read album ${albumId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(albumResult, 'album detail');
    }
    if (album === undefined) {
      return undefined;
    }
    let trackResult: relationalStore.ResultSet | undefined;
    const tracks: Array<TrackListItem> = [];
    try {
      trackResult = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
          COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
          COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
          COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), '#', m.availability_state
         FROM track t
         JOIN media_file m ON m.id = t.media_file_id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         WHERE t.album_id = ?
         ORDER BY CASE WHEN t.disc_number IS NULL OR t.disc_number <= 0 THEN 1 ELSE 0 END,
          t.disc_number ASC,
          CASE WHEN t.track_number IS NULL OR t.track_number <= 0 THEN 1 ELSE 0 END,
          t.track_number ASC, t.id ASC`,
        [albumId]
      );
      while (trackResult.goToNextRow()) {
        tracks.push({
          id: trackResult.getLong(0), title: trackResult.getString(1),
          artistDisplay: trackResult.getString(2), albumDisplay: trackResult.getString(3),
          durationMs: trackResult.getLong(4), trackNumber: trackResult.getLong(5),
          discNumber: trackResult.getLong(6), smallArtworkHash: trackResult.getString(7),
          smallArtworkPath: trackResult.getString(8), artworkHash: trackResult.getString(9),
          artworkPath: trackResult.getString(10), artworkWidth: trackResult.getLong(11),
          artworkHeight: trackResult.getLong(12), palettePrimary: trackResult.getString(13),
          paletteSecondary: trackResult.getString(14), paletteAccent: trackResult.getString(15),
          sectionKey: trackResult.getString(16),
          availability: trackResult.getLong(17) as AvailabilityState
        });
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read album tracks ${albumId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(trackResult, 'album tracks');
    }
    const albumArtists = await this.getAlbumArtists(albumId);
    return {
      album: album,
      albumArtists: albumArtists,
      relatedAlbums: albumArtists.length > 0 ? await this.getRelatedAlbums(albumId) : [],
      releaseYear: releaseYear,
      genreDisplay: genreDisplay,
      tracks: tracks
    };
  }

  async getTrackNavigationTargets(trackId: number): Promise<TrackNavigationTargets | undefined> {
    let albumResult: relationalStore.ResultSet | undefined;
    let albumId = -1;
    let album: AlbumReference | undefined;
    try {
      albumResult = await this.database.getStore().querySql(
        `SELECT t.album_id, COALESCE(al.title, ''), COALESCE(a.palette_primary, '#FF7C4DFF')
         FROM track t
         LEFT JOIN album al ON al.id = t.album_id
         LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
         WHERE t.id = ? LIMIT 1`,
        [trackId]
      );
      if (!albumResult.goToNextRow()) {
        return undefined;
      }
      if (!albumResult.isColumnNull(0)) {
        albumId = albumResult.getLong(0);
        album = {
          id: albumId,
          title: albumResult.getString(1),
          palettePrimary: albumResult.getString(2)
        };
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read navigation targets for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(albumResult, 'track navigation');
    }
    return {
      trackId: trackId,
      trackArtists: await this.getTrackArtists(trackId),
      albumArtists: albumId >= 0 ? await this.getAlbumArtists(albumId) : [],
      album: album
    };
  }

  async getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    let artistResult: relationalStore.ResultSet | undefined;
    let artist: ArtistReference | undefined;
    try {
      artistResult = await this.database.getStore().querySql(
        'SELECT id, name FROM person WHERE id = ? LIMIT 1',
        [artistId]
      );
      if (artistResult.goToNextRow()) {
        artist = {
          id: artistResult.getLong(0),
          name: artistResult.getString(1)
        };
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artist ${artistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(artistResult, 'artist detail');
    }
    if (artist === undefined) {
      return undefined;
    }
    const albums = await this.getArtistAlbums(artistId);
    const tracks = await this.getArtistTracks(artistId);
    let totalDurationMs = 0;
    for (let index = 0; index < tracks.length; index += 1) {
      totalDurationMs += tracks[index].durationMs;
    }
    return {
      artist: artist,
      albumCount: albums.length,
      trackCount: tracks.length,
      totalDurationMs: totalDurationMs,
      albums: albums,
      tracks: tracks
    };
  }

  private async getTrackArtists(trackId: number): Promise<Array<ArtistReference>> {
    try {
      const resultSet = await this.database.getStore().querySql(
        `SELECT p.id, p.name
         FROM track_credit tc JOIN person p ON p.id = tc.person_id
         WHERE tc.track_id = ? AND tc.role = ?
         ORDER BY tc.ordinal`,
        [trackId, CreditRole.TRACK_ARTIST]
      );
      return this.readArtistReferences(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artists for track ${trackId}`, error);
    }
  }

  async getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    try {
      const resultSet = await this.database.getStore().querySql(
        `SELECT p.id, p.name
         FROM album_credit ac JOIN person p ON p.id = ac.person_id
         WHERE ac.album_id = ?
         ORDER BY ac.ordinal`,
        [albumId]
      );
      return this.readArtistReferences(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artists for album ${albumId}`, error);
    }
  }

  private readArtistReferences(resultSet: relationalStore.ResultSet): Array<ArtistReference> {
    const artists: Array<ArtistReference> = [];
    try {
      while (resultSet.goToNextRow()) {
        artists.push({
          id: resultSet.getLong(0),
          name: resultSet.getString(1)
        });
      }
      return artists;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to decode artist references', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist references');
    }
  }

  private async getArtistAlbums(artistId: number): Promise<Array<AlbumListItem>> {
    try {
      const resultSet = await this.database.getStore().querySql(
        `SELECT DISTINCT al.id, al.title, al.album_artist_display, al.track_count,
          al.total_duration_ms, COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), '#',
          (SELECT COUNT(*) FROM track unavailable_track
           JOIN media_file unavailable_file ON unavailable_file.id = unavailable_track.media_file_id
           WHERE unavailable_track.album_id = al.id
             AND unavailable_file.availability_state <> ${AvailabilityState.AVAILABLE})
         FROM album_credit ac
         JOIN album al ON al.id = ac.album_id
         LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
         WHERE ac.person_id = ?
         ORDER BY al.release_date_sort DESC, al.sort_title_key, al.id`,
        [artistId]
      );
      return this.readAlbumListItems(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read albums for artist ${artistId}`, error);
    }
  }

  private async getRelatedAlbums(albumId: number): Promise<Array<AlbumListItem>> {
    try {
      const resultSet = await this.database.getStore().querySql(
        `SELECT DISTINCT al.id, al.title, al.album_artist_display, al.track_count,
          al.total_duration_ms, COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), '#',
          (SELECT COUNT(*) FROM track unavailable_track
           JOIN media_file unavailable_file ON unavailable_file.id = unavailable_track.media_file_id
           WHERE unavailable_track.album_id = al.id
             AND unavailable_file.availability_state <> ${AvailabilityState.AVAILABLE})
         FROM album_credit current_credit
         JOIN album_credit related_credit
           ON related_credit.person_id = current_credit.person_id
         JOIN album al ON al.id = related_credit.album_id
         LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
         WHERE current_credit.album_id = ?
           AND al.id <> ?
         ORDER BY al.release_date_sort DESC, al.sort_title_key, al.id`,
        [albumId, albumId]
      );
      return this.readAlbumListItems(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read albums related to ${albumId}`, error);
    }
  }

  private readAlbumListItems(resultSet: relationalStore.ResultSet): Array<AlbumListItem> {
    const albums: Array<AlbumListItem> = [];
    try {
      while (resultSet.goToNextRow()) {
        albums.push({
          id: resultSet.getLong(0),
          title: resultSet.getString(1),
          albumArtistDisplay: resultSet.getString(2),
          trackCount: resultSet.getLong(3),
          totalDurationMs: resultSet.getLong(4),
          artworkPath: resultSet.getString(5),
          artworkWidth: resultSet.getLong(6),
          artworkHeight: resultSet.getLong(7),
          palettePrimary: resultSet.getString(8),
          paletteSecondary: resultSet.getString(9),
          paletteAccent: resultSet.getString(10),
          sectionKey: resultSet.getString(11),
          unavailableTrackCount: resultSet.getLong(12)
        });
      }
      return albums;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to decode album list', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'album list');
    }
  }

  private async getArtistTracks(artistId: number): Promise<Array<TrackListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const tracks: Array<TrackListItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
          COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
          COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
          COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
          COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
          COALESCE(a.palette_accent, '#FFFFB347'), '#', m.availability_state
         FROM track t
         JOIN media_file m ON m.id = t.media_file_id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         WHERE EXISTS (
           SELECT 1 FROM track_credit tc
           WHERE tc.track_id = t.id AND tc.person_id = ? AND tc.role = ?
         ) OR EXISTS (
           SELECT 1 FROM album_credit ac
           WHERE ac.album_id = t.album_id AND ac.person_id = ?
         )
         ORDER BY t.album_natural_key,
          CASE WHEN t.disc_number IS NULL OR t.disc_number <= 0 THEN 1 ELSE 0 END,
          t.disc_number,
          CASE WHEN t.track_number IS NULL OR t.track_number <= 0 THEN 1 ELSE 0 END,
          t.track_number, t.title_natural_key, t.id`,
        [artistId, CreditRole.TRACK_ARTIST, artistId]
      );
      while (resultSet.goToNextRow()) {
        tracks.push({
          id: resultSet.getLong(0), title: resultSet.getString(1),
          artistDisplay: resultSet.getString(2), albumDisplay: resultSet.getString(3),
          durationMs: resultSet.getLong(4), trackNumber: resultSet.getLong(5),
          discNumber: resultSet.getLong(6), smallArtworkHash: resultSet.getString(7),
          smallArtworkPath: resultSet.getString(8), artworkHash: resultSet.getString(9),
          artworkPath: resultSet.getString(10), artworkWidth: resultSet.getLong(11),
          artworkHeight: resultSet.getLong(12), palettePrimary: resultSet.getString(13),
          paletteSecondary: resultSet.getString(14), paletteAccent: resultSet.getString(15),
          sectionKey: resultSet.getString(16),
          availability: resultSet.getLong(17) as AvailabilityState
        });
      }
      return tracks;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read tracks for artist ${artistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist tracks');
    }
  }

  async hasUri(uri: string): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT 1 FROM media_file WHERE uri = ? LIMIT 1',
        [uri]
      );
      return resultSet.goToNextRow();
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to check media URI ${uri}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'media URI lookup');
    }
  }

  async getPersistedMediaUris(): Promise<Array<string>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const uris: Array<string> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT uri FROM media_file WHERE authorization_persisted = 1 ORDER BY id'
      );
      while (resultSet.goToNextRow()) {
        const uri = resultSet.getString(0);
        if (uri.length > 0) {
          uris.push(uri);
        }
      }
      return uris;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read persisted media URIs', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'persisted media URI lookup');
    }
  }

  async hasUris(uris: Array<string>): Promise<Array<string>> {
    const existingUris: Array<string> = [];
    for (let offset = 0; offset < uris.length; offset += URI_QUERY_BATCH_SIZE) {
      const batch = uris.slice(offset, Math.min(offset + URI_QUERY_BATCH_SIZE, uris.length));
      if (batch.length === 0) {
        continue;
      }
      const placeholders = batch.map(() => '?').join(', ');
      let resultSet: relationalStore.ResultSet | undefined;
      try {
        resultSet = await this.database.getStore().querySql(
          `SELECT uri FROM media_file WHERE uri IN (${placeholders})`, batch
        );
        while (resultSet.goToNextRow()) {
          existingUris.push(resultSet.getString(0));
        }
      } catch (error) {
        throw RelationalStoreSafety.operationError(
          `Unable to check media URI batch at offset ${offset}`, error
        );
      } finally {
        RelationalStoreSafety.closeResultSet(resultSet, 'media URI batch lookup');
      }
    }
    return existingUris;
  }

  async findDuplicateCandidates(fileSize: number, quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    if (fileSize <= 0 || quickFingerprint.length === 0) {
      return [];
    }
    let resultSet: relationalStore.ResultSet | undefined;
    const candidates: Array<DuplicateCandidate> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, f.uri, f.content_fingerprint FROM media_file f
         JOIN track t ON t.media_file_id = f.id
         WHERE f.file_size = ? AND f.quick_fingerprint = ?`,
        [fileSize, quickFingerprint]
      );
      while (resultSet.goToNextRow()) {
        candidates.push({
          trackId: resultSet.getLong(0),
          uri: resultSet.getString(1),
          fullFingerprint: resultSet.getString(2)
        });
      }
      return candidates;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to find duplicate media candidates', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'duplicate media lookup');
    }
  }

  updateFullFingerprint(trackId: number, fullFingerprint: string): Promise<void> {
    if (fullFingerprint.length === 0) {
      return Promise.resolve();
    }
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(
        `UPDATE media_file SET content_fingerprint = ?, updated_at = ?
         WHERE id = (SELECT media_file_id FROM track WHERE id = ?) AND content_fingerprint = ''`,
        [fullFingerprint, Date.now(), trackId]
      );
    });
  }

  async findArtworkBySourceHash(sourceHash: string): Promise<ArtworkAssetLookup | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT a.small_hash, a.small_path, a.small_format, a.small_width, a.small_height, a.small_byte_size,
          a.large_hash, a.large_path, a.large_format, a.large_width, a.large_height, a.large_byte_size,
          a.palette_primary, a.palette_secondary, a.palette_accent
         FROM artwork_source s JOIN artwork_asset a ON a.id = s.asset_id
         WHERE s.source_hash = ? LIMIT 1`,
        [sourceHash]
      );
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      return {
        smallHash: resultSet.getString(0),
        smallPath: resultSet.getString(1),
        smallFormat: resultSet.getString(2),
        smallWidth: resultSet.getLong(3),
        smallHeight: resultSet.getLong(4),
        smallByteSize: resultSet.getLong(5),
        largeHash: resultSet.getString(6),
        largePath: resultSet.getString(7),
        largeFormat: resultSet.getString(8),
        largeWidth: resultSet.getLong(9),
        largeHeight: resultSet.getLong(10),
        largeByteSize: resultSet.getLong(11),
        palettePrimary: resultSet.getString(12),
        paletteSecondary: resultSet.getString(13),
        paletteAccent: resultSet.getString(14)
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to find artwork source ${sourceHash}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artwork source lookup');
    }
  }

  async getUnreferencedArtworkAssets(): Promise<Array<ArtworkCleanupCandidate>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const candidates: Array<ArtworkCleanupCandidate> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT candidate.id, candidate.small_path, candidate.large_path,
          NOT EXISTS (
            SELECT 1 FROM artwork_asset active
            WHERE active.id <> candidate.id AND active.ref_count > 0
              AND (active.small_path = candidate.small_path OR active.large_path = candidate.small_path)
          ),
          NOT EXISTS (
            SELECT 1 FROM artwork_asset active
            WHERE active.id <> candidate.id AND active.ref_count > 0
              AND (active.small_path = candidate.large_path OR active.large_path = candidate.large_path)
          )
         FROM artwork_asset candidate WHERE candidate.ref_count = 0 ORDER BY candidate.id`
      );
      while (resultSet.goToNextRow()) {
        candidates.push({
          assetId: resultSet.getLong(0),
          smallPath: resultSet.getString(1),
          largePath: resultSet.getString(2),
          deleteSmall: resultSet.getLong(3) !== 0,
          deleteLarge: resultSet.getLong(4) !== 0
        });
      }
      return candidates;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read unreferenced artwork assets', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'unreferenced artwork lookup');
    }
  }

  async getReferencedArtworkPaths(): Promise<Array<string>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const paths: Array<string> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT small_path, large_path FROM artwork_asset WHERE ref_count > 0'
      );
      while (resultSet.goToNextRow()) {
        const smallPath = resultSet.getString(0);
        const largePath = resultSet.getString(1);
        if (smallPath.length > 0 && paths.indexOf(smallPath) < 0) {
          paths.push(smallPath);
        }
        if (largePath.length > 0 && paths.indexOf(largePath) < 0) {
          paths.push(largePath);
        }
      }
      return paths;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read referenced artwork paths', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'referenced artwork lookup');
    }
  }

  async getPaletteRefreshAssets(): Promise<Array<PaletteRefreshAsset>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const assets: Array<PaletteRefreshAsset> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT id, small_path FROM artwork_asset WHERE ref_count > 0 ORDER BY id'
      );
      while (resultSet.goToNextRow()) {
        const asset: PaletteRefreshAsset = {
          id: resultSet.getLong(0),
          artworkPath: resultSet.getString(1)
        };
        assets.push(asset);
      }
      return assets;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read artwork palette refresh assets', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artwork palette refresh lookup');
    }
  }

  removeUnreferencedArtwork(assetId: number): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(
        'DELETE FROM artwork_asset WHERE id = ? AND ref_count = 0',
        [assetId]
      );
    });
  }

  private async queryCatalog(fromClause: string,
    descriptor: LibrarySortDescriptor): Promise<LibraryCatalog> {
    if (!descriptor.alphabetic) {
      return {
        totalCount: await this.readCount(this.database.getStore(), `SELECT COUNT(*) FROM ${fromClause}`),
        sections: [],
        indexPresentation: descriptor.indexPresentation()
      };
    }
    let resultSet: relationalStore.ResultSet | undefined;
    const sections: Array<LibrarySection> = [];
    let totalCount = 0;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT ${descriptor.sectionExpression}, COUNT(*)
         FROM ${fromClause}
         GROUP BY ${descriptor.sectionExpression}
         ORDER BY ${descriptor.sectionOrderClause}`
      );
      while (resultSet.goToNextRow()) {
        sections.push({
          label: resultSet.getString(0),
          startIndex: totalCount
        });
        totalCount += resultSet.getLong(1);
      }
      return {
        totalCount: totalCount,
        sections: sections,
        indexPresentation: LibraryIndexPresentation.ALPHABET
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to build catalog for ${fromClause}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'catalog section lookup');
    }
  }

  private async readCount(store: relationalStore.RdbStore, sql: string): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await store.querySql(sql);
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read catalog count', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'catalog count lookup');
    }
  }

  private buildSections<T extends TrackListItem | AlbumListItem>(items: Array<T>): Array<LibrarySection> {
    const sections: Array<LibrarySection> = [];
    let previous = '';
    for (let index = 0; index < items.length; index += 1) {
      const section = items[index].sectionKey;
      if (section !== previous) {
        sections.push({ label: section, startIndex: index });
        previous = section;
      }
    }
    return sections;
  }

  private static pageOffset(offset: number): number {
    return offset > 0 ? Math.floor(offset) : 0;
  }

  private static pageLimit(limit: number): number {
    if (!(limit > 0)) {
      return 1;
    }
    return Math.min(256, Math.floor(limit));
  }
}
