import {
  FullPlayerPagerSpec,
  MiniPlayerGestureRegion,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMotionSpec
} from './PlayerMotion';

export enum MiniBarResizeAction {
  NONE = 0,
  EXPAND = 1,
  COLLAPSE = 2
}

export class PlayerMorphGesturePolicy {
  static miniPlayerRegion(localX: number, measuredWidth: number,
    miniBarExpanded: boolean): MiniPlayerGestureRegion {
    const miniPlayerWidth = Math.max(
      measuredWidth,
      PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
    );
    if (localX <= PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE) {
      return MiniPlayerGestureRegion.ARTWORK;
    }
    const playbackButtonStart = miniPlayerWidth -
      PlayerLayoutSpec.MINI_PLAYBACK_BUTTON_SIZE - 8;
    if (miniBarExpanded && localX >= playbackButtonStart) {
      return MiniPlayerGestureRegion.PLAYBACK_BUTTON;
    }
    return MiniPlayerGestureRegion.OTHER;
  }

  static resolveAxis(currentAxis: PlayerGestureAxis, offsetX: number,
    offsetY: number): PlayerGestureAxis {
    if (currentAxis !== PlayerGestureAxis.UNDECIDED) {
      return currentAxis;
    }
    const horizontalDistance = Math.abs(offsetX);
    const verticalDistance = Math.abs(offsetY);
    if (Math.max(horizontalDistance, verticalDistance) <=
      PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE) {
      return PlayerGestureAxis.UNDECIDED;
    }
    return horizontalDistance > verticalDistance ?
      PlayerGestureAxis.HORIZONTAL : PlayerGestureAxis.VERTICAL;
  }

  static resistedHorizontalOffset(horizontalOffset: number): number {
    const renderDistance = Math.abs(horizontalOffset);
    return horizontalOffset /
      (1 + renderDistance / PlayerMotionSpec.HORIZONTAL_SWIPE_RESISTANCE);
  }

  static miniBarResizeAction(region: MiniPlayerGestureRegion, miniBarExpanded: boolean,
    horizontalOffset: number): MiniBarResizeAction {
    if (!miniBarExpanded &&
      region === MiniPlayerGestureRegion.ARTWORK &&
      horizontalOffset <= -PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD) {
      return MiniBarResizeAction.EXPAND;
    }
    if (miniBarExpanded &&
      (region === MiniPlayerGestureRegion.ARTWORK ||
        region === MiniPlayerGestureRegion.PLAYBACK_BUTTON) &&
      horizontalOffset >= PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD) {
      return MiniBarResizeAction.COLLAPSE;
    }
    return MiniBarResizeAction.NONE;
  }

  static fullPlayerTargetPosition(startPosition: number, currentPosition: number,
    pageSpan: number, paneCount: number): number {
    const safePageSpan = Math.max(1, pageSpan);
    const movement = currentPosition - startPosition;
    let targetPosition = Math.round(startPosition);
    if (Math.abs(movement) * safePageSpan >=
      FullPlayerPagerSpec.swipeCompletionDistance()) {
      targetPosition += movement > 0 ? 1 : -1;
    }
    return FullPlayerPagerSpec.clampPosition(targetPosition, paneCount);
  }

  static morphTargetProgress(startProgress: number, currentProgress: number,
    fallbackTarget: number, travelDistance: number): number {
    const movement = (currentProgress - startProgress) * Math.max(1, travelDistance);
    if (Math.abs(movement) < PlayerMotionSpec.MORPH_GESTURE_COMPLETION_DISTANCE) {
      return fallbackTarget <= 0 ? 0 : 1;
    }
    return movement > 0 ? 1 : 0;
  }
}
