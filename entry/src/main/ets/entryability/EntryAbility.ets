import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { appRuntimeLifecycle } from '../application/runtime/AppRuntimeLifecycle';
import { AppAppearancePalette, appAppearanceController } from '../appearance/AppAppearance';
import { playbackRuntime } from '../playback/PlaybackRuntime';

const DOMAIN = 0x0000;
const TAG = 'wPlayer/EntryAbility';
export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  private runtimeLease: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    const activation = appRuntimeLifecycle.activate(() => {
      return playbackRuntime.initialize(this.context);
    });
    this.runtimeLease = activation.lease;
    activation.completion.catch((error: Object) => {
      hilog.error(DOMAIN, TAG, 'Failed to initialize playback runtime. Cause: %{public}s', JSON.stringify(error));
    });
    hilog.info(DOMAIN, TAG, 'Ability created');
  }

  onDestroy(): void {
    const lease = this.runtimeLease;
    this.runtimeLease = 0;
    appRuntimeLifecycle.deactivate(lease, () => playbackRuntime.shutdown()).catch((error: Object) => {
      hilog.warn(DOMAIN, TAG, 'Failed to shut down playback runtime. Cause: %{public}s', JSON.stringify(error));
    });
    hilog.info(DOMAIN, TAG, 'Ability destroyed');
  }

  onConfigurationUpdate(_newConfig: Configuration): void {
    appAppearanceController.notifyChanged();
    this.applyMainWindowAppearance();
    hilog.info(DOMAIN, TAG, 'Application appearance refreshed');
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
        this.mainWindow = windowStage.getMainWindowSync();
        await this.mainWindow.setWindowLayoutFullScreen(true);
        await this.mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
        await this.applyMainWindowAppearance();
      } catch (windowError) {
        const businessError = windowError as BusinessError;
        hilog.error(DOMAIN, TAG, 'Failed to configure main window. Cause: %{public}s', JSON.stringify(businessError));
      }
      hilog.info(DOMAIN, TAG, 'Main content loaded');
    });
  }

  private async applyMainWindowAppearance(): Promise<void> {
    if (this.mainWindow === undefined) {
      return;
    }
    try {
      const palette = AppAppearancePalette.resolve(this.context);
      this.mainWindow.setWindowBackgroundColor(palette.windowBackground);
      await this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: palette.systemBarContent,
        navigationBarContentColor: palette.systemBarContent
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to apply window appearance. Cause: %{public}s', JSON.stringify(error));
    }
  }

  onWindowStageDestroy(): void {
    this.mainWindow = undefined;
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onForeground(): void {
    appAppearanceController.notifyChanged();
    this.applyMainWindowAppearance();
    hilog.info(DOMAIN, TAG, 'Ability entered foreground');
  }

  onBackground(): void {
    playbackRuntime.onBackground();
    hilog.info(DOMAIN, TAG, 'Ability entered background');
  }
}
