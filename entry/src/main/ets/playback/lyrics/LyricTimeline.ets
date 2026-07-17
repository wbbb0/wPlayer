import { TimedLyricLine } from './LyricsParser';

export class LyricTimeline {
  static activeIndexAt(lines: Array<TimedLyricLine>, positionMs: number): number {
    let lower = 0;
    let upper = lines.length;
    while (lower < upper) {
      const middle = lower + Math.floor((upper - lower) / 2);
      if (lines[middle].timeMs <= positionMs) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    return lower - 1;
  }
}
