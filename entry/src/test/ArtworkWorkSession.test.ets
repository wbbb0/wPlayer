import { describe, expect, it } from '@ohos/hypium';
import {
  ArtworkWorkCancellation,
  ArtworkWorkOutcome,
  ArtworkWorkRequest,
  ArtworkWorkResult,
  ArtworkWorkSession
} from '../main/ets/library/artwork/ArtworkWorkSession';
import { BoundedAsyncWorkQueue } from '../main/ets/library/importer/BoundedAsyncWorkQueue';

export default function artworkWorkSessionTest() {
  describe('Artwork work session', () => {
    it('resolves newly queued work as skipped after cancellation', 0, async () => {
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          return { outcome: ArtworkWorkOutcome.COMPLETED, sourceHasArtwork: true, errorMessage: '' };
        }
      );
      session.cancel();
      const result = await session.enqueue({
        trackId: 1,
        uri: 'uri',
        fileSize: 1,
        modifiedAt: 1
      });
      expect(result.outcome).assertEqual(ArtworkWorkOutcome.SKIPPED);
      await session.waitForIdle();
    });

    it('turns an unexpected processor exception into a failed result', 0, async () => {
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          throw new Error('failure');
        }
      );
      const result = await session.enqueue({
        trackId: 2,
        uri: 'uri',
        fileSize: 2,
        modifiedAt: 2
      });
      expect(result.outcome).assertEqual(ArtworkWorkOutcome.FAILED);
      await session.waitForIdle();
    });

    it('keeps queued artwork idle until the metadata stage releases it', 0, async () => {
      let processed = false;
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          processed = true;
          return { outcome: ArtworkWorkOutcome.COMPLETED, sourceHasArtwork: true, errorMessage: '' };
        },
        false
      );
      const pending = session.enqueue({
        trackId: 3,
        uri: 'uri',
        fileSize: 3,
        modifiedAt: 3
      });
      expect(processed).assertFalse();
      session.startProcessing();
      const result = await pending;
      expect(processed).assertTrue();
      expect(result.outcome).assertEqual(ArtworkWorkOutcome.COMPLETED);
      await session.waitForIdle();
    });

    it('runs only the configured number of artwork workers', 0, async () => {
      let active = 0;
      let peak = 0;
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          active += 1;
          peak = Math.max(peak, active);
          await new Promise<void>((resolve: () => void) => {
            setTimeout(resolve, 0);
          });
          active -= 1;
          return { outcome: ArtworkWorkOutcome.COMPLETED, sourceHasArtwork: true, errorMessage: '' };
        },
        true,
        3
      );
      const tasks: Array<Promise<ArtworkWorkResult>> = [];
      for (let index = 0; index < 12; index += 1) {
        tasks.push(session.enqueue({
          trackId: index,
          uri: `uri-${index}`,
          fileSize: index,
          modifiedAt: index
        }));
      }
      await Promise.all(tasks);
      expect(peak).assertEqual(3);
      await session.waitForIdle();
    });

    it('cancels a large idle queue without shifting each item', 0, async () => {
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          return { outcome: ArtworkWorkOutcome.COMPLETED, sourceHasArtwork: true, errorMessage: '' };
        },
        false,
        3
      );
      const tasks: Array<Promise<ArtworkWorkResult>> = [];
      for (let index = 0; index < 2048; index += 1) {
        tasks.push(session.enqueue({
          trackId: index,
          uri: `uri-${index}`,
          fileSize: index,
          modifiedAt: index
        }));
      }
      session.cancel();
      const results = await Promise.all(tasks);
      expect(results.length).assertEqual(2048);
      expect(results[0].outcome).assertEqual(ArtworkWorkOutcome.SKIPPED);
      expect(results[results.length - 1].outcome).assertEqual(ArtworkWorkOutcome.SKIPPED);
      await session.waitForIdle();
    });

    it('bounds concurrent producers before they enter the artwork processor', 0, async () => {
      let active = 0;
      let peak = 0;
      const queue = new BoundedAsyncWorkQueue<number>(3, async (_work: number): Promise<void> => {
        active += 1;
        peak = Math.max(peak, active);
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, 0);
        });
        active -= 1;
      });
      const admissions: Array<Promise<void>> = [];
      for (let index = 0; index < 24; index += 1) {
        admissions.push(queue.enqueue(index));
      }
      await Promise.all(admissions);
      await queue.closeAndWait();
      expect(peak).assertEqual(3);
    });

    it('drains later queued work before surfacing the first processor failure', 0, async () => {
      let processed = 0;
      const queue = new BoundedAsyncWorkQueue<number>(2, async (work: number): Promise<void> => {
        processed += 1;
        if (work === 1) {
          throw new Error('queue failure');
        }
      });
      await Promise.all([queue.enqueue(1), queue.enqueue(2), queue.enqueue(3)]);
      let failed = false;
      try {
        await queue.closeAndWait();
      } catch (_error) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect(processed).assertEqual(3);
    });

    it('closes only after producers already waiting for capacity are drained', 0, async () => {
      const processed: Array<number> = [];
      const queue = new BoundedAsyncWorkQueue<number>(1, async (work: number): Promise<void> => {
        await new Promise<void>((resolve: () => void): void => {
          setTimeout(resolve, 0);
        });
        processed.push(work);
      });
      const admissions: Array<Promise<void>> = [
        queue.enqueue(1), queue.enqueue(2), queue.enqueue(3)
      ];
      const closing = queue.closeAndWait();
      await Promise.all(admissions);
      await closing;
      expect(processed.join(',')).assertEqual('1,2,3');
    });

    it('rejects new work after closing starts and keeps close idempotent', 0, async () => {
      const queue = new BoundedAsyncWorkQueue<number>(1, async (_work: number): Promise<void> => {});
      await queue.enqueue(1);
      const firstClose = queue.closeAndWait();
      let rejected = false;
      try {
        await queue.enqueue(2);
      } catch (_error) {
        rejected = true;
      }
      await firstClose;
      await queue.closeAndWait();
      expect(rejected).assertTrue();
    });

    it('settles every admitted artwork item as skipped after cancellation', 0, async () => {
      let processed = 0;
      let skipped = 0;
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          return { outcome: ArtworkWorkOutcome.COMPLETED, sourceHasArtwork: true, errorMessage: '' };
        },
        false,
        2
      );
      const queue = new BoundedAsyncWorkQueue<ArtworkWorkRequest>(2,
        async (request: ArtworkWorkRequest): Promise<void> => {
          const result = await session.enqueue(request);
          processed += 1;
          if (result.outcome === ArtworkWorkOutcome.SKIPPED) {
            skipped += 1;
          }
        });
      const admissions: Array<Promise<void>> = [];
      for (let index = 0; index < 8; index += 1) {
        admissions.push(queue.enqueue({
          trackId: index,
          uri: `uri-${index}`,
          fileSize: index,
          modifiedAt: index
        }));
      }
      session.cancel();
      await Promise.all(admissions);
      await queue.closeAndWait();
      expect(processed).assertEqual(8);
      expect(skipped).assertEqual(8);
      await session.waitForIdle();
    });
  });
}
