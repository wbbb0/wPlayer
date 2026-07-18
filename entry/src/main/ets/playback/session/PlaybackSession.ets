import { common, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { image } from '@kit.ImageKit';
import { PlaybackTrack, PlaybackTransportState, RepeatMode } from '../model/PlaybackModels';

export interface PlaybackSessionCommands {
  play(): void;
  pause(): void;
  stop(): void;
  next(): void;
  previous(): void;
  seek(positionMs: number): void;
}

export class PlaybackSession {
  private readonly context: common.UIAbilityContext;
  private readonly commands: PlaybackSessionCommands;
  private session?: avSession.AVSession;
  private initializePromise?: Promise<void>;
  private backgroundRunning: boolean = false;
  private backgroundDesired: boolean = false;
  private backgroundTail: Promise<void> = Promise.resolve();
  private metadataUpdateTail: Promise<void> = Promise.resolve();
  private playbackStateUpdateTail: Promise<void> = Promise.resolve();
  private metadataUpdateEpoch: number = 0;
  private metadataTrackId: number = -1;
  private metadataLyrics: string = '';
  private shuttingDown: boolean = false;

  constructor(context: common.UIAbilityContext, commands: PlaybackSessionCommands) {
    this.context = context;
    this.commands = commands;
  }

  initialize(): Promise<void> {
    if (this.session !== undefined) {
      return Promise.resolve();
    }
    if (this.initializePromise === undefined) {
      this.initializePromise = this.initializeInternal();
    }
    return this.initializePromise;
  }

  updateMetadata(track: PlaybackTrack, artwork?: image.PixelMap | string, lyrics: string = ''): Promise<void> {
    if (this.metadataTrackId !== track.id) {
      this.metadataTrackId = track.id;
      this.metadataLyrics = '';
    }
    if (lyrics.length > 0) {
      this.metadataLyrics = lyrics;
    }
    const epoch = ++this.metadataUpdateEpoch;
    return this.enqueueMetadataUpdate(async () => {
      await this.initialize();
      if (this.session === undefined || epoch !== this.metadataUpdateEpoch) {
        return;
      }
      const metadata: avSession.AVMetadata = {
        assetId: `${track.id}`,
        title: track.title,
        artist: track.artistDisplay,
        album: track.albumDisplay,
        duration: track.durationMs,
        avQueueName: '所有音乐',
        avQueueId: 'library.all'
      };
      if (artwork !== undefined && (typeof artwork !== 'string' || artwork.length > 0)) {
        metadata.mediaImage = artwork;
      }
      if (this.metadataLyrics.length > 0 && this.metadataLyrics.length < 40960) {
        if (/\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]/.test(this.metadataLyrics)) {
          metadata.lyric = this.metadataLyrics;
        } else {
          metadata.singleLyricText = this.metadataLyrics;
        }
      }
      await this.session.setAVMetadata(metadata);
    });
  }

  updatePlaybackState(state: PlaybackTransportState, positionMs: number, repeatMode: RepeatMode,
    shuffleEnabled: boolean): Promise<void> {
    this.setBackgroundDesired(state === PlaybackTransportState.PLAYING);
    return this.enqueuePlaybackStateUpdate(async () => {
      await this.initialize();
      if (this.session !== undefined) {
        await this.session.setAVPlaybackState({
          state: PlaybackSession.sessionStateOf(state),
          // AVSession expects the configured playback rate, not zero when paused.
          speed: 1,
          position: { elapsedTime: positionMs, updateTime: Date.now() },
          loopMode: PlaybackSession.loopModeOf(repeatMode, shuffleEnabled)
        });
      }
    });
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    await Promise.all([this.metadataUpdateTail, this.playbackStateUpdateTail]);
    this.setBackgroundDesired(false);
    await this.backgroundTail;
    if (this.session !== undefined) {
      try {
        await this.session.deactivate();
        await this.session.destroy();
      } catch (error) {
        console.warn(`Unable to destroy AVSession: ${PlaybackSession.messageOf(error)}`);
      }
      this.session = undefined;
    }
    this.initializePromise = undefined;
  }

  private async initializeInternal(): Promise<void> {
    try {
      const session = await avSession.createAVSession(this.context, 'wPlayer', 'audio');
      session.on('play', () => this.commands.play());
      session.on('pause', () => this.commands.pause());
      session.on('stop', () => this.commands.stop());
      session.on('playNext', () => this.commands.next());
      session.on('playPrevious', () => this.commands.previous());
      session.on('seek', (time: number) => this.commands.seek(time));
      await session.activate();
      this.session = session;
    } catch (error) {
      this.initializePromise = undefined;
      console.warn(`Unable to initialize AVSession: ${PlaybackSession.messageOf(error)}`);
    }
  }

  private enqueueMetadataUpdate(operation: () => Promise<void>): Promise<void> {
    const pending = this.enqueueUpdate(this.metadataUpdateTail, operation);
    this.metadataUpdateTail = pending.catch((error: Object) => {
      console.warn(`Unable to update AVSession metadata: ${PlaybackSession.messageOf(error)}`);
    });
    return pending;
  }

  private enqueuePlaybackStateUpdate(operation: () => Promise<void>): Promise<void> {
    const pending = this.enqueueUpdate(this.playbackStateUpdateTail, operation);
    this.playbackStateUpdateTail = pending.catch((error: Object) => {
      console.warn(`Unable to update AVSession playback state: ${PlaybackSession.messageOf(error)}`);
    });
    return pending;
  }

  private enqueueUpdate(tail: Promise<void>, operation: () => Promise<void>): Promise<void> {
    if (this.shuttingDown) {
      return Promise.resolve();
    }
    return tail.then(async () => {
      if (!this.shuttingDown) {
        await operation();
      }
    });
  }

  private setBackgroundDesired(desired: boolean): void {
    this.backgroundDesired = desired;
    this.backgroundTail = this.backgroundTail.then(async () => {
      if (this.backgroundDesired === this.backgroundRunning) {
        return;
      }
      if (this.backgroundDesired) {
        const launchAgent = await wantAgent.getWantAgent({
          wants: [{
            bundleName: this.context.abilityInfo.bundleName,
            abilityName: this.context.abilityInfo.name
          }],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 1001,
          actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        });
        await backgroundTaskManager.startBackgroundRunning(
          this.context,
          backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
          launchAgent
        );
        this.backgroundRunning = true;
      } else {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
        this.backgroundRunning = false;
      }
    }).catch((error: Object) => {
      console.warn(`Unable to update audio background task: ${PlaybackSession.messageOf(error)}`);
    });
  }

  private static sessionStateOf(state: PlaybackTransportState): avSession.PlaybackState {
    if (state === PlaybackTransportState.PREPARING) {
      return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
    }
    if (state === PlaybackTransportState.PLAYING) {
      return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    }
    if (state === PlaybackTransportState.PAUSED) {
      return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    }
    if (state === PlaybackTransportState.COMPLETED) {
      return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
    }
    if (state === PlaybackTransportState.ERROR) {
      // Some system controllers reject ERROR as a publishable media-control state.
      return avSession.PlaybackState.PLAYBACK_STATE_STOP;
    }
    return avSession.PlaybackState.PLAYBACK_STATE_IDLE;
  }

  private static loopModeOf(repeatMode: RepeatMode, shuffleEnabled: boolean): avSession.LoopMode {
    if (shuffleEnabled) {
      return avSession.LoopMode.LOOP_MODE_SHUFFLE;
    }
    if (repeatMode === RepeatMode.ONE) {
      return avSession.LoopMode.LOOP_MODE_SINGLE;
    }
    if (repeatMode === RepeatMode.ALL) {
      return avSession.LoopMode.LOOP_MODE_LIST;
    }
    return avSession.LoopMode.LOOP_MODE_SEQUENCE;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
