import { window } from '@kit.ArkUI';
import { describe, it, expect } from '@ohos/hypium';
import {
  SystemBarStyleController,
  SystemBarWindow
} from '../main/ets/appearance/SystemBarStyleController';

class FakeSystemBarWindow extends SystemBarWindow {
  enableApplyCount: number = 0;
  propertyApplyCount: number = 0;
  lastProperties?: window.SystemBarProperties;

  async setSystemBarEnable(_names: Array<'status' | 'navigation'>): Promise<void> {
    this.enableApplyCount += 1;
  }

  async setSystemBarProperties(
    systemBarProperties: window.SystemBarProperties
  ): Promise<void> {
    this.propertyApplyCount += 1;
    this.lastProperties = systemBarProperties;
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
  });
}
