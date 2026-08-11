import { QueueEntry, RepeatMode } from '../../playback/model/PlaybackModels';
import { PlayerMorphGesturePolicy } from './PlayerMorphGesturePolicy';
import { PlayerMotionSpec } from './PlayerMotion';

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
    if (currentIndex < 0 || currentIndex >= entries.length) {
      return {};
    }
    const previous = currentIndex > 0 ? entries[currentIndex - 1] : undefined;
    let next = currentIndex + 1 < entries.length ? entries[currentIndex + 1] : undefined;
    if (next === undefined && repeatMode === RepeatMode.ALL && entries.length > 1) {
      next = entries[0];
    }
    return {
      previous: previous,
      current: entries[currentIndex],
      next: next
    };
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
