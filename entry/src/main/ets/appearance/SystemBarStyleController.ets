import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const SOFT_BLACK = '#FF202020';
const SOFT_WHITE = '#FFF5F5F5';

class SystemBarColorEntry {
  readonly ownerId: string;
  contentColor: string | undefined;

  constructor(ownerId: string, contentColor: string | undefined) {
    this.ownerId = ownerId;
    this.contentColor = contentColor;
  }
}

export class SystemBarStyleController {
  private mainWindow?: window.Window;
  private readonly colorEntries: Array<SystemBarColorEntry> = [];
  private autoContentColor: string = SOFT_BLACK;
  private fullscreenOverlayActive: boolean = false;
  private fullscreenOverlayStatusBarVisible: boolean = true;
  private appliedContentColor: string | undefined = undefined;
  private appliedStatusBarVisible: boolean | undefined = undefined;
  private requestEpoch: number = 0;
  private failedRequestEpoch: number = -1;
  private applying: boolean = false;

  bindWindow(mainWindow: window.Window): void {
    if (this.mainWindow === mainWindow) {
      return;
    }
    this.mainWindow = mainWindow;
    this.appliedContentColor = undefined;
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
    this.requestApply();
  }

  unbindWindow(mainWindow?: window.Window): void {
    if (mainWindow !== undefined && this.mainWindow !== mainWindow) {
      return;
    }
    this.mainWindow = undefined;
    this.appliedContentColor = undefined;
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
  }

  setAutoContentColor(contentColor: string): void {
    if (this.autoContentColor === contentColor) {
      return;
    }
    this.autoContentColor = contentColor;
    this.requestApply();
  }

  submitContentColor(ownerId: string, contentColor: string | undefined): void {
    const index = this.colorEntryIndex(ownerId);
    if (index >= 0) {
      if (this.colorEntries[index].contentColor === contentColor) {
        return;
      }
      this.colorEntries[index].contentColor = contentColor;
    } else {
      this.colorEntries.push(new SystemBarColorEntry(ownerId, contentColor));
    }
    this.requestApply();
  }

  removeContentColor(ownerId: string): void {
    const index = this.colorEntryIndex(ownerId);
    if (index < 0) {
      return;
    }
    this.colorEntries.splice(index, 1);
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

  private colorEntryIndex(ownerId: string): number {
    for (let index = 0; index < this.colorEntries.length; index += 1) {
      if (this.colorEntries[index].ownerId === ownerId) {
        return index;
      }
    }
    return -1;
  }

  private topColorEntry(): SystemBarColorEntry | undefined {
    if (this.colorEntries.length === 0) {
      return undefined;
    }
    return this.colorEntries[this.colorEntries.length - 1];
  }

  private desiredContentColor(): string {
    return this.softenedContentColor(this.topColorEntry()?.contentColor ?? this.autoContentColor);
  }

  private softenedContentColor(contentColor: string): string {
    const normalizedColor = contentColor.toUpperCase();
    if (normalizedColor === '#FF000000' || normalizedColor === '#000000') {
      return SOFT_BLACK;
    }
    if (normalizedColor === '#FFFFFFFF' || normalizedColor === '#FFFFFF') {
      return SOFT_WHITE;
    }
    return contentColor;
  }

  private desiredStatusBarVisible(): boolean {
    return !this.fullscreenOverlayActive || this.fullscreenOverlayStatusBarVisible;
  }

  private requestApply(): void {
    this.requestEpoch += 1;
    const desiredContentColor = this.desiredContentColor();
    const desiredStatusBarVisible = this.desiredStatusBarVisible();
    if (this.mainWindow === undefined || this.applying ||
      (this.appliedContentColor === desiredContentColor &&
        this.appliedStatusBarVisible === desiredStatusBarVisible)) {
      return;
    }
    this.applyLatest();
  }

  private async applyLatest(): Promise<void> {
    this.applying = true;
    while (this.mainWindow !== undefined) {
      const desiredContentColor = this.desiredContentColor();
      const desiredStatusBarVisible = this.desiredStatusBarVisible();
      if (this.appliedContentColor === desiredContentColor &&
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
          statusBarContentColor: desiredContentColor,
          navigationBarColor: '#00000000',
          navigationBarContentColor: desiredContentColor,
          enableStatusBarAnimation: true,
          enableNavigationBarAnimation: true
        });
        if (this.mainWindow === targetWindow) {
          this.appliedContentColor = desiredContentColor;
          this.appliedStatusBarVisible = desiredStatusBarVisible;
          this.failedRequestEpoch = -1;
        }
      } catch (error) {
        if (this.mainWindow === targetWindow) {
          this.failedRequestEpoch = targetEpoch;
        }
        const businessError = error as BusinessError;
        console.warn(`Unable to update system-bar style: ${businessError.code}, ${businessError.message}`);
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
