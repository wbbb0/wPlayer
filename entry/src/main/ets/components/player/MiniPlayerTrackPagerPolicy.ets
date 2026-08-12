import { QueueEntry, RepeatMode } from '../../playback/model/PlaybackModels';
import { PlayerMorphGesturePolicy } from './PlayerMorphGesturePolicy';
import { PlayerMotionSpec } from './PlayerMotion';
import { PlayerTrackPagerPolicy } from './PlayerTrackPagerPolicy';

export enum MiniPlayerTrackPageTarget {
  CURRENT,
  PREVIOUS,
  NEXT
}

export interface MiniPlayerTrackWindow {
  previous?: QueueEntry;
  current?: QueueEntry;
  next?: QueueEntry;
}

export class MiniPlayerTrackPagerPolicy {
  static readonly SWIPE_COMPLETION_DISTANCE: number =
    PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
  static readonly SETTLE_DURATION: number = 280;
  static readonly SETTLE_SPRING_RESPONSE: number = 0.36;
  static readonly SETTLE_SPRING_DAMPING: number = 0.88;

  static window(entries: Array<QueueEntry>, currentIndex: number,
    repeatMode: RepeatMode): MiniPlayerTrackWindow {
    return PlayerTrackPagerPolicy.window(entries, currentIndex, repeatMode);
  }

  static dragOffset(candidateOffset: number, pageWidth: number,
    hasPrevious: boolean, hasNext: boolean): number {
    const width = Math.max(1, pageWidth);
    const minimum = hasNext ? -width : 0;
    const maximum = hasPrevious ? width : 0;
    if (candidateOffset < minimum) {
      return minimum + PlayerMorphGesturePolicy.resistedHorizontalOffset(candidateOffset - minimum);
    }
    if (candidateOffset > maximum) {
      return maximum + PlayerMorphGesturePolicy.resistedHorizontalOffset(candidateOffset - maximum);
    }
    return candidateOffset;
  }

  static target(offset: number, hasPrevious: boolean,
    hasNext: boolean): MiniPlayerTrackPageTarget {
    if (hasNext && offset <= -MiniPlayerTrackPagerPolicy.SWIPE_COMPLETION_DISTANCE) {
      return MiniPlayerTrackPageTarget.NEXT;
    }
    if (hasPrevious && offset >= MiniPlayerTrackPagerPolicy.SWIPE_COMPLETION_DISTANCE) {
      return MiniPlayerTrackPageTarget.PREVIOUS;
    }
    return MiniPlayerTrackPageTarget.CURRENT;
  }

  static targetOffset(target: MiniPlayerTrackPageTarget, pageWidth: number): number {
    const width = Math.max(1, pageWidth);
    if (target === MiniPlayerTrackPageTarget.PREVIOUS) {
      return width;
    }
    if (target === MiniPlayerTrackPageTarget.NEXT) {
      return -width;
    }
    return 0;
  }

  static commitEntry(window: MiniPlayerTrackWindow, target: MiniPlayerTrackPageTarget,
    activeEntryId: number): QueueEntry | undefined {
    if (window.current === undefined || window.current.queueEntryId !== activeEntryId) {
      return undefined;
    }
    if (target === MiniPlayerTrackPageTarget.PREVIOUS) {
      return window.previous;
    }
    if (target === MiniPlayerTrackPageTarget.NEXT) {
      return window.next;
    }
    return undefined;
  }
}
