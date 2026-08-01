import { relationalStore } from '@kit.ArkData';
import { LibraryDatabase } from './LibraryDatabase';
import {
  PersistedPlaybackQueueItem,
  PersistedPlaybackQueueSnapshot
} from './MusicRepositoryTypes';
import { RelationalStoreSafety } from './RelationalStoreSafety';

const PLAYBACK_QUEUE_INSERT_BATCH_SIZE = 500;

export class MusicLibraryPlaybackQueueStore {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  async getSnapshot(): Promise<PersistedPlaybackQueueSnapshot | undefined> {
    let stateResult: relationalStore.ResultSet | undefined;
    let itemResult: relationalStore.ResultSet | undefined;
    let currentPosition = -1;
    try {
      const store = this.database.getStore();
      stateResult = await store.querySql(
        'SELECT current_position, shuffle_enabled FROM playback_queue_state WHERE singleton = 1'
      );
      if (!stateResult.goToNextRow()) {
        return undefined;
      }
      currentPosition = stateResult.getLong(0);
      const shuffleEnabled = stateResult.getLong(1) === 1;
      RelationalStoreSafety.closeResultSet(stateResult, 'playback queue state');
      stateResult = undefined;
      itemResult = await store.querySql(
        'SELECT position, playback_position, track_id FROM playback_queue_item ORDER BY position'
      );
      const items: Array<PersistedPlaybackQueueItem> = [];
      while (itemResult.goToNextRow()) {
        items.push({
          position: itemResult.getLong(0),
          playbackPosition: itemResult.getLong(1),
          trackId: itemResult.getLong(2)
        });
      }
      return {
        items: items,
        currentPosition: currentPosition,
        shuffleEnabled: shuffleEnabled
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read persisted playback queue', error);
    } finally {
      RelationalStoreSafety.closeResultSet(stateResult, 'playback queue state');
      RelationalStoreSafety.closeResultSet(itemResult, 'playback queue items');
    }
  }

  replaceSnapshot(snapshot: PersistedPlaybackQueueSnapshot): Promise<void> {
    const immutableSnapshot: PersistedPlaybackQueueSnapshot = {
      items: snapshot.items.map((item: PersistedPlaybackQueueItem): PersistedPlaybackQueueItem => ({
        position: item.position,
        playbackPosition: item.playbackPosition,
        trackId: item.trackId
      })),
      currentPosition: snapshot.currentPosition,
      shuffleEnabled: snapshot.shuffleEnabled
    };
    return this.database.enqueueWrite(async (transaction): Promise<void> => {
      await transaction.execute(
        `CREATE TEMP TABLE IF NOT EXISTS temp_playback_queue_item (
           position INTEGER NOT NULL,
           playback_position INTEGER NOT NULL,
           track_id INTEGER NOT NULL
         )`
      );
      await transaction.execute('DELETE FROM temp_playback_queue_item');
      const buckets: Array<relationalStore.ValuesBucket> = immutableSnapshot.items.map(
        (item: PersistedPlaybackQueueItem): relationalStore.ValuesBucket => ({
          position: item.position,
          playback_position: item.playbackPosition,
          track_id: item.trackId
        }));
      for (let offset = 0; offset < buckets.length;
        offset += PLAYBACK_QUEUE_INSERT_BATCH_SIZE) {
        await transaction.batchInsert(
          'temp_playback_queue_item',
          buckets.slice(offset, Math.min(offset + PLAYBACK_QUEUE_INSERT_BATCH_SIZE, buckets.length))
        );
      }
      await transaction.execute('DELETE FROM playback_queue_item');
      await transaction.execute(
        `INSERT INTO playback_queue_item(position, playback_position, track_id)
         SELECT position, playback_position, track_id
         FROM temp_playback_queue_item ORDER BY position`
      );
      await transaction.execute('DROP TABLE temp_playback_queue_item');
      await transaction.execute(
        `INSERT OR REPLACE INTO playback_queue_state(
           singleton, current_position, shuffle_enabled, updated_at
         ) VALUES(1, ?, ?, ?)`,
        [immutableSnapshot.currentPosition, immutableSnapshot.shuffleEnabled ? 1 : 0, Date.now()]
      );
    });
  }

  updateCurrentPosition(currentPosition: number): Promise<void> {
    return this.database.enqueueWrite(async (transaction): Promise<void> => {
      await transaction.execute(
        `UPDATE playback_queue_state SET current_position = ?, updated_at = ?
         WHERE singleton = 1`,
        [currentPosition, Date.now()]
      );
    });
  }
}
