import { relationalStore } from '@kit.ArkData';
import {
  AlbumDetail,
  AlbumListItem,
  AlbumReference,
  ArtistDetail,
  ArtistDetailOverview,
  ArtistReference,
  AvailabilityState,
  ArtworkPictureType,
  CreditRole,
  EmbeddedArtwork,
  MediaFormat,
  TrackCreditDetail,
  TrackDetail,
  TrackListItem,
  TrackNavigationTargets,
  TrackRawTag
} from '../model/LibraryModels';
import { LibraryDatabase } from './LibraryDatabase';
import {
  albumListItemFromCurrentRow,
  artistReferenceFromCurrentRow,
  trackListItemFromCurrentRow
} from './MusicLibraryQueryRows';
import { RelationalStoreSafety } from './RelationalStoreSafety';
import { LibraryQueryPagingPolicy } from './LibraryQueryPagingPolicy';
import { LibraryCollectionQueryPolicy } from './LibraryCollectionQueryPolicy';

interface ArtistTrackStatistics {
  trackCount: number;
  totalDurationMs: number;
}

/**
 * Owns detail and navigation reads. MusicRepository remains responsible for invalidating observable projections.
 */
export class MusicLibraryDetailQueries {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
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
    const tracks = await this.queryAlbumTracks(albumId);
    const albumArtists = await this.getAlbumArtists(albumId);
    const relatedAlbumCount = albumArtists.length > 0 ? await this.getRelatedAlbumCount(albumId) : 0;
    return {
      album: album,
      albumArtists: albumArtists,
      relatedAlbumCount: relatedAlbumCount,
      relatedAlbums: relatedAlbumCount > 0 ? await this.getRelatedAlbumPage(
        albumId, 0, LibraryCollectionQueryPolicy.RELATED_ALBUM_PREVIEW_LIMIT
      ) : [],
      releaseYear: releaseYear,
      genreDisplay: genreDisplay,
      tracks: tracks
    };
  }

  private async queryAlbumTracks(albumId: number): Promise<Array<TrackListItem>> {
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
         WHERE t.album_id = ?
         ORDER BY CASE WHEN t.disc_number IS NULL OR t.disc_number <= 0 THEN 1 ELSE 0 END,
          t.disc_number ASC,
          CASE WHEN t.track_number IS NULL OR t.track_number <= 0 THEN 1 ELSE 0 END,
          t.track_number ASC, t.id ASC`,
        [albumId]
      );
      while (resultSet.goToNextRow()) {
        tracks.push(trackListItemFromCurrentRow(resultSet));
      }
      return tracks;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read album tracks ${albumId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'album tracks');
    }
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

  async getTrackDetail(trackId: number): Promise<TrackDetail | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    let detail: TrackDetail | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, t.title, t.sort_title, t.artist_display, t.album_display,
          t.album_artist_display, t.composer_display,
          COALESCE(t.track_number, 0), COALESCE(t.total_track_count, 0), t.track_number_raw,
          COALESCE(t.disc_number, 0), COALESCE(t.total_disc_count, 0), t.disc_number_raw,
          t.release_date_raw, t.original_release_date_raw, t.duration_ms,
          t.sample_rate, t.channel_count, t.bits_per_sample, t.bit_rate,
          m.display_name, m.uri, m.file_size, m.modified_at, m.format, m.mime_type,
          m.authorization_persisted, m.availability_state,
          COALESCE(a.large_path, ''), COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
          COALESCE(a.palette_primary, '#FF7C4DFF')
         FROM track t
         JOIN media_file m ON m.id = t.media_file_id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         WHERE t.id = ? LIMIT 1`,
        [trackId]
      );
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      detail = {
        id: resultSet.getLong(0),
        title: resultSet.getString(1),
        sortTitle: resultSet.getString(2),
        artistDisplay: resultSet.getString(3),
        albumDisplay: resultSet.getString(4),
        albumArtistDisplay: resultSet.getString(5),
        composerDisplay: resultSet.getString(6),
        trackNumber: resultSet.getLong(7),
        totalTrackCount: resultSet.getLong(8),
        trackNumberRaw: resultSet.getString(9),
        discNumber: resultSet.getLong(10),
        totalDiscCount: resultSet.getLong(11),
        discNumberRaw: resultSet.getString(12),
        releaseDateRaw: resultSet.getString(13),
        originalReleaseDateRaw: resultSet.getString(14),
        durationMs: resultSet.getLong(15),
        sampleRate: resultSet.getLong(16),
        channelCount: resultSet.getLong(17),
        bitsPerSample: resultSet.getLong(18),
        bitRate: resultSet.getLong(19),
        displayName: resultSet.getString(20),
        uri: resultSet.getString(21),
        fileSize: resultSet.getLong(22),
        modifiedAt: resultSet.getLong(23),
        format: resultSet.getString(24) as MediaFormat,
        mimeType: resultSet.getString(25),
        authorizationPersisted: resultSet.getLong(26) === 1,
        availability: resultSet.getLong(27) as AvailabilityState,
        artworkPath: resultSet.getString(28),
        artworkWidth: resultSet.getLong(29),
        artworkHeight: resultSet.getLong(30),
        palettePrimary: resultSet.getString(31),
        credits: [],
        genres: [],
        rawTags: [],
        artworks: []
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read track detail ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track detail');
    }
    detail.credits = await this.getTrackCredits(trackId);
    detail.genres = await this.getTrackGenres(trackId);
    detail.rawTags = await this.getTrackRawTags(trackId);
    detail.artworks = await this.getTrackArtworks(trackId);
    return detail;
  }

  private async getTrackCredits(trackId: number): Promise<Array<TrackCreditDetail>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const values: Array<TrackCreditDetail> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT tc.role, p.name, tc.ordinal
         FROM track_credit tc JOIN person p ON p.id = tc.person_id
         WHERE tc.track_id = ?
         ORDER BY tc.role, tc.ordinal`,
        [trackId]
      );
      while (resultSet.goToNextRow()) {
        values.push({
          role: resultSet.getLong(0) as CreditRole,
          name: resultSet.getString(1),
          ordinal: resultSet.getLong(2)
        });
      }
      return values;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read credits for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track credits');
    }
  }

  private async getTrackGenres(trackId: number): Promise<Array<string>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const values: Array<string> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT g.name
         FROM track_genre tg JOIN genre g ON g.id = tg.genre_id
         WHERE tg.track_id = ?
         ORDER BY tg.ordinal`,
        [trackId]
      );
      while (resultSet.goToNextRow()) {
        values.push(resultSet.getString(0));
      }
      return values;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read genres for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track genres');
    }
  }

  private async getTrackRawTags(trackId: number): Promise<Array<TrackRawTag>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const values: Array<TrackRawTag> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT tag_key, ordinal, raw_value
         FROM track_tag_extra
         WHERE track_id = ?
         ORDER BY tag_key, ordinal`,
        [trackId]
      );
      while (resultSet.goToNextRow()) {
        values.push({
          key: resultSet.getString(0),
          ordinal: resultSet.getLong(1),
          value: resultSet.getString(2)
        });
      }
      return values;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read raw tags for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track raw tags');
    }
  }

  private async getTrackArtworks(trackId: number): Promise<Array<EmbeddedArtwork>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const values: Array<EmbeddedArtwork> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT id, picture_type, mime_type, description, width, height, color_depth,
          byte_offset, byte_length, payload_offset, ordinal, unsynchronized
         FROM track_artwork
         WHERE track_id = ?
         ORDER BY ordinal`,
        [trackId]
      );
      while (resultSet.goToNextRow()) {
        values.push({
          id: resultSet.getLong(0),
          pictureType: resultSet.getLong(1) as ArtworkPictureType,
          mimeType: resultSet.getString(2),
          description: resultSet.getString(3),
          width: resultSet.getLong(4),
          height: resultSet.getLong(5),
          colorDepth: resultSet.getLong(6),
          byteOffset: resultSet.getLong(7),
          byteLength: resultSet.getLong(8),
          payloadOffset: resultSet.getLong(9),
          ordinal: resultSet.getLong(10),
          unsynchronized: resultSet.getLong(11) === 1
        });
      }
      return values;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artworks for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track artworks');
    }
  }

  async getArtistOverview(artistId: number): Promise<ArtistDetailOverview | undefined> {
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
    const albumCount = await this.getArtistAlbumCount(artistId);
    const statistics = await this.getArtistTrackStatistics(artistId);
    return {
      artist: artist,
      albumCount: albumCount,
      trackCount: statistics.trackCount,
      totalDurationMs: statistics.totalDurationMs,
      albums: albumCount > 0 ? await this.getArtistAlbumPage(
        artistId, 0, LibraryCollectionQueryPolicy.ARTIST_ALBUM_PREVIEW_LIMIT
      ) : [],
      trackPreview: statistics.trackCount > 0 ? await this.getArtistTrackPage(
        artistId, 0, LibraryCollectionQueryPolicy.ARTIST_TRACK_PREVIEW_LIMIT
      ) : []
    };
  }

  async getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    const overview = await this.getArtistOverview(artistId);
    if (overview === undefined) {
      return undefined;
    }
    return {
      artist: overview.artist,
      albumCount: overview.albumCount,
      trackCount: overview.trackCount,
      totalDurationMs: overview.totalDurationMs,
      albums: await this.getArtistAlbums(artistId),
      trackPreview: overview.trackPreview,
      tracks: await this.getArtistTracks(artistId)
    };
  }

  private async getArtistTrackStatistics(artistId: number): Promise<ArtistTrackStatistics> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT COUNT(*), COALESCE(SUM(t.duration_ms), 0)
         FROM track t
         WHERE EXISTS (
           SELECT 1 FROM track_credit tc
           WHERE tc.track_id = t.id AND tc.person_id = ? AND tc.role = ?
         ) OR EXISTS (
           SELECT 1 FROM album_credit ac
           WHERE ac.album_id = t.album_id AND ac.person_id = ?
         )`,
        [artistId, CreditRole.TRACK_ARTIST, artistId]
      );
      if (!resultSet.goToNextRow()) {
        return { trackCount: 0, totalDurationMs: 0 };
      }
      return {
        trackCount: resultSet.getLong(0),
        totalDurationMs: resultSet.getLong(1)
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(
        `Unable to read track statistics for artist ${artistId}`,
        error
      );
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist track statistics');
    }
  }

  async getArtistTrackCount(artistId: number): Promise<number> {
    return (await this.getArtistTrackStatistics(artistId)).trackCount;
  }

  private async getTrackArtists(trackId: number): Promise<Array<ArtistReference>> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT p.id, p.name
         FROM track_credit tc JOIN person p ON p.id = tc.person_id
         WHERE tc.track_id = ? AND tc.role = ?
         ORDER BY tc.ordinal`,
        [trackId, CreditRole.TRACK_ARTIST]
      );
      return this.readArtistReferences(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artists for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track artists');
    }
  }

  async getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT p.id, p.name
         FROM album_credit ac JOIN person p ON p.id = ac.person_id
         WHERE ac.album_id = ?
         ORDER BY ac.ordinal`,
        [albumId]
      );
      return this.readArtistReferences(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artists for album ${albumId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'album artists');
    }
  }

  private readArtistReferences(resultSet: relationalStore.ResultSet): Array<ArtistReference> {
    const artists: Array<ArtistReference> = [];
    try {
      while (resultSet.goToNextRow()) {
        artists.push(artistReferenceFromCurrentRow(resultSet));
      }
      return artists;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to decode artist references', error);
    }
  }

  async getArtistAlbumCount(artistId: number): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT COUNT(DISTINCT al.id)
         FROM album_credit ac
         JOIN album al ON al.id = ac.album_id
         WHERE ac.person_id = ?`,
        [artistId]
      );
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to count albums for artist ${artistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist album count');
    }
  }

  getArtistAlbumPage(artistId: number, offset: number,
    limit: number): Promise<Array<AlbumListItem>> {
    return this.queryArtistAlbums(
      artistId,
      LibraryQueryPagingPolicy.offset(offset),
      LibraryQueryPagingPolicy.limit(limit)
    );
  }

  getArtistAlbums(artistId: number): Promise<Array<AlbumListItem>> {
    return this.queryArtistAlbums(artistId);
  }

  private async queryArtistAlbums(artistId: number, offset?: number,
    limit?: number): Promise<Array<AlbumListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      const pageClause = offset === undefined || limit === undefined ? '' : ' LIMIT ? OFFSET ?';
      const bindings: Array<number> = [artistId];
      if (offset !== undefined && limit !== undefined) {
        bindings.push(limit, offset);
      }
      resultSet = await this.database.getStore().querySql(
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
         ORDER BY al.release_date_sort DESC, al.sort_title_key, al.id${pageClause}`,
        bindings
      );
      return this.readAlbumListItems(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read albums for artist ${artistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist albums');
    }
  }

  async getRelatedAlbumCount(albumId: number): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT COUNT(DISTINCT al.id)
         FROM album_credit current_credit
         JOIN album_credit related_credit
           ON related_credit.person_id = current_credit.person_id
         JOIN album al ON al.id = related_credit.album_id
         WHERE current_credit.album_id = ?
           AND al.id <> ?`,
        [albumId, albumId]
      );
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to count albums related to ${albumId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'related album count');
    }
  }

  getRelatedAlbumPage(albumId: number, offset: number,
    limit: number): Promise<Array<AlbumListItem>> {
    return this.queryRelatedAlbums(
      albumId,
      LibraryQueryPagingPolicy.offset(offset),
      LibraryQueryPagingPolicy.limit(limit)
    );
  }

  getRelatedAlbums(albumId: number): Promise<Array<AlbumListItem>> {
    return this.queryRelatedAlbums(albumId);
  }

  private async queryRelatedAlbums(albumId: number, offset?: number,
    limit?: number): Promise<Array<AlbumListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      const pageClause = offset === undefined || limit === undefined ? '' : ' LIMIT ? OFFSET ?';
      const bindings: Array<number> = [albumId, albumId];
      if (offset !== undefined && limit !== undefined) {
        bindings.push(limit, offset);
      }
      resultSet = await this.database.getStore().querySql(
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
         ORDER BY al.release_date_sort DESC, al.sort_title_key, al.id${pageClause}`,
        bindings
      );
      return this.readAlbumListItems(resultSet);
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read albums related to ${albumId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'related albums');
    }
  }

  private readAlbumListItems(resultSet: relationalStore.ResultSet): Array<AlbumListItem> {
    const albums: Array<AlbumListItem> = [];
    try {
      while (resultSet.goToNextRow()) {
        albums.push(albumListItemFromCurrentRow(resultSet));
      }
      return albums;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to decode album list', error);
    }
  }

  getArtistTrackPage(artistId: number, offset: number,
    limit: number): Promise<Array<TrackListItem>> {
    return this.queryArtistTracks(
      artistId,
      LibraryQueryPagingPolicy.offset(offset),
      LibraryQueryPagingPolicy.limit(limit)
    );
  }

  getArtistTracks(artistId: number): Promise<Array<TrackListItem>> {
    return this.queryArtistTracks(artistId);
  }

  getAlbumTracks(albumId: number): Promise<Array<TrackListItem>> {
    return this.queryAlbumTracks(albumId);
  }

  private async queryArtistTracks(artistId: number, offset?: number,
    limit?: number): Promise<Array<TrackListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const tracks: Array<TrackListItem> = [];
    try {
      const pageClause = offset === undefined || limit === undefined ? '' : ' LIMIT ? OFFSET ?';
      const bindings: Array<number> = [artistId, CreditRole.TRACK_ARTIST, artistId];
      if (offset !== undefined && limit !== undefined) {
        bindings.push(limit, offset);
      }
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
          t.track_number, t.title_natural_key, t.id${pageClause}`,
        bindings
      );
      while (resultSet.goToNextRow()) {
        tracks.push(trackListItemFromCurrentRow(resultSet));
      }
      return tracks;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read tracks for artist ${artistId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist tracks');
    }
  }

}
