import { relationalStore } from '@kit.ArkData';
import {
  AvailabilityState,
  PlaylistDetail,
  PlaylistItemInput,
  PlaylistItemSource,
  PlaylistKind,
  PlaylistMutationResult,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackItem,
  PlaylistTrackSortField,
  PlaylistTransferTrack,
  SortDirection
} from '../../library/model/LibraryModels';
import { LibraryDatabase } from '../../library/data/LibraryDatabase';
import { RelationalStoreSafety } from '../../library/data/RelationalStoreSafety';
import {
  COMPLETED_HISTORY_FIXED_KEY,
  COMPLETED_HISTORY_NAME,
  PlaylistContentPlan,
  PlaylistPolicy
} from './PlaylistPolicy';

const INPUT_BATCH_SIZE = 400;
const MAX_PAGE_SIZE = 500;

/**
 * Transactional playlist persistence.
 *
 * Parsing and matching import files intentionally live elsewhere. This class
 * receives resolved track IDs, keeps write transactions short, and stages large
 * batches in a temporary table instead of issuing one statement per track.
 */
export class PlaylistRepository {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  async getPlaylists(field: PlaylistSortField, direction: SortDirection): Promise<Array<PlaylistSummary>> {
    const order = direction === SortDirection.ASCENDING ? 'ASC' : 'DESC';
    let orderClause = `p.normalized_name ${order}, p.id ${order}`;
    if (field === PlaylistSortField.LAST_PLAYED) {
      orderClause = `p.last_played_at = 0 ASC, p.last_played_at ${order}, p.id ${order}`;
    } else if (field === PlaylistSortField.UPDATED_AT) {
      orderClause = `p.updated_at ${order}, p.id ${order}`;
    } else if (field === PlaylistSortField.CREATED_AT) {
      orderClause = `p.created_at ${order}, p.id ${order}`;
    } else if (field === PlaylistSortField.TRACK_COUNT) {
      orderClause = `track_count ${order}, p.id ${order}`;
    } else if (field === PlaylistSortField.TOTAL_DURATION) {
      orderClause = `total_duration_ms ${order}, p.id ${order}`;
    }
    let resultSet: relationalStore.ResultSet | undefined;
    const playlists: Array<PlaylistSummary> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `${this.summarySelect()}
         ORDER BY p.kind DESC, ${orderClause}`
      );
      while (resultSet.goToNextRow()) {
        playlists.push(this.readSummary(resultSet));
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query playlists', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'playlist list');
    }
    return playlists;
  }

  async getPlaylist(playlistId: number): Promise<PlaylistSummary | undefined> {
    return this.queryPlaylist(this.database.getStore(), playlistId);
  }

  async getCompletedPlaylist(): Promise<PlaylistSummary> {
    const existing = await this.queryCompletedPlaylist(this.database.getStore());
    if (existing !== undefined) {
      return existing;
    }
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.ensureCompletedPlaylistInTransaction(transaction, Date.now());
      const playlist = await this.queryCompletedPlaylist(transaction);
      if (playlist === undefined) {
        throw new Error('Completed-history playlist could not be created');
      }
      return playlist;
    });
  }

  createPlaylist(name: string): Promise<PlaylistSummary> {
    const displayName = PlaylistPolicy.requireName(name);
    const normalizedName = PlaylistPolicy.normalizeName(displayName);
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requireNameAvailable(transaction, normalizedName);
      const now = Date.now();
      const id = await transaction.insert('playlist', {
        kind: PlaylistKind.USER,
        fixed_key: '',
        name: displayName,
        normalized_name: normalizedName,
        item_sort_field: PlaylistTrackSortField.MANUAL,
        item_sort_direction: SortDirection.ASCENDING,
        created_at: now,
        updated_at: now,
        last_played_at: 0
      });
      const playlist = await this.queryPlaylist(transaction, id);
      if (playlist === undefined) {
        throw new Error('Created playlist is missing');
      }
      return playlist;
    });
  }

  renamePlaylist(playlistId: number, name: string): Promise<PlaylistSummary> {
    const displayName = PlaylistPolicy.requireName(name);
    const normalizedName = PlaylistPolicy.normalizeName(displayName);
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      const current = await this.requirePlaylist(transaction, playlistId);
      if (!PlaylistPolicy.canRename(current.kind)) {
        throw new Error('System playlist cannot be renamed');
      }
      await this.requireNameAvailable(transaction, normalizedName, playlistId);
      await transaction.execute(
        'UPDATE playlist SET name = ?, normalized_name = ?, updated_at = ? WHERE id = ?',
        [displayName, normalizedName, Date.now(), playlistId]
      );
      const updated = await this.queryPlaylist(transaction, playlistId);
      if (updated === undefined) {
        throw new Error('Renamed playlist is missing');
      }
      return updated;
    });
  }

  deletePlaylist(playlistId: number): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      const current = await this.requirePlaylist(transaction, playlistId);
      if (!PlaylistPolicy.canDelete(current.kind)) {
        throw new Error('System playlist cannot be deleted');
      }
      await transaction.execute('DELETE FROM playlist WHERE id = ?', [playlistId]);
    });
  }

  updateItemSort(
    playlistId: number,
    field: PlaylistTrackSortField,
    direction: SortDirection
  ): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requirePlaylist(transaction, playlistId);
      await transaction.execute(
        `UPDATE playlist SET item_sort_field = ?, item_sort_direction = ?, updated_at = ?
         WHERE id = ?`,
        [field, direction, Date.now(), playlistId]
      );
    });
  }

  markPlayed(playlistId: number, playedAt: number = Date.now()): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requirePlaylist(transaction, playlistId);
      await transaction.execute(
        'UPDATE playlist SET last_played_at = ? WHERE id = ?',
        [playedAt, playlistId]
      );
    });
  }

  async getPlaylistDetail(
    playlistId: number,
    offset: number = 0,
    limit: number = 100,
    field?: PlaylistTrackSortField,
    direction?: SortDirection
  ): Promise<PlaylistDetail | undefined> {
    const playlist = await this.getPlaylist(playlistId);
    if (playlist === undefined) {
      return undefined;
    }
    const selectedField = field === undefined ? playlist.itemSortField : field;
    const selectedDirection = direction === undefined ? playlist.itemSortDirection : direction;
    const safeOffset = Math.max(0, offset);
    const safeLimit = Math.max(1, Math.min(MAX_PAGE_SIZE, limit));
    const orderClause = this.itemOrderClause(selectedField, selectedDirection);
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<PlaylistTrackItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
        COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
        COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
        COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'),
        COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'),
        CASE
          WHEN ? = ${PlaylistTrackSortField.TITLE} THEN t.title_section
          WHEN ? = ${PlaylistTrackSortField.ARTIST} THEN t.artist_section
          WHEN ? = ${PlaylistTrackSortField.ALBUM} THEN t.album_section
          ELSE '#'
        END,
        f.availability_state,
        pi.manual_position, pi.added_at, pi.add_source,
        pi.first_qualified_at, pi.last_qualified_at,
        MAX(COALESCE(rs.last_played_at, 0), COALESCE(ps.last_played_at, 0)),
        COALESCE(ps.last_completed_at, 0)
       FROM playlist_item pi
       JOIN track t ON t.id = pi.track_id
       JOIN media_file f ON f.id = t.media_file_id
       LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
       LEFT JOIN track_playback_stats ps ON ps.track_id = t.id
       LEFT JOIN track_playback_state rs ON rs.track_id = t.id
       WHERE pi.playlist_id = ?
       ORDER BY ${orderClause}
         LIMIT ? OFFSET ?`,
        [selectedField, selectedField, selectedField, playlistId, safeLimit, safeOffset]
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
          availability: resultSet.getLong(17) as AvailabilityState,
          position: resultSet.getLong(18),
          addedAt: resultSet.getLong(19),
          source: resultSet.getLong(20) as PlaylistItemSource,
          firstQualifiedAt: resultSet.getLong(21),
          lastQualifiedAt: resultSet.getLong(22),
          lastPlayedAt: resultSet.getLong(23),
          lastCompletedAt: resultSet.getLong(24)
        });
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to query playlist ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist ${playlistId}`);
    }
    return {
      playlist: playlist,
      items: items,
      offset: safeOffset,
      totalCount: playlist.trackCount
    };
  }

  async getPlaylistTrackIds(
    playlistId: number,
    field?: PlaylistTrackSortField,
    direction?: SortDirection
  ): Promise<Array<number>> {
    const playlist = await this.getPlaylist(playlistId);
    if (playlist === undefined) {
      return [];
    }
    const selectedField = field === undefined ? playlist.itemSortField : field;
    const selectedDirection = direction === undefined ? playlist.itemSortDirection : direction;
    let resultSet: relationalStore.ResultSet | undefined;
    const trackIds: Array<number> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id
       FROM playlist_item pi
       JOIN track t ON t.id = pi.track_id
       LEFT JOIN track_playback_stats ps ON ps.track_id = t.id
       LEFT JOIN track_playback_state rs ON rs.track_id = t.id
       WHERE pi.playlist_id = ?
         ORDER BY ${this.itemOrderClause(selectedField, selectedDirection)}`,
        [playlistId]
      );
      while (resultSet.goToNextRow()) {
        trackIds.push(resultSet.getLong(0));
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to query playlist track IDs ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist track IDs ${playlistId}`);
    }
    return trackIds;
  }

  async getTransferCatalog(): Promise<Array<PlaylistTransferTrack>> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, f.uri, f.display_name, t.title, t.artist_display, t.album_display, t.duration_ms,
        0, COALESCE(ps.last_completed_at, 0)
       FROM track t
       JOIN media_file f ON f.id = t.media_file_id
       LEFT JOIN track_playback_stats ps ON ps.track_id = t.id
       WHERE f.availability_state = 0
         ORDER BY t.id`
      );
      return this.readTransferTracks(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query playlist transfer catalog', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'playlist transfer catalog');
    }
  }

  async getPlaylistTransferTracks(playlistId: number): Promise<Array<PlaylistTransferTrack>> {
    const playlist = await this.getPlaylist(playlistId);
    if (playlist === undefined) {
      return [];
    }
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, f.uri, f.display_name, t.title, t.artist_display, t.album_display, t.duration_ms,
        pi.first_qualified_at, pi.last_qualified_at
       FROM playlist_item pi
       JOIN track t ON t.id = pi.track_id
       JOIN media_file f ON f.id = t.media_file_id
       LEFT JOIN track_playback_stats ps ON ps.track_id = t.id
       LEFT JOIN track_playback_state rs ON rs.track_id = t.id
       WHERE pi.playlist_id = ?
         ORDER BY ${this.itemOrderClause(playlist.itemSortField, playlist.itemSortDirection)}`,
        [playlistId]
      );
      return this.readTransferTracks(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to query playlist transfer tracks ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist transfer tracks ${playlistId}`);
    }
  }

  private readTransferTracks(resultSet: relationalStore.ResultSet): Array<PlaylistTransferTrack> {
    const tracks: Array<PlaylistTransferTrack> = [];
    try {
      while (resultSet.goToNextRow()) {
        tracks.push({
          trackId: resultSet.getLong(0),
          uri: resultSet.getString(1),
          displayName: resultSet.getString(2),
          title: resultSet.getString(3),
          artistDisplay: resultSet.getString(4),
          albumDisplay: resultSet.getString(5),
          durationMs: resultSet.getLong(6),
          firstQualifiedAt: resultSet.getLong(7),
          lastQualifiedAt: resultSet.getLong(8)
        });
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to decode playlist transfer tracks', error);
    }
    return tracks;
  }

  mergeItems(playlistId: number, items: Array<PlaylistItemInput>): Promise<PlaylistMutationResult> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requireEditableItems(transaction, playlistId);
      const existingTrackIds = await this.getMemberTrackIds(transaction, playlistId);
      const plan = PlaylistPolicy.planMerge(existingTrackIds, items);
      return this.insertPlan(transaction, playlistId, items.length, plan, false);
    });
  }

  addItems(playlistId: number, items: Array<PlaylistItemInput>): Promise<PlaylistMutationResult> {
    return this.mergeItems(playlistId, items);
  }

  replaceItems(playlistId: number, items: Array<PlaylistItemInput>): Promise<PlaylistMutationResult> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requireEditableItems(transaction, playlistId);
      const plan = PlaylistPolicy.planReplace(items);
      return this.insertPlan(transaction, playlistId, items.length, plan, true);
    });
  }

  removeItems(playlistId: number, trackIds: Array<number>): Promise<number> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requireEditableItems(transaction, playlistId);
      const uniqueIds = this.uniqueTrackIds(trackIds);
      if (uniqueIds.length === 0) {
        return 0;
      }
      const before = await this.countMembers(transaction, playlistId);
      for (let offset = 0; offset < uniqueIds.length; offset += INPUT_BATCH_SIZE) {
        const batch = uniqueIds.slice(offset, Math.min(offset + INPUT_BATCH_SIZE, uniqueIds.length));
        const placeholders = batch.map(() => '?').join(', ');
        const args: Array<relationalStore.ValueType> = [playlistId];
        for (let index = 0; index < batch.length; index += 1) {
          args.push(batch[index]);
        }
        await transaction.execute(
          `DELETE FROM playlist_item WHERE playlist_id = ? AND track_id IN (${placeholders})`,
          args
        );
      }
      const after = await this.countMembers(transaction, playlistId);
      if (after !== before) {
        await transaction.execute('UPDATE playlist SET updated_at = ? WHERE id = ?', [Date.now(), playlistId]);
      }
      return before - after;
    });
  }

  reorderItems(playlistId: number, reorderedTrackIds: Array<number>): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.requireEditableItems(transaction, playlistId);
      const currentTrackIds = await this.getMemberTrackIds(transaction, playlistId);
      if (!PlaylistPolicy.isCompleteReorder(currentTrackIds, reorderedTrackIds)) {
        throw new Error('Reorder must contain every playlist track exactly once');
      }
      await transaction.execute('DROP TABLE IF EXISTS temp_playlist_reorder');
      await transaction.execute(
        `CREATE TEMP TABLE temp_playlist_reorder (
          track_id INTEGER PRIMARY KEY,
          manual_position INTEGER NOT NULL
        )`
      );
      const buckets: Array<relationalStore.ValuesBucket> = [];
      for (let index = 0; index < reorderedTrackIds.length; index += 1) {
        buckets.push({ track_id: reorderedTrackIds[index], manual_position: index });
      }
      await this.batchInsert(transaction, 'temp_playlist_reorder', buckets);
      await transaction.execute(
        `UPDATE playlist_item SET manual_position = (
          SELECT r.manual_position FROM temp_playlist_reorder r
          WHERE r.track_id = playlist_item.track_id
        ) WHERE playlist_id = ?`,
        [playlistId]
      );
      await transaction.execute('DROP TABLE temp_playlist_reorder');
      await transaction.execute('UPDATE playlist SET updated_at = ? WHERE id = ?', [Date.now(), playlistId]);
    });
  }

  recordCompletedPlayback(
    trackId: number,
    completedAt: number = Date.now(),
    collectInPlaylist: boolean = true
  ): Promise<number | undefined> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction): Promise<number | undefined> => {
      if (!await this.trackExists(transaction, trackId)) {
        return undefined;
      }
      await transaction.execute(
        `INSERT OR IGNORE INTO track_playback_stats(
          track_id, play_count, completed_count, last_started_at, last_played_at, last_completed_at
        ) VALUES(?, 0, 0, 0, 0, 0)`,
        [trackId]
      );
      await transaction.execute(
        `UPDATE track_playback_stats SET
          completed_count = completed_count + 1,
          last_played_at = ?,
          last_completed_at = ?
         WHERE track_id = ?`,
        [completedAt, completedAt, trackId]
      );
      let completedPlaylistId: number | undefined;
      if (collectInPlaylist) {
        const playlistId = await this.ensureCompletedPlaylistInTransaction(transaction, completedAt);
        completedPlaylistId = playlistId;
        const existing = await this.hasMember(transaction, playlistId, trackId);
        if (!existing) {
          const position = await this.nextPosition(transaction, playlistId);
          await transaction.insert('playlist_item', {
            playlist_id: playlistId,
            track_id: trackId,
            manual_position: position,
            added_at: completedAt,
            add_source: PlaylistItemSource.AUTO_COMPLETED,
            first_qualified_at: completedAt,
            last_qualified_at: completedAt
          });
        } else {
          await transaction.execute(
            `UPDATE playlist_item SET
              first_qualified_at = CASE WHEN first_qualified_at = 0 THEN ? ELSE first_qualified_at END,
              last_qualified_at = ?
             WHERE playlist_id = ? AND track_id = ?`,
            [completedAt, completedAt, playlistId, trackId]
          );
        }
        await transaction.execute('UPDATE playlist SET updated_at = ? WHERE id = ?', [completedAt, playlistId]);
      }
      await transaction.execute(
        `UPDATE track_playback_state SET resume_position_ms = 0, completed = 1,
          last_played_at = ?, updated_at = ? WHERE track_id = ?`,
        [completedAt, completedAt, trackId]
      );
      return completedPlaylistId;
    });
  }

  private async insertPlan(
    transaction: relationalStore.Transaction,
    playlistId: number,
    requested: number,
    plan: PlaylistContentPlan,
    replace: boolean
  ): Promise<PlaylistMutationResult> {
    try {
      const before = replace ? 0 : await this.countMembers(transaction, playlistId);
      if (!replace && plan.items.length === 0) {
        return {
          requested: requested,
          inserted: 0,
          alreadyPresent: plan.alreadyPresent + plan.duplicateInput,
          unavailable: 0
        };
      }
      await this.stageItems(transaction, plan.items);
      const available = await this.countStagedAvailable(transaction);
      if (replace) {
        await transaction.execute('DELETE FROM playlist_item WHERE playlist_id = ?', [playlistId]);
      }
      const startPosition = replace ? 0 : await this.nextPosition(transaction, playlistId);
      const now = Date.now();
      await transaction.execute(
        `INSERT OR IGNORE INTO playlist_item(
          playlist_id, track_id, manual_position, added_at, add_source,
          first_qualified_at, last_qualified_at
        )
        SELECT ?, s.track_id, ? + s.ordinal, ?,
          s.add_source, s.qualified_at, s.qualified_at
        FROM temp_playlist_input s
        JOIN track t ON t.id = s.track_id
        ORDER BY s.ordinal`,
        [playlistId, startPosition, now]
      );
      const after = await this.countMembers(transaction, playlistId);
      await transaction.execute('DROP TABLE temp_playlist_input');
      const inserted = replace ? after : after - before;
      if (replace || inserted > 0) {
        await transaction.execute('UPDATE playlist SET updated_at = ? WHERE id = ?', [now, playlistId]);
      }
      return {
        requested: requested,
        inserted: inserted,
        alreadyPresent: plan.alreadyPresent + plan.duplicateInput,
        unavailable: plan.items.length - available
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to update playlist ${playlistId}`, error);
    }
  }

  private async stageItems(
    transaction: relationalStore.Transaction,
    items: Array<PlaylistItemInput>
  ): Promise<void> {
    try {
      await transaction.execute('DROP TABLE IF EXISTS temp_playlist_input');
      await transaction.execute(
        `CREATE TEMP TABLE temp_playlist_input (
          ordinal INTEGER PRIMARY KEY,
          track_id INTEGER NOT NULL UNIQUE,
          add_source INTEGER NOT NULL,
          qualified_at INTEGER NOT NULL
        )`
      );
      const buckets: Array<relationalStore.ValuesBucket> = [];
      for (let index = 0; index < items.length; index += 1) {
        const item = items[index];
        buckets.push({
          ordinal: index,
          track_id: item.trackId,
          add_source: item.source,
          qualified_at: item.qualifiedAt === undefined ? 0 : item.qualifiedAt
        });
      }
      await this.batchInsert(transaction, 'temp_playlist_input', buckets);
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to stage playlist items', error);
    }
  }

  private async batchInsert(
    transaction: relationalStore.Transaction,
    table: string,
    buckets: Array<relationalStore.ValuesBucket>
  ): Promise<void> {
    try {
      for (let offset = 0; offset < buckets.length; offset += INPUT_BATCH_SIZE) {
        await transaction.batchInsert(
          table,
          buckets.slice(offset, Math.min(offset + INPUT_BATCH_SIZE, buckets.length))
        );
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to populate ${table}`, error);
    }
  }

  private itemOrderClause(field: PlaylistTrackSortField, direction: SortDirection): string {
    const order = direction === SortDirection.ASCENDING ? 'ASC' : 'DESC';
    if (field === PlaylistTrackSortField.ADDED_AT) {
      return `pi.added_at ${order}, pi.manual_position ${order}, t.id ${order}`;
    }
    if (field === PlaylistTrackSortField.TITLE) {
      return `t.title_section = '#' ASC, t.title_natural_key ${order}, t.id ${order}`;
    }
    if (field === PlaylistTrackSortField.ARTIST) {
      return `t.artist_section = '#' ASC, t.artist_natural_key ${order}, t.id ${order}`;
    }
    if (field === PlaylistTrackSortField.ALBUM) {
      return `t.album_section = '#' ASC, t.album_natural_key ${order},
        COALESCE(t.disc_number, 0) ASC, COALESCE(t.track_number, 0) ASC, t.id ASC`;
    }
    if (field === PlaylistTrackSortField.RELEASE_DATE) {
      return `t.release_date_sort = 0 ASC, t.release_date_sort ${order}, t.id ${order}`;
    }
    if (field === PlaylistTrackSortField.DURATION) {
      return `t.duration_ms ${order}, t.id ${order}`;
    }
    if (field === PlaylistTrackSortField.LAST_PLAYED) {
      return `MAX(COALESCE(rs.last_played_at, 0), COALESCE(ps.last_played_at, 0)) = 0 ASC,
        MAX(COALESCE(rs.last_played_at, 0), COALESCE(ps.last_played_at, 0)) ${order}, t.id ${order}`;
    }
    if (field === PlaylistTrackSortField.LAST_COMPLETED) {
      return `COALESCE(ps.last_completed_at, 0) = 0 ASC,
        COALESCE(ps.last_completed_at, 0) ${order}, t.id ${order}`;
    }
    return `pi.manual_position ${order}, t.id ${order}`;
  }

  private summarySelect(whereClause: string = ''): string {
    return `SELECT p.id, p.kind, p.name, p.item_sort_field, p.item_sort_direction,
      COUNT(t.id) AS track_count,
      COALESCE(SUM(t.duration_ms), 0) AS total_duration_ms,
      p.created_at, p.updated_at, p.last_played_at
      FROM playlist p
      LEFT JOIN playlist_item pi ON pi.playlist_id = p.id
      LEFT JOIN track t ON t.id = pi.track_id
      ${whereClause}
      GROUP BY p.id, p.kind, p.name, p.item_sort_field, p.item_sort_direction,
        p.created_at, p.updated_at, p.last_played_at`;
  }

  private readSummary(resultSet: relationalStore.ResultSet): PlaylistSummary {
    try {
      return {
        id: resultSet.getLong(0),
        kind: resultSet.getLong(1) as PlaylistKind,
        name: resultSet.getString(2),
        itemSortField: resultSet.getLong(3) as PlaylistTrackSortField,
        itemSortDirection: resultSet.getLong(4) as SortDirection,
        trackCount: resultSet.getLong(5),
        totalDurationMs: resultSet.getLong(6),
        createdAt: resultSet.getLong(7),
        updatedAt: resultSet.getLong(8),
        lastPlayedAt: resultSet.getLong(9)
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to decode playlist summary', error);
    }
  }

  private async queryPlaylist(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number
  ): Promise<PlaylistSummary | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql(`${this.summarySelect('WHERE p.id = ?')} LIMIT 1`, [playlistId]);
      return resultSet.goToNextRow() ? this.readSummary(resultSet) : undefined;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to query playlist ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist ${playlistId}`);
    }
  }

  private async queryCompletedPlaylist(
    source: relationalStore.RdbStore | relationalStore.Transaction
  ): Promise<PlaylistSummary | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql(
        `${this.summarySelect('WHERE p.fixed_key = ?')} LIMIT 1`,
        [COMPLETED_HISTORY_FIXED_KEY]
      );
      return resultSet.goToNextRow() ? this.readSummary(resultSet) : undefined;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query completed-history playlist', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'completed-history playlist');
    }
  }

  private async requirePlaylist(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number
  ): Promise<PlaylistSummary> {
    const playlist = await this.queryPlaylist(source, playlistId);
    if (playlist === undefined) {
      throw new Error('Playlist does not exist');
    }
    return playlist;
  }

  private async requireEditableItems(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number
  ): Promise<void> {
    const playlist = await this.requirePlaylist(source, playlistId);
    if (!PlaylistPolicy.canEditItems(playlist.kind)) {
      throw new Error('Playlist contents cannot be edited');
    }
  }

  private async requireNameAvailable(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    normalizedName: string,
    excludingId: number = 0
  ): Promise<void> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql(
        'SELECT id FROM playlist WHERE normalized_name = ? AND id <> ? LIMIT 1',
        [normalizedName, excludingId]
      );
      if (resultSet.goToNextRow()) {
        throw new Error('A playlist with this name already exists');
      }
    } catch (error) {
      if (error instanceof Error && error.message === 'A playlist with this name already exists') {
        throw error;
      }
      throw RelationalStoreSafety.operationError('Unable to check playlist name', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'playlist name lookup');
    }
  }

  private async ensureCompletedPlaylistInTransaction(
    transaction: relationalStore.Transaction,
    now: number
  ): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await transaction.querySql(
        'SELECT id FROM playlist WHERE fixed_key = ? LIMIT 1',
        [COMPLETED_HISTORY_FIXED_KEY]
      );
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(0);
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to find completed-history playlist', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'completed-history playlist lookup');
    }
    try {
      return await transaction.insert('playlist', {
        kind: PlaylistKind.COMPLETED_HISTORY,
        fixed_key: COMPLETED_HISTORY_FIXED_KEY,
        name: COMPLETED_HISTORY_NAME,
        normalized_name: PlaylistPolicy.normalizeName(COMPLETED_HISTORY_NAME),
        item_sort_field: PlaylistTrackSortField.ADDED_AT,
        item_sort_direction: SortDirection.DESCENDING,
        created_at: now,
        updated_at: now,
        last_played_at: 0
      });
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to create completed-history playlist', error);
    }
  }

  private async getMemberTrackIds(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number
  ): Promise<Array<number>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const ids: Array<number> = [];
    try {
      resultSet = await source.querySql(
        'SELECT track_id FROM playlist_item WHERE playlist_id = ? ORDER BY manual_position, track_id',
        [playlistId]
      );
      while (resultSet.goToNextRow()) {
        ids.push(resultSet.getLong(0));
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to query playlist members ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist members ${playlistId}`);
    }
    return ids;
  }

  private async countMembers(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number
  ): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql(
        'SELECT COUNT(*) FROM playlist_item WHERE playlist_id = ?',
        [playlistId]
      );
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to count playlist members ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist member count ${playlistId}`);
    }
  }

  private async countStagedAvailable(transaction: relationalStore.Transaction): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await transaction.querySql(
        'SELECT COUNT(*) FROM temp_playlist_input s JOIN track t ON t.id = s.track_id'
      );
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to count available staged playlist items', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'staged playlist item count');
    }
  }

  private async nextPosition(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number
  ): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql(
        'SELECT COALESCE(MAX(manual_position), -1) + 1 FROM playlist_item WHERE playlist_id = ?',
        [playlistId]
      );
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to find next playlist position ${playlistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist next position ${playlistId}`);
    }
  }

  private async hasMember(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    playlistId: number,
    trackId: number
  ): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql(
        'SELECT 1 FROM playlist_item WHERE playlist_id = ? AND track_id = ? LIMIT 1',
        [playlistId, trackId]
      );
      return resultSet.goToNextRow();
    } catch (error) {
      throw RelationalStoreSafety.operationError(
        `Unable to check playlist member ${playlistId}/${trackId}`,
        error
      );
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `playlist member ${playlistId}/${trackId}`);
    }
  }

  private async trackExists(
    source: relationalStore.RdbStore | relationalStore.Transaction,
    trackId: number
  ): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await source.querySql('SELECT 1 FROM track WHERE id = ? LIMIT 1', [trackId]);
      return resultSet.goToNextRow();
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to check track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `track ${trackId}`);
    }
  }

  private uniqueTrackIds(trackIds: Array<number>): Array<number> {
    const seen = new Set<number>();
    const unique: Array<number> = [];
    for (let index = 0; index < trackIds.length; index += 1) {
      if (!seen.has(trackIds[index])) {
        seen.add(trackIds[index]);
        unique.push(trackIds[index]);
      }
    }
    return unique;
  }
}
