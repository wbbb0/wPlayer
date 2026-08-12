import { QueueEntry, RepeatMode } from '../../playback/model/PlaybackModels';

export interface PlayerTrackWindow {
  previous?: QueueEntry;
  current?: QueueEntry;
  next?: QueueEntry;
}

export class PlayerTrackPagerPolicy {
  static window(entries: Array<QueueEntry>, currentIndex: number,
    repeatMode: RepeatMode): PlayerTrackWindow {
    if (currentIndex < 0 || currentIndex >= entries.length) {
      return {};
    }
    const previous = currentIndex > 0 ? entries[currentIndex - 1] : undefined;
    let next = currentIndex + 1 < entries.length ? entries[currentIndex + 1] : undefined;
    if (next === undefined && repeatMode === RepeatMode.ALL && entries.length > 1) {
      next = entries[0];
    }
    return { previous: previous, current: entries[currentIndex], next: next };
  }
}
