import { LibraryCatalog, LibrarySection } from '../model/LibraryModels';
import { LibraryQueryPagingPolicy } from './LibraryQueryPagingPolicy';

export interface LibrarySectionPageSegment {
  label: string;
  localOffset: number;
  limit: number;
}

/**
 * Maps one global, position-based page onto the catalog's ordered sections.
 *
 * The catalog is the ordering authority: callers must execute the returned
 * segments in order and must not sort section labels again.
 */
export class LibrarySectionPagePlanner {
  static plan(catalog: LibraryCatalog, offset: number,
    limit: number): Array<LibrarySectionPageSegment> {
    LibrarySectionPagePlanner.validateCatalog(catalog);
    const safeOffset = LibraryQueryPagingPolicy.offset(offset);
    const safeLimit = LibraryQueryPagingPolicy.limit(limit);
    if (safeOffset >= catalog.totalCount || catalog.totalCount <= 0) {
      return [];
    }

    const endExclusive = Math.min(catalog.totalCount, safeOffset + safeLimit);
    const segments: Array<LibrarySectionPageSegment> = [];
    let sectionIndex = LibrarySectionPagePlanner.sectionIndexForOffset(catalog.sections, safeOffset);
    let cursor = safeOffset;
    while (cursor < endExclusive && sectionIndex < catalog.sections.length) {
      const section = catalog.sections[sectionIndex];
      const sectionEnd = sectionIndex + 1 < catalog.sections.length ?
        catalog.sections[sectionIndex + 1].startIndex : catalog.totalCount;
      if (section.startIndex > cursor || sectionEnd <= cursor) {
        throw new Error('Alphabetic catalog section boundaries are inconsistent');
      }
      const segmentEnd = Math.min(sectionEnd, endExclusive);
      segments.push({
        label: section.label,
        localOffset: cursor - section.startIndex,
        limit: segmentEnd - cursor
      });
      cursor = segmentEnd;
      sectionIndex += 1;
    }
    if (cursor !== endExclusive) {
      throw new Error('Alphabetic catalog does not cover the requested page');
    }
    return segments;
  }

  private static validateCatalog(catalog: LibraryCatalog): void {
    if (!Number.isFinite(catalog.totalCount) || !Number.isInteger(catalog.totalCount) ||
      catalog.totalCount < 0) {
      throw new Error('Alphabetic catalog total count is invalid');
    }
    if (catalog.totalCount === 0) {
      if (catalog.sections.length !== 0) {
        throw new Error('Empty alphabetic catalog must not contain sections');
      }
      return;
    }
    if (catalog.sections.length === 0 || catalog.sections[0].startIndex !== 0) {
      throw new Error('Alphabetic catalog must start at index zero');
    }
    let previousStart = -1;
    catalog.sections.forEach((section: LibrarySection): void => {
      if (!Number.isFinite(section.startIndex) || !Number.isInteger(section.startIndex) ||
        section.startIndex <= previousStart || section.startIndex < 0 ||
        section.startIndex >= catalog.totalCount) {
        throw new Error('Alphabetic catalog section boundaries are inconsistent');
      }
      previousStart = section.startIndex;
    });
  }

  private static sectionIndexForOffset(sections: Array<LibrarySection>, offset: number): number {
    let low = 0;
    let high = sections.length - 1;
    let selected = -1;
    while (low <= high) {
      const middle = Math.floor((low + high) / 2);
      if (sections[middle].startIndex <= offset) {
        selected = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return selected;
  }
}
