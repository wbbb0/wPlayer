import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { AvailabilityState } from '../../library/model/LibraryModels';
import { PlaybackTrack, PlayerState } from '../model/PlaybackModels';
import { RequestEpoch } from '../support/RequestEpoch';

const STATE_WAIT_TIMEOUT_MS = 10000;
const SEEK_WAIT_TIMEOUT_MS = 8000;

export interface PlaybackEngineListener {
  onStateChanged(state: PlayerState, message?: string): void;
  onPositionChanged(positionMs: number): void;
  onDurationChanged(durationMs: number): void;
  onCompleted(): void;
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

export class PlaybackEngine {
  private player?: media.AVPlayer;
  private sourceFile?: fs.File;
  private audioSessionManager?: audio.AudioSessionManager;
  private outputDeviceChangedCallback?: (event: audio.CurrentOutputDeviceChangedEvent) => void;
  private rawState: string = 'idle';
  private listener?: PlaybackEngineListener;
  private commandTail: Promise<void> = Promise.resolve();
  private readonly requestEpoch: RequestEpoch = new RequestEpoch();
  private activeEpoch: number = 0;
  private pendingStateWait?: PendingStateWait;
  private pendingSeekWait?: PendingSeekWait;
  private resumeAfterOutputReconnect: boolean = false;
  private shuttingDown: boolean = false;

  setListener(listener: PlaybackEngineListener): void {
    this.listener = listener;
  }

  playTrack(track: PlaybackTrack, resumePositionMs: number, playWhenReady: () => boolean): Promise<void> {
    const epoch = this.requestEpoch.begin();
    this.listener?.onStateChanged(PlayerState.LOADING);
    return this.enqueue(async () => {
      this.resumeAfterOutputReconnect = false;
      this.activeEpoch = epoch;
      await this.loadTrack(track, resumePositionMs, epoch, playWhenReady);
    });
  }

  invalidateAndStop(): Promise<void> {
    this.requestEpoch.invalidate();
    this.rejectPendingWaits(new Error('Playback request superseded'));
    return this.enqueue(async () => {
      this.resumeAfterOutputReconnect = false;
      if (this.player !== undefined && this.rawState !== 'idle' && this.rawState !== 'released') {
        await this.resetForSource(this.player);
      }
    });
  }

  togglePlayback(): Promise<void> {
    return this.enqueue(async () => {
      this.resumeAfterOutputReconnect = false;
      if (this.player === undefined) {
        return;
      }
      if (this.rawState === 'playing') {
        await this.player.pause();
      } else if (this.rawState === 'prepared' || this.rawState === 'paused' || this.rawState === 'completed') {
        await this.ensureAudioSession();
        await this.player.play();
      }
    });
  }

  play(): Promise<void> {
    return this.enqueue(async () => {
      this.resumeAfterOutputReconnect = false;
      if (this.player !== undefined &&
        (this.rawState === 'prepared' || this.rawState === 'paused' || this.rawState === 'completed')) {
        await this.ensureAudioSession();
        await this.player.play();
      }
    });
  }

  pause(): Promise<void> {
    return this.enqueue(async () => {
      this.resumeAfterOutputReconnect = false;
      if (this.player !== undefined && this.rawState === 'playing') {
        await this.player.pause();
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
    this.resumeAfterOutputReconnect = false;
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
    this.shuttingDown = false;
  }

  private async loadTrack(track: PlaybackTrack, resumePositionMs: number, epoch: number,
    playWhenReady: () => boolean): Promise<void> {
    if (track.availability !== AvailabilityState.AVAILABLE) {
      throw new Error('音乐文件当前不可用，请重新授权或重新导入');
    }
    try {
      const player = await this.ensurePlayer();
      this.ensureCurrent(epoch);
      await this.resetForSource(player);
      this.ensureCurrent(epoch);

      let sourceFile: fs.File;
      try {
        sourceFile = fs.openSync(track.uri, fs.OpenMode.READ_ONLY);
      } catch (error) {
        const cause = new Error(`无法打开音乐文件：${PlaybackEngine.messageOf(error)}`);
        this.listener?.onStateChanged(PlayerState.ERROR, cause.message);
        throw cause;
      }
      this.sourceFile = sourceFile;
      const initialized = this.waitForState('initialized');
      player.fdSrc = { fd: sourceFile.fd, offset: 0, length: track.fileSize };
      await initialized;
      this.ensureCurrent(epoch);
      player.audioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      await player.prepare();
      this.ensureCurrent(epoch);
      if (resumePositionMs > 0) {
        await this.seekInternal(resumePositionMs);
        this.ensureCurrent(epoch);
      }
      if (playWhenReady()) {
        await this.ensureAudioSession();
        await player.play();
      }
    } catch (error) {
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
      if (PlaybackEngine.messageOf(error) !== 'Playback request superseded') {
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
          this.onOutputDeviceChanged(event);
        };
        this.audioSessionManager.on('currentOutputDeviceChanged', callback);
        this.outputDeviceChangedCallback = callback;
      }
      if (!this.audioSessionManager.isAudioSessionActivated()) {
        await this.audioSessionManager.activateAudioSession({
          concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT
        });
      }
    } catch (error) {
      console.warn(`Unable to initialize audio output monitoring: ${PlaybackEngine.messageOf(error)}`);
    }
  }

  private onOutputDeviceChanged(event: audio.CurrentOutputDeviceChangedEvent): void {
    if (event.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE &&
      this.rawState === 'playing') {
      this.pauseForOutputDisconnect().catch((error: Object) => {
        console.warn(`Unable to pause after audio output disconnect: ${PlaybackEngine.messageOf(error)}`);
      });
      return;
    }
    if (event.changeReason === audio.AudioStreamDeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE) {
      this.resumeForOutputReconnect().catch((error: Object) => {
        console.warn(`Unable to resume after audio output reconnect: ${PlaybackEngine.messageOf(error)}`);
      });
    }
  }

  private pauseForOutputDisconnect(): Promise<void> {
    return this.enqueue(async () => {
      if (this.player === undefined || this.rawState !== 'playing') {
        return;
      }
      this.resumeAfterOutputReconnect = true;
      try {
        await this.player.pause();
      } catch (error) {
        this.resumeAfterOutputReconnect = false;
        throw error instanceof Error ? error : new Error(`${error}`);
      }
    });
  }

  private resumeForOutputReconnect(): Promise<void> {
    return this.enqueue(async () => {
      if (!this.resumeAfterOutputReconnect) {
        return;
      }
      this.resumeAfterOutputReconnect = false;
      if (this.player === undefined || this.rawState !== 'paused') {
        return;
      }
      await this.ensureAudioSession();
      await this.player.play();
    });
  }

  private unsubscribeOutputDeviceChanges(): void {
    if (this.audioSessionManager === undefined || this.outputDeviceChangedCallback === undefined) {
      return;
    }
    try {
      this.audioSessionManager.off('currentOutputDeviceChanged', this.outputDeviceChangedCallback);
    } catch (error) {
      console.warn(`Unable to stop audio output monitoring: ${PlaybackEngine.messageOf(error)}`);
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
      throw new Error('Playback request superseded');
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
