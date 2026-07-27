import { describe, expect, it } from '@ohos/hypium';
import {
  PlaybackPictureInPictureLifecycle
} from '../main/ets/playback/pip/PlaybackPictureInPictureLifecycle';

class FakePiPController {
  readonly id: number;

  constructor(id: number) {
    this.id = id;
  }
}

class DeferredOperation {
  readonly promise: Promise<void>;
  private complete: () => void = (): void => {};

  constructor() {
    this.promise = new Promise<void>((resolve: () => void): void => {
      this.complete = resolve;
    });
  }

  resolve(): void {
    this.complete();
  }
}

export default function playbackPictureInPictureLifecycleTest() {
  describe('Playback picture-in-picture lifecycle', () => {
    it('invalidates pending work before disposal completes', 0, () => {
      const lifecycle = new PlaybackPictureInPictureLifecycle();
      const epoch = lifecycle.current();
      const controller = new FakePiPController(1);

      expect(lifecycle.ownsController(epoch, controller, controller)).assertTrue();

      lifecycle.beginDispose();

      expect(lifecycle.canStartOperation()).assertFalse();
      expect(lifecycle.isCurrent(epoch)).assertFalse();
      expect(lifecycle.ownsController(epoch, controller, controller)).assertFalse();
    });

    it('rejects an old controller after the reusable lifecycle restarts', 0, () => {
      const lifecycle = new PlaybackPictureInPictureLifecycle();
      const oldEpoch = lifecycle.current();
      const oldController = new FakePiPController(1);

      lifecycle.beginDispose();
      lifecycle.finishDispose();

      const newEpoch = lifecycle.current();
      const newController = new FakePiPController(2);
      expect(lifecycle.canStartOperation()).assertTrue();
      expect(lifecycle.ownsController(oldEpoch, oldController, newController)).assertFalse();
      expect(lifecycle.ownsController(newEpoch, newController, newController)).assertTrue();
    });

    it('waits for a pending enter before final controller cleanup', 0, async () => {
      const lifecycle = new PlaybackPictureInPictureLifecycle();
      const pendingEnter = new DeferredOperation();
      let cleanupCount = 0;
      lifecycle.beginDispose();

      const disposal = lifecycle.runDisposal(
        undefined,
        pendingEnter.promise,
        undefined,
        async (_pendingStopSucceeded: boolean): Promise<void> => {
          cleanupCount += 1;
        }
      );
      await Promise.resolve();
      expect(cleanupCount).assertEqual(0);

      pendingEnter.resolve();
      await disposal;

      expect(cleanupCount).assertEqual(1);
      lifecycle.finishDispose();
      expect(lifecycle.canStartOperation()).assertTrue();
    });

    it('invalidates post-start side effects while still performing final cleanup', 0, async () => {
      const lifecycle = new PlaybackPictureInPictureLifecycle();
      const startPiP = new DeferredOperation();
      const epoch = lifecycle.current();
      let minimized = false;
      let stopCount = 0;
      const pendingEnter = startPiP.promise.then((): void => {
        if (lifecycle.isCurrent(epoch)) {
          minimized = true;
        }
      });

      lifecycle.beginDispose();
      const disposal = lifecycle.runDisposal(
        undefined,
        pendingEnter,
        undefined,
        async (_pendingStopSucceeded: boolean): Promise<void> => {
          stopCount += 1;
        }
      );
      startPiP.resolve();
      await disposal;

      expect(minimized).assertFalse();
      expect(stopCount).assertEqual(1);
    });

    it('reports a failed pending stop so final cleanup can retry it', 0, async () => {
      const lifecycle = new PlaybackPictureInPictureLifecycle();
      let pendingStopSucceeded = true;
      lifecycle.beginDispose();

      await lifecycle.runDisposal(
        undefined,
        undefined,
        Promise.reject(new Error('stop failed')),
        async (succeeded: boolean): Promise<void> => {
          pendingStopSucceeded = succeeded;
        }
      );

      expect(pendingStopSucceeded).assertFalse();
    });
  });
}
