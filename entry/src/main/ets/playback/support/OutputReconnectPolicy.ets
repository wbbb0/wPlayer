import { PlayerState } from '../model/PlaybackModels';

export class OutputReconnectPolicy {
  private resumeAfterOutputReconnect: boolean = false;

  recordOutputUnavailable(hasCurrentTrack: boolean, playWhenReady: boolean, state: PlayerState): boolean {
    if (!hasCurrentTrack || (!playWhenReady && state !== PlayerState.PLAYING)) {
      this.resumeAfterOutputReconnect = false;
      return false;
    }
    this.resumeAfterOutputReconnect = true;
    return true;
  }

  clear(): void {
    this.resumeAfterOutputReconnect = false;
  }

  shouldResume(hasCurrentTrack: boolean, state: PlayerState): boolean {
    if (!this.resumeAfterOutputReconnect) {
      return false;
    }
    this.resumeAfterOutputReconnect = false;
    return hasCurrentTrack && OutputReconnectPolicy.isRecoverableState(state);
  }

  hasPendingResume(): boolean {
    return this.resumeAfterOutputReconnect;
  }

  private static isRecoverableState(state: PlayerState): boolean {
    return state === PlayerState.PAUSED ||
      state === PlayerState.READY ||
      state === PlayerState.COMPLETED;
  }
}
