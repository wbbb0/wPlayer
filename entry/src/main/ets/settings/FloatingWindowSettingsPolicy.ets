export enum FloatingWindowOpenBehavior {
  DO_NOTHING = 0,
  MINIMIZE_APP = 1,
  CLOSE_PLAYER_PAGE = 2
}

export enum FloatingWindowAutoCloseBehavior {
  NEVER = 0,
  APP_FOREGROUND = 1,
  PLAYER_PAGE_OPENED = 2
}

const OPEN_BEHAVIOR_LABELS: Array<string> = [
  '什么也不做',
  '最小化应用',
  '关闭播放页面'
];

const AUTO_CLOSE_BEHAVIOR_LABELS: Array<string> = [
  '不自动关闭',
  '应用在前台时',
  '打开播放页面时'
];

export class FloatingWindowSettingsPolicy {
  static readonly OPEN_BEHAVIOR_DEFAULT: FloatingWindowOpenBehavior =
    FloatingWindowOpenBehavior.MINIMIZE_APP;
  static readonly AUTO_START_ON_MINIMIZE_DEFAULT: boolean = false;
  static readonly AUTO_CLOSE_BEHAVIOR_DEFAULT: FloatingWindowAutoCloseBehavior =
    FloatingWindowAutoCloseBehavior.APP_FOREGROUND;

  static normalizeOpenBehavior(value: number): FloatingWindowOpenBehavior {
    if (value === FloatingWindowOpenBehavior.DO_NOTHING ||
      value === FloatingWindowOpenBehavior.CLOSE_PLAYER_PAGE) {
      return value;
    }
    return FloatingWindowOpenBehavior.MINIMIZE_APP;
  }

  static openBehaviorLabel(value: number): string {
    return OPEN_BEHAVIOR_LABELS[FloatingWindowSettingsPolicy.normalizeOpenBehavior(value)];
  }

  static openBehaviorFromLegacy(autoMinimizeApp: boolean): FloatingWindowOpenBehavior {
    return autoMinimizeApp ?
      FloatingWindowOpenBehavior.MINIMIZE_APP : FloatingWindowOpenBehavior.DO_NOTHING;
  }

  static normalizeAutoCloseBehavior(value: number): FloatingWindowAutoCloseBehavior {
    if (value === FloatingWindowAutoCloseBehavior.NEVER ||
      value === FloatingWindowAutoCloseBehavior.PLAYER_PAGE_OPENED) {
      return value;
    }
    return FloatingWindowAutoCloseBehavior.APP_FOREGROUND;
  }

  static autoCloseBehaviorLabel(value: number): string {
    return AUTO_CLOSE_BEHAVIOR_LABELS[
      FloatingWindowSettingsPolicy.normalizeAutoCloseBehavior(value)
    ];
  }

  static shouldMinimizeAfterOpen(value: number): boolean {
    return FloatingWindowSettingsPolicy.normalizeOpenBehavior(value) ===
      FloatingWindowOpenBehavior.MINIMIZE_APP;
  }

  static shouldClosePlayerPageAfterOpen(value: number): boolean {
    return FloatingWindowSettingsPolicy.normalizeOpenBehavior(value) ===
      FloatingWindowOpenBehavior.CLOSE_PLAYER_PAGE;
  }

  static shouldCloseOnForeground(value: number): boolean {
    return FloatingWindowSettingsPolicy.normalizeAutoCloseBehavior(value) ===
      FloatingWindowAutoCloseBehavior.APP_FOREGROUND;
  }

  static shouldCloseOnPlayerPageOpened(value: number): boolean {
    return FloatingWindowSettingsPolicy.normalizeAutoCloseBehavior(value) ===
      FloatingWindowAutoCloseBehavior.PLAYER_PAGE_OPENED;
  }

  static shouldEnableAutoStart(preferenceEnabled: boolean,
    hasCurrentTrack: boolean, playing: boolean): boolean {
    return preferenceEnabled && hasCurrentTrack && playing;
  }
}
