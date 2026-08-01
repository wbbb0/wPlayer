import { describe, expect, it } from '@ohos/hypium';
import {
  KeepScreenOnWindow,
  PlayerPageKeepScreenOnController
} from '../main/ets/application/window/PlayerPageKeepScreenOnController';

class FakeKeepScreenOnWindow implements KeepScreenOnWindow {
  values: Array<boolean> = [];

  setWindowKeepScreenOn(value: boolean): Promise<void> {
    this.values.push(value);
    return Promise.resolve();
  }
}

class FailOnceKeepScreenOnWindow implements KeepScreenOnWindow {
  values: Array<boolean> = [];
  private failed: boolean = false;

  setWindowKeepScreenOn(value: boolean): Promise<void> {
    this.values.push(value);
    if (!this.failed) {
      this.failed = true;
      return Promise.reject(new Error('transient failure'));
    }
    return Promise.resolve();
  }
}

export default function playerPageKeepScreenOnControllerTest() {
  describe('Player-page keep-screen-on controller', () => {
    it('requires a foreground visible player page and an enabled preference', 0, async () => {
      const controller = new PlayerPageKeepScreenOnController();
      const target = new FakeKeepScreenOnWindow();
      controller.bindWindow(target);
      controller.setForeground(true);
      controller.setPreferenceEnabled(true);
      controller.setPlayerPageVisible(true);
      controller.setForeground(false);
      await controller.flush();

      expect(target.values.length).assertEqual(3);
      expect(target.values[0]).assertFalse();
      expect(target.values[1]).assertTrue();
      expect(target.values[2]).assertFalse();
    });

    it('releases the bound window when it is replaced', 0, async () => {
      const controller = new PlayerPageKeepScreenOnController();
      const first = new FakeKeepScreenOnWindow();
      const second = new FakeKeepScreenOnWindow();
      controller.setForeground(true);
      controller.setPreferenceEnabled(true);
      controller.setPlayerPageVisible(true);
      controller.bindWindow(first);
      controller.bindWindow(second);
      controller.unbindWindow(second);
      await controller.flush();

      expect(first.values[0]).assertTrue();
      expect(first.values[1]).assertFalse();
      expect(second.values[0]).assertTrue();
      expect(second.values[1]).assertFalse();
    });

    it('retries a transient native failure before considering the state applied', 0, async () => {
      const controller = new PlayerPageKeepScreenOnController();
      const target = new FailOnceKeepScreenOnWindow();
      controller.setForeground(true);
      controller.setPreferenceEnabled(true);
      controller.setPlayerPageVisible(true);
      controller.bindWindow(target);
      await controller.flush();

      expect(target.values.length).assertEqual(2);
      expect(target.values[0]).assertTrue();
      expect(target.values[1]).assertTrue();
    });

    it('serializes rapid effective-state changes in their requested order', 0, async () => {
      const controller = new PlayerPageKeepScreenOnController();
      const target = new FakeKeepScreenOnWindow();
      controller.bindWindow(target);
      controller.setForeground(true);
      controller.setPreferenceEnabled(true);
      controller.setPlayerPageVisible(true);
      controller.setPlayerPageVisible(false);
      controller.setPlayerPageVisible(true);
      await controller.flush();

      expect(target.values.length).assertEqual(4);
      expect(target.values[0]).assertFalse();
      expect(target.values[1]).assertTrue();
      expect(target.values[2]).assertFalse();
      expect(target.values[3]).assertTrue();
    });
  });
}
