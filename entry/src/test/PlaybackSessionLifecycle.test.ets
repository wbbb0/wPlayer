import { describe, expect, it } from '@ohos/hypium';
import {
  PlaybackSessionLifecycle, PlaybackSessionResource
} from '../main/ets/playback/session/PlaybackSessionLifecycle';

class FakeSessionResource implements PlaybackSessionResource {
  activateCount: number = 0;
  deactivateCount: number = 0;
  destroyCount: number = 0;
  failActivation: boolean = false;
  failDeactivation: boolean = false;
  activation?: Promise<void>;

  async activate(): Promise<void> {
    this.activateCount += 1;
    await this.activation;
    if (this.failActivation) {
      throw new Error('activate failed');
    }
  }

  async deactivate(): Promise<void> {
    this.deactivateCount += 1;
    if (this.failDeactivation) {
      throw new Error('deactivate failed');
    }
  }

  async destroy(): Promise<void> {
    this.destroyCount += 1;
  }
}

export default function playbackSessionLifecycleTest() {
  describe('AVSession resource ownership', () => {
    it('destroys failed activation and permits a fresh retry', 0, async () => {
      const lifecycle = new PlaybackSessionLifecycle<FakeSessionResource>((_error: Object): void => {});
      const failed = new FakeSessionResource();
      failed.failActivation = true;
      let caught = false;
      await lifecycle.initialize(async () => failed, async (_session) => {})
        .catch((): void => { caught = true; });
      expect(caught).assertTrue();
      expect(failed.destroyCount).assertEqual(1);
      expect(lifecycle.current()).assertUndefined();
      const successful = new FakeSessionResource();
      await lifecycle.initialize(async () => successful, async (_session) => {});
      expect(lifecycle.current()).assertEqual(successful);
      await lifecycle.shutdown();
      expect(successful.destroyCount).assertEqual(1);
    });

    it('destroys a resource when command registration fails', 0, async () => {
      const lifecycle = new PlaybackSessionLifecycle<FakeSessionResource>((_error: Object): void => {});
      const resource = new FakeSessionResource();
      await lifecycle.initialize(async () => resource, async (_session) => {
        throw new Error('registration failed');
      }).catch((): void => {});
      expect(resource.activateCount).assertEqual(0);
      expect(resource.destroyCount).assertEqual(1);
    });

    it('always destroys after deactivation fails and closes only once', 0, async () => {
      const failures: Array<Object> = [];
      const lifecycle = new PlaybackSessionLifecycle<FakeSessionResource>((error: Object): void => {
        failures.push(error);
      });
      const resource = new FakeSessionResource();
      resource.failDeactivation = true;
      await lifecycle.initialize(async () => resource, async (_session) => {});
      await Promise.all([lifecycle.shutdown(), lifecycle.shutdown()]);
      expect(resource.deactivateCount).assertEqual(1);
      expect(resource.destroyCount).assertEqual(1);
      expect(failures.length).assertEqual(1);
      expect(lifecycle.current()).assertUndefined();
      expect(await lifecycle.initialize(async () => resource, async (_session) => {})).assertUndefined();
    });

    it('joins initialization and disposes an activation completed during shutdown', 0, async () => {
      const lifecycle = new PlaybackSessionLifecycle<FakeSessionResource>((_error: Object): void => {});
      const resource = new FakeSessionResource();
      let finish: () => void = (): void => {};
      resource.activation = new Promise<void>((resolve): void => { finish = resolve; });
      let creates = 0;
      const create = async (): Promise<FakeSessionResource> => { creates += 1; return resource; };
      const first = lifecycle.initialize(create, async (_session) => {});
      const second = lifecycle.initialize(create, async (_session) => {});
      await Promise.resolve();
      await Promise.resolve();
      const closing = lifecycle.shutdown();
      finish();
      await Promise.all([first, second, closing]);
      expect(creates).assertEqual(1);
      expect(resource.deactivateCount).assertEqual(1);
      expect(resource.destroyCount).assertEqual(1);
      expect(lifecycle.current()).assertUndefined();
    });
  });
}
