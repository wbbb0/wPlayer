export const PERIODIC_PROGRESS_PERSIST_INTERVAL_MS: number = 30000;

export class PlaybackPowerPolicy {
  static shouldPersistProgress(isPlaying: boolean, nowMs: number, lastWriteAtMs: number): boolean {
    return isPlaying &&
      lastWriteAtMs > 0 &&
      nowMs >= lastWriteAtMs &&
      nowMs - lastWriteAtMs >= PERIODIC_PROGRESS_PERSIST_INTERVAL_MS;
  }

  static resumeStateChanged(trackId: number, positionMs: number,
    previousTrackId: number, previousPositionMs: number): boolean {
    return trackId !== previousTrackId || positionMs !== previousPositionMs;
  }
}
