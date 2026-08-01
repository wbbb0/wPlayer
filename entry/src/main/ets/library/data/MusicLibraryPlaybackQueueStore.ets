import { relationalStore } from '@kit.ArkData';
import { LibraryDatabase } from './LibraryDatabase';
import {
  PersistedPlaybackQueueItem,
  PersistedPlaybackQueueSnapshot
} from './MusicRepositoryTypes';
import { RelationalStoreSafety } from './RelationalStoreSafety';

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
        'SELECT current_position FROM playback_queue_state WHERE singleton = 1'
      );
      if (!stateResult.goToNextRow()) {
        return undefined;
      }
      currentPosition = stateResult.getLong(0);
      RelationalStoreSafety.closeResultSet(stateResult, 'playback queue state');
      stateResult = undefined;
      itemResult = await store.querySql(
        'SELECT position, track_id FROM playback_queue_item ORDER BY position'
      );
      const items: Array<PersistedPlaybackQueueItem> = [];
      while (itemResult.goToNextRow()) {
        items.push({
          position: itemResult.getLong(0),
          trackId: itemResult.getLong(1)
        });
      }
      return { items: items, currentPosition: currentPosition };
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read persisted playback queue', error);
    } finally {
      RelationalStoreSafety.closeResultSet(stateResult, 'playback queue state');
      RelationalStoreSafety.closeResultSet(itemResult, 'playback queue items');
    }
  }

  replaceSnapshot(trackIds: Array<number>, currentPosition: number): Promise<void> {
    const immutableIds = trackIds.slice();
    return this.database.enqueueWrite(async (transaction): Promise<void> => {
      await transaction.execute('DELETE FROM playback_queue_item');
      for (let position = 0; position < immutableIds.length; position += 1) {
        await transaction.execute(
          'INSERT INTO playback_queue_item(position, track_id) VALUES(?, ?)',
          [position, immutableIds[position]]
        );
      }
      await transaction.execute(
        `INSERT OR REPLACE INTO playback_queue_state(singleton, current_position, updated_at)
         VALUES(1, ?, ?)`,
        [currentPosition, Date.now()]
      );
    });
  }

  updateCurrentPosition(currentPosition: number): Promise<void> {
    return this.database.enqueueWrite(async (transaction): Promise<void> => {
      await transaction.execute(
        `INSERT OR REPLACE INTO playback_queue_state(singleton, current_position, updated_at)
         VALUES(1, ?, ?)`,
        [currentPosition, Date.now()]
      );
    });
  }
}
