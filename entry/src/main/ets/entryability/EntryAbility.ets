import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'wPlayer/EntryAbility';
const SYSTEM_BAR_PROPERTIES: window.SystemBarProperties = {
  statusBarColor: '#00000000',
  navigationBarColor: '#00000000',
  statusBarContentColor: '#FF242633',
  navigationBarContentColor: '#FF242633'
};

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Ability created');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability destroyed');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Window stage created');
    this.loadMainContent(windowStage);
  }

  private loadMainContent(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', async (error: BusinessError) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(error));
        return;
      }
      try {
        const mainWindow: window.Window = windowStage.getMainWindowSync();
        await mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowBackgroundColor('#FFF4F4FA');
        await mainWindow.setWindowSystemBarProperties(SYSTEM_BAR_PROPERTIES);
      } catch (windowError) {
        const businessError = windowError as BusinessError;
        hilog.error(DOMAIN, TAG, 'Failed to configure main window. Cause: %{public}s', JSON.stringify(businessError));
      }
      hilog.info(DOMAIN, TAG, 'Main content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability entered foreground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability entered background');
  }
}
