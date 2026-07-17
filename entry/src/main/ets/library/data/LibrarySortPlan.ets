import {
  AlbumSortField,
  LibraryIndexPresentation,
  SortDirection,
  TrackSortField
} from '../model/LibraryModels';

/**
 * One authoritative description of a library ordering.
 *
 * Full snapshots, random-access pages and alphabet-section metadata must use
 * the same descriptor so their global indexes cannot drift apart.
 */
export class LibrarySortDescriptor {
  readonly alphabetic: boolean;
  readonly sectionExpression: string;
  readonly orderClause: string;
  readonly sectionOrderClause: string;

  constructor(alphabetic: boolean, sectionExpression: string, orderClause: string,
    sectionOrderClause: string = '') {
    this.alphabetic = alphabetic;
    this.sectionExpression = sectionExpression;
    this.orderClause = orderClause;
    this.sectionOrderClause = sectionOrderClause;
  }

  indexPresentation(): LibraryIndexPresentation {
    return this.alphabetic ? LibraryIndexPresentation.ALPHABET : LibraryIndexPresentation.SCROLLBAR;
  }
}

export class LibrarySortPlan {
  static track(field: TrackSortField, direction: SortDirection): LibrarySortDescriptor {
    const order = LibrarySortPlan.order(direction);
    if (field === TrackSortField.TITLE) {
      return LibrarySortPlan.alphabetic('t.title_section', 't.title_natural_key', 't.id', order);
    }
    if (field === TrackSortField.ALBUM) {
      return LibrarySortPlan.alphabetic('t.album_section', 't.album_natural_key', 't.id', order);
    }
    if (field === TrackSortField.ARTIST) {
      return LibrarySortPlan.alphabetic('t.artist_section', 't.artist_natural_key', 't.id', order);
    }
    if (field === TrackSortField.RELEASE_DATE) {
      return new LibrarySortDescriptor(
        false,
        "'#'",
        `t.release_date_sort = 0 ASC, t.release_date_sort ${order}, t.id ${order}`
      );
    }
    return new LibrarySortDescriptor(false, "'#'", `t.created_at ${order}, t.id ${order}`);
  }

  static album(field: AlbumSortField, direction: SortDirection): LibrarySortDescriptor {
    const order = LibrarySortPlan.order(direction);
    if (field === AlbumSortField.TITLE) {
      return LibrarySortPlan.alphabetic('al.title_section', 'al.title_natural_key', 'al.id', order);
    }
    if (field === AlbumSortField.ALBUM_ARTIST) {
      return LibrarySortPlan.alphabetic('al.artist_section', 'al.artist_natural_key', 'al.id', order);
    }
    if (field === AlbumSortField.RELEASE_DATE) {
      return new LibrarySortDescriptor(
        false,
        "'#'",
        `al.release_date_sort = 0 ASC, al.release_date_sort ${order}, al.id ${order}`
      );
    }
    return new LibrarySortDescriptor(false, "'#'", `al.created_at ${order}, al.id ${order}`);
  }

  private static alphabetic(sectionExpression: string, valueExpression: string,
    idExpression: string, order: string): LibrarySortDescriptor {
    return new LibrarySortDescriptor(
      true,
      sectionExpression,
      `${sectionExpression} = '#' ASC, ${valueExpression} ${order}, ${idExpression} ${order}`,
      `${sectionExpression} = '#' ASC, ${sectionExpression} ${order}`
    );
  }

  private static order(direction: SortDirection): string {
    return direction === SortDirection.ASCENDING ? 'ASC' : 'DESC';
  }
}
