import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryRemovalCommit,
  LibraryRemovalRepository
} from '../main/ets/library/data/MusicRepositoryTypes';
import { LibraryRemovalService } from '../main/ets/library/maintenance/LibraryRemovalService';

class FakeRemovalRepository implements LibraryRemovalRepository {
  clearCommit: LibraryRemovalCommit = { removedCount: 0, persistedUris: [] };
  removeCommit: LibraryRemovalCommit = { removedCount: 0, persistedUris: [] };
  failClear: boolean = false;
  events: Array<string> = [];

  async commitClearLibrary(): Promise<LibraryRemovalCommit> {
    this.events.push('commit-clear');
    if (this.failClear) {
      throw new Error('database rollback');
    }
    return this.clearCommit;
  }

  async commitRemoveTracks(_trackIds: Array<number>): Promise<LibraryRemovalCommit> {
    this.events.push('commit-remove');
    return this.removeCommit;
  }
}

export default function libraryRemovalServiceTest() {
  describe('LibraryRemovalService', () => {
    it('revokes persisted permissions only after the database commit', 0, async () => {
      const repository = new FakeRemovalRepository();
      repository.removeCommit = {
        removedCount: 2,
        persistedUris: ['file://one', 'file://two']
      };
      const revoked: Array<string> = [];
      const service = new LibraryRemovalService(repository, async (uris: Array<string>): Promise<void> => {
        repository.events.push('revoke');
        revoked.push(...uris);
      });

      const commit = await service.removeTracks([4, 8]);

      expect(repository.events.join(',')).assertEqual('commit-remove,revoke');
      expect(commit.removedCount).assertEqual(2);
      expect(revoked.join(',')).assertEqual('file://one,file://two');
    });

    it('does not revoke permissions when the database commit fails', 0, async () => {
      const repository = new FakeRemovalRepository();
      repository.failClear = true;
      let revokeCount = 0;
      const service = new LibraryRemovalService(repository, async (_uris: Array<string>): Promise<void> => {
        revokeCount += 1;
      });
      let rejected = false;

      try {
        await service.clearLibrary();
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
      expect(revokeCount).assertEqual(0);
    });

    it('keeps the committed deletion successful when permission cleanup fails', 0, async () => {
      const repository = new FakeRemovalRepository();
      repository.clearCommit = {
        removedCount: 3,
        persistedUris: ['file://stale']
      };
      const service = new LibraryRemovalService(repository, async (_uris: Array<string>): Promise<void> => {
        throw new Error('permission service unavailable');
      });

      const commit = await service.clearLibrary();

      expect(commit.removedCount).assertEqual(3);
      expect(repository.events.join(',')).assertEqual('commit-clear');
    });

    it('skips the permission service when no persisted authorization was removed', 0, async () => {
      const repository = new FakeRemovalRepository();
      repository.removeCommit = { removedCount: 1, persistedUris: [] };
      let revokeCount = 0;
      const service = new LibraryRemovalService(repository, async (_uris: Array<string>): Promise<void> => {
        revokeCount += 1;
      });

      await service.removeTracks([9]);

      expect(revokeCount).assertEqual(0);
    });
  });
}
