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
  static readonly DRAG_DISTANCE: number = 280;
  static readonly EXPAND_THRESHOLD: number = 0.28;
  static readonly OPEN_DURATION: number = 420;
  static readonly CLOSE_DURATION: number = 340;
  static readonly CANCEL_DURATION: number = 280;
  static readonly BACKGROUND_HANDOFF_DURATION: number = 140;
  static readonly GESTURE_AXIS_LOCK_DISTANCE: number = 4;
  static readonly HORIZONTAL_SWIPE_RESISTANCE: number = 120;
  static readonly HORIZONTAL_HAPTIC_THRESHOLD: number = 48;
  static readonly FULL_CONTENT_FADE_START: number = 0.06;
  static readonly FULL_CONTENT_FADE_RATE: number = 3.2;
  static readonly MINI_CONTENT_FADE_START: number = 0.08;
  static readonly MINI_CONTENT_FADE_RATE: number = 4.2;
  static readonly MINI_CONTENT_VISIBLE_LIMIT: number = 0.32;
}

export class PlayerLayoutSpec {
  static readonly DEFAULT_MINI_PLAYER_SIZE: number = 56;
  static readonly DEFAULT_ARTWORK_TARGET_X: number = 127;
  static readonly DEFAULT_ARTWORK_TARGET_Y: number = 180;
  static readonly MINI_ARTWORK_SIZE: number = 48;
  static readonly MINI_ARTWORK_RADIUS: number = 24;
  static readonly FULL_ARTWORK_SIZE: number = 286;
  static readonly FULL_ARTWORK_RADIUS: number = 18;
  static readonly MINI_ARTWORK_INSET: number = 4;
}
