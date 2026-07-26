import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';
import {
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec
} from './PlayerMotion';

export class PlayerMorphGeometry {
  static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  static usesWideLayout(width: number): boolean {
    return width >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT;
  }

  static fullPlayerFrame(phase: PlayerMorphPhase, rootFrame: PlayerFrame,
    frozenRootFrame: PlayerFrame): PlayerFrame {
    const measuredFrame = phase === PlayerMorphPhase.OPEN ? rootFrame : frozenRootFrame;
    // Area.globalPosition is window-relative, while the overlay is already
    // hosted by the root component. Keep the measured size but normalize the
    // render frame to the overlay's local coordinate space.
    return {
      x: 0,
      y: 0,
      width: measuredFrame.width,
      height: measuredFrame.height
    };
  }

  static paneCount(frame: PlayerFrame): number {
    return FullPlayerPagerSpec.paneCount(frame.width, frame.height);
  }

  static pageSpan(frame: PlayerFrame): number {
    return FullPlayerPagerSpec.pageSpan(frame.width, PlayerMorphGeometry.paneCount(frame));
  }

  static morphValue(start: number, end: number, progress: number): number {
    const safeProgress = PlayerMorphGeometry.clamp(progress, 0, 1);
    return start + (end - start) * safeProgress;
  }

  static miniPlaybackButtonFrame(miniPlayerFrame: PlayerFrame): PlayerFrame {
    const size = PlayerLayoutSpec.MINI_PLAYBACK_BUTTON_SIZE;
    return {
      x: miniPlayerFrame.x + miniPlayerFrame.width - size - 8,
      y: miniPlayerFrame.y + (miniPlayerFrame.height - size) / 2,
      width: size,
      height: size
    };
  }

  static interpolateFrame(start: PlayerFrame, end: PlayerFrame, progress: number): PlayerFrame {
    return {
      x: PlayerMorphGeometry.morphValue(start.x, end.x, progress),
      y: PlayerMorphGeometry.morphValue(start.y, end.y, progress),
      width: PlayerMorphGeometry.morphValue(start.width, end.width, progress),
      height: PlayerMorphGeometry.morphValue(start.height, end.height, progress)
    };
  }

  static verticalTravelDistance(miniPlayerFrame: PlayerFrame, rootFrame: PlayerFrame): number {
    return Math.max(1, miniPlayerFrame.y - rootFrame.y);
  }

  static gestureCompletionProgress(miniPlayerFrame: PlayerFrame, rootFrame: PlayerFrame): number {
    return Math.min(
      PlayerMotionSpec.GESTURE_COMPLETION_FRACTION,
      PlayerMotionSpec.GESTURE_COMPLETION_MAX_DISTANCE /
        PlayerMorphGeometry.verticalTravelDistance(miniPlayerFrame, rootFrame)
    );
  }
}
