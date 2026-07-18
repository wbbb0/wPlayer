import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SortKeyNormalizer } from '../metadata/SortKeyNormalizer';
import { ARTWORK_PALETTE_VERSION } from '../artwork/ArtworkPaletteExtractor';
import { RelationalStoreSafety } from './RelationalStoreSafety';

const DATABASE_NAME = 'music_library.db';
const DATABASE_VERSION = 11;
const SORT_REBUILD_BATCH_SIZE = 500;

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DATABASE_NAME,
  securityLevel: relationalStore.SecurityLevel.S2,
  allowRebuild: false
};

const CURRENT_SCHEMA: Array<string> = [
  `CREATE TABLE schema_meta (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    version INTEGER NOT NULL,
    migrated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE media_file (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uri TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    file_size INTEGER NOT NULL DEFAULT 0,
    modified_at INTEGER NOT NULL DEFAULT 0,
    quick_fingerprint TEXT NOT NULL DEFAULT '',
    content_fingerprint TEXT NOT NULL DEFAULT '',
    format TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT '',
    authorization_persisted INTEGER NOT NULL DEFAULT 0,
    availability_state INTEGER NOT NULL DEFAULT 0,
    import_state INTEGER NOT NULL DEFAULT 0,
    last_checked_at INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE artwork_asset (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    small_hash TEXT NOT NULL,
    small_path TEXT NOT NULL,
    small_format TEXT NOT NULL,
    small_width INTEGER NOT NULL DEFAULT 0,
    small_height INTEGER NOT NULL DEFAULT 0,
    small_byte_size INTEGER NOT NULL DEFAULT 0,
    large_hash TEXT NOT NULL,
    large_path TEXT NOT NULL,
    large_format TEXT NOT NULL,
    large_width INTEGER NOT NULL DEFAULT 0,
    large_height INTEGER NOT NULL DEFAULT 0,
    large_byte_size INTEGER NOT NULL DEFAULT 0,
    palette_primary TEXT NOT NULL DEFAULT '#FF7C4DFF',
    palette_secondary TEXT NOT NULL DEFAULT '#FFFF4D8D',
    palette_accent TEXT NOT NULL DEFAULT '#FFFFB347',
    palette_version INTEGER NOT NULL DEFAULT ${ARTWORK_PALETTE_VERSION},
    ref_count INTEGER NOT NULL DEFAULT 0 CHECK (ref_count >= 0),
    unreferenced_at INTEGER,
    created_at INTEGER NOT NULL,
    UNIQUE (small_hash, large_hash)
  )`,
  `CREATE TABLE artwork_source (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_hash TEXT NOT NULL UNIQUE,
    asset_id INTEGER NOT NULL REFERENCES artwork_asset(id) ON DELETE CASCADE,
    mime_type TEXT NOT NULL DEFAULT '',
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    byte_size INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE album (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identity_key TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    title_key TEXT NOT NULL,
    sort_title_key TEXT NOT NULL,
    title_natural_key TEXT NOT NULL DEFAULT '',
    title_section TEXT NOT NULL DEFAULT '#',
    album_artist_display TEXT NOT NULL DEFAULT '',
    album_artist_key TEXT NOT NULL DEFAULT '',
    artist_natural_key TEXT NOT NULL DEFAULT '',
    artist_section TEXT NOT NULL DEFAULT '#',
    release_date_raw TEXT NOT NULL DEFAULT '',
    release_year INTEGER,
    release_month INTEGER,
    release_day INTEGER,
    release_date_precision INTEGER NOT NULL DEFAULT 0,
    release_date_sort INTEGER NOT NULL DEFAULT 0,
    track_count INTEGER NOT NULL DEFAULT 0,
    total_duration_ms INTEGER NOT NULL DEFAULT 0,
    primary_artwork_id INTEGER REFERENCES artwork_asset(id) ON DELETE SET NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE track (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    media_file_id INTEGER NOT NULL UNIQUE REFERENCES media_file(id) ON DELETE CASCADE,
    album_id INTEGER REFERENCES album(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    sort_title TEXT NOT NULL DEFAULT '',
    sort_key TEXT NOT NULL,
    title_natural_key TEXT NOT NULL DEFAULT '',
    title_section TEXT NOT NULL DEFAULT '#',
    artist_display TEXT NOT NULL DEFAULT '',
    artist_natural_key TEXT NOT NULL DEFAULT '',
    artist_section TEXT NOT NULL DEFAULT '#',
    album_display TEXT NOT NULL DEFAULT '',
    album_natural_key TEXT NOT NULL DEFAULT '',
    album_section TEXT NOT NULL DEFAULT '#',
    album_artist_display TEXT NOT NULL DEFAULT '',
    composer_display TEXT NOT NULL DEFAULT '',
    track_number INTEGER,
    total_track_count INTEGER,
    track_number_raw TEXT NOT NULL DEFAULT '',
    disc_number INTEGER,
    total_disc_count INTEGER,
    disc_number_raw TEXT NOT NULL DEFAULT '',
    release_date_raw TEXT NOT NULL DEFAULT '',
    release_year INTEGER,
    release_month INTEGER,
    release_day INTEGER,
    release_date_precision INTEGER NOT NULL DEFAULT 0,
    release_date_sort INTEGER NOT NULL DEFAULT 0,
    original_release_date_raw TEXT NOT NULL DEFAULT '',
    original_release_year INTEGER,
    original_release_month INTEGER,
    original_release_day INTEGER,
    original_release_date_precision INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    sample_rate INTEGER NOT NULL DEFAULT 0,
    channel_count INTEGER NOT NULL DEFAULT 0,
    bits_per_sample INTEGER NOT NULL DEFAULT 0,
    bit_rate INTEGER NOT NULL DEFAULT 0,
    primary_artwork_id INTEGER REFERENCES artwork_asset(id) ON DELETE SET NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE person (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    name_key TEXT NOT NULL UNIQUE,
    sort_name_key TEXT NOT NULL
  )`,
  `CREATE TABLE track_credit (
    track_id INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    person_id INTEGER NOT NULL REFERENCES person(id) ON DELETE CASCADE,
    role INTEGER NOT NULL,
    ordinal INTEGER NOT NULL,
    PRIMARY KEY (track_id, role, ordinal)
  )`,
  `CREATE TABLE album_credit (
    album_id INTEGER NOT NULL REFERENCES album(id) ON DELETE CASCADE,
    person_id INTEGER NOT NULL REFERENCES person(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    PRIMARY KEY (album_id, ordinal)
  )`,
  `CREATE TABLE genre (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    name_key TEXT NOT NULL UNIQUE
  )`,
  `CREATE TABLE track_genre (
    track_id INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    genre_id INTEGER NOT NULL REFERENCES genre(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    PRIMARY KEY (track_id, ordinal)
  )`,
  `CREATE TABLE track_tag_extra (
    track_id INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    tag_key TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    raw_value TEXT NOT NULL,
    PRIMARY KEY (track_id, tag_key, ordinal)
  )`,
  `CREATE TABLE track_artwork (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    track_id INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    source_id INTEGER REFERENCES artwork_source(id) ON DELETE SET NULL,
    asset_id INTEGER REFERENCES artwork_asset(id) ON DELETE SET NULL,
    picture_type INTEGER NOT NULL,
    ordinal INTEGER NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    mime_type TEXT NOT NULL DEFAULT '',
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    color_depth INTEGER NOT NULL DEFAULT 0,
    byte_offset INTEGER NOT NULL DEFAULT 0,
    byte_length INTEGER NOT NULL DEFAULT 0,
    payload_offset INTEGER NOT NULL DEFAULT 0,
    unsynchronized INTEGER NOT NULL DEFAULT 0,
    UNIQUE (track_id, ordinal)
  )`,
  `CREATE TABLE playlist (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind INTEGER NOT NULL DEFAULT 0 CHECK (kind IN (0, 1)),
    fixed_key TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    item_sort_field INTEGER NOT NULL DEFAULT 0,
    item_sort_direction INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_played_at INTEGER NOT NULL DEFAULT 0,
    CHECK (
      (kind = 0 AND fixed_key = '') OR
      (kind = 1 AND fixed_key = 'completed_history' AND name = '完整听过' AND normalized_name = '完整听过')
    ),
    UNIQUE (normalized_name)
  )`,
  `CREATE TABLE playlist_item (
    playlist_id INTEGER NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
    track_id INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    manual_position INTEGER NOT NULL,
    added_at INTEGER NOT NULL,
    add_source INTEGER NOT NULL DEFAULT 0 CHECK (add_source IN (0, 1, 2)),
    first_qualified_at INTEGER NOT NULL DEFAULT 0,
    last_qualified_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (playlist_id, track_id)
  )`,
  `CREATE TABLE track_playback_stats (
    track_id INTEGER PRIMARY KEY REFERENCES track(id) ON DELETE CASCADE,
    play_count INTEGER NOT NULL DEFAULT 0,
    completed_count INTEGER NOT NULL DEFAULT 0,
    last_started_at INTEGER NOT NULL DEFAULT 0,
    last_played_at INTEGER NOT NULL DEFAULT 0,
    last_completed_at INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE track_playback_state (
    track_id INTEGER PRIMARY KEY REFERENCES track(id) ON DELETE CASCADE,
    resume_position_ms INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    completed INTEGER NOT NULL DEFAULT 0,
    last_played_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL
  )`,
  'CREATE INDEX idx_media_file_fingerprint ON media_file(file_size, quick_fingerprint)',
  `CREATE UNIQUE INDEX idx_media_file_content_fingerprint ON media_file(file_size, content_fingerprint)
   WHERE content_fingerprint <> ''`,
  'CREATE INDEX idx_media_file_availability ON media_file(availability_state, id)',
  'CREATE INDEX idx_track_sort ON track(sort_key, id)',
  'CREATE INDEX idx_track_title_natural ON track(title_section, title_natural_key, id)',
  'CREATE INDEX idx_track_album_natural ON track(album_section, album_natural_key, id)',
  'CREATE INDEX idx_track_artist_natural ON track(artist_section, artist_natural_key, id)',
  'CREATE INDEX idx_track_release_date ON track(release_date_sort, id)',
  'CREATE INDEX idx_track_created_at ON track(created_at, id)',
  'CREATE INDEX idx_track_album_order ON track(album_id, disc_number, track_number, id)',
  'CREATE INDEX idx_album_sort ON album(sort_title_key, id)',
  'CREATE INDEX idx_album_title_natural ON album(title_section, title_natural_key, id)',
  'CREATE INDEX idx_album_artist_natural ON album(artist_section, artist_natural_key, id)',
  'CREATE INDEX idx_album_release_date ON album(release_date_sort, id)',
  'CREATE INDEX idx_album_created_at ON album(created_at, id)',
  'CREATE INDEX idx_track_credit_person_role ON track_credit(person_id, role, track_id)',
  'CREATE INDEX idx_track_genre_genre ON track_genre(genre_id, track_id)',
  'CREATE INDEX idx_track_artwork_fallback ON track_artwork(track_id, picture_type, ordinal)',
  'CREATE INDEX idx_artwork_asset_gc ON artwork_asset(ref_count, unreferenced_at)',
  `CREATE UNIQUE INDEX idx_playlist_fixed_key ON playlist(fixed_key)
   WHERE fixed_key <> ''`,
  'CREATE INDEX idx_playlist_name ON playlist(normalized_name, id)',
  'CREATE INDEX idx_playlist_last_played ON playlist(last_played_at, id)',
  'CREATE INDEX idx_playlist_updated ON playlist(updated_at, id)',
  'CREATE INDEX idx_playlist_created ON playlist(created_at, id)',
  'CREATE INDEX idx_playlist_item_manual ON playlist_item(playlist_id, manual_position, track_id)',
  'CREATE INDEX idx_playlist_item_added ON playlist_item(playlist_id, added_at, track_id)',
  'CREATE INDEX idx_playlist_item_track ON playlist_item(track_id, playlist_id)',
  'CREATE INDEX idx_playback_stats_played ON track_playback_stats(last_played_at, track_id)',
  'CREATE INDEX idx_playback_stats_completed ON track_playback_stats(last_completed_at, track_id)',
  `INSERT OR IGNORE INTO playlist(
    kind, fixed_key, name, normalized_name, item_sort_field, item_sort_direction,
    created_at, updated_at, last_played_at
  ) VALUES(1, 'completed_history', '完整听过', '完整听过', 1, 1,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000, 0)`,
  `CREATE TRIGGER IF NOT EXISTS protect_completed_playlist_update
   BEFORE UPDATE OF kind, fixed_key, name, normalized_name ON playlist
   WHEN OLD.fixed_key = 'completed_history' OR NEW.kind = 1
   BEGIN
     SELECT RAISE(ABORT, 'completed-history playlist is fixed');
   END`,
  `CREATE TRIGGER IF NOT EXISTS protect_completed_playlist_delete
   BEFORE DELETE ON playlist
   WHEN OLD.fixed_key = 'completed_history'
   BEGIN
     SELECT RAISE(ABORT, 'completed-history playlist cannot be deleted');
   END`
];

export class LibraryDatabase {
  private store?: relationalStore.RdbStore;
  private initializePromise?: Promise<boolean>;
  private writeTail: Promise<void> = Promise.resolve();

  initialize(context: common.Context): Promise<boolean> {
    if (this.store !== undefined) {
      return Promise.resolve(false);
    }
    if (this.initializePromise === undefined) {
      this.initializePromise = this.openAndMigrate(context);
    }
    return this.initializePromise;
  }

  getStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('LibraryDatabase has not been initialized');
    }
    return this.store;
  }

  enqueueWrite<T>(operation: (transaction: relationalStore.Transaction) => Promise<T>): Promise<T> {
    const pending: Promise<T> = this.writeTail.then(async () => {
      const transaction = await this.getStore().createTransaction({
        transactionType: relationalStore.TransactionType.IMMEDIATE
      });
      try {
        const result = await operation(transaction);
        await transaction.commit();
        return result;
      } catch (error) {
        try {
          await transaction.rollback();
        } catch (_) {
        }
        const cause = error as Error;
        throw cause;
      }
    });
    this.writeTail = pending.then(() => undefined, () => undefined);
    return pending;
  }

  rebuildSortIndexes(): Promise<void> {
    return this.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await this.rebuildSortKeys(transaction);
    });
  }

  async close(): Promise<void> {
    await this.writeTail;
    if (this.store !== undefined) {
      try {
        await this.store.close();
      } catch (error) {
        throw RelationalStoreSafety.operationError('Unable to close library database', error);
      }
      this.store = undefined;
      this.initializePromise = undefined;
    }
  }

  private async openAndMigrate(context: common.Context): Promise<boolean> {
    let store: relationalStore.RdbStore | undefined;
    try {
      store = await relationalStore.getRdbStore(context, STORE_CONFIG);
      await store.execute('PRAGMA foreign_keys = ON');
      const rebuilt = await this.migrate(store);
      this.store = store;
      return rebuilt;
    } catch (error) {
      if (store !== undefined) {
        try {
          await store.close();
        } catch (closeError) {
          console.warn(`Unable to close failed library database: ${RelationalStoreSafety.errorMessage(closeError)}`);
        }
      }
      this.initializePromise = undefined;
      throw RelationalStoreSafety.operationError('Unable to initialize library database', error);
    }
  }

  private async migrate(store: relationalStore.RdbStore): Promise<boolean> {
    const hasSchemaMeta = await this.tableExists(store, 'schema_meta');
    if (!hasSchemaMeta) {
      let transaction: relationalStore.Transaction | undefined;
      try {
        transaction = await store.createTransaction({
          transactionType: relationalStore.TransactionType.IMMEDIATE
        });
        for (let index = 0; index < CURRENT_SCHEMA.length; index += 1) {
          await transaction.execute(this.withIfNotExists(CURRENT_SCHEMA[index]));
        }
        await transaction.execute(
          'INSERT INTO schema_meta(singleton, version, migrated_at) VALUES(1, ?, ?)',
          [DATABASE_VERSION, Date.now()]
        );
        await transaction.commit();
        store.version = DATABASE_VERSION;
        return false;
      } catch (error) {
        if (transaction !== undefined) {
          try {
            await transaction.rollback();
          } catch (_) {
          }
        }
        throw RelationalStoreSafety.operationError('Unable to create library schema', error);
      }
    }

    const version = await this.readSchemaVersion(store);
    if (version !== DATABASE_VERSION) {
      await this.rebuildSchema(store);
      return true;
    }
    if (store.version !== DATABASE_VERSION) {
      store.version = DATABASE_VERSION;
    }
    return false;
  }

  private async rebuildSchema(store: relationalStore.RdbStore): Promise<void> {
    let transaction: relationalStore.Transaction | undefined;
    const tables = [
      'import_error', 'import_job', 'playlist_item', 'track_playback_stats', 'track_playback_state',
      'playlist', 'track_artwork', 'track_tag_extra', 'track_genre',
      'album_credit', 'track_credit', 'genre', 'person', 'track', 'media_file', 'album',
      'artwork_source', 'artwork_asset', 'schema_meta'
    ];
    try {
      transaction = await store.createTransaction({
        transactionType: relationalStore.TransactionType.IMMEDIATE
      });
      for (let index = 0; index < tables.length; index += 1) {
        await transaction.execute(`DROP TABLE IF EXISTS ${tables[index]}`);
      }
      for (let index = 0; index < CURRENT_SCHEMA.length; index += 1) {
        await transaction.execute(this.withIfNotExists(CURRENT_SCHEMA[index]));
      }
      await transaction.execute(
        'INSERT INTO schema_meta(singleton, version, migrated_at) VALUES(1, ?, ?)',
        [DATABASE_VERSION, Date.now()]
      );
      await transaction.commit();
      store.version = DATABASE_VERSION;
    } catch (error) {
      if (transaction !== undefined) {
        try {
          await transaction.rollback();
        } catch (_) {
        }
      }
      throw RelationalStoreSafety.operationError('Unable to rebuild library schema', error);
    }
  }

  private async rebuildSortKeys(transaction: relationalStore.Transaction): Promise<void> {
    try {
      await transaction.execute('DROP TABLE IF EXISTS temp_track_sort_rebuild');
      await transaction.execute(
      `CREATE TEMP TABLE temp_track_sort_rebuild (
        id INTEGER PRIMARY KEY,
        title_key TEXT NOT NULL,
        title_section TEXT NOT NULL,
        album_key TEXT NOT NULL,
        album_section TEXT NOT NULL,
        artist_key TEXT NOT NULL,
        artist_section TEXT NOT NULL,
        release_date_sort INTEGER NOT NULL
      )`
      );
      const trackBuckets: Array<relationalStore.ValuesBucket> = [];
      const trackResults = await transaction.querySql(
      `SELECT id, CASE WHEN sort_title = '' THEN title ELSE sort_title END,
        album_display, artist_display, COALESCE(release_year, 0),
        COALESCE(release_month, 0), COALESCE(release_day, 0)
       FROM track`
      );
      try {
        while (trackResults.goToNextRow()) {
          const title = SortKeyNormalizer.natural(trackResults.getString(1));
          const album = SortKeyNormalizer.natural(trackResults.getString(2));
          const artist = SortKeyNormalizer.natural(trackResults.getString(3));
          trackBuckets.push({
            id: trackResults.getLong(0),
            title_key: title.key,
            title_section: title.section,
            album_key: album.key,
            album_section: album.section,
            artist_key: artist.key,
            artist_section: artist.section,
            release_date_sort: SortKeyNormalizer.dateParts(
              trackResults.getLong(4), trackResults.getLong(5), trackResults.getLong(6)
            )
          });
        }
      } finally {
        RelationalStoreSafety.closeResultSet(trackResults, 'track sort rebuild');
      }
      await this.batchInsert(transaction, 'temp_track_sort_rebuild', trackBuckets);
      await transaction.execute(
      `UPDATE track SET
        title_natural_key = (SELECT title_key FROM temp_track_sort_rebuild s WHERE s.id = track.id),
        title_section = (SELECT title_section FROM temp_track_sort_rebuild s WHERE s.id = track.id),
        album_natural_key = (SELECT album_key FROM temp_track_sort_rebuild s WHERE s.id = track.id),
        album_section = (SELECT album_section FROM temp_track_sort_rebuild s WHERE s.id = track.id),
        artist_natural_key = (SELECT artist_key FROM temp_track_sort_rebuild s WHERE s.id = track.id),
        artist_section = (SELECT artist_section FROM temp_track_sort_rebuild s WHERE s.id = track.id),
        release_date_sort = (SELECT release_date_sort FROM temp_track_sort_rebuild s WHERE s.id = track.id)
       WHERE id IN (SELECT id FROM temp_track_sort_rebuild)`
      );
      await transaction.execute('DROP TABLE temp_track_sort_rebuild');

      await transaction.execute('DROP TABLE IF EXISTS temp_album_sort_rebuild');
      await transaction.execute(
      `CREATE TEMP TABLE temp_album_sort_rebuild (
        id INTEGER PRIMARY KEY,
        title_key TEXT NOT NULL,
        title_section TEXT NOT NULL,
        artist_key TEXT NOT NULL,
        artist_section TEXT NOT NULL,
        release_date_sort INTEGER NOT NULL
      )`
      );
      const albumBuckets: Array<relationalStore.ValuesBucket> = [];
      const albumResults = await transaction.querySql(
      `SELECT id, title, album_artist_display, COALESCE(release_year, 0),
        COALESCE(release_month, 0), COALESCE(release_day, 0)
       FROM album`
      );
      try {
        while (albumResults.goToNextRow()) {
          const title = SortKeyNormalizer.natural(albumResults.getString(1));
          const artist = SortKeyNormalizer.natural(albumResults.getString(2));
          albumBuckets.push({
            id: albumResults.getLong(0),
            title_key: title.key,
            title_section: title.section,
            artist_key: artist.key,
            artist_section: artist.section,
            release_date_sort: SortKeyNormalizer.dateParts(
              albumResults.getLong(3), albumResults.getLong(4), albumResults.getLong(5)
            )
          });
        }
      } finally {
        RelationalStoreSafety.closeResultSet(albumResults, 'album sort rebuild');
      }
      await this.batchInsert(transaction, 'temp_album_sort_rebuild', albumBuckets);
      await transaction.execute(
      `UPDATE album SET
        title_natural_key = (SELECT title_key FROM temp_album_sort_rebuild s WHERE s.id = album.id),
        title_section = (SELECT title_section FROM temp_album_sort_rebuild s WHERE s.id = album.id),
        artist_natural_key = (SELECT artist_key FROM temp_album_sort_rebuild s WHERE s.id = album.id),
        artist_section = (SELECT artist_section FROM temp_album_sort_rebuild s WHERE s.id = album.id),
        release_date_sort = (SELECT release_date_sort FROM temp_album_sort_rebuild s WHERE s.id = album.id)
       WHERE id IN (SELECT id FROM temp_album_sort_rebuild)`
      );
      await transaction.execute('DROP TABLE temp_album_sort_rebuild');
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to rebuild library sort keys', error);
    }
  }

  private async batchInsert(transaction: relationalStore.Transaction, table: string,
    buckets: Array<relationalStore.ValuesBucket>): Promise<void> {
    try {
      for (let offset = 0; offset < buckets.length; offset += SORT_REBUILD_BATCH_SIZE) {
        await transaction.batchInsert(
          table,
          buckets.slice(offset, Math.min(offset + SORT_REBUILD_BATCH_SIZE, buckets.length))
        );
      }
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to populate ${table}`, error);
    }
  }

  private withIfNotExists(sql: string): string {
    if (sql.startsWith('CREATE TABLE ')) {
      return sql.replace('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS ');
    }
    if (sql.startsWith('CREATE INDEX ')) {
      return sql.replace('CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS ');
    }
    return sql;
  }

  private async tableExists(store: relationalStore.RdbStore, tableName: string): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await store.querySql(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [tableName]
      );
      return resultSet.goToNextRow();
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to inspect table ${tableName}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, `table ${tableName}`);
    }
  }

  private async readSchemaVersion(store: relationalStore.RdbStore): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await store.querySql('SELECT version FROM schema_meta WHERE singleton = 1 LIMIT 1');
      if (!resultSet.goToNextRow()) {
        throw new Error('Library database schema version is missing');
      }
      return resultSet.getLong(0);
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read library schema version', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'schema version query');
    }
  }
}
