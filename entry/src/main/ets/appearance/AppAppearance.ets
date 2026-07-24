import { common, ConfigurationConstant } from '@kit.AbilityKit';

export type AppAppearanceListener = (epoch: number) => void;

export class AppAppearancePalette {
  readonly systemBarContent: string;
  readonly windowBackground: string;

  constructor(systemBarContent: string, windowBackground: string) {
    this.systemBarContent = systemBarContent;
    this.windowBackground = windowBackground;
  }

  static resolve(context: common.UIAbilityContext): AppAppearancePalette {
    const darkMode = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return new AppAppearancePalette(
      AppAppearancePalette.resolveColor(context, 'system_bar_content', darkMode ? '#FFF5F5F5' : '#FF202020'),
      AppAppearancePalette.resolveColor(
        context,
        'wplayer_start_window_background',
        darkMode ? '#FF000000' : '#FFFFFFFF'
      )
    );
  }

  static fallback(): AppAppearancePalette {
    return new AppAppearancePalette('#FF202020', '#FFFFFFFF');
  }

  private static resolveColor(context: common.UIAbilityContext, name: string, fallback: string): string {
    try {
      const color = context.resourceManager.getColorByNameSync(name);
      return `#${(color >>> 0).toString(16).padStart(8, '0').toUpperCase()}`;
    } catch (_error) {
      return fallback;
    }
  }
}

export class AppAppearanceController {
  private epoch: number = 0;
  private readonly listeners: Array<AppAppearanceListener> = [];

  addListener(listener: AppAppearanceListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  removeListener(listener: AppAppearanceListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  notifyChanged(): void {
    this.epoch += 1;
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index += 1) {
      listeners[index](this.epoch);
    }
  }
}

export const appAppearanceController: AppAppearanceController = new AppAppearanceController();
