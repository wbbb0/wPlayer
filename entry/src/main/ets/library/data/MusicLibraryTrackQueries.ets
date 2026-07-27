import { relationalStore } from '@kit.ArkData';
import {
  AvailabilityState,
  ArtworkPictureType,
  ArtworkState,
  LibraryCatalog,
  LibraryIndexPresentation,
  LibraryPage,
  LibrarySection,
  MediaFileCheckCandidate,
  MediaFormat,
  SortDirection,
  TrackAvailabilityUpdate,
  TrackListItem,
  TrackSortField,
  UnavailableTrackItem
} from '../model/LibraryModels';
import { PlaybackTrack, QueueTrack, ResumeState } from '../../playback/model/PlaybackModels';
import { LibraryDatabase } from './LibraryDatabase';
import { LibraryQueryPagingPolicy } from './LibraryQueryPagingPolicy';
import { trackListItemFromCurrentRow } from './MusicLibraryQueryRows';
import { LibrarySortDescriptor, LibrarySortPlan } from './LibrarySortPlan';
import {
  LibrarySectionPagePlanner,
  LibrarySectionPageSegment
} from './LibrarySectionPagePlanner';
import { RelationalStoreSafety } from './RelationalStoreSafety';

const PLAYBACK_QUEUE_QUERY_BATCH_SIZE = 128;

/**
 * Owns track-domain reads and writes. MusicRepository remains responsible for invalidating observable projections.
 */
export class MusicLibraryTrackQueries {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  getTrackCatalog(field: TrackSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.queryCatalog(LibrarySortPlan.track(field, direction));
  }

  async getTrackPage(field: TrackSortField, direction: SortDirection,
    catalog: LibraryCatalog, offset: number, limit: number): Promise<LibraryPage<TrackListItem>> {
    const safeOffset = LibraryQueryPagingPolicy.offset(offset);
    const safeLimit = LibraryQueryPagingPolicy.limit(limit);
    const descriptor = LibrarySortPlan.track(field, direction);
    return {
      offset: safeOffset,
      items: descriptor.alphabetic ?
        await this.queryTrackSectionPage(descriptor, catalog, safeOffset, safeLimit) :
        await this.queryTrackItems(descriptor, '', descriptor.orderClause,
          ' LIMIT ? OFFSET ?', [safeLimit, safeOffset])
    };
  }

  getTrackPlaybackOrder(field: TrackSortField,
    direction: SortDirection): Promise<Array<TrackListItem>> {
    const descriptor = LibrarySortPlan.track(field, direction);
    return this.queryTrackItems(descriptor, '', descriptor.orderClause, '', []);
  }

  private async queryTrackSectionPage(descriptor: LibrarySortDescriptor, catalog: LibraryCatalog,
    offset: number, limit: number): Promise<Array<TrackListItem>> {
    const segments = LibrarySectionPagePlanner.plan(catalog, offset, limit);
    const items: Array<TrackListItem> = [];
    for (let index = 0; index < segments.length; index += 1) {
      const segment: LibrarySectionPageSegment = segments[index];
      const segmentItems = await this.queryTrackItems(
        descriptor,
        ` WHERE ${descriptor.sectionExpression} = ?`,
        descriptor.sectionLocalOrderClause,
        ' LIMIT ? OFFSET ?',
        [segment.label, segment.limit, segment.localOffset]
      );
      if (segmentItems.length !== segment.limit) {
        throw new Error('Track catalog changed while loading an alphabetic page');
      }
      items.push(...segmentItems);
    }
    return items;
  }

  private async queryTrackItems(descriptor: LibrarySortDescriptor, filterClause: string,
    orderClause: string, paginationClause: string,
    bindArgs: Array<relationalStore.ValueType>): Promise<Array<TrackListItem>> {
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
         ${filterClause}
         ORDER BY ${orderClause}${paginationClause}`,
        bindArgs
      );
      while (resultSet.goToNextRow()) {
        items.push(trackListItemFromCurrentRow(resultSet));
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
           COALESCE(a.small_path, ''), COALESCE(a.large_path, ''),
           COALESCE(a.small_width, 0), COALESCE(a.small_height, 0), COALESCE(a.small_byte_size, 0),
           COALESCE(a.large_width, 0), COALESCE(a.large_height, 0), COALESCE(a.large_byte_size, 0),
           COALESCE(s.width, 0), COALESCE(s.height, 0)
         FROM media_file f JOIN track t ON t.media_file_id = f.id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         LEFT JOIN artwork_source s ON s.asset_id = a.id
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
          artworkLargePath: resultSet.getString(10),
          artworkSmallWidth: resultSet.getLong(11),
          artworkSmallHeight: resultSet.getLong(12),
          artworkSmallByteSize: resultSet.getLong(13),
          artworkLargeWidth: resultSet.getLong(14),
          artworkLargeHeight: resultSet.getLong(15),
          artworkLargeByteSize: resultSet.getLong(16),
          artworkSourceWidth: resultSet.getLong(17),
          artworkSourceHeight: resultSet.getLong(18)
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


  private async queryCatalog(descriptor: LibrarySortDescriptor): Promise<LibraryCatalog> {
    if (!descriptor.alphabetic) {
      return {
        totalCount: await this.readCount(this.database.getStore(), 'SELECT COUNT(*) FROM track'),
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
         FROM track t
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
      throw RelationalStoreSafety.operationError('Unable to build track catalog', error);
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
}
