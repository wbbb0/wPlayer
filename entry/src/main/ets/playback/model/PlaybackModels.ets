import { image } from '@kit.ImageKit';
import { AvailabilityState, MediaFormat, ParsedArtwork } from '../../library/model/LibraryModels';
import { DynamicColor, DynamicContainerRole, ForegroundEmphasis } from '../../appearance/DynamicColor';

export const DEFAULT_PLAYER_PALETTE_PRIMARY: string = '#FF5B5CE2';
export const DEFAULT_PLAYER_PALETTE_SECONDARY: string = '#FF5B5CE2';
export const DEFAULT_PLAYER_PALETTE_ACCENT: string = '#FF5B5CE2';

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
  palettePrimary: string;
  paletteSecondary: string;
  paletteAccent: string;
}

export class QueueTrackDataSource implements IDataSource {
  private items: Array<QueueTrack> = [];
  private readonly listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): QueueTrack {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replace(items: Array<QueueTrack>): void {
    this.items = items.slice();
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

export enum PlaybackIntent {
  PAUSED,
  PLAYING
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
  playbackIntent: PlaybackIntent = PlaybackIntent.PAUSED;
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
  queueItems: Array<QueueTrack> = [];
  readonly queueDataSource: QueueTrackDataSource = new QueueTrackDataSource();
  queueCurrentIndex: number = -1;
  palettePrimary: string = DEFAULT_PLAYER_PALETTE_PRIMARY;
  paletteSecondary: string = DEFAULT_PLAYER_PALETTE_SECONDARY;
  paletteAccent: string = DEFAULT_PLAYER_PALETTE_ACCENT;

  isPlaying(): boolean {
    return this.playbackIntent === PlaybackIntent.PLAYING;
  }

  hasCurrentTrack(): boolean {
    return this.currentTrack !== undefined;
  }

  themePrimary(): string {
    return this.hasCurrentTrack() ? this.palettePrimary : DEFAULT_PLAYER_PALETTE_PRIMARY;
  }

  themeSecondary(): string {
    return this.hasCurrentTrack() ? this.paletteSecondary : DEFAULT_PLAYER_PALETTE_SECONDARY;
  }

  themeAccent(): string {
    return this.hasCurrentTrack() ? this.paletteAccent : DEFAULT_PLAYER_PALETTE_ACCENT;
  }

  themeOnPrimary(): string {
    return DynamicColor.foreground(this.themePrimary(), DynamicContainerRole.PRIMARY);
  }

  themeOnPrimaryMedium(): string {
    return DynamicColor.withEmphasis(this.themeOnPrimary(), ForegroundEmphasis.MEDIUM);
  }

  themeOnSecondary(): string {
    return DynamicColor.foreground(this.themeSecondary(), DynamicContainerRole.SECONDARY);
  }

  themeOnSecondaryMedium(): string {
    return DynamicColor.withEmphasis(this.themeOnSecondary(), ForegroundEmphasis.MEDIUM);
  }

  themeOnAccent(): string {
    return DynamicColor.foreground(this.themeAccent(), DynamicContainerRole.ACCENT);
  }

  themeOnAccentMedium(): string {
    return DynamicColor.withEmphasis(this.themeOnAccent(), ForegroundEmphasis.MEDIUM);
  }
}
