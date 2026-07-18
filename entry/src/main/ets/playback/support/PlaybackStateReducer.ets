import { PlaybackTransportState, PlayerState } from '../model/PlaybackModels';

/**
 * Projects AVPlayer's technical lifecycle onto a stable user-facing transport state.
 *
 * Source replacement emits idle/loading/ready even when two tracks are played
 * continuously. Those states remain observable through PlayerStore.state, but must
 * not temporarily turn a playing transport into a paused one.
 */
export class PlaybackStateReducer {
  private transportState: PlaybackTransportState = PlaybackTransportState.IDLE;
  private sourceChangeActive: boolean = false;

  current(): PlaybackTransportState {
    return this.transportState;
  }

  beginSourceChange(playWhenReady: boolean): PlaybackTransportState {
    const preservePlaying = playWhenReady &&
      this.transportState === PlaybackTransportState.PLAYING;
    this.sourceChangeActive = true;
    this.transportState = preservePlaying ? PlaybackTransportState.PLAYING :
      (playWhenReady ? PlaybackTransportState.PREPARING : PlaybackTransportState.PAUSED);
    return this.transportState;
  }

  updateIntent(playWhenReady: boolean): PlaybackTransportState {
    if (!playWhenReady) {
      this.transportState = PlaybackTransportState.PAUSED;
      return this.transportState;
    }
    if (this.transportState !== PlaybackTransportState.PLAYING) {
      this.transportState = PlaybackTransportState.PREPARING;
    }
    return this.transportState;
  }

  reduce(state: PlayerState, playWhenReady: boolean): PlaybackTransportState {
    if (state === PlayerState.PLAYING) {
      this.sourceChangeActive = false;
      this.transportState = playWhenReady ?
        PlaybackTransportState.PLAYING : PlaybackTransportState.PAUSED;
      return this.transportState;
    }
    if (state === PlayerState.PAUSED) {
      this.sourceChangeActive = false;
      this.transportState = PlaybackTransportState.PAUSED;
      return this.transportState;
    }
    if (state === PlayerState.ERROR) {
      this.sourceChangeActive = false;
      this.transportState = PlaybackTransportState.ERROR;
      return this.transportState;
    }
    if (state === PlayerState.COMPLETED) {
      this.sourceChangeActive = false;
      if (!playWhenReady || this.transportState !== PlaybackTransportState.PLAYING) {
        this.transportState = PlaybackTransportState.COMPLETED;
      }
      return this.transportState;
    }
    if (state === PlayerState.IDLE && !this.sourceChangeActive) {
      this.transportState = PlaybackTransportState.IDLE;
      return this.transportState;
    }
    if (state === PlayerState.LOADING || state === PlayerState.READY) {
      if (!playWhenReady) {
        this.transportState = PlaybackTransportState.PAUSED;
      } else if (this.transportState !== PlaybackTransportState.PLAYING) {
        this.transportState = PlaybackTransportState.PREPARING;
      }
    }
    return this.transportState;
  }

  settleCompletion(): PlaybackTransportState {
    this.sourceChangeActive = false;
    this.transportState = PlaybackTransportState.COMPLETED;
    return this.transportState;
  }

  reset(): PlaybackTransportState {
    this.sourceChangeActive = false;
    this.transportState = PlaybackTransportState.IDLE;
    return this.transportState;
  }
}
