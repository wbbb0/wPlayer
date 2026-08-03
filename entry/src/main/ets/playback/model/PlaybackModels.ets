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
export class QueueEntryPresentation {
  entry: QueueEntry;
  displayIndex: number;
  currentDisplayIndex: number;

  constructor(entry: QueueEntry, displayIndex: number, currentDisplayIndex: number) {
    this.entry = entry;
    this.displayIndex = displayIndex;
    this.currentDisplayIndex = currentDisplayIndex;
  }

  isActive(): boolean {
    return this.displayIndex === this.currentDisplayIndex;
  }
}

export interface QueueIndexExchange {
  start: number;
  end: number;
}

export class QueuePermutationLayers {
  readonly first: Array<QueueIndexExchange>;
  readonly second: Array<QueueIndexExchange>;

  constructor(first: Array<QueueIndexExchange>, second: Array<QueueIndexExchange>) {
    this.first = first;
    this.second = second;
  }
}

export class QueuePermutationPolicy {
  static project(currentEntryIds: Array<number>, targetEntryIds: Array<number>): QueuePermutationLayers {
    const first: Array<QueueIndexExchange> = [];
    const second: Array<QueueIndexExchange> = [];
    const targetIndexById = new Map<number, number>();
    targetEntryIds.forEach((entryId: number, index: number): void => {
      targetIndexById.set(entryId, index);
    });
    const destinationBySource: Array<number> = currentEntryIds.map((entryId: number): number =>
      targetIndexById.get(entryId) as number);
    const visited = new Set<number>();
    for (let source = 0; source < destinationBySource.length; source += 1) {
      if (visited.has(source) || destinationBySource[source] === source) {
        visited.add(source);
        continue;
      }
      const cycle: Array<number> = [];
      let cursor = source;
      while (!visited.has(cursor)) {
        visited.add(cursor);
        cycle.push(cursor);
        cursor = destinationBySource[cursor];
      }
      for (let left = 0; left < Math.floor(cycle.length / 2); left += 1) {
        first.push({ start: cycle[left], end: cycle[cycle.length - 1 - left] });
      }
      for (let left = 1; left <= Math.floor((cycle.length - 1) / 2); left += 1) {
        second.push({ start: cycle[left], end: cycle[cycle.length - left] });
      }
    }
    return new QueuePermutationLayers(first, second);
  }
}

export type QueueFrameScheduler = (task: () => void) => void;
export type QueueProjectionComplete = (currentIndex: number) => void;

export class QueueTrackDataSource implements IDataSource {
  private items: Array<QueueEntryPresentation> = [];
  private readonly listeners: Array<DataChangeListener> = [];
  private frameScheduler?: QueueFrameScheduler;
  private projectionEpoch: number = 0;
  private projectionPending: boolean = false;
  private targetCurrentEntryId: number = -1;
  private targetCurrentIndex: number = -1;
  private projectionCompletion?: QueueProjectionComplete;

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): QueueEntryPresentation {
    return this.items[index];
  }

  snapshot(): Array<QueueEntry> {
    return this.items.map((item: QueueEntryPresentation): QueueEntry => item.entry);
  }

  setFrameScheduler(scheduler: QueueFrameScheduler | undefined): void {
    this.frameScheduler = scheduler;
  }

  hasPendingProjection(): boolean {
    return this.projectionPending;
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

  replace(items: Array<QueueEntry>, currentIndex: number = -1): void {
    this.projectionEpoch += 1;
    this.projectionPending = false;
    this.projectionCompletion = undefined;
    this.items = items.map((entry: QueueEntry, index: number): QueueEntryPresentation =>
      new QueueEntryPresentation(entry, index, currentIndex));
    const operations: Array<DataOperation> = [{ type: DataOperationType.RELOAD }];
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(operations));
  }

  applySnapshot(
    items: Array<QueueEntry>,
    currentIndex: number,
    changedIndices: Array<number>,
    onComplete: QueueProjectionComplete
  ): void {
    this.targetCurrentIndex = currentIndex;
    this.targetCurrentEntryId = currentIndex >= 0 && currentIndex < items.length ?
      items[currentIndex].queueEntryId : -1;
    this.projectionCompletion = onComplete;
    if (!this.hasSameUniqueIdentities(items)) {
      this.replace(items, currentIndex);
      onComplete(currentIndex);
      return;
    }
    const epoch = ++this.projectionEpoch;
    const currentIds = this.items.map((item: QueueEntryPresentation): number =>
      item.entry.queueEntryId);
    const targetIds = items.map((entry: QueueEntry): number => entry.queueEntryId);
    const layers = QueuePermutationPolicy.project(currentIds, targetIds);
    if (layers.first.length === 0 && layers.second.length === 0) {
      this.updatePresentation(items, this.targetCurrentEntryId);
      this.notifyChanged(changedIndices);
      this.completeProjection();
      return;
    }
    if (this.listeners.length === 0 || this.frameScheduler === undefined) {
      this.items = items.map((entry: QueueEntry, index: number): QueueEntryPresentation =>
        new QueueEntryPresentation(entry, index, currentIndex));
      this.completeProjection();
      return;
    }
    this.applyExchangeLayer(layers.first, this.targetCurrentEntryId);
    if (layers.second.length === 0) {
      this.updatePresentation(items, this.targetCurrentEntryId);
      this.completeProjection();
      return;
    }
    this.projectionPending = true;
    this.frameScheduler((): void => {
      if (epoch !== this.projectionEpoch) {
        return;
      }
      this.applyExchangeLayer(layers.second, this.targetCurrentEntryId);
      this.updatePresentation(items, this.targetCurrentEntryId);
      this.completeProjection();
    });
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

  applyCurrentIndex(
    currentIndex: number,
    currentEntryId: number,
    changedIndices: Array<number>,
    onComplete: QueueProjectionComplete
  ): void {
    this.targetCurrentIndex = currentIndex;
    this.targetCurrentEntryId = currentEntryId;
    this.projectionCompletion = onComplete;
    this.updatePresentationIndices(currentEntryId);
    if (this.projectionPending) {
      return;
    }
    this.notifyChanged(changedIndices);
    this.completeProjection();
  }

  private hasSameUniqueIdentities(items: Array<QueueEntry>): boolean {
    if (items.length !== this.items.length) {
      return false;
    }
    const identities = new Set<number>();
    this.items.forEach((item: QueueEntryPresentation): void => {
      identities.add(item.entry.queueEntryId);
    });
    if (identities.size !== this.items.length) {
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

  private applyExchangeLayer(exchanges: Array<QueueIndexExchange>, currentEntryId: number): void {
    if (exchanges.length === 0) {
      return;
    }
    exchanges.forEach((exchange: QueueIndexExchange): void => {
      const startItem = this.items[exchange.start];
      this.items[exchange.start] = this.items[exchange.end];
      this.items[exchange.end] = startItem;
    });
    this.updatePresentationIndices(currentEntryId);
    const operations: Array<DataOperation> = exchanges.map((exchange: QueueIndexExchange): DataOperation => ({
      type: DataOperationType.EXCHANGE,
      index: { start: exchange.start, end: exchange.end }
    }));
    this.listeners.forEach((listener: DataChangeListener): void =>
      listener.onDatasetChange(operations));
  }

  private updatePresentation(items: Array<QueueEntry>, currentEntryId: number): void {
    const entriesById = new Map<number, QueueEntry>();
    items.forEach((entry: QueueEntry): void => {
      entriesById.set(entry.queueEntryId, entry);
    });
    this.items.forEach((item: QueueEntryPresentation): void => {
      item.entry = entriesById.get(item.entry.queueEntryId) as QueueEntry;
    });
    this.updatePresentationIndices(currentEntryId);
  }

  private updatePresentationIndices(currentEntryId: number): void {
    const currentIndex = this.items.findIndex((item: QueueEntryPresentation): boolean =>
      item.entry.queueEntryId === currentEntryId);
    this.items.forEach((item: QueueEntryPresentation, index: number): void => {
      item.displayIndex = index;
      item.currentDisplayIndex = currentIndex;
    });
  }

  private completeProjection(): void {
    this.projectionPending = false;
    const completion = this.projectionCompletion;
    this.projectionCompletion = undefined;
    if (completion !== undefined) {
      completion(this.targetCurrentIndex);
    }
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
    if (this.queueCurrentIndex === index && !this.queueDataSource.hasPendingProjection()) {
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
