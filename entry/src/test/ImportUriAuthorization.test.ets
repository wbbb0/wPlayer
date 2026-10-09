import { describe, expect, it } from '@ohos/hypium';
import { ImportUriAuthorization } from '../main/ets/library/importer/ImportUriAuthorization';

export default function importUriAuthorizationTest() {
  describe('Import authorization ownership', () => {
    it('restores existing records only after successful activation', 0, async () => {
      const events: Array<string> = [];
      const authorization = new ImportUriAuthorization(async (uris) => {
        events.push(`activate:${uris.join(',')}`);
        return { successfulUris: ['existing'], failedUris: ['revoked'], cancelled: false };
      }, async (uris) => { events.push(`restore:${uris.join(',')}`); }, (): boolean => false);
      authorization.retainExisting(['existing', 'revoked']);
      const result = await authorization.restoreExisting(['new', 'existing', 'revoked']);
      expect(events.join(';')).assertEqual('activate:existing,revoked;restore:existing');
      expect(result.successfulUris.join(',')).assertEqual('existing');
      expect(result.failedUris.join(',')).assertEqual('revoked');
      expect(authorization.newUris(['new', 'existing', 'revoked']).join(',')).assertEqual('new');
    });

    it('retains existing grants when a transactional restore fails', 0, async () => {
      const authorization = new ImportUriAuthorization(async (uris) => ({
        successfulUris: uris, failedUris: [], cancelled: false
      }), async (_uris) => { throw new Error('database failed'); }, (): boolean => false);
      authorization.retainExisting(['existing']);
      const result = await authorization.restoreExisting(['existing']);
      expect(result.failedUris.join(',')).assertEqual('existing');
      expect(result.errorMessage).assertEqual('database failed');
      expect(authorization.newUris(['existing']).length).assertEqual(0);
    });

    it('does not update records when cancelled during permission activation', 0, async () => {
      let cancelled = false;
      let writes = 0;
      const authorization = new ImportUriAuthorization(async (uris) => {
        cancelled = true;
        return { successfulUris: uris, failedUris: [], cancelled: true };
      }, async (_uris) => { writes += 1; }, (): boolean => cancelled);
      authorization.retainExisting(['existing']);
      const result = await authorization.restoreExisting(['existing', 'new']);
      expect(writes).assertEqual(0);
      expect(result.successfulUris.length).assertEqual(0);
      expect(authorization.newUris(['existing', 'new']).join(',')).assertEqual('new');
    });

    it('does not activate an empty selection or new import as a restored record', 0, async () => {
      let calls = 0;
      const authorization = new ImportUriAuthorization(async (uris) => {
        calls += 1;
        return { successfulUris: uris, failedUris: [], cancelled: false };
      }, async (_uris) => { calls += 1; }, (): boolean => false);
      await authorization.restoreExisting([]);
      await authorization.restoreExisting(['new']);
      expect(calls).assertEqual(0);
    });
  });
}
