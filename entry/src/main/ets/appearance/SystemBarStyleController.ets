import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

export class SystemBarStyleController {
  private mainWindow?: window.Window;
  private appearanceContentColor: string = '#FF202020';
  private playerContentColor: string = '';
  private playerOverrideActive: boolean = false;
  private fullscreenOverlayContentColor: string = '';
  private fullscreenOverlayActive: boolean = false;
  private fullscreenOverlayStatusBarVisible: boolean = true;
  private appliedContentColor: string = '';
  private appliedStatusBarVisible: boolean | undefined = undefined;
  private requestEpoch: number = 0;
  private failedRequestEpoch: number = -1;
  private applying: boolean = false;

  bindWindow(mainWindow: window.Window): void {
    if (this.mainWindow === mainWindow) {
      return;
    }
    this.mainWindow = mainWindow;
    this.appliedContentColor = '';
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
    this.requestApply();
  }

  unbindWindow(mainWindow?: window.Window): void {
    if (mainWindow !== undefined && this.mainWindow !== mainWindow) {
      return;
    }
    this.mainWindow = undefined;
    this.appliedContentColor = '';
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
  }

  setAppearanceContentColor(contentColor: string): void {
    if (this.appearanceContentColor === contentColor) {
      return;
    }
    this.appearanceContentColor = contentColor;
    this.requestApply();
  }

  setPlayerContentColor(active: boolean, contentColor: string): void {
    if (this.playerOverrideActive === active && this.playerContentColor === contentColor) {
      return;
    }
    this.playerOverrideActive = active;
    this.playerContentColor = contentColor;
    this.requestApply();
  }

  setFullscreenOverlayStyle(active: boolean, contentColor: string, statusBarVisible: boolean): void {
    if (this.fullscreenOverlayActive === active &&
      this.fullscreenOverlayContentColor === contentColor &&
      this.fullscreenOverlayStatusBarVisible === statusBarVisible) {
      return;
    }
    this.fullscreenOverlayActive = active;
    this.fullscreenOverlayContentColor = contentColor;
    this.fullscreenOverlayStatusBarVisible = statusBarVisible;
    this.requestApply();
  }

  private desiredContentColor(): string {
    if (this.fullscreenOverlayActive && this.fullscreenOverlayContentColor.length > 0) {
      return this.fullscreenOverlayContentColor;
    }
    if (this.playerOverrideActive && this.playerContentColor.length > 0) {
      return this.playerContentColor;
    }
    return this.appearanceContentColor;
  }

  private desiredStatusBarVisible(): boolean {
    return !this.fullscreenOverlayActive || this.fullscreenOverlayStatusBarVisible;
  }

  private requestApply(): void {
    this.requestEpoch += 1;
    const desiredColor = this.desiredContentColor();
    const desiredStatusBarVisible = this.desiredStatusBarVisible();
    if (this.mainWindow === undefined || this.applying ||
      (this.appliedContentColor === desiredColor &&
        this.appliedStatusBarVisible === desiredStatusBarVisible)) {
      return;
    }
    this.applyLatest();
  }

  private async applyLatest(): Promise<void> {
    this.applying = true;
    while (this.mainWindow !== undefined) {
      const desiredColor = this.desiredContentColor();
      const desiredStatusBarVisible = this.desiredStatusBarVisible();
      if (this.appliedContentColor === desiredColor &&
        this.appliedStatusBarVisible === desiredStatusBarVisible) {
        break;
      }
      const targetWindow = this.mainWindow;
      const targetEpoch = this.requestEpoch;
      try {
        await targetWindow.setWindowSystemBarEnable(
          desiredStatusBarVisible ? ['status', 'navigation'] : ['navigation']
        );
        await targetWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: desiredColor,
          navigationBarContentColor: desiredColor,
          enableStatusBarAnimation: true,
          enableNavigationBarAnimation: true
        });
        if (this.mainWindow === targetWindow) {
          this.appliedContentColor = desiredColor;
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
      (this.appliedContentColor !== this.desiredContentColor() ||
        this.appliedStatusBarVisible !== this.desiredStatusBarVisible()) &&
      this.failedRequestEpoch !== this.requestEpoch) {
      this.applyLatest();
    }
  }
}

export const systemBarStyleController: SystemBarStyleController = new SystemBarStyleController();
