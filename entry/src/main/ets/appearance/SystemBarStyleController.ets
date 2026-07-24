import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

export class SystemBarStyleController {
  private mainWindow?: window.Window;
  private appearanceContentColor: string = '#FF202020';
  private playerContentColor: string = '';
  private playerOverrideActive: boolean = false;
  private fullscreenOverlayActive: boolean = false;
  private fullscreenOverlayStatusBarVisible: boolean = true;
  private appliedPlayerOverrideActive: boolean = false;
  private appliedPlayerContentColor: string = '';
  private appliedStatusBarVisible: boolean | undefined = undefined;
  private requestEpoch: number = 0;
  private failedRequestEpoch: number = -1;
  private applying: boolean = false;

  bindWindow(mainWindow: window.Window): void {
    if (this.mainWindow === mainWindow) {
      return;
    }
    this.mainWindow = mainWindow;
    this.appliedPlayerOverrideActive = false;
    this.appliedPlayerContentColor = '';
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
    this.requestApply();
  }

  unbindWindow(mainWindow?: window.Window): void {
    if (mainWindow !== undefined && this.mainWindow !== mainWindow) {
      return;
    }
    this.mainWindow = undefined;
    this.appliedPlayerOverrideActive = false;
    this.appliedPlayerContentColor = '';
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
  }

  setAppearanceContentColor(contentColor: string): void {
    this.appearanceContentColor = contentColor;
  }

  setPlayerContentColor(active: boolean, contentColor: string): void {
    if (this.playerOverrideActive === active && this.playerContentColor === contentColor) {
      return;
    }
    this.playerOverrideActive = active;
    this.playerContentColor = contentColor;
    this.requestApply();
  }

  setFullscreenOverlayStyle(active: boolean, statusBarVisible: boolean): void {
    if (this.fullscreenOverlayActive === active &&
      this.fullscreenOverlayStatusBarVisible === statusBarVisible) {
      return;
    }
    this.fullscreenOverlayActive = active;
    this.fullscreenOverlayStatusBarVisible = statusBarVisible;
    this.requestApply();
  }

  private desiredStatusBarVisible(): boolean {
    return !this.fullscreenOverlayActive || this.fullscreenOverlayStatusBarVisible;
  }

  private requestApply(): void {
    this.requestEpoch += 1;
    const desiredStatusBarVisible = this.desiredStatusBarVisible();
    if (this.mainWindow === undefined || this.applying ||
      (this.appliedStatusBarVisible === desiredStatusBarVisible &&
        this.appliedPlayerOverrideActive === this.playerOverrideActive &&
        (!this.playerOverrideActive || this.appliedPlayerContentColor === this.playerContentColor))) {
      return;
    }
    this.applyLatest();
  }

  private async applyLatest(): Promise<void> {
    this.applying = true;
    while (this.mainWindow !== undefined) {
      const desiredStatusBarVisible = this.desiredStatusBarVisible();
      const desiredPlayerOverrideActive = this.playerOverrideActive;
      const desiredPlayerContentColor = this.playerContentColor;
      if (this.appliedStatusBarVisible === desiredStatusBarVisible &&
        this.appliedPlayerOverrideActive === desiredPlayerOverrideActive &&
        (!desiredPlayerOverrideActive || this.appliedPlayerContentColor === desiredPlayerContentColor)) {
        break;
      }
      const targetWindow = this.mainWindow;
      const targetEpoch = this.requestEpoch;
      try {
        await targetWindow.setWindowSystemBarEnable(
          desiredStatusBarVisible ? ['status', 'navigation'] : ['navigation']
        );
        if (desiredPlayerOverrideActive) {
          await targetWindow.setWindowSystemBarProperties({
            statusBarColor: '#00000000',
            navigationBarColor: '#00000000',
            statusBarContentColor: desiredPlayerContentColor,
            enableStatusBarAnimation: true,
            enableNavigationBarAnimation: true
          });
        } else if (this.appliedPlayerOverrideActive) {
          await targetWindow.setWindowSystemBarProperties({
            statusBarColor: '#00000000',
            navigationBarColor: '#00000000',
            statusBarContentColor: this.appearanceContentColor,
            enableStatusBarAnimation: true,
            enableNavigationBarAnimation: true
          });
        } else {
          await targetWindow.setWindowSystemBarProperties({
            statusBarColor: '#00000000',
            navigationBarColor: '#00000000',
            enableStatusBarAnimation: true,
            enableNavigationBarAnimation: true
          });
        }
        if (this.mainWindow === targetWindow) {
          this.appliedPlayerOverrideActive = desiredPlayerOverrideActive;
          this.appliedPlayerContentColor = desiredPlayerOverrideActive ? desiredPlayerContentColor : '';
          this.appliedStatusBarVisible = desiredStatusBarVisible;
          this.failedRequestEpoch = -1;
        }
      } catch (error) {
        if (this.mainWindow === targetWindow) {
          this.failedRequestEpoch = targetEpoch;
        }
        const businessError = error as BusinessError;
        console.warn(`Unable to update system-bar content: ${businessError.code}, ${businessError.message}`);
        break;
      }
    }
    this.applying = false;
    if (this.mainWindow !== undefined &&
      (this.appliedStatusBarVisible !== this.desiredStatusBarVisible() ||
        this.appliedPlayerOverrideActive !== this.playerOverrideActive ||
        (this.playerOverrideActive && this.appliedPlayerContentColor !== this.playerContentColor)) &&
      this.failedRequestEpoch !== this.requestEpoch) {
      this.applyLatest();
    }
  }
}

export const systemBarStyleController: SystemBarStyleController = new SystemBarStyleController();
