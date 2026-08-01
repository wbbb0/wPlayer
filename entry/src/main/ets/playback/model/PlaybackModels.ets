import { image } from '@kit.ImageKit';
import { AvailabilityState, MediaFormat, ParsedArtwork } from '../../library/model/LibraryModels';
import { DynamicColor, DynamicContainerRole, ForegroundEmphasis } from '../../appearance/DynamicColor';
import { TimedLyricLine } from '../lyrics/LyricsParser';

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

export enum PlaybackTransportState {
  IDLE = 'idle',
  PREPARING = 'preparing',
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

export interface QueueEntry {
  queueEntryId: number;
  track: QueueTrack;
}

export class QueueTrackDataSource implements IDataSource {
  private items: Array<QueueEntry> = [];
  private readonly listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): QueueEntry {
    return this.items[index];
  }

  snapshot(): Array<QueueEntry> {
    return this.items.slice();
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

  replace(items: Array<QueueEntry>): void {
    this.items = items.slice();
    const operations: Array<DataOperation> = [{ type: DataOperationType.RELOAD }];
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(operations));
  }

  notifyChanged(indices: Array<number>): void {
    const unique = new Set<number>();
    indices.forEach((index: number): void => {
      if (index >= 0 && index < this.items.length) {
        unique.add(index);
      }
    });
    if (unique.size === 0) {
      return;
    }
    const operations: Array<DataOperation> = [];
    unique.forEach((index: number): void => {
      operations.push({ type: DataOperationType.CHANGE, index: index });
    });
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(operations));
  }
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

export enum CompletedCollectionMode {
  SMART = 0,
  DEFAULT_ON = 1,
  DEFAULT_OFF = 2
}

export enum PlaybackOriginKind {
  LIBRARY = 0,
  ALBUM = 1,
  PLAYLIST = 2,
  COMPLETED_PLAYLIST = 3,
  RESTORED_QUEUE = 4
}

export type LyricIndexListener = (index: number) => void;
export type QueueIndexListener = (index: number) => void;

export class LyricLineDataSource implements IDataSource {
  private items: Array<TimedLyricLine> = [];
  private readonly listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): TimedLyricLine {
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

  replace(items: Array<TimedLyricLine>): void {
    this.items = items.slice();
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

@Observed
export class PlaybackProgressStore {
  positionMs: number = 0;
  durationMs: number = 0;
}

@Observed
export class PlayerStore {
  state: PlayerState = PlayerState.IDLE;
  transportState: PlaybackTransportState = PlaybackTransportState.IDLE;
  playWhenReady: boolean = false;
  currentTrack?: QueueTrack;
  readonly progress: PlaybackProgressStore = new PlaybackProgressStore();
  miniArtwork?: image.PixelMap;
  miniArtworkUri: string = '';
  miniArtworkRevision: number = 0;
  heroArtwork?: image.PixelMap;
  heroArtworkUri: string = '';
  heroArtworkPreferPixelMap: boolean = false;
  heroArtworkRevision: number = 0;
  errorMessage: string = '';
  lyrics: string = '';
  timedLyrics: Array<TimedLyricLine> = [];
  readonly lyricDataSource: LyricLineDataSource = new LyricLineDataSource();
  lyricDocumentRevision: number = 0;
  activeLyricIndex: number = -1;
  private readonly lyricIndexListeners: Array<LyricIndexListener> = [];
  shuffleEnabled: boolean = false;
  repeatMode: RepeatMode = RepeatMode.ALL;
  queuePhase: QueueBuildPhase = QueueBuildPhase.EMPTY;
  queueSize: number = 0;
  readonly queueDataSource: QueueTrackDataSource = new QueueTrackDataSource();
  queueCurrentIndex: number = -1;
  private readonly queueIndexListeners: Array<QueueIndexListener> = [];
  completedCollectionEnabled: boolean = true;
  completedCollectionMode: CompletedCollectionMode = CompletedCollectionMode.SMART;
  palettePrimary: string = DEFAULT_PLAYER_PALETTE_PRIMARY;
  paletteSecondary: string = DEFAULT_PLAYER_PALETTE_SECONDARY;
  paletteAccent: string = DEFAULT_PLAYER_PALETTE_ACCENT;
  themeBaseBackground: string = '#FFFFFFFF';

  isPlaying(): boolean {
    return this.transportState === PlaybackTransportState.PLAYING;
  }

  showsPauseControl(): boolean {
    return this.transportState === PlaybackTransportState.PLAYING ||
      this.transportState === PlaybackTransportState.PREPARING;
  }

  keepsActivePlaybackVisual(): boolean {
    return this.showsPauseControl();
  }

  setMiniArtwork(artwork: image.PixelMap | undefined, uri: string): void {
    this.miniArtwork = artwork;
    this.miniArtworkUri = uri;
    this.miniArtworkRevision += 1;
  }

  addLyricIndexListener(listener: LyricIndexListener): void {
    if (this.lyricIndexListeners.indexOf(listener) < 0) {
      this.lyricIndexListeners.push(listener);
    }
  }

  removeLyricIndexListener(listener: LyricIndexListener): void {
    const index = this.lyricIndexListeners.indexOf(listener);
    if (index >= 0) {
      this.lyricIndexListeners.splice(index, 1);
    }
  }

  setActiveLyricIndex(index: number): void {
    if (this.activeLyricIndex === index) {
      return;
    }
    this.activeLyricIndex = index;
    this.lyricIndexListeners.slice().forEach((listener: LyricIndexListener) => listener(index));
  }

  setTimedLyrics(lines: Array<TimedLyricLine>): void {
    this.timedLyrics = lines;
    this.lyricDataSource.replace(lines);
    this.lyricDocumentRevision += 1;
  }

  addQueueIndexListener(listener: QueueIndexListener): void {
    if (this.queueIndexListeners.indexOf(listener) < 0) {
      this.queueIndexListeners.push(listener);
    }
  }

  removeQueueIndexListener(listener: QueueIndexListener): void {
    const index = this.queueIndexListeners.indexOf(listener);
    if (index >= 0) {
      this.queueIndexListeners.splice(index, 1);
    }
  }

  setQueueCurrentIndex(index: number): void {
    if (this.queueCurrentIndex === index) {
      return;
    }
    const previousIndex = this.queueCurrentIndex;
    this.queueCurrentIndex = index;
    this.queueDataSource.notifyChanged([previousIndex, index]);
    this.queueIndexListeners.slice().forEach((listener: QueueIndexListener) => listener(index));
  }

  hasCurrentTrack(): boolean {
    return this.currentTrack !== undefined;
  }

  hasCurrentArtwork(): boolean {
    const track = this.currentTrack;
    if (track === undefined) {
      return false;
    }
    return this.miniArtwork !== undefined ||
      this.heroArtwork !== undefined ||
      this.miniArtworkUri.length > 0 ||
      this.heroArtworkUri.length > 0 ||
      track.smallArtworkPath.length > 0 ||
      track.largeArtworkPath.length > 0;
  }

  private themeColor(color: string, fallback: string): string {
    return this.hasCurrentArtwork() && color.length > 0 ? color : fallback;
  }

  themePrimary(): string {
    return this.themeColor(this.palettePrimary, DEFAULT_PLAYER_PALETTE_PRIMARY);
  }

  themeSecondary(): string {
    return this.themeColor(this.paletteSecondary, DEFAULT_PLAYER_PALETTE_SECONDARY);
  }

  themeAccent(): string {
    return this.themeColor(this.paletteAccent, DEFAULT_PLAYER_PALETTE_ACCENT);
  }

  themeOnPrimary(): string {
    return DynamicColor.foreground(
      this.themePrimary(),
      DynamicContainerRole.PRIMARY
    );
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
