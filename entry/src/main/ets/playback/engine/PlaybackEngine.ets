import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { AvailabilityState } from '../../library/model/LibraryModels';
import { PlaybackTrack, PlayerState } from '../model/PlaybackModels';
import { RequestEpoch } from '../support/RequestEpoch';

const STATE_WAIT_TIMEOUT_MS = 10000;
const SEEK_WAIT_TIMEOUT_MS = 8000;
const PLAYBACK_REQUEST_SUPERSEDED: Error = new Error('Playback request superseded');

export interface PlaybackEngineListener {
  onStateChanged(state: PlayerState, message?: string): void;
  onPositionChanged(positionMs: number): void;
  onDurationChanged(durationMs: number): void;
  onCompleted(): void;
  onOutputDeviceUnavailable(): void;
  onOutputDeviceAvailable(): void;
  onAudioSessionPauseHint(): void;
  onAudioSessionResumeHint(): void;
  onAudioSessionStopHint(): void;
}

interface PendingStateWait {
  expected: string;
  resolve: () => void;
  reject: (error: Error) => void;
  timerId: number;
}

interface PendingSeekWait {
  resolve: () => void;
  reject: (error: Error) => void;
  timerId: number;
}

export class PlaybackFileError extends Error {
  readonly availability: AvailabilityState;

  constructor(message: string, availability: AvailabilityState) {
    super(message);
    this.availability = availability;
  }
}

export class PlaybackEngine {
  private player?: media.AVPlayer;
  private sourceFile?: fs.File;
  private audioSessionManager?: audio.AudioSessionManager;
  private outputDeviceChangedCallback?: (event: audio.CurrentOutputDeviceChangedEvent) => void;
  private audioSessionStateChangedCallback?: (event: audio.AudioSessionStateChangedEvent) => void;
  private rawState: string = 'idle';
  private listener?: PlaybackEngineListener;
  private commandTail: Promise<void> = Promise.resolve();
  private readonly requestEpoch: RequestEpoch = new RequestEpoch();
  private activeEpoch: number = 0;
  private pendingStateWait?: PendingStateWait;
  private pendingSeekWait?: PendingSeekWait;
  private shuttingDown: boolean = false;

  setListener(listener: PlaybackEngineListener): void {
    this.listener = listener;
  }

  playTrack(track: PlaybackTrack, resumePositionMs: number, playWhenReady: () => boolean): Promise<void> {
    const epoch = this.requestEpoch.begin();
    this.listener?.onStateChanged(PlayerState.LOADING);
    return this.enqueue(async () => {
      this.activeEpoch = epoch;
      await this.loadTrack(track, resumePositionMs, epoch, playWhenReady);
    });
  }

  invalidateAndStop(): Promise<void> {
    this.requestEpoch.invalidate();
    this.rejectPendingWaits(PLAYBACK_REQUEST_SUPERSEDED);
    return this.enqueue(async () => {
      if (this.player !== undefined && this.rawState !== 'idle' && this.rawState !== 'released') {
        await this.resetForSource(this.player);
      }
    });
  }

  togglePlayback(): Promise<void> {
    const epoch = this.activeEpoch;
    return this.enqueue(async () => {
      if (this.player === undefined) {
        return;
      }
      if (this.rawState === 'playing') {
        await this.player.pause();
        this.publishConfirmedState(epoch, PlayerState.PAUSED);
      } else if (this.rawState === 'prepared' || this.rawState === 'paused' || this.rawState === 'completed') {
        await this.ensureAudioSession();
        this.ensureCurrent(epoch);
        await this.player.play();
        this.ensureCurrent(epoch);
        this.publishConfirmedState(epoch, PlayerState.PLAYING);
      }
    });
  }

  play(): Promise<void> {
    const epoch = this.activeEpoch;
    return this.enqueue(async () => {
      if (this.player === undefined ||
        (this.rawState !== 'prepared' && this.rawState !== 'paused' && this.rawState !== 'completed')) {
        throw new Error(`Playback source is not ready: ${this.rawState}`);
      }
      await this.ensureAudioSession();
      this.ensureCurrent(epoch);
      await this.player.play();
      this.ensureCurrent(epoch);
      this.publishConfirmedState(epoch, PlayerState.PLAYING);
    });
  }

  pause(): Promise<void> {
    const epoch = this.activeEpoch;
    return this.enqueue(async () => {
      if (this.player !== undefined && this.rawState === 'playing') {
        await this.player.pause();
        this.publishConfirmedState(epoch, PlayerState.PAUSED);
      }
    });
  }

  seek(positionMs: number): Promise<void> {
    return this.enqueue(async () => {
      if (this.player === undefined || !PlaybackEngine.canSeek(this.rawState)) {
        return;
      }
      await this.seekInternal(Math.max(0, positionMs));
    });
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    this.requestEpoch.invalidate();
    this.rejectPendingWaits(new Error('Playback engine shut down'));
    this.unsubscribeOutputDeviceChanges();
    await this.commandTail;
    if (this.player !== undefined && this.rawState !== 'released') {
      try {
        await this.player.release();
      } catch (error) {
        console.warn(`Unable to release AVPlayer: ${PlaybackEngine.messageOf(error)}`);
      }
    }
    this.player = undefined;
    this.rawState = 'released';
    this.closeSourceFile();
    await this.deactivateAudioSession();
    this.audioSessionManager = undefined;
    this.outputDeviceChangedCallback = undefined;
    this.audioSessionStateChangedCallback = undefined;
    this.shuttingDown = false;
  }

  private async loadTrack(track: PlaybackTrack, resumePositionMs: number, epoch: number,
    playWhenReady: () => boolean): Promise<void> {
    if (track.availability !== AvailabilityState.AVAILABLE) {
      throw new Error('音乐文件当前不可用，请重新授权或重新导入');
    }
    let sourcePreparationActive = false;
    try {
      const player = await this.ensurePlayer();
      this.ensureCurrent(epoch);
      await this.resetForSource(player);
      this.ensureCurrent(epoch);

      let sourceFile: fs.File;
      try {
        sourceFile = fs.openSync(track.uri, fs.OpenMode.READ_ONLY);
      } catch (error) {
        const cause = new PlaybackFileError(
          `无法打开音乐文件：${PlaybackEngine.messageOf(error)}`,
          AvailabilityState.UNAVAILABLE
        );
        this.listener?.onStateChanged(PlayerState.ERROR, cause.message);
        throw cause;
      }
      this.sourceFile = sourceFile;
      sourcePreparationActive = true;
      const initialized = this.waitForState('initialized');
      player.fdSrc = { fd: sourceFile.fd, offset: 0, length: track.fileSize };
      await initialized;
      this.ensureCurrent(epoch);
      player.audioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      await player.prepare();
      sourcePreparationActive = false;
      this.ensureCurrent(epoch);
      if (resumePositionMs > 0) {
        await this.seekInternal(resumePositionMs);
        this.ensureCurrent(epoch);
      }
      if (playWhenReady()) {
        await this.ensureAudioSession();
        this.ensureCurrent(epoch);
        if (!playWhenReady()) {
          return;
        }
        await player.play();
        this.ensureCurrent(epoch);
        if (!playWhenReady()) {
          await player.pause();
          this.publishConfirmedState(epoch, PlayerState.PAUSED);
          return;
        }
        this.publishConfirmedState(epoch, PlayerState.PLAYING);
      }
    } catch (error) {
      if (error === PLAYBACK_REQUEST_SUPERSEDED) {
        throw PLAYBACK_REQUEST_SUPERSEDED;
      }
      if (error instanceof PlaybackFileError) {
        throw error;
      }
      if (sourcePreparationActive) {
        throw new PlaybackFileError(
          `无法解析音乐文件：${PlaybackEngine.messageOf(error)}`,
          AvailabilityState.CORRUPTED
        );
      }
      throw new Error(`Unable to load playback source: ${PlaybackEngine.messageOf(error)}`);
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player !== undefined && this.rawState !== 'released') {
      return this.player;
    }
    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (error) {
      throw new Error(`Unable to create AVPlayer: ${PlaybackEngine.messageOf(error)}`);
    }
    player.on('stateChange', (state: string) => {
      this.rawState = state;
      if (this.pendingStateWait !== undefined && this.pendingStateWait.expected === state) {
        const pending = this.pendingStateWait;
        this.pendingStateWait = undefined;
        clearTimeout(pending.timerId);
        pending.resolve();
      }
      if (!this.requestEpoch.isCurrent(this.activeEpoch)) {
        return;
      }
      const applicationState = PlaybackEngine.applicationStateOf(state);
      if (applicationState !== undefined) {
        this.listener?.onStateChanged(applicationState);
      }
      if (state === 'completed') {
        this.listener?.onCompleted();
      }
    });
    player.on('error', (error: BusinessError) => {
      const cause = new Error(`${error.code}: ${error.message}`);
      if (this.pendingStateWait !== undefined) {
        const pending = this.pendingStateWait;
        this.pendingStateWait = undefined;
        clearTimeout(pending.timerId);
        pending.reject(cause);
      }
      if (this.pendingSeekWait !== undefined) {
        const pending = this.pendingSeekWait;
        this.pendingSeekWait = undefined;
        clearTimeout(pending.timerId);
        pending.reject(cause);
      }
      if (this.requestEpoch.isCurrent(this.activeEpoch)) {
        this.listener?.onStateChanged(PlayerState.ERROR, cause.message);
      }
    });
    player.on('timeUpdate', (time: number) => {
      if (this.requestEpoch.isCurrent(this.activeEpoch)) {
        this.listener?.onPositionChanged(time);
      }
    });
    player.on('durationUpdate', (duration: number) => {
      if (this.requestEpoch.isCurrent(this.activeEpoch)) {
        this.listener?.onDurationChanged(duration);
      }
    });
    player.on('seekDone', () => {
      if (this.pendingSeekWait !== undefined) {
        const pending = this.pendingSeekWait;
        this.pendingSeekWait = undefined;
        clearTimeout(pending.timerId);
        pending.resolve();
      }
    });
    this.player = player;
    this.rawState = player.state;
    return player;
  }

  private async resetForSource(player: media.AVPlayer): Promise<void> {
    if (this.rawState !== 'idle') {
      try {
        await player.reset();
        this.rawState = player.state;
      } catch (error) {
        throw new Error(`Unable to reset AVPlayer: ${PlaybackEngine.messageOf(error)}`);
      }
    }
    this.closeSourceFile();
  }

  private seekInternal(positionMs: number): Promise<void> {
    if (this.player === undefined || !PlaybackEngine.canSeek(this.rawState)) {
      return Promise.resolve();
    }
    const pending = new Promise<void>((resolve, reject) => {
      const timerId = setTimeout(() => {
        if (this.pendingSeekWait !== undefined && this.pendingSeekWait.timerId === timerId) {
          this.pendingSeekWait = undefined;
          reject(new Error('Playback seek timed out'));
        }
      }, SEEK_WAIT_TIMEOUT_MS);
      this.pendingSeekWait = { resolve: resolve, reject: reject, timerId: timerId };
    });
    this.player.seek(positionMs, media.SeekMode.SEEK_CLOSEST);
    return pending;
  }

  private waitForState(expected: string): Promise<void> {
    if (this.rawState === expected) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve, reject) => {
      const timerId = setTimeout(() => {
        if (this.pendingStateWait !== undefined && this.pendingStateWait.timerId === timerId) {
          this.pendingStateWait = undefined;
          reject(new Error(`Playback state ${expected} timed out`));
        }
      }, STATE_WAIT_TIMEOUT_MS);
      this.pendingStateWait = { expected: expected, resolve: resolve, reject: reject, timerId: timerId };
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const pending = this.commandTail.then(operation);
    this.commandTail = pending.catch((error: Object) => {
      if (error !== PLAYBACK_REQUEST_SUPERSEDED) {
        this.listener?.onStateChanged(PlayerState.ERROR, PlaybackEngine.messageOf(error));
      }
    });
    return pending;
  }

  private async ensureAudioSession(): Promise<void> {
    if (this.shuttingDown) {
      return;
    }
    try {
      if (this.audioSessionManager === undefined) {
        this.audioSessionManager = audio.getAudioManager().getSessionManager();
      }
      if (this.outputDeviceChangedCallback === undefined) {
        const callback = (event: audio.CurrentOutputDeviceChangedEvent): void => {
          if (event.changeReason ===
            audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
            this.listener?.onOutputDeviceUnavailable();
            return;
          }
          if (event.changeReason ===
            audio.AudioStreamDeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE) {
            this.listener?.onOutputDeviceAvailable();
          }
        };
        this.audioSessionManager.on('currentOutputDeviceChanged', callback);
        this.outputDeviceChangedCallback = callback;
      }
      if (this.audioSessionStateChangedCallback === undefined) {
        const callback = (event: audio.AudioSessionStateChangedEvent): void => {
          if (event.stateChangeHint ===
            audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME) {
            this.listener?.onAudioSessionResumeHint();
            return;
          }
          if (event.stateChangeHint ===
            audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE) {
            this.listener?.onAudioSessionPauseHint();
            return;
          }
          if (event.stateChangeHint ===
            audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP ||
            event.stateChangeHint ===
              audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP) {
            this.listener?.onAudioSessionStopHint();
          }
        };
        this.audioSessionManager.on('audioSessionStateChanged', callback);
        this.audioSessionStateChangedCallback = callback;
      }
      if (!this.audioSessionManager.isAudioSessionActivated()) {
        await this.audioSessionManager.activateAudioSession({
          concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
        });
      }
    } catch (error) {
      console.warn(`Unable to activate audio session: ${PlaybackEngine.messageOf(error)}`);
    }
  }

  private unsubscribeOutputDeviceChanges(): void {
    if (this.audioSessionManager === undefined) {
      return;
    }
    if (this.outputDeviceChangedCallback !== undefined) {
      try {
        this.audioSessionManager.off('currentOutputDeviceChanged', this.outputDeviceChangedCallback);
      } catch (error) {
        console.warn(`Unable to stop audio output monitoring: ${PlaybackEngine.messageOf(error)}`);
      }
      this.outputDeviceChangedCallback = undefined;
    }
    if (this.audioSessionStateChangedCallback !== undefined) {
      try {
        this.audioSessionManager.off('audioSessionStateChanged', this.audioSessionStateChangedCallback);
      } catch (error) {
        console.warn(`Unable to stop audio session monitoring: ${PlaybackEngine.messageOf(error)}`);
      }
      this.audioSessionStateChangedCallback = undefined;
    }
  }

  private async deactivateAudioSession(): Promise<void> {
    if (this.audioSessionManager === undefined) {
      return;
    }
    try {
      if (this.audioSessionManager.isAudioSessionActivated()) {
        await this.audioSessionManager.deactivateAudioSession();
      }
    } catch (error) {
      console.warn(`Unable to deactivate audio session: ${PlaybackEngine.messageOf(error)}`);
    }
  }

  private ensureCurrent(epoch: number): void {
    if (!this.requestEpoch.isCurrent(epoch)) {
      throw PLAYBACK_REQUEST_SUPERSEDED;
    }
  }

  private publishConfirmedState(epoch: number, state: PlayerState): void {
    if (this.requestEpoch.isCurrent(epoch) && epoch === this.activeEpoch) {
      this.listener?.onStateChanged(state);
    }
  }

  private rejectPendingWaits(error: Error): void {
    if (this.pendingStateWait !== undefined) {
      const pending = this.pendingStateWait;
      this.pendingStateWait = undefined;
      clearTimeout(pending.timerId);
      pending.reject(error);
    }
    if (this.pendingSeekWait !== undefined) {
      const pending = this.pendingSeekWait;
      this.pendingSeekWait = undefined;
      clearTimeout(pending.timerId);
      pending.reject(error);
    }
  }

  private closeSourceFile(): void {
    if (this.sourceFile !== undefined) {
      try {
        fs.closeSync(this.sourceFile);
      } catch (error) {
        console.warn(`Unable to close playback file: ${PlaybackEngine.messageOf(error)}`);
      }
      this.sourceFile = undefined;
    }
  }

  private static canSeek(state: string): boolean {
    return state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed';
  }

  private static applicationStateOf(state: string): PlayerState | undefined {
    if (state === 'idle' || state === 'stopped' || state === 'released') {
      return PlayerState.IDLE;
    }
    if (state === 'initialized') {
      return PlayerState.LOADING;
    }
    if (state === 'prepared') {
      return PlayerState.READY;
    }
    if (state === 'playing') {
      return PlayerState.PLAYING;
    }
    if (state === 'paused') {
      return PlayerState.PAUSED;
    }
    if (state === 'completed') {
      return PlayerState.COMPLETED;
    }
    if (state === 'error') {
      return PlayerState.ERROR;
    }
    return undefined;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
