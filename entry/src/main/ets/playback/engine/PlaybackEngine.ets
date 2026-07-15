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
  private rawState: string = 'idle';
  private listener?: PlaybackEngineListener;
  private commandTail: Promise<void> = Promise.resolve();
  private readonly requestEpoch: RequestEpoch = new RequestEpoch();
  private activeEpoch: number = 0;
  private pendingStateWait?: PendingStateWait;
  private pendingSeekWait?: PendingSeekWait;

  setListener(listener: PlaybackEngineListener): void {
    this.listener = listener;
  }

  playTrack(track: PlaybackTrack, resumePositionMs: number): Promise<void> {
    const epoch = this.requestEpoch.begin();
    this.listener?.onStateChanged(PlayerState.LOADING);
    return this.enqueue(async () => {
      this.activeEpoch = epoch;
      await this.loadAndPlay(track, resumePositionMs, epoch);
    });
  }

  invalidateAndStop(): Promise<void> {
    this.requestEpoch.invalidate();
    this.rejectPendingWaits(new Error('Playback request superseded'));
    return this.enqueue(async () => {
      if (this.player !== undefined && this.rawState !== 'idle' && this.rawState !== 'released') {
        await this.resetForSource(this.player);
      }
    });
  }

  togglePlayback(): Promise<void> {
    return this.enqueue(async () => {
      if (this.player === undefined) {
        return;
      }
      if (this.rawState === 'playing') {
        await this.player.pause();
      } else if (this.rawState === 'prepared' || this.rawState === 'paused' || this.rawState === 'completed') {
        await this.player.play();
      }
    });
  }

  play(): Promise<void> {
    return this.enqueue(async () => {
      if (this.player !== undefined &&
        (this.rawState === 'prepared' || this.rawState === 'paused' || this.rawState === 'completed')) {
        await this.player.play();
      }
    });
  }

  pause(): Promise<void> {
    return this.enqueue(async () => {
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
    this.requestEpoch.invalidate();
    this.rejectPendingWaits(new Error('Playback engine shut down'));
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
  }

  private async loadAndPlay(track: PlaybackTrack, resumePositionMs: number, epoch: number): Promise<void> {
    if (track.availability !== AvailabilityState.AVAILABLE) {
      throw new Error('音乐文件当前不可用，请重新授权或重新导入');
    }
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
    await player.play();
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player !== undefined && this.rawState !== 'released') {
      return this.player;
    }
    const player = await media.createAVPlayer();
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
      await player.reset();
      this.rawState = player.state;
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
