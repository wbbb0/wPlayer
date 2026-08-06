import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LibraryDatabase } from '../../../main/ets/library/data/LibraryDatabase';

const SUCCESS_CONFIG: relationalStore.StoreConfig = {
  name: 'wplayer_migration_v13_success.db',
  securityLevel: relationalStore.SecurityLevel.S2,
  allowRebuild: false
};
const ROLLBACK_CONFIG: relationalStore.StoreConfig = {
  name: 'wplayer_migration_v13_rollback.db',
  securityLevel: relationalStore.SecurityLevel.S2,
  allowRebuild: false
};

async function deleteStore(context: common.Context,
  config: relationalStore.StoreConfig): Promise<void> {
  try {
    await relationalStore.deleteRdbStore(context, config);
  } catch (_) {
  }
}

async function createVersion13Fixture(context: common.Context,
  config: relationalStore.StoreConfig, includeEncodingVersion: boolean): Promise<void> {
  await deleteStore(context, config);
  const store = await relationalStore.getRdbStore(context, config);
  try {
    await store.execute(
      `CREATE TABLE schema_meta (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        version INTEGER NOT NULL,
        migrated_at INTEGER NOT NULL
      )`
    );
    const encodingColumn = includeEncodingVersion ?
      ', encoding_version INTEGER NOT NULL DEFAULT 99' : '';
    await store.execute(
      `CREATE TABLE artwork_asset (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        small_path TEXT NOT NULL,
        large_path TEXT NOT NULL,
        marker TEXT NOT NULL${encodingColumn}
      )`
    );
    await store.execute(
      'INSERT INTO schema_meta(singleton, version, migrated_at) VALUES(1, 13, 1)'
    );
    await store.execute(
      "INSERT INTO artwork_asset(small_path, large_path, marker) VALUES('old-small.jpg', 'old-large.jpg', 'retained')"
    );
    store.version = 13;
  } finally {
    await store.close();
  }
}

async function readFirstLong(store: relationalStore.RdbStore, sql: string): Promise<number> {
  const resultSet = await store.querySql(sql);
  try {
    return resultSet.goToNextRow() ? resultSet.getLong(0) : -1;
  } finally {
    resultSet.close();
  }
}

async function readFirstString(store: relationalStore.RdbStore, sql: string): Promise<string> {
  const resultSet = await store.querySql(sql);
  try {
    return resultSet.goToNextRow() ? resultSet.getString(0) : '';
  } finally {
    resultSet.close();
  }
}

async function currentAbilityContext(): Promise<common.Context> {
  const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  return ability.context;
}

export default function libraryDatabaseMigrationTest() {
  describe('Library database migration', () => {
    it('migratesVersion13ArtworkAssetsAndRetainsRows', 0, async () => {
      const context = await currentAbilityContext();
      await createVersion13Fixture(context, SUCCESS_CONFIG, false);
      const database = new LibraryDatabase(SUCCESS_CONFIG);
      try {
        await database.initialize(context);
        const store = database.getStore();
        expect(await readFirstLong(
          store,
          "SELECT COUNT(*) FROM pragma_table_info('artwork_asset') WHERE name = 'encoding_version'"
        )).assertEqual(1);
        expect(await readFirstLong(
          store,
          'SELECT encoding_version FROM artwork_asset WHERE id = 1'
        )).assertEqual(1);
        expect(await readFirstString(
          store,
          'SELECT marker FROM artwork_asset WHERE id = 1'
        )).assertEqual('retained');
        expect(await readFirstLong(
          store,
          'SELECT version FROM schema_meta WHERE singleton = 1'
        )).assertEqual(14);
      } finally {
        await database.close();
        await deleteStore(context, SUCCESS_CONFIG);
      }
    });

    it('rollsBackVersion13MigrationFailureWithoutLosingRows', 0, async () => {
      const context = await currentAbilityContext();
      await createVersion13Fixture(context, ROLLBACK_CONFIG, true);
      const database = new LibraryDatabase(ROLLBACK_CONFIG);
      let rejected = false;
      try {
        await database.initialize(context);
      } catch (_) {
        rejected = true;
      } finally {
        await database.close();
      }
      expect(rejected).assertTrue();
      const store = await relationalStore.getRdbStore(context, ROLLBACK_CONFIG);
      try {
        expect(await readFirstLong(
          store,
          'SELECT version FROM schema_meta WHERE singleton = 1'
        )).assertEqual(13);
        expect(await readFirstString(
          store,
          'SELECT marker FROM artwork_asset WHERE id = 1'
        )).assertEqual('retained');
      } finally {
        await store.close();
        await deleteStore(context, ROLLBACK_CONFIG);
      }
    });
  });
}
