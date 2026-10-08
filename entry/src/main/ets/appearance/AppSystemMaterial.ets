import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

export class AppSystemMaterial {
  private static dialogMaterial: uiMaterial.Material | undefined = undefined;

  static dialog(): uiMaterial.Material | undefined {
    // apiAvailable itself is absent on the minimum supported API 23 runtime.
    if (deviceInfo.sdkApiVersion >= 24 && deviceInfo.apiAvailable('26.0.0')) {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        if (AppSystemMaterial.dialogMaterial === undefined) {
          // The system owns the performance level and the user's light-sense setting.
          AppSystemMaterial.dialogMaterial = new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THICK
          });
        }
        return AppSystemMaterial.dialogMaterial;
      }
    }
    return undefined;
  }

  static sheetContentBackground(fallback: string): string {
    return AppSystemMaterial.dialog() === undefined ? fallback : '#00000000';
  }
}
