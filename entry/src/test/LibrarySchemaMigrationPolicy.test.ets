import { describe, expect, it } from '@ohos/hypium';
import {
  LibrarySchemaMigrationAction,
  LibrarySchemaMigrationPolicy
} from '../main/ets/library/data/LibrarySchemaMigrationPolicy';

export default function librarySchemaMigrationPolicyTest() {
  describe('Library schema migration policy', () => {
    it('keeps schema 14 current', 0, () => {
      expect(LibrarySchemaMigrationPolicy.actionFor(14))
        .assertEqual(LibrarySchemaMigrationAction.CURRENT);
    });

    it('supports each retained production migration entry', 0, () => {
      expect(LibrarySchemaMigrationPolicy.actionFor(12))
        .assertEqual(LibrarySchemaMigrationAction.MIGRATE);
      expect(LibrarySchemaMigrationPolicy.actionFor(13))
        .assertEqual(LibrarySchemaMigrationAction.MIGRATE);
    });

    it('rejects unknown older and newer schemas', 0, () => {
      expect(LibrarySchemaMigrationPolicy.actionFor(11))
        .assertEqual(LibrarySchemaMigrationAction.REJECT);
      expect(LibrarySchemaMigrationPolicy.actionFor(15))
        .assertEqual(LibrarySchemaMigrationAction.REJECT);
    });
  });
}
