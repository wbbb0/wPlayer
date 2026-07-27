import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { appRuntimeLifecycle } from '../application/runtime/AppRuntimeLifecycle';
import { AppAppearancePalette, appAppearanceController } from '../appearance/AppAppearance';
import {
  HarmonySystemBarFrameHost,
  HarmonySystemBarWindow,
  SystemBarWindow,
  systemBarStyleController
} from '../appearance/SystemBarStyleController';
import { playbackRuntime } from '../playback/PlaybackRuntime';

const DOMAIN = 0x0000;
const TAG = 'wPlayer/EntryAbility';

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  private systemBarWindow?: SystemBarWindow;
  private runtimeLease: number = 0;
  private foregroundActive: boolean = false;

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
    if (this.foregroundActive) {
      this.scheduleSystemBarReapply(true);
    }
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
        await this.applyMainWindowAppearance();
        this.systemBarWindow = new HarmonySystemBarWindow(this.mainWindow);
        systemBarStyleController.bindWindow(this.systemBarWindow);
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
      systemBarStyleController.setAutoContentColor(palette.systemBarContent);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to apply window appearance. Cause: %{public}s', JSON.stringify(error));
    }
  }

  private scheduleSystemBarReapply(acrossLayoutFrames: boolean = false): void {
    const targetWindow = this.mainWindow;
    if (targetWindow === undefined) {
      return;
    }
    try {
      const frameHost = new HarmonySystemBarFrameHost(targetWindow.getUIContext());
      if (acrossLayoutFrames) {
        systemBarStyleController.scheduleReapplyAcrossLayoutFrames(frameHost);
      } else {
        systemBarStyleController.scheduleReapplyAfterFrame(frameHost);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to schedule system-bar replay. Cause: %{public}s', JSON.stringify(error));
      systemBarStyleController.reapplyCurrentStyle();
    }
  }

  onWindowStageDestroy(): void {
    systemBarStyleController.unbindWindow(this.systemBarWindow);
    this.systemBarWindow = undefined;
    this.mainWindow = undefined;
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onForeground(): void {
    this.foregroundActive = true;
    systemBarStyleController.setReplaySchedulingEnabled(true);
    appAppearanceController.notifyChanged();
    this.applyMainWindowAppearance();
    this.scheduleSystemBarReapply();
    playbackRuntime.onForeground();
    hilog.info(DOMAIN, TAG, 'Ability entered foreground');
  }

  onBackground(): void {
    this.foregroundActive = false;
    systemBarStyleController.setReplaySchedulingEnabled(false);
    playbackRuntime.onBackground();
    hilog.info(DOMAIN, TAG, 'Ability entered background');
  }
}
