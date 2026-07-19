import {
  ImportItemDetailKind,
  ImportItemOutcome,
  ImportItemResult
} from '../model/LibraryModels';

export class ImportDetailPolicy {
  static shouldRetain(item: ImportItemResult): boolean {
    return item.outcome !== ImportItemOutcome.IMPORTED;
  }

  static kindOf(item: ImportItemResult): ImportItemDetailKind | undefined {
    if (item.detailKind !== undefined) {
      return item.detailKind;
    }
    if (item.outcome === ImportItemOutcome.FAILED) {
      return ImportItemDetailKind.FAILED;
    }
    if (item.outcome === ImportItemOutcome.DUPLICATE) {
      return ImportItemDetailKind.CONTENT_DUPLICATE;
    }
    return undefined;
  }
}
