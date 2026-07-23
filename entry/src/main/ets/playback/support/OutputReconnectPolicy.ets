import { PlayerState } from '../model/PlaybackModels';

const DEFAULT_RESUME_WINDOW_MS = 5 * 60 * 1000;

export class OutputReconnectPolicy {
  private resumeAfterOutputReconnect: boolean = false;
  private unavailableAtMs: number = 0;

  recordOutputUnavailable(hasCurrentTrack: boolean, playWhenReady: boolean, state: PlayerState,
    autoResumeEnabled: boolean = true, nowMs: number = Date.now()): boolean {
    if (!autoResumeEnabled || !hasCurrentTrack || (!playWhenReady && state !== PlayerState.PLAYING)) {
      this.resumeAfterOutputReconnect = false;
      this.unavailableAtMs = 0;
      return false;
    }
    this.resumeAfterOutputReconnect = true;
    this.unavailableAtMs = nowMs;
    return true;
  }

  clear(): void {
    this.resumeAfterOutputReconnect = false;
    this.unavailableAtMs = 0;
  }

  shouldResume(hasCurrentTrack: boolean, state: PlayerState,
    maxResumeWindowMs: number = DEFAULT_RESUME_WINDOW_MS, nowMs: number = Date.now()): boolean {
    if (!this.resumeAfterOutputReconnect) {
      return false;
    }
    this.resumeAfterOutputReconnect = false;
    const unavailableAtMs = this.unavailableAtMs;
    this.unavailableAtMs = 0;
    if (maxResumeWindowMs >= 0 && (unavailableAtMs <= 0 || nowMs - unavailableAtMs > maxResumeWindowMs)) {
      return false;
    }
    return hasCurrentTrack && OutputReconnectPolicy.isRecoverableState(state);
  }

  hasPendingResume(): boolean {
    return this.resumeAfterOutputReconnect;
  }

  private static isRecoverableState(state: PlayerState): boolean {
    return state === PlayerState.PAUSED ||
      state === PlayerState.READY ||
      state === PlayerState.COMPLETED ||
      state === PlayerState.LOADING;
  }
}
