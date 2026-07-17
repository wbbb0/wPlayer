import { describe, it, expect } from '@ohos/hypium';
import {
  AppRuntimeLifecycle,
  RuntimeActivation
} from '../main/ets/application/runtime/AppRuntimeLifecycle';

class DeferredSignal {
  private resolver?: () => void;
  private readonly promise: Promise<void>;

  constructor() {
    this.promise = new Promise<void>((resolve: () => void) => {
      this.resolver = resolve;
    });
  }

  wait(): Promise<void> {
    return this.promise;
  }

  open(): void {
    this.resolver?.();
  }
}

export default function appRuntimeLifecycleTest() {
  describe('Application runtime lifecycle', () => {
    it('serializes shutdown after initialization', 0, async () => {
      const lifecycle = new AppRuntimeLifecycle();
      const events: Array<string> = [];
      const activation = lifecycle.activate(async (): Promise<void> => {
        events.push('initialize');
      });
      await activation.completion;
      await lifecycle.deactivate(activation.lease, async (): Promise<void> => {
        events.push('shutdown');
      });

      expect(events.length).assertEqual(2);
      expect(events[0]).assertEqual('initialize');
      expect(events[1]).assertEqual('shutdown');
    });

    it('does not let an old shutdown clear a rapidly recreated runtime', 0, async () => {
      const lifecycle = new AppRuntimeLifecycle();
      const initializeGate = new DeferredSignal();
      const events: Array<string> = [];
      const first = lifecycle.activate(async (): Promise<void> => {
        events.push('initialize-first-start');
        await initializeGate.wait();
        events.push('initialize-first-end');
      });
      await Promise.resolve();

      const staleShutdown = lifecycle.deactivate(first.lease, async (): Promise<void> => {
        events.push('shutdown-first');
      });
      const second: RuntimeActivation = lifecycle.activate(async (): Promise<void> => {
        events.push('initialize-second');
      });
      initializeGate.open();

      await first.completion;
      await staleShutdown;
      await second.completion;
      expect(events.length).assertEqual(3);
      expect(events[0]).assertEqual('initialize-first-start');
      expect(events[1]).assertEqual('initialize-first-end');
      expect(events[2]).assertEqual('initialize-second');
    });

    it('ignores a destroy callback from an older ability generation', 0, async () => {
      const lifecycle = new AppRuntimeLifecycle();
      const first = lifecycle.activate(async (): Promise<void> => {});
      await first.completion;
      const second = lifecycle.activate(async (): Promise<void> => {});
      await second.completion;

      let shutdownCount = 0;
      await lifecycle.deactivate(first.lease, async (): Promise<void> => {
        shutdownCount += 1;
      });
      expect(shutdownCount).assertEqual(0);
    });

    it('continues processing lifecycle work after an initialization failure', 0, async () => {
      const lifecycle = new AppRuntimeLifecycle();
      const first = lifecycle.activate(async (): Promise<void> => {
        throw new Error('expected initialization failure');
      });
      try {
        await first.completion;
      } catch (_error) {
      }

      let initialized = false;
      const second = lifecycle.activate(async (): Promise<void> => {
        initialized = true;
      });
      await second.completion;
      expect(initialized).assertTrue();
    });
  });
}
