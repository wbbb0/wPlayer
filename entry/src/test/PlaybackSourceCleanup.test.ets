import { describe, expect, it } from '@ohos/hypium';
import { PlaybackSourceCleanup } from '../main/ets/playback/engine/PlaybackSourceCleanup';

export default function playbackSourceCleanupTest() {
  describe('PlaybackSourceCleanup', () => {
    it('resets before closing a failed source', 0, async () => {
      const events: Array<string> = [];

      const result = await PlaybackSourceCleanup.run(
        async (): Promise<void> => {
          events.push('reset');
        },
        async (): Promise<void> => {
          events.push('release');
        },
        (): void => {
          events.push('close');
        }
      );

      expect(events.join(',')).assertEqual('reset,close');
      expect(result.resetError === undefined).assertTrue();
    });

    it('releases an unusable player before closing when reset fails', 0, async () => {
      const events: Array<string> = [];

      const result = await PlaybackSourceCleanup.run(
        async (): Promise<void> => {
          events.push('reset');
          throw new Error('reset failed');
        },
        async (): Promise<void> => {
          events.push('release');
        },
        (): void => {
          events.push('close');
        }
      );

      expect(events.join(',')).assertEqual('reset,release,close');
      expect(result.resetError !== undefined).assertTrue();
      expect(result.releaseError === undefined).assertTrue();
    });

    it('still closes exactly once when both reset and release fail', 0, async () => {
      const events: Array<string> = [];
      let closeCount = 0;

      const result = await PlaybackSourceCleanup.run(
        async (): Promise<void> => {
          events.push('reset');
          throw new Error('reset failed');
        },
        async (): Promise<void> => {
          events.push('release');
          throw new Error('release failed');
        },
        (): void => {
          events.push('close');
          closeCount += 1;
        }
      );

      expect(events.join(',')).assertEqual('reset,release,close');
      expect(closeCount).assertEqual(1);
      expect(result.releaseError !== undefined).assertTrue();
    });
  });
}
