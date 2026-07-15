import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

export type AvoidAreaChangeHandler =
  (type: window.AvoidAreaType, area: window.AvoidArea) => void;

/**
 * Owns the window avoid-area subscription and invalidates stale async starts.
 */
export class WindowAvoidAreaController {
  private mainWindow?: window.Window;
  private active: boolean = false;
  private epoch: number = 0;
  private readonly handler: AvoidAreaChangeHandler;
  private readonly changeCallback = (options: window.AvoidAreaOptions): void => {
    if (this.active) {
      this.handler(options.type, options.area);
    }
  };

  constructor(handler: AvoidAreaChangeHandler) {
    this.handler = handler;
  }

  start(context: common.Context): void {
    this.active = true;
    const startEpoch = ++this.epoch;
    this.attach(context, startEpoch);
  }

  stop(): void {
    this.active = false;
    ++this.epoch;
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('avoidAreaChange', this.changeCallback);
      this.mainWindow = undefined;
    }
  }

  private async attach(context: common.Context, startEpoch: number): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(context);
      if (!this.active || startEpoch !== this.epoch) {
        return;
      }
      if (this.mainWindow !== undefined) {
        this.mainWindow.off('avoidAreaChange', this.changeCallback);
      }
      this.mainWindow = mainWindow;
      this.handler(
        window.AvoidAreaType.TYPE_SYSTEM,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      );
      this.handler(
        window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      );
      mainWindow.on('avoidAreaChange', this.changeCallback);
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to observe window avoid areas: ${businessError.code}, ${businessError.message}`);
    }
  }
}
