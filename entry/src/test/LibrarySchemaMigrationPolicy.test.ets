import { describe, expect, it } from '@ohos/hypium';
import {
  LibrarySchemaMigrationAction,
  LibrarySchemaMigrationPolicy
} from '../main/ets/library/data/LibrarySchemaMigrationPolicy';

export default function librarySchemaMigrationPolicyTest() {
  describe('Library schema migration policy', () => {
    it('keeps schema 13 current', 0, () => {
      expect(LibrarySchemaMigrationPolicy.actionFor(13))
        .assertEqual(LibrarySchemaMigrationAction.CURRENT);
    });

    it('supports the production schema 12 migration', 0, () => {
      expect(LibrarySchemaMigrationPolicy.actionFor(12))
        .assertEqual(LibrarySchemaMigrationAction.MIGRATE_PRODUCTION);
    });

    it('rejects unknown older and newer schemas', 0, () => {
      expect(LibrarySchemaMigrationPolicy.actionFor(11))
        .assertEqual(LibrarySchemaMigrationAction.REJECT);
      expect(LibrarySchemaMigrationPolicy.actionFor(14))
        .assertEqual(LibrarySchemaMigrationAction.REJECT);
    });
  });
}
