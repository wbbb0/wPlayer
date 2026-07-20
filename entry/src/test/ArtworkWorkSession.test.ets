import { describe, expect, it } from '@ohos/hypium';
import {
  ArtworkWorkCancellation,
  ArtworkWorkOutcome,
  ArtworkWorkRequest,
  ArtworkWorkResult,
  ArtworkWorkSession
} from '../main/ets/library/artwork/ArtworkWorkSession';

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
  });
}
