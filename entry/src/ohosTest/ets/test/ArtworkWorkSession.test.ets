import { describe, expect, it } from '@ohos/hypium';
import {
  ArtworkWorkCancellation,
  ArtworkWorkOutcome,
  ArtworkWorkRequest,
  ArtworkWorkResult,
  ArtworkWorkSession
} from '../../../main/ets/library/artwork/ArtworkWorkSession';

export default function artworkWorkSessionTest() {
  describe('ArtworkWorkSession', () => {
    it('limitsConcurrentArtworkWorkers', 0, async () => {
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

    it('cancelsQueuedArtworkAsSkipped', 0, async () => {
      const session = new ArtworkWorkSession(
        async (_request: ArtworkWorkRequest,
          _cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> => {
          return { outcome: ArtworkWorkOutcome.COMPLETED, sourceHasArtwork: true, errorMessage: '' };
        },
        false,
        3
      );
      const tasks: Array<Promise<ArtworkWorkResult>> = [];
      for (let index = 0; index < 256; index += 1) {
        tasks.push(session.enqueue({
          trackId: index,
          uri: `uri-${index}`,
          fileSize: index,
          modifiedAt: index
        }));
      }
      session.cancel();
      const results = await Promise.all(tasks);
      expect(results.length).assertEqual(256);
      expect(results[0].outcome).assertEqual(ArtworkWorkOutcome.SKIPPED);
      expect(results[results.length - 1].outcome).assertEqual(ArtworkWorkOutcome.SKIPPED);
      await session.waitForIdle();
    });
  });
}
