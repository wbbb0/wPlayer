import { relationalStore } from '@kit.ArkData';
import {
  AlbumListItem,
  AlbumSortField,
  AvailabilityState,
  LibraryCatalog,
  LibraryIndexPresentation,
  LibraryPage,
  LibrarySection,
  SortDirection
} from '../model/LibraryModels';
import { LibraryDatabase } from './LibraryDatabase';
import { LibraryQueryPagingPolicy } from './LibraryQueryPagingPolicy';
import { albumListItemFromCurrentRow } from './MusicLibraryQueryRows';
import { LibrarySortDescriptor, LibrarySortPlan } from './LibrarySortPlan';
import {
  LibrarySectionPagePlanner,
  LibrarySectionPageSegment
} from './LibrarySectionPagePlanner';
import { RelationalStoreSafety } from './RelationalStoreSafety';

/**
 * Owns album-domain reads. MusicRepository remains responsible for invalidating observable projections.
 */
export class MusicLibraryAlbumQueries {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  getAlbumCatalog(field: AlbumSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.queryCatalog(LibrarySortPlan.album(field, direction));
  }

  async getAlbumPage(field: AlbumSortField, direction: SortDirection,
    catalog: LibraryCatalog, offset: number, limit: number): Promise<LibraryPage<AlbumListItem>> {
    const safeOffset = LibraryQueryPagingPolicy.offset(offset);
    const safeLimit = LibraryQueryPagingPolicy.limit(limit);
    const descriptor = LibrarySortPlan.album(field, direction);
    return {
      offset: safeOffset,
      items: descriptor.alphabetic ?
        await this.queryAlbumSectionPage(descriptor, catalog, safeOffset, safeLimit) :
        await this.queryAlbumItems(descriptor, '', descriptor.orderClause,
          [safeLimit, safeOffset])
    };
  }

  private async queryAlbumSectionPage(descriptor: LibrarySortDescriptor, catalog: LibraryCatalog,
    offset: number, limit: number): Promise<Array<AlbumListItem>> {
    const segments = LibrarySectionPagePlanner.plan(catalog, offset, limit);
    const items: Array<AlbumListItem> = [];
    for (let index = 0; index < segments.length; index += 1) {
      const segment: LibrarySectionPageSegment = segments[index];
      const segmentItems = await this.queryAlbumItems(
        descriptor,
        ` WHERE ${descriptor.sectionExpression} = ?`,
        descriptor.sectionLocalOrderClause,
        [segment.label, segment.limit, segment.localOffset]
      );
      if (segmentItems.length !== segment.limit) {
        throw new Error('Album catalog changed while loading an alphabetic page');
      }
      items.push(...segmentItems);
    }
    return items;
  }

  private async queryAlbumItems(descriptor: LibrarySortDescriptor, filterClause: string,
    orderClause: string, bindArgs: Array<relationalStore.ValueType>): Promise<Array<AlbumListItem>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<AlbumListItem> = [];
    try {
      resultSet = await this.database.getStore().querySql(
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
         ${filterClause}
         ORDER BY ${orderClause} LIMIT ? OFFSET ?`,
        bindArgs
      );
      while (resultSet.goToNextRow()) {
        items.push(albumListItemFromCurrentRow(resultSet));
      }
      return items;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to query albums', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'album list');
    }
  }


  private async queryCatalog(descriptor: LibrarySortDescriptor): Promise<LibraryCatalog> {
    if (!descriptor.alphabetic) {
      return {
        totalCount: await this.readCount(this.database.getStore(), 'SELECT COUNT(*) FROM album'),
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
         FROM album al
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
      throw RelationalStoreSafety.operationError('Unable to build album catalog', error);
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
