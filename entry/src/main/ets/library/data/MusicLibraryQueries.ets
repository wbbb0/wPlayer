import { relationalStore } from '@kit.ArkData';
import {
  AlbumReference,
  AlbumListItem,
  AlbumDetail,
  AlbumSortField,
  ArtistDetail,
  ArtistReference,
  AvailabilityState,
  ArtworkPictureType,
  CreditRole,
  LibraryCatalog,
  LibraryIndexPresentation,
  LibraryPage,
  LibrarySection,
  LibrarySnapshot,
  LibraryStatistics,
  MediaFormat,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField,
  SortDirection
} from '../model/LibraryModels';
import { PlaybackTrack, ResumeState } from '../../playback/model/PlaybackModels';
import { LibraryDatabase } from './LibraryDatabase';
import {
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate
} from './MusicRepositoryTypes';
import { PaletteRefreshAsset } from './MusicRepositoryTypes';
import { LibrarySortDescriptor, LibrarySortPlan } from './LibrarySortPlan';

const URI_QUERY_BATCH_SIZE = 128;

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
      artworkCount: await this.readCount(store, 'SELECT COUNT(*) FROM artwork_asset WHERE ref_count > 0')
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
    const resultSet = await this.database.getStore().querySql(
      `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
        COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
        COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
        COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), ${descriptor.sectionExpression}
       FROM track t LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
       ORDER BY ${descriptor.orderClause}${paginationClause}`,
      bindArgs
    );
    const items: Array<TrackListItem> = [];
    try {
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
          sectionKey: resultSet.getString(16)
        });
      }
    } finally {
      resultSet.close();
    }
    return items;
  }

  async getPlaybackTrack(trackId: number): Promise<PlaybackTrack | undefined> {
    const resultSet = await this.database.getStore().querySql(
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
    try {
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
    } finally {
      resultSet.close();
    }
  }

  async getResumeState(trackId: number): Promise<ResumeState> {
    const resultSet = await this.database.getStore().querySql(
      `SELECT resume_position_ms, duration_ms, completed
       FROM track_playback_state WHERE track_id = ? LIMIT 1`,
      [trackId]
    );
    try {
      if (!resultSet.goToNextRow() || resultSet.getLong(2) === 1) {
        return { positionMs: 0, durationMs: 0 };
      }
      return { positionMs: resultSet.getLong(0), durationMs: resultSet.getLong(1) };
    } finally {
      resultSet.close();
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
    const resultSet = await this.database.getStore().querySql(
      `SELECT al.id, al.title, al.album_artist_display, al.track_count,
        al.total_duration_ms, COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), ${descriptor.sectionExpression}
       FROM album al LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
       ORDER BY ${descriptor.orderClause}${paginationClause}`,
      bindArgs
    );
    return this.readAlbumListItems(resultSet);
  }

  async getAlbumDetail(albumId: number): Promise<AlbumDetail | undefined> {
    const albumResult = await this.database.getStore().querySql(
      `SELECT al.id, al.title, al.album_artist_display, al.track_count,
        al.total_duration_ms, COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), '#',
        COALESCE(al.release_year, 0),
        COALESCE((SELECT GROUP_CONCAT(g.name) FROM genre g WHERE g.id IN (
          SELECT tg.genre_id FROM track_genre tg JOIN track grouped_track ON grouped_track.id = tg.track_id
          WHERE grouped_track.album_id = al.id
        )), '')
       FROM album al LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
       WHERE al.id = ? LIMIT 1`,
      [albumId]
    );
    let album: AlbumListItem | undefined;
    let releaseYear: number = 0;
    let genreDisplay: string = '';
    try {
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
          sectionKey: albumResult.getString(11)
        };
        releaseYear = albumResult.getLong(12);
        genreDisplay = albumResult.getString(13);
      }
    } finally {
      albumResult.close();
    }
    if (album === undefined) {
      return undefined;
    }
    const trackResult = await this.database.getStore().querySql(
      `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
        COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
        COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
        COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), '#'
       FROM track t LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
       WHERE t.album_id = ?
       ORDER BY CASE WHEN t.disc_number IS NULL OR t.disc_number <= 0 THEN 1 ELSE 0 END,
        t.disc_number ASC,
        CASE WHEN t.track_number IS NULL OR t.track_number <= 0 THEN 1 ELSE 0 END,
        t.track_number ASC, t.id ASC`,
      [albumId]
    );
    const tracks: Array<TrackListItem> = [];
    try {
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
          sectionKey: trackResult.getString(16)
        });
      }
    } finally {
      trackResult.close();
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
    const albumResult = await this.database.getStore().querySql(
      `SELECT t.album_id, COALESCE(al.title, ''), COALESCE(a.palette_primary, '#FF7C4DFF')
       FROM track t
       LEFT JOIN album al ON al.id = t.album_id
       LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
       WHERE t.id = ? LIMIT 1`,
      [trackId]
    );
    let albumId = -1;
    let album: AlbumReference | undefined;
    try {
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
    } finally {
      albumResult.close();
    }
    return {
      trackId: trackId,
      trackArtists: await this.getTrackArtists(trackId),
      albumArtists: albumId >= 0 ? await this.getAlbumArtists(albumId) : [],
      album: album
    };
  }

  async getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    const artistResult = await this.database.getStore().querySql(
      'SELECT id, name FROM person WHERE id = ? LIMIT 1',
      [artistId]
    );
    let artist: ArtistReference | undefined;
    try {
      if (artistResult.goToNextRow()) {
        artist = {
          id: artistResult.getLong(0),
          name: artistResult.getString(1)
        };
      }
    } finally {
      artistResult.close();
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
    const resultSet = await this.database.getStore().querySql(
      `SELECT p.id, p.name
       FROM track_credit tc JOIN person p ON p.id = tc.person_id
       WHERE tc.track_id = ? AND tc.role = ?
       ORDER BY tc.ordinal`,
      [trackId, CreditRole.TRACK_ARTIST]
    );
    return this.readArtistReferences(resultSet);
  }

  private async getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    const resultSet = await this.database.getStore().querySql(
      `SELECT p.id, p.name
       FROM album_credit ac JOIN person p ON p.id = ac.person_id
       WHERE ac.album_id = ?
       ORDER BY ac.ordinal`,
      [albumId]
    );
    return this.readArtistReferences(resultSet);
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
    } finally {
      resultSet.close();
    }
    return artists;
  }

  private async getArtistAlbums(artistId: number): Promise<Array<AlbumListItem>> {
    const resultSet = await this.database.getStore().querySql(
      `SELECT DISTINCT al.id, al.title, al.album_artist_display, al.track_count,
        al.total_duration_ms, COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), '#'
       FROM album_credit ac
       JOIN album al ON al.id = ac.album_id
       LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
       WHERE ac.person_id = ?
       ORDER BY al.release_date_sort DESC, al.sort_title_key, al.id`,
      [artistId]
    );
    return this.readAlbumListItems(resultSet);
  }

  private async getRelatedAlbums(albumId: number): Promise<Array<AlbumListItem>> {
    const resultSet = await this.database.getStore().querySql(
      `SELECT DISTINCT al.id, al.title, al.album_artist_display, al.track_count,
        al.total_duration_ms, COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), '#'
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
          sectionKey: resultSet.getString(11)
        });
      }
    } finally {
      resultSet.close();
    }
    return albums;
  }

  private async getArtistTracks(artistId: number): Promise<Array<TrackListItem>> {
    const resultSet = await this.database.getStore().querySql(
      `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
        COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
        COALESCE(a.small_hash, ''), COALESCE(a.small_path, ''),
        COALESCE(a.large_hash, ''), COALESCE(a.large_path, ''),
        COALESCE(a.large_width, 0), COALESCE(a.large_height, 0),
        COALESCE(a.palette_primary, '#FF7C4DFF'), COALESCE(a.palette_secondary, '#FFFF4D8D'),
        COALESCE(a.palette_accent, '#FFFFB347'), '#'
       FROM track t LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
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
    const tracks: Array<TrackListItem> = [];
    try {
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
          sectionKey: resultSet.getString(16)
        });
      }
    } finally {
      resultSet.close();
    }
    return tracks;
  }

  async hasUri(uri: string): Promise<boolean> {
    const resultSet = await this.database.getStore().querySql(
      'SELECT 1 FROM media_file WHERE uri = ? LIMIT 1',
      [uri]
    );
    try {
      return resultSet.goToNextRow();
    } finally {
      resultSet.close();
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
      const resultSet = await this.database.getStore().querySql(
        `SELECT uri FROM media_file WHERE uri IN (${placeholders})`, batch
      );
      try {
        while (resultSet.goToNextRow()) {
          existingUris.push(resultSet.getString(0));
        }
      } finally {
        resultSet.close();
      }
    }
    return existingUris;
  }

  async findDuplicateCandidates(fileSize: number, quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    if (fileSize <= 0 || quickFingerprint.length === 0) {
      return [];
    }
    const resultSet = await this.database.getStore().querySql(
      `SELECT t.id, f.uri, f.content_fingerprint FROM media_file f
       JOIN track t ON t.media_file_id = f.id
       WHERE f.file_size = ? AND f.quick_fingerprint = ?`,
      [fileSize, quickFingerprint]
    );
    const candidates: Array<DuplicateCandidate> = [];
    try {
      while (resultSet.goToNextRow()) {
        candidates.push({
          trackId: resultSet.getLong(0),
          uri: resultSet.getString(1),
          fullFingerprint: resultSet.getString(2)
        });
      }
    } finally {
      resultSet.close();
    }
    return candidates;
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
    const resultSet = await this.database.getStore().querySql(
      `SELECT a.small_hash, a.small_path, a.small_format, a.small_width, a.small_height, a.small_byte_size,
        a.large_hash, a.large_path, a.large_format, a.large_width, a.large_height, a.large_byte_size,
        a.palette_primary, a.palette_secondary, a.palette_accent
       FROM artwork_source s JOIN artwork_asset a ON a.id = s.asset_id
       WHERE s.source_hash = ? LIMIT 1`,
      [sourceHash]
    );
    try {
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
    } finally {
      resultSet.close();
    }
  }

  async getUnreferencedArtworkAssets(): Promise<Array<ArtworkCleanupCandidate>> {
    const resultSet = await this.database.getStore().querySql(
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
    const candidates: Array<ArtworkCleanupCandidate> = [];
    try {
      while (resultSet.goToNextRow()) {
        candidates.push({
          assetId: resultSet.getLong(0),
          smallPath: resultSet.getString(1),
          largePath: resultSet.getString(2),
          deleteSmall: resultSet.getLong(3) !== 0,
          deleteLarge: resultSet.getLong(4) !== 0
        });
      }
    } finally {
      resultSet.close();
    }
    return candidates;
  }

  async getReferencedArtworkPaths(): Promise<Array<string>> {
    const resultSet = await this.database.getStore().querySql(
      'SELECT small_path, large_path FROM artwork_asset WHERE ref_count > 0'
    );
    const paths: Array<string> = [];
    try {
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
    } finally {
      resultSet.close();
    }
    return paths;
  }

  async getPaletteRefreshAssets(): Promise<Array<PaletteRefreshAsset>> {
    const resultSet = await this.database.getStore().querySql(
      'SELECT id, small_path FROM artwork_asset WHERE ref_count > 0 ORDER BY id'
    );
    const assets: Array<PaletteRefreshAsset> = [];
    try {
      while (resultSet.goToNextRow()) {
        const asset: PaletteRefreshAsset = {
          id: resultSet.getLong(0),
          artworkPath: resultSet.getString(1)
        };
        assets.push(asset);
      }
    } finally {
      resultSet.close();
    }
    return assets;
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
    const resultSet = await this.database.getStore().querySql(
      `SELECT ${descriptor.sectionExpression}, COUNT(*)
       FROM ${fromClause}
       GROUP BY ${descriptor.sectionExpression}
       ORDER BY ${descriptor.sectionOrderClause}`
    );
    const sections: Array<LibrarySection> = [];
    let totalCount = 0;
    try {
      while (resultSet.goToNextRow()) {
        sections.push({
          label: resultSet.getString(0),
          startIndex: totalCount
        });
        totalCount += resultSet.getLong(1);
      }
    } finally {
      resultSet.close();
    }
    return {
      totalCount: totalCount,
      sections: sections,
      indexPresentation: LibraryIndexPresentation.ALPHABET
    };
  }

  private async readCount(store: relationalStore.RdbStore, sql: string): Promise<number> {
    const resultSet = await store.querySql(sql);
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } finally {
      resultSet.close();
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
