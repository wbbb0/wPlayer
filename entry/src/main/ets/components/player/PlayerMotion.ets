export interface PlayerFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PlayerPoint {
  x: number;
  y: number;
}

export enum PlayerGestureAxis {
  UNDECIDED,
  HORIZONTAL,
  VERTICAL
}

export enum PlayerMorphPhase {
  IDLE,
  DRAGGING,
  OPENING,
  OPEN,
  CLOSING,
  BACKGROUND_HANDOFF
}

export class PlayerMotionSpec {
  static readonly GESTURE_COMPLETION_FRACTION: number = 0.28;
  static readonly GESTURE_COMPLETION_MAX_DISTANCE: number = 120;
  static readonly OPEN_DURATION: number = 420;
  static readonly CLOSE_DURATION: number = 340;
  static readonly CANCEL_DURATION: number = 280;
  static readonly CLOSE_CANCEL_DURATION: number = 240;
  static readonly BACKGROUND_HANDOFF_DURATION: number = 140;
  static readonly OPEN_SPRING_RESPONSE: number = 0.48;
  static readonly OPEN_SPRING_DAMPING: number = 0.88;
  static readonly CLOSE_CURVE_X1: number = 0.2;
  static readonly CLOSE_CURVE_Y1: number = 0;
  static readonly CLOSE_CURVE_X2: number = 0.1;
  static readonly CLOSE_CURVE_Y2: number = 1;
  static readonly GESTURE_AXIS_LOCK_DISTANCE: number = 4;
  static readonly HORIZONTAL_SWIPE_RESISTANCE: number = 120;
  static readonly HORIZONTAL_HAPTIC_THRESHOLD: number = 48;
  static readonly FULL_CONTENT_COLLAPSE_FADE_START: number = 0.2;
  static readonly FULL_CONTENT_COLLAPSE_FADE_END: number = 0.8;
  static readonly MINI_CONTENT_FADE_START: number = 0.08;
  static readonly MINI_CONTENT_FADE_RATE: number = 4.2;
  static readonly MINI_CONTENT_VISIBLE_LIMIT: number = 0.32;
  static readonly FULL_ARTWORK_SHADOW_RADIUS: number = 38;
  static readonly FULL_ARTWORK_SHADOW_OFFSET_Y: number = 20;

  static fullContentOpacity(expandProgress: number): number {
    const normalizedExpandProgress = Math.max(0, Math.min(1, expandProgress));
    const collapseProgress = 1 - normalizedExpandProgress;
    const fadeProgress = (collapseProgress - PlayerMotionSpec.FULL_CONTENT_COLLAPSE_FADE_START) /
      (PlayerMotionSpec.FULL_CONTENT_COLLAPSE_FADE_END -
        PlayerMotionSpec.FULL_CONTENT_COLLAPSE_FADE_START);
    return 1 - Math.max(0, Math.min(1, fadeProgress));
  }
}

export class PlayerLayoutSpec {
  static readonly DEFAULT_MINI_PLAYER_SIZE: number = 56;
  static readonly DEFAULT_ARTWORK_TARGET_X: number = 127;
  static readonly DEFAULT_ARTWORK_TARGET_Y: number = 180;
  static readonly MINI_ARTWORK_SIZE: number = 48;
  static readonly MINI_ARTWORK_RADIUS: number = 24;
  static readonly FULL_ARTWORK_SIZE: number = 286;
  static readonly FULL_ARTWORK_RADIUS: number = 10;
  static readonly MINI_ARTWORK_INSET: number = 4;
  static readonly FULL_PLAYER_HORIZONTAL_INSET: number = 28;
  static readonly FULL_PLAYER_NON_ARTWORK_HEIGHT: number = 256;

  static fullArtworkSize(rootWidth: number, rootHeight: number,
    topInset: number, bottomInset: number): number {
    if (rootWidth <= 0 || rootHeight <= 0) {
      return PlayerLayoutSpec.FULL_ARTWORK_SIZE;
    }
    const widthLimit = rootWidth - PlayerLayoutSpec.FULL_PLAYER_HORIZONTAL_INSET * 2;
    const heightLimit = rootHeight - topInset - bottomInset -
      PlayerLayoutSpec.FULL_PLAYER_NON_ARTWORK_HEIGHT;
    return Math.max(1, Math.min(widthLimit, heightLimit));
  }
}
