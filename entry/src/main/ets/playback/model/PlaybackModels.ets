import { image } from '@kit.ImageKit';
import { AvailabilityState, MediaFormat, ParsedArtwork } from '../../library/model/LibraryModels';

export enum PlayerState {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  ERROR = 'error'
}

export enum RepeatMode {
  OFF = 0,
  ALL = 1,
  ONE = 2
}

export enum QueueBuildPhase {
  EMPTY = 0,
  BUILDING = 1,
  READY = 2,
  FAILED = 3
}

export interface QueueTrack {
  id: number;
  title: string;
  artistDisplay: string;
  albumDisplay: string;
  durationMs: number;
  smallArtworkHash: string;
  smallArtworkPath: string;
  largeArtworkHash: string;
  largeArtworkPath: string;
  artworkWidth: number;
  artworkHeight: number;
}

export interface PlaybackTrack extends QueueTrack {
  uri: string;
  fileSize: number;
  modifiedAt: number;
  format: MediaFormat;
  availability: AvailabilityState;
  authorizationPersisted: boolean;
  artwork?: ParsedArtwork;
}

export interface ResumeState {
  positionMs: number;
  durationMs: number;
}

@Observed
export class PlayerStore {
  state: PlayerState = PlayerState.IDLE;
  currentTrack?: QueueTrack;
  positionMs: number = 0;
  durationMs: number = 0;
  miniArtwork?: image.PixelMap;
  miniArtworkUri: string = '';
  heroArtwork?: image.PixelMap;
  heroArtworkUri: string = '';
  heroArtworkPreferPixelMap: boolean = false;
  errorMessage: string = '';
  shuffleEnabled: boolean = false;
  repeatMode: RepeatMode = RepeatMode.ALL;
  queuePhase: QueueBuildPhase = QueueBuildPhase.EMPTY;
  queueSize: number = 0;

  isPlaying(): boolean {
    return this.state === PlayerState.PLAYING;
  }

  hasCurrentTrack(): boolean {
    return this.currentTrack !== undefined;
  }
}
