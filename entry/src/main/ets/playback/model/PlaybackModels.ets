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

@Observed
export class QueuePositionSlot {
  readonly index: number;

  constructor(index: number) {
    this.index = index;
  }
}

@Observed
export class QueueProjectionState {
  revision: number = 0;
  private entries: Array<QueueEntry> = [];
  private currentIndex: number = -1;
  private indexByEntryId: Map<number, number> = new Map<number, number>();

  replace(entries: Array<QueueEntry>, currentIndex: number): void {
    const nextIndexByEntryId = new Map<number, number>();
    entries.forEach((entry: QueueEntry, index: number): void => {
      nextIndexByEntryId.set(entry.queueEntryId, index);
    });
    this.entries = entries.slice();
    this.indexByEntryId = nextIndexByEntryId;
    this.currentIndex = currentIndex;
    this.revision += 1;
  }

  entryAt(index: number): QueueEntry | undefined {
    if (this.revision < 0) {
      return undefined;
    }
    return this.entries[index];
  }

  snapshot(): Array<QueueEntry> {
    return this.entries.slice();
  }

  setCurrentIndex(currentIndex: number): void {
    if (this.currentIndex === currentIndex) {
      return;
    }
    this.currentIndex = currentIndex;
    this.revision += 1;
  }

  displayIndex(entryId: number): number {
    if (this.revision < 0) {
      return -1;
    }
    return this.indexByEntryId.get(entryId) ?? -1;
  }

  activeIndex(): number {
    if (this.revision < 0) {
      return -1;
    }
    return this.currentIndex;
  }

  isActive(entryId: number): boolean {
    const displayIndex = this.displayIndex(entryId);
    return displayIndex >= 0 && displayIndex === this.activeIndex();
  }
}
export type QueueProjectionComplete = (currentIndex: number) => void;
export type QueueProjectionListener = () => void;

export class QueueTrackDataSource implements IDataSource {
  readonly projectionState: QueueProjectionState = new QueueProjectionState();
  private slots: Array<QueuePositionSlot> = [];
  private readonly listeners: Array<DataChangeListener> = [];
  private readonly projectionListeners: Array<QueueProjectionListener> = [];

  totalCount(): number {
    return this.slots.length;
  }

  getData(index: number): QueuePositionSlot {
    return this.slots[index];
  }

  snapshot(): Array<QueueEntry> {
    return this.projectionState.snapshot();
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

  addProjectionListener(listener: QueueProjectionListener): void {
    if (this.projectionListeners.indexOf(listener) < 0) {
      this.projectionListeners.push(listener);
    }
  }

  removeProjectionListener(listener: QueueProjectionListener): void {
    const index = this.projectionListeners.indexOf(listener);
    if (index >= 0) {
      this.projectionListeners.splice(index, 1);
    }
  }

  replace(items: Array<QueueEntry>, currentIndex: number = -1): void {
    this.slots = items.map((_entry: QueueEntry, index: number): QueuePositionSlot =>
      new QueuePositionSlot(index));
    this.projectionState.replace(items, currentIndex);
    this.notifyReloaded();
  }

  applySnapshot(
    items: Array<QueueEntry>,
    currentIndex: number,
    changedIndices: Array<number>,
    onComplete: QueueProjectionComplete
  ): void {
    if (!this.hasSameUniqueIdentities(items)) {
      this.replace(items, currentIndex);
      onComplete(currentIndex);
      return;
    }
    const currentItems = this.projectionState.snapshot();
    const currentIds = currentItems.map((entry: QueueEntry): number => entry.queueEntryId);
    const targetIds = items.map((entry: QueueEntry): number => entry.queueEntryId);
    if (QueueTrackDataSource.sameOrder(currentIds, targetIds)) {
      if (this.entriesChanged(currentItems, items)) {
        this.projectionState.replace(items, currentIndex);
      } else {
        this.projectionState.setCurrentIndex(currentIndex);
      }
      this.notifyChanged(changedIndices);
      onComplete(currentIndex);
      return;
    }
    this.projectionState.replace(items, currentIndex);
    this.notifyProjectionChanged();
    onComplete(currentIndex);
  }

  notifyChanged(indices: Array<number>): void {
    const unique = new Set<number>();
    indices.forEach((index: number): void => {
      if (index >= 0 && index < this.slots.length) {
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

  applyCurrentIndex(
    currentIndex: number,
    _currentEntryId: number,
    changedIndices: Array<number>,
    onComplete: QueueProjectionComplete
  ): void {
    this.projectionState.setCurrentIndex(currentIndex);
    this.notifyChanged(changedIndices);
    onComplete(currentIndex);
  }

  private hasSameUniqueIdentities(items: Array<QueueEntry>): boolean {
    const currentItems = this.projectionState.snapshot();
    if (items.length !== currentItems.length) {
      return false;
    }
    const identities = new Set<number>();
    currentItems.forEach((entry: QueueEntry): void => {
      identities.add(entry.queueEntryId);
    });
    if (identities.size !== currentItems.length) {
      return false;
    }
    const targetIdentities = new Set<number>();
    for (let index = 0; index < items.length; index += 1) {
      const identity = items[index].queueEntryId;
      if (!identities.has(identity) || targetIdentities.has(identity)) {
        return false;
      }
      targetIdentities.add(identity);
    }
    return true;
  }

  private entriesChanged(current: Array<QueueEntry>, target: Array<QueueEntry>): boolean {
    for (let index = 0; index < current.length; index += 1) {
      if (current[index] !== target[index]) {
        return true;
      }
    }
    return false;
  }

  private notifyProjectionChanged(): void {
    this.projectionListeners.slice().forEach((listener: QueueProjectionListener): void => listener());
  }

  private notifyReloaded(): void {
    this.notifyProjectionChanged();
    const operations: Array<DataOperation> = [{ type: DataOperationType.RELOAD }];
    this.listeners.forEach((listener: DataChangeListener): void =>
      listener.onDatasetChange(operations));
  }

  private static sameOrder(currentIds: Array<number>, targetIds: Array<number>): boolean {
    if (currentIds.length !== targetIds.length) {
      return false;
    }
    for (let index = 0; index < currentIds.length; index += 1) {
      if (currentIds[index] !== targetIds[index]) {
        return false;
      }
    }
    return true;
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

  setQueueCurrentIndex(index: number, currentEntryId: number = -1): void {
    if (this.queueCurrentIndex === index) {
      return;
    }
    const previousIndex = this.queueCurrentIndex;
    this.queueDataSource.applyCurrentIndex(
      index,
      currentEntryId,
      [previousIndex, index],
      (projectedIndex: number): void => {
        this.queueCurrentIndex = projectedIndex;
        this.queueIndexListeners.slice().forEach((listener: QueueIndexListener): void =>
          listener(projectedIndex));
      }
    );
  }

  applyQueueSnapshot(entries: Array<QueueEntry>, currentIndex: number): void {
    const previousIndex = this.queueCurrentIndex;
    const changedIndices: Array<number> = previousIndex === currentIndex ?
      [] : [previousIndex, currentIndex];
    this.queueDataSource.applySnapshot(
      entries,
      currentIndex,
      changedIndices,
      (projectedIndex: number): void => {
        this.queueCurrentIndex = projectedIndex;
        if (previousIndex !== projectedIndex) {
          this.queueIndexListeners.slice().forEach((listener: QueueIndexListener): void =>
            listener(projectedIndex));
        }
      }
    );
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
