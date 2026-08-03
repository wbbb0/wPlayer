import { relationalStore } from '@kit.ArkData';
import {
  CreditRole,
  LibraryCatalog,
  LibraryCategoryKind,
  LibraryCategoryListItem,
  LibraryIndexPresentation,
  LibrarySection,
  TrackListItem
} from '../model/LibraryModels';
import { LibraryDatabase } from './LibraryDatabase';
import { trackListItemFromCurrentRow } from './MusicLibraryQueryRows';
import { LibraryQueryPagingPolicy } from './LibraryQueryPagingPolicy';
import {
  LibrarySectionPagePlanner,
  LibrarySectionPageSegment
} from './LibrarySectionPagePlanner';
import { RelationalStoreSafety } from './RelationalStoreSafety';

export class MusicLibraryBrowseQueries {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  getArtistCatalog(): Promise<LibraryCatalog> {
    return this.queryCatalog(
      `SELECT p.name_section, COUNT(*) FROM person p WHERE EXISTS (
         SELECT 1 FROM track_credit tc
         WHERE tc.person_id = p.id AND tc.role = ${CreditRole.TRACK_ARTIST}
       ) OR EXISTS (
         SELECT 1 FROM album_credit ac WHERE ac.person_id = p.id
       ) GROUP BY p.name_section
       ORDER BY p.name_section = '#' ASC, p.name_section ASC`,
      'artist catalog'
    );
  }

  async getArtistPage(catalog: LibraryCatalog, offset: number,
    limit: number): Promise<Array<LibraryCategoryListItem>> {
    const segments = LibrarySectionPagePlanner.plan(catalog, offset, limit);
    const items: Array<LibraryCategoryListItem> = [];
    for (let index = 0; index < segments.length; index += 1) {
      const segment = segments[index];
      const segmentItems = await this.queryArtistSegment(segment);
      if (segmentItems.length !== segment.limit) {
        throw new Error('Artist catalog changed while loading an alphabetic page');
      }
      items.push(...segmentItems);
    }
    return items;
  }

  private async queryArtistSegment(
    segment: LibrarySectionPageSegment
  ): Promise<Array<LibraryCategoryListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<LibraryCategoryListItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `WITH page_person AS (
           SELECT p.id, p.name, p.sort_name_key, p.name_section
           FROM person p
           WHERE p.name_section = ? AND (
             EXISTS (
               SELECT 1 FROM track_credit tc
               WHERE tc.person_id = p.id AND tc.role = ${CreditRole.TRACK_ARTIST}
             ) OR EXISTS (
               SELECT 1 FROM album_credit ac WHERE ac.person_id = p.id
             )
           )
           ORDER BY p.sort_name_key, p.id
           LIMIT ? OFFSET ?
         )
         SELECT pp.id, pp.name,
           (SELECT COUNT(*) FROM (
             SELECT tc.track_id
             FROM track_credit tc
             WHERE tc.person_id = pp.id AND tc.role = ${CreditRole.TRACK_ARTIST}
             UNION
             SELECT t.id
             FROM album_credit ac JOIN track t ON t.album_id = ac.album_id
             WHERE ac.person_id = pp.id
           )),
           (SELECT COUNT(DISTINCT ac.album_id) FROM album_credit ac WHERE ac.person_id = pp.id),
           pp.name_section
         FROM page_person pp
         ORDER BY pp.sort_name_key, pp.id`,
        [segment.label, segment.limit, segment.localOffset]
      );
      while (resultSet.goToNextRow()) {
        items.push({
          id: resultSet.getLong(0),
          kind: LibraryCategoryKind.ARTIST,
          name: resultSet.getString(1),
          trackCount: resultSet.getLong(2),
          albumCount: resultSet.getLong(3),
          sectionKey: resultSet.getString(4)
        });
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read artist page', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artist page');
    }
  }

  getGenreCatalog(): Promise<LibraryCatalog> {
    return this.queryCatalog(
      `SELECT g.name_section, COUNT(*) FROM genre g
       WHERE EXISTS (SELECT 1 FROM track_genre tg WHERE tg.genre_id = g.id)
       GROUP BY g.name_section
       ORDER BY g.name_section = '#' ASC, g.name_section ASC`,
      'genre catalog'
    );
  }

  async getGenrePage(catalog: LibraryCatalog, offset: number,
    limit: number): Promise<Array<LibraryCategoryListItem>> {
    const segments = LibrarySectionPagePlanner.plan(catalog, offset, limit);
    const items: Array<LibraryCategoryListItem> = [];
    for (let index = 0; index < segments.length; index += 1) {
      const segment = segments[index];
      const segmentItems = await this.queryGenreSegment(segment);
      if (segmentItems.length !== segment.limit) {
        throw new Error('Genre catalog changed while loading an alphabetic page');
      }
      items.push(...segmentItems);
    }
    return items;
  }

  private async queryGenreSegment(
    segment: LibrarySectionPageSegment
  ): Promise<Array<LibraryCategoryListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<LibraryCategoryListItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `WITH page_genre AS (
           SELECT g.id, g.name, g.sort_name_key, g.name_section
           FROM genre g
           WHERE g.name_section = ? AND EXISTS (
             SELECT 1 FROM track_genre tg WHERE tg.genre_id = g.id
           )
           ORDER BY g.sort_name_key, g.id
           LIMIT ? OFFSET ?
         )
         SELECT pg.id, pg.name, COUNT(DISTINCT tg.track_id), pg.name_section
         FROM page_genre pg JOIN track_genre tg ON tg.genre_id = pg.id
         GROUP BY pg.id, pg.name, pg.sort_name_key, pg.name_section
         ORDER BY pg.sort_name_key, pg.id`,
        [segment.label, segment.limit, segment.localOffset]
      );
      while (resultSet.goToNextRow()) {
        items.push({
          id: resultSet.getLong(0),
          kind: LibraryCategoryKind.GENRE,
          name: resultSet.getString(1),
          trackCount: resultSet.getLong(2),
          albumCount: 0,
          sectionKey: resultSet.getString(3)
        });
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read genre page', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'genre page');
    }
  }

  getGenreTrackCount(genreId: number): Promise<number> {
    return this.readBoundCount(
      'SELECT COUNT(DISTINCT track_id) FROM track_genre WHERE genre_id = ?',
      [genreId],
      `genre ${genreId} track count`
    );
  }

  getGenreTrackPage(genreId: number, offset: number, limit: number): Promise<Array<TrackListItem>> {
    return this.queryGenreTracks(
      genreId,
      LibraryQueryPagingPolicy.offset(offset),
      LibraryQueryPagingPolicy.limit(limit)
    );
  }

  getGenreTracks(genreId: number): Promise<Array<TrackListItem>> {
    return this.queryGenreTracks(genreId);
  }

  private async queryGenreTracks(genreId: number, offset?: number,
    limit?: number): Promise<Array<TrackListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<TrackListItem> = [];
    try {
      const pageClause = offset === undefined || limit === undefined ? '' : ' LIMIT ? OFFSET ?';
      const bindings: Array<number> = [genreId];
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
         FROM track_genre tg
         JOIN track t ON t.id = tg.track_id
         JOIN media_file m ON m.id = t.media_file_id
         LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
         WHERE tg.genre_id = ?
         ORDER BY t.title_natural_key, t.id${pageClause}`,
        bindings
      );
      while (resultSet.goToNextRow()) {
        items.push(trackListItemFromCurrentRow(resultSet));
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read tracks for genre ${genreId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'genre tracks');
    }
  }

  private async queryCatalog(sql: string, label: string): Promise<LibraryCatalog> {
    let resultSet: relationalStore.ResultSet | undefined;
    const sections: Array<LibrarySection> = [];
    let totalCount = 0;
    try {
      resultSet = await this.database.getStore().querySql(sql);
      while (resultSet.goToNextRow()) {
        sections.push({ label: resultSet.getString(0), startIndex: totalCount });
        totalCount += resultSet.getLong(1);
      }
      return {
        totalCount: totalCount,
        sections: sections,
        indexPresentation: LibraryIndexPresentation.ALPHABET
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read ${label}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, label);
    }
  }

  private async readBoundCount(sql: string, bindings: Array<number>, label: string): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(sql, bindings);
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read ${label}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, label);
    }
  }
}
