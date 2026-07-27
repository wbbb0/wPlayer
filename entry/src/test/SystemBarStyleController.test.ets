import { FrameCallback, window } from '@kit.ArkUI';
import { describe, it, expect } from '@ohos/hypium';
import {
  SystemBarFrameHost,
  SystemBarStyleController,
  SystemBarWindow
} from '../main/ets/appearance/SystemBarStyleController';

class FakeSystemBarWindow extends SystemBarWindow {
  enableApplyCount: number = 0;
  propertyApplyCount: number = 0;
  lastProperties?: window.SystemBarProperties;
  private blockNextPropertyApply: boolean = false;
  private propertyApplyResolver?: () => void;

  async setSystemBarEnable(_names: Array<'status' | 'navigation'>): Promise<void> {
    this.enableApplyCount += 1;
  }

  async setSystemBarProperties(
    systemBarProperties: window.SystemBarProperties
  ): Promise<void> {
    this.propertyApplyCount += 1;
    this.lastProperties = systemBarProperties;
    if (this.blockNextPropertyApply) {
      this.blockNextPropertyApply = false;
      await new Promise<void>((resolve: () => void) => {
        this.propertyApplyResolver = resolve;
      });
      this.propertyApplyResolver = undefined;
    }
  }

  blockNextProperties(): void {
    this.blockNextPropertyApply = true;
  }

  releaseProperties(): void {
    this.propertyApplyResolver?.();
  }
}

class FakeSystemBarFrameHost extends SystemBarFrameHost {
  readonly callbacks: Array<FrameCallback> = [];

  constructor() {
    super();
  }

  postFrameCallback(callback: FrameCallback): void {
    this.callbacks.push(callback);
  }

  runIdle(index: number): void {
    this.callbacks[index].onIdle(0);
  }
}

async function flushSystemBarApply(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

export default function systemBarStyleControllerTest() {
  describe('System bar style controller', () => {
    it('reapplies the current style after the window returns to foreground', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      controller.bindWindow(targetWindow);
      await flushSystemBarApply();
      expect(targetWindow.propertyApplyCount).assertEqual(1);

      controller.reapplyCurrentStyle();
      await flushSystemBarApply();

      expect(targetWindow.enableApplyCount).assertEqual(2);
      expect(targetWindow.propertyApplyCount).assertEqual(2);
    });

    it('keeps the top overlay owner when foreground style is replayed', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      controller.bindWindow(targetWindow);
      await flushSystemBarApply();
      controller.submitContentColor('navigation', '#FF000000');
      await flushSystemBarApply();
      controller.submitContentColor('full_player', '#FFFFFFFF');
      await flushSystemBarApply();

      controller.reapplyCurrentStyle();
      await flushSystemBarApply();

      expect(targetWindow.lastProperties?.statusBarContentColor).assertEqual('#FFF5F5F5');
      expect(targetWindow.lastProperties?.navigationBarContentColor).assertEqual('#FFF5F5F5');
    });

    it('does not let an in-flight apply swallow a same-style replay', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      targetWindow.blockNextProperties();
      controller.bindWindow(targetWindow);
      await flushSystemBarApply();
      expect(targetWindow.propertyApplyCount).assertEqual(1);

      controller.reapplyCurrentStyle();
      targetWindow.releaseProperties();
      await flushSystemBarApply();

      expect(targetWindow.propertyApplyCount).assertEqual(2);
    });

    it('rewrites the latest style after an in-flight request becomes stale', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      controller.bindWindow(targetWindow);
      await flushSystemBarApply();
      targetWindow.blockNextProperties();

      controller.submitContentColor('full_player', '#FFFFFFFF');
      await flushSystemBarApply();
      expect(targetWindow.propertyApplyCount).assertEqual(2);
      controller.removeContentColor('full_player');
      targetWindow.releaseProperties();
      await flushSystemBarApply();

      expect(targetWindow.propertyApplyCount).assertEqual(3);
      expect(targetWindow.lastProperties?.statusBarContentColor).assertEqual('#FF202020');
    });

    it('coalesces frame replays and keeps a new generation pending', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      const frameHost = new FakeSystemBarFrameHost();
      controller.bindWindow(targetWindow);
      controller.setReplaySchedulingEnabled(true);
      await flushSystemBarApply();

      controller.scheduleReapplyAfterFrame(frameHost);
      controller.scheduleReapplyAfterFrame(frameHost);
      expect(frameHost.callbacks.length).assertEqual(1);

      controller.setReplaySchedulingEnabled(false);
      controller.setReplaySchedulingEnabled(true);
      controller.scheduleReapplyAfterFrame(frameHost);
      expect(frameHost.callbacks.length).assertEqual(2);
      frameHost.runIdle(0);
      controller.scheduleReapplyAfterFrame(frameHost);
      expect(frameHost.callbacks.length).assertEqual(2);

      frameHost.runIdle(1);
      await flushSystemBarApply();
      expect(targetWindow.propertyApplyCount).assertEqual(2);
    });

    it('replays across two layout frames without duplicating the first callback', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      const frameHost = new FakeSystemBarFrameHost();
      controller.bindWindow(targetWindow);
      controller.setReplaySchedulingEnabled(true);
      await flushSystemBarApply();

      controller.scheduleReapplyAfterFrame(frameHost);
      controller.scheduleReapplyAcrossLayoutFrames(frameHost);
      expect(frameHost.callbacks.length).assertEqual(1);
      frameHost.runIdle(0);
      await flushSystemBarApply();
      expect(frameHost.callbacks.length).assertEqual(2);
      frameHost.runIdle(1);
      await flushSystemBarApply();

      expect(targetWindow.propertyApplyCount).assertEqual(3);
    });

    it('invalidates a queued layout follow-up before a new generation', 0, () => {
      const controller = new SystemBarStyleController();
      const frameHost = new FakeSystemBarFrameHost();
      controller.setReplaySchedulingEnabled(true);
      controller.scheduleReapplyAcrossLayoutFrames(frameHost);
      expect(frameHost.callbacks.length).assertEqual(1);

      controller.setReplaySchedulingEnabled(false);
      controller.setReplaySchedulingEnabled(true);
      controller.scheduleReapplyAfterFrame(frameHost);
      frameHost.runIdle(0);
      expect(frameHost.callbacks.length).assertEqual(2);
      frameHost.runIdle(1);

      expect(frameHost.callbacks.length).assertEqual(2);
    });

    it('does not schedule while background replay is disabled', 0, () => {
      const controller = new SystemBarStyleController();
      const frameHost = new FakeSystemBarFrameHost();

      controller.scheduleReapplyAfterFrame(frameHost);

      expect(frameHost.callbacks.length).assertEqual(0);
    });

    it('replays the latest owner instead of reviving a removed player owner', 0, async () => {
      const controller = new SystemBarStyleController();
      const targetWindow = new FakeSystemBarWindow();
      const frameHost = new FakeSystemBarFrameHost();
      controller.bindWindow(targetWindow);
      controller.setReplaySchedulingEnabled(true);
      await flushSystemBarApply();
      controller.submitContentColor('full_player', '#FFFFFFFF');
      await flushSystemBarApply();

      controller.scheduleReapplyAfterFrame(frameHost);
      controller.removeContentColor('full_player');
      await flushSystemBarApply();
      frameHost.runIdle(0);
      await flushSystemBarApply();

      expect(targetWindow.lastProperties?.statusBarContentColor).assertEqual('#FF202020');
    });
  });
}
