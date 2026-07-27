import { describe, expect, it } from '@ohos/hypium';
import {
  MediaImportOperation,
  MediaImportWorkQueue
} from '../main/ets/library/importer/MediaImportOperation';

class TestImportQueue implements MediaImportWorkQueue {
  cancelCount: number = 0;
  waitCount: number = 0;
  private idle: Promise<void>;
  private resolveIdle?: () => void;

  constructor(initiallyIdle: boolean = true) {
    this.idle = initiallyIdle ? Promise.resolve() :
      new Promise<void>((resolve: () => void): void => {
        this.resolveIdle = resolve;
      });
  }

  cancel(): void {
    this.cancelCount += 1;
  }

  waitForIdle(): Promise<void> {
    this.waitCount += 1;
    return this.idle;
  }

  release(): void {
    this.resolveIdle?.();
  }
}

export default function mediaImportOperationTest() {
  describe('Media import operation', () => {
    it('shares one cancellation state with attached work', 0, () => {
      const operation = new MediaImportOperation();
      const queue = new TestImportQueue();
      operation.attachQueue(queue);
      operation.cancel();
      expect(operation.isCancelled()).assertTrue();
      expect(queue.cancelCount).assertEqual(1);
    });

    it('cancels a queue attached after cancellation', 0, () => {
      const operation = new MediaImportOperation();
      operation.cancel();
      const queue = new TestImportQueue();
      operation.attachQueue(queue);
      expect(queue.cancelCount).assertEqual(1);
    });

    it('rejects a distinct second queue while allowing identity attach', 0, () => {
      const operation = new MediaImportOperation();
      const first = new TestImportQueue();
      operation.attachQueue(first);
      operation.attachQueue(first);
      let rejected = false;
      try {
        operation.attachQueue(new TestImportQueue());
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('waits for running queue work and detaches by identity', 0, async () => {
      const operation = new MediaImportOperation();
      const queue = new TestImportQueue(false);
      operation.attachQueue(queue);
      let completed = false;
      const waiting = operation.cancelAndWait().then((): void => {
        completed = true;
      });
      await Promise.resolve();
      expect(completed).assertFalse();
      queue.release();
      await waiting;
      expect(completed).assertTrue();
      expect(queue.waitCount).assertEqual(1);
      operation.attachQueue(new TestImportQueue());
    });
  });
}
