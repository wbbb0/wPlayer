import { FrameCallback, window } from '@kit.ArkUI';
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

export abstract class SystemBarFrameHost {
  abstract postFrameCallback(callback: FrameCallback): void;
}

export class HarmonySystemBarFrameHost extends SystemBarFrameHost {
  private readonly uiContext: UIContext;

  constructor(uiContext: UIContext) {
    super();
    this.uiContext = uiContext;
  }

  postFrameCallback(callback: FrameCallback): void {
    this.uiContext.postFrameCallback(callback);
  }
}

class SystemBarReplayFrameCallback extends FrameCallback {
  private readonly onIdleFrame: () => void;

  constructor(onIdleFrame: () => void) {
    super();
    this.onIdleFrame = onIdleFrame;
  }

  onFrame(_frameTimeInNano: number): void {
  }

  onIdle(_timeLeftInNano: number): void {
    this.onIdleFrame();
  }
}

export abstract class SystemBarWindow {
  abstract setSystemBarEnable(names: Array<'status' | 'navigation'>): Promise<void>;
  abstract setSystemBarProperties(systemBarProperties: window.SystemBarProperties): Promise<void>;
}

export class HarmonySystemBarWindow extends SystemBarWindow {
  private readonly targetWindow: window.Window;

  constructor(targetWindow: window.Window) {
    super();
    this.targetWindow = targetWindow;
  }

  setSystemBarEnable(names: Array<'status' | 'navigation'>): Promise<void> {
    try {
      return this.targetWindow.setWindowSystemBarEnable(names);
    } catch (error) {
      const businessError = error as BusinessError;
      return Promise.reject(new Error(
        `Unable to enable system bars: ${businessError.code}, ${businessError.message}`
      ));
    }
  }

  setSystemBarProperties(systemBarProperties: window.SystemBarProperties): Promise<void> {
    try {
      return this.targetWindow.setWindowSystemBarProperties(systemBarProperties);
    } catch (error) {
      const businessError = error as BusinessError;
      return Promise.reject(new Error(
        `Unable to set system-bar properties: ${businessError.code}, ${businessError.message}`
      ));
    }
  }
}

export class SystemBarStyleController {
  private mainWindow?: SystemBarWindow;
  private readonly colorEntries: Array<SystemBarColorEntry> = [];
  private autoContentColor: string = SOFT_BLACK;
  private fullscreenOverlayActive: boolean = false;
  private fullscreenOverlayStatusBarVisible: boolean = true;
  private appliedContentColor: string | undefined = undefined;
  private appliedStatusBarVisible: boolean | undefined = undefined;
  private requestEpoch: number = 0;
  private failedRequestEpoch: number = -1;
  private applying: boolean = false;
  private replaySchedulingEnabled: boolean = false;
  private replayGeneration: number = 0;
  private replayPending: boolean = false;
  private replayFollowUpFrameHost?: SystemBarFrameHost;

  bindWindow(mainWindow: SystemBarWindow): void {
    if (this.mainWindow === mainWindow) {
      return;
    }
    this.invalidateScheduledReapply();
    this.mainWindow = mainWindow;
    this.appliedContentColor = undefined;
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
    this.requestApply();
  }

  unbindWindow(mainWindow?: SystemBarWindow): void {
    if (mainWindow !== undefined && this.mainWindow !== mainWindow) {
      return;
    }
    this.invalidateScheduledReapply();
    this.mainWindow = undefined;
    this.appliedContentColor = undefined;
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
  }

  reapplyCurrentStyle(): void {
    this.appliedContentColor = undefined;
    this.appliedStatusBarVisible = undefined;
    this.failedRequestEpoch = -1;
    this.requestApply();
  }

  setReplaySchedulingEnabled(enabled: boolean): void {
    if (this.replaySchedulingEnabled === enabled) {
      return;
    }
    this.replaySchedulingEnabled = enabled;
    if (!enabled) {
      this.invalidateScheduledReapply();
    }
  }

  scheduleReapplyAfterFrame(frameHost: SystemBarFrameHost): void {
    this.scheduleFrameReplay(frameHost, false);
  }

  scheduleReapplyAcrossLayoutFrames(frameHost: SystemBarFrameHost): void {
    this.scheduleFrameReplay(frameHost, true);
  }

  private scheduleFrameReplay(frameHost: SystemBarFrameHost, followUp: boolean): void {
    if (!this.replaySchedulingEnabled) {
      return;
    }
    if (followUp) {
      this.replayFollowUpFrameHost = frameHost;
    }
    if (this.replayPending) {
      return;
    }
    this.replayPending = true;
    const generation = this.replayGeneration;
    try {
      frameHost.postFrameCallback(new SystemBarReplayFrameCallback((): void => {
        if (this.replayGeneration !== generation) {
          return;
        }
        this.replayPending = false;
        const followUpFrameHost = this.replayFollowUpFrameHost;
        this.replayFollowUpFrameHost = undefined;
        this.reapplyCurrentStyle();
        if (followUpFrameHost !== undefined) {
          this.scheduleReapplyAfterFrame(followUpFrameHost);
        }
      }));
    } catch (error) {
      if (this.replayGeneration !== generation) {
        return;
      }
      this.replayPending = false;
      this.replayFollowUpFrameHost = undefined;
      console.warn(`Unable to schedule system-bar replay: ${JSON.stringify(error)}`);
      this.reapplyCurrentStyle();
    }
  }

  private invalidateScheduledReapply(): void {
    this.replayGeneration += 1;
    this.replayPending = false;
    this.replayFollowUpFrameHost = undefined;
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
        await targetWindow.setSystemBarEnable(
          desiredStatusBarVisible ? ['status', 'navigation'] : ['navigation']
        );
        await targetWindow.setSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: desiredContentColor,
          navigationBarColor: '#00000000',
          navigationBarContentColor: desiredContentColor,
          enableStatusBarAnimation: true,
          enableNavigationBarAnimation: true
        });
        if (this.mainWindow === targetWindow) {
          if (this.requestEpoch === targetEpoch) {
            this.appliedContentColor = desiredContentColor;
            this.appliedStatusBarVisible = desiredStatusBarVisible;
            this.failedRequestEpoch = -1;
          } else {
            this.appliedContentColor = undefined;
            this.appliedStatusBarVisible = undefined;
          }
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
