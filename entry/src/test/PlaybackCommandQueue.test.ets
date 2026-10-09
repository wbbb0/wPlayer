import { describe, expect, it } from '@ohos/hypium';
import { PlaybackCommandQueue } from '../main/ets/playback/engine/PlaybackCommandQueue';
import { RequestEpoch } from '../main/ets/playback/support/RequestEpoch';

export default function playbackCommandQueueTest() {
  describe('Playback command ownership', () => {
    it('ignores late failure and queued work from a replaced source', 0, async () => {
      const epoch = new RequestEpoch();
      let failures = 0;
      let obsoleteRuns = 0;
      let latestRuns = 0;
      let rejectOld: (error: Error) => void = (_error: Error): void => {};
      const oldWork = new Promise<void>((_resolve, reject): void => { rejectOld = reject; });
      const queue = new PlaybackCommandQueue(epoch, (_error: Object): void => { failures += 1; });
      const firstEpoch = epoch.begin();
      const first = queue.enqueue(firstEpoch, (): Promise<void> => oldWork);
      await Promise.resolve();
      const obsolete = queue.enqueue(firstEpoch, async (): Promise<void> => { obsoleteRuns += 1; });
      const latest = queue.enqueue(epoch.begin(), async (): Promise<void> => { latestRuns += 1; });
      rejectOld(new Error('old pause failed'));
      await Promise.all([first, obsolete, latest]);
      expect(failures).assertEqual(0);
      expect(obsoleteRuns).assertEqual(0);
      expect(latestRuns).assertEqual(1);
    });

    it('returns cleanup failure without clearing the next source intent during lookup', 0, async () => {
      const epoch = new RequestEpoch();
      let activeSourceEpoch = epoch.begin();
      let playWhenReady = true;
      let cleanupFailed = false;
      let released = false;
      const queue = new PlaybackCommandQueue(epoch, (_error: Object): void => { playWhenReady = false; },
        (submittedEpoch: number): boolean => submittedEpoch === activeSourceEpoch);
      const stopEpoch = epoch.invalidate();
      await queue.enqueue(stopEpoch, async (): Promise<void> => {
        released = true;
        throw new Error('reset failed after successful release');
      }).catch((): void => { cleanupFailed = true; });
      // Repository and permission lookup complete after old-source cleanup, before the new source begins.
      expect(cleanupFailed).assertTrue();
      expect(released).assertTrue();
      expect(playWhenReady).assertTrue();
      const nextEpoch = epoch.begin();
      let started = false;
      await queue.enqueue(nextEpoch, async (): Promise<void> => {
        activeSourceEpoch = nextEpoch;
        started = playWhenReady;
      });
      expect(started).assertTrue();
      await queue.enqueue(nextEpoch, async (): Promise<void> => {
        throw new Error('new active source failed');
      }).catch((): void => {});
      expect(playWhenReady).assertFalse();
    });

    it('reports active failure once and still executes the next command', 0, async () => {
      const epoch = new RequestEpoch();
      const messages: Array<string> = [];
      const queue = new PlaybackCommandQueue(epoch, (error: Object): void => {
        messages.push(error instanceof Error ? error.message : `${error}`);
      });
      let caught = false;
      await queue.enqueue(epoch.begin(), async (): Promise<void> => {
        throw new Error('active failure');
      }).catch((): void => { caught = true; });
      let completed = false;
      await queue.enqueue(epoch.current(), async (): Promise<void> => { completed = true; });
      await queue.flush();
      expect(caught).assertTrue();
      expect(messages.join(',')).assertEqual('active failure');
      expect(completed).assertTrue();
    });
  });
}
