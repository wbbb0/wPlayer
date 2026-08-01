import { window } from '@kit.ArkUI';

export interface KeepScreenOnWindow {
  setWindowKeepScreenOn(value: boolean): Promise<void>;
}

export class HarmonyKeepScreenOnWindow implements KeepScreenOnWindow {
  private readonly target: window.Window;

  constructor(target: window.Window) {
    this.target = target;
  }

  setWindowKeepScreenOn(value: boolean): Promise<void> {
    try {
      return this.target.setWindowKeepScreenOn(value);
    } catch (error) {
      return Promise.reject(error as Error);
    }
  }
}

export class PlayerPageKeepScreenOnController {
  private boundWindow?: KeepScreenOnWindow;
  private foreground: boolean = false;
  private preferenceEnabled: boolean = false;
  private playerPageVisible: boolean = false;
  private appliedWindow?: KeepScreenOnWindow;
  private appliedValue: boolean = false;
  private requestedWindow?: KeepScreenOnWindow;
  private requestedValue: boolean = false;
  private requestSequence: number = 0;
  private writeTail: Promise<void> = Promise.resolve();

  bindWindow(target: KeepScreenOnWindow): void {
    if (this.boundWindow === target) {
      return;
    }
    const previous = this.boundWindow;
    this.boundWindow = target;
    if (previous !== undefined) {
      this.enqueue(previous, false);
    }
    this.synchronize();
  }

  unbindWindow(target?: KeepScreenOnWindow): void {
    if (target !== undefined && this.boundWindow !== target) {
      return;
    }
    const previous = this.boundWindow;
    this.boundWindow = undefined;
    if (previous !== undefined) {
      this.enqueue(previous, false);
    }
  }

  setForeground(value: boolean): void {
    if (this.foreground === value) {
      return;
    }
    this.foreground = value;
    this.synchronize();
  }

  setPreferenceEnabled(value: boolean): void {
    if (this.preferenceEnabled === value) {
      return;
    }
    this.preferenceEnabled = value;
    this.synchronize();
  }

  setPlayerPageVisible(value: boolean): void {
    if (this.playerPageVisible === value) {
      return;
    }
    this.playerPageVisible = value;
    this.synchronize();
  }

  flush(): Promise<void> {
    return this.writeTail;
  }

  private synchronize(): void {
    const target = this.boundWindow;
    if (target === undefined) {
      return;
    }
    const effective = this.foreground && this.preferenceEnabled && this.playerPageVisible;
    if (this.requestedWindow === target && this.requestedValue === effective) {
      return;
    }
    if (this.appliedWindow === target && this.appliedValue === effective) {
      return;
    }
    this.enqueue(target, effective);
  }

  private enqueue(target: KeepScreenOnWindow, value: boolean): void {
    this.requestedWindow = target;
    this.requestedValue = value;
    this.requestSequence += 1;
    const sequence = this.requestSequence;
    this.writeTail = this.writeTail.then(async (): Promise<void> => {
      let finalError: Error | undefined;
      for (let attempt = 0; attempt < 2; attempt += 1) {
        try {
          await target.setWindowKeepScreenOn(value);
          this.appliedWindow = target;
          this.appliedValue = value;
          finalError = undefined;
          break;
        } catch (error) {
          finalError = error instanceof Error ? error : new Error(`${error}`);
        }
      }
      if (sequence === this.requestSequence) {
        this.requestedWindow = undefined;
      }
      if (finalError !== undefined) {
        console.warn(`Unable to update player-page keep-screen-on state: ${finalError.message}`);
      }
    });
  }
}

export const playerPageKeepScreenOnController: PlayerPageKeepScreenOnController =
  new PlayerPageKeepScreenOnController();
