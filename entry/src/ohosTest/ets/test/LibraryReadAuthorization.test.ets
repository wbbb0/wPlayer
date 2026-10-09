import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LibraryDatabase } from '../../../main/ets/library/data/LibraryDatabase';
import { MusicLibraryMaintenanceQueries } from '../../../main/ets/library/data/MusicLibraryMaintenanceQueries';

const CONFIG: relationalStore.StoreConfig = {
  name: 'wplayer_authorization_regression.db',
  securityLevel: relationalStore.SecurityLevel.S2,
  allowRebuild: false
};

async function deleteFixture(context: common.Context): Promise<void> {
  try {
    await relationalStore.deleteRdbStore(context, CONFIG);
  } catch (_) {
  }
}

export default function libraryReadAuthorizationTest() {
  describe('Existing library authorization', () => {
    it('restores authorization without replacing tracks history or memberships', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      await deleteFixture(context);
      const database = new LibraryDatabase(CONFIG);
      try {
        await database.initialize(context);
        const store = database.getStore();
        await store.execute(
          `INSERT INTO media_file(id, uri, display_name, format, authorization_persisted,
            availability_state, created_at, updated_at)
           VALUES(1, 'file://existing', 'a.mp3', 'mp3', 0, 2, 1, 1),
             (2, 'file://corrupted', 'b.mp3', 'mp3', 0, 3, 1, 1),
             (3, 'file://unavailable', 'c.mp3', 'mp3', 0, 1, 1, 1)`
        );
        await store.execute(
          `INSERT INTO track(id, media_file_id, title, sort_key, created_at, updated_at)
           VALUES(41, 1, 'retained title', 'a', 1, 1)`
        );
        await store.execute(
          `INSERT INTO playlist(id, name, normalized_name, created_at, updated_at)
           VALUES(17, 'retained playlist', 'retained playlist', 1, 1)`
        );
        await store.execute('INSERT INTO playlist_item(playlist_id, track_id, manual_position, added_at) VALUES(17, 41, 7, 1)');
        await store.execute('INSERT INTO track_playback_stats(track_id, play_count, completed_count) VALUES(41, 8, 3)');
        await store.execute('INSERT INTO track_playback_state(track_id, resume_position_ms, updated_at) VALUES(41, 1234, 1)');
        const maintenance = new MusicLibraryMaintenanceQueries(database);
        await maintenance.restoreReadAuthorization(['file://existing', 'file://corrupted', 'file://unavailable']);
        await maintenance.restoreReadAuthorization(['file://existing']);
        const result = await store.querySql(
          `SELECT t.id, t.title, f.authorization_persisted, f.availability_state,
            p.manual_position, s.play_count, s.completed_count, r.resume_position_ms
           FROM track t JOIN media_file f ON f.id = t.media_file_id
           JOIN playlist_item p ON p.track_id = t.id JOIN track_playback_stats s ON s.track_id = t.id
           JOIN track_playback_state r ON r.track_id = t.id WHERE t.id = 41`
        );
        try {
          expect(result.goToNextRow()).assertTrue();
          expect(result.getLong(0)).assertEqual(41);
          expect(result.getString(1)).assertEqual('retained title');
          expect(result.getLong(2)).assertEqual(1);
          expect(result.getLong(3)).assertEqual(0);
          expect(result.getLong(4)).assertEqual(7);
          expect(result.getLong(5)).assertEqual(8);
          expect(result.getLong(6)).assertEqual(3);
          expect(result.getLong(7)).assertEqual(1234);
          expect(result.goToNextRow()).assertFalse();
        } finally {
          result.close();
        }
        const damaged = await store.querySql('SELECT availability_state, authorization_persisted FROM media_file WHERE id IN (2, 3) ORDER BY id');
        try {
          expect(damaged.goToNextRow()).assertTrue();
          expect(damaged.getLong(0)).assertEqual(3);
          expect(damaged.getLong(1)).assertEqual(1);
          expect(damaged.goToNextRow()).assertTrue();
          expect(damaged.getLong(0)).assertEqual(1);
        } finally {
          damaged.close();
        }
        await store.execute(
          `INSERT INTO artwork_asset(id, small_hash, small_path, small_format,
            large_hash, large_path, large_format, ref_count, created_at)
           VALUES(1, 's1', 'artwork/shared.webp', 'image/webp', 'l1', 'artwork/shared.webp', 'image/webp', 1, 1),
             (2, 's2', '', 'image/webp', 'l2', 'artwork/shared.webp', 'image/webp', 1, 1),
             (3, 's3', 'artwork/orphan.webp', 'image/webp', 'l3', '', 'image/webp', 0, 1)`
        );
        expect((await maintenance.getReferencedArtworkPaths()).join(',')).assertEqual('artwork/shared.webp');
      } finally {
        await database.close();
        await deleteFixture(context);
      }
    });
  });
}
