import { PlayerState } from '../model/PlaybackModels';
import { OutputReconnectPolicy } from '../support/OutputReconnectPolicy';

const OUTPUT_RECONNECT_RESUME_WINDOW_MS = 5 * 60 * 1000;

export enum AudioRecoveryAction {
  NONE,
  PAUSE,
  RESUME
}

export class PlaybackAudioRecoveryCoordinator {
  private readonly outputReconnectPolicy: OutputReconnectPolicy = new OutputReconnectPolicy();
  private resumeAfterAudioFocusRelease: boolean = false;

  outputUnavailable(hasCurrentTrack: boolean, playWhenReady: boolean, state: PlayerState,
    autoResumeEnabled: boolean): AudioRecoveryAction {
    return this.outputReconnectPolicy.recordOutputUnavailable(
      hasCurrentTrack,
      playWhenReady,
      state,
      autoResumeEnabled
    ) ? AudioRecoveryAction.PAUSE : AudioRecoveryAction.NONE;
  }

  outputAvailable(hasCurrentTrack: boolean, state: PlayerState,
    autoResumeEnabled: boolean): AudioRecoveryAction {
    if (!autoResumeEnabled) {
      this.outputReconnectPolicy.clear();
      return AudioRecoveryAction.NONE;
    }
    const shouldResume = this.outputReconnectPolicy.shouldResume(
      hasCurrentTrack,
      state,
      OUTPUT_RECONNECT_RESUME_WINDOW_MS
    );
    if (shouldResume) {
      this.resumeAfterAudioFocusRelease = false;
      return AudioRecoveryAction.RESUME;
    }
    return AudioRecoveryAction.NONE;
  }

  audioPauseHint(hasCurrentTrack: boolean, playWhenReady: boolean): AudioRecoveryAction {
    if (!hasCurrentTrack || !playWhenReady) {
      this.resumeAfterAudioFocusRelease = false;
      return AudioRecoveryAction.NONE;
    }
    this.resumeAfterAudioFocusRelease = true;
    return AudioRecoveryAction.PAUSE;
  }

  audioResumeHint(hasCurrentTrack: boolean, state: PlayerState): AudioRecoveryAction {
    if (!this.resumeAfterAudioFocusRelease) {
      return AudioRecoveryAction.NONE;
    }
    this.resumeAfterAudioFocusRelease = false;
    if (!hasCurrentTrack || !PlaybackAudioRecoveryCoordinator.isRecoverableState(state)) {
      return AudioRecoveryAction.NONE;
    }
    // Consuming both pending intents prevents an output reconnect and focus release
    // from issuing two play commands for the same interruption.
    this.outputReconnectPolicy.clear();
    return AudioRecoveryAction.RESUME;
  }

  audioStopHint(hasCurrentTrack: boolean, state: PlayerState): AudioRecoveryAction {
    this.clear();
    if (!hasCurrentTrack) {
      return AudioRecoveryAction.NONE;
    }
    return state === PlayerState.PLAYING ? AudioRecoveryAction.PAUSE : AudioRecoveryAction.NONE;
  }

  clear(): void {
    this.outputReconnectPolicy.clear();
    this.resumeAfterAudioFocusRelease = false;
  }

  private static isRecoverableState(state: PlayerState): boolean {
    return state === PlayerState.PAUSED ||
      state === PlayerState.READY ||
      state === PlayerState.COMPLETED ||
      state === PlayerState.LOADING;
  }
}
