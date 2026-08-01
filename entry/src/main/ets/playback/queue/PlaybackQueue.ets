import { QueueBuildPhase, QueueEntry, QueueTrack, RepeatMode } from '../model/PlaybackModels';

export interface PlaybackQueueWindow {
  items: Array<QueueTrack>;
  currentIndex: number;
}

export interface PlaybackQueueSnapshot {
  entries: Array<QueueEntry>;
  currentIndex: number;
}

export interface PlaybackQueueStateItem {
  position: number;
  playbackPosition: number;
  trackId: number;
}

export interface PlaybackQueueStateSnapshot {
  items: Array<PlaybackQueueStateItem>;
  currentPosition: number;
}

export interface PlaybackQueueRemovalResult {
  removedCurrent: boolean;
  current?: QueueTrack;
}

export class PlaybackQueue {
  private items: Array<QueueEntry> = [];
  private order: Array<number> = [];
  private cursor: number = -1;
  private nextEntryId: number = 0;
  private readonly firstItemIndexById: Map<number, number> = new Map<number, number>();
  private readonly cursorByEntryId: Map<number, number> = new Map<number, number>();

  build(items: Array<QueueTrack>, currentTrackId: number, shuffleEnabled: boolean): QueueBuildPhase {
    if (items.length === 0) {
      this.clear();
      return QueueBuildPhase.EMPTY;
    }
    this.items = items.map((item: QueueTrack) => this.createEntry(item));
    this.rebuildItemIndex();
    const currentIndex = this.firstItemIndexById.get(currentTrackId);
    if (currentIndex === undefined) {
      this.clear();
      return QueueBuildPhase.FAILED;
    }
    this.order = this.buildOrder(currentIndex, shuffleEnabled);
    this.cursor = shuffleEnabled ? 0 : currentIndex;
    this.rebuildCursorIndex();
    return QueueBuildPhase.READY;
  }

  restore(items: Array<QueueTrack>, playbackPositions: Array<number>,
    currentPosition: number): QueueBuildPhase {
    if (items.length === 0 || playbackPositions.length !== items.length ||
      currentPosition < 0 || currentPosition >= items.length ||
      !PlaybackQueue.isPermutation(playbackPositions)) {
      this.clear();
      return items.length === 0 ? QueueBuildPhase.EMPTY : QueueBuildPhase.FAILED;
    }
    this.items = items.map((item: QueueTrack) => this.createEntry(item));
    this.order = new Array<number>(items.length);
    playbackPositions.forEach((playbackPosition: number, itemIndex: number): void => {
      this.order[playbackPosition] = itemIndex;
    });
    this.cursor = currentPosition;
    this.rebuildIndexes();
    return QueueBuildPhase.READY;
  }

  setShuffle(enabled: boolean): boolean {
    if (this.items.length === 0 || this.cursor < 0 || this.cursor >= this.order.length) {
      return false;
    }
    const currentItemIndex = this.order[this.cursor];
    this.order = this.buildOrder(currentItemIndex, enabled);
    this.cursor = enabled ? 0 : currentItemIndex;
    this.rebuildCursorIndex();
    return true;
  }

  current(): QueueTrack | undefined {
    return this.itemAtCursor(this.cursor);
  }

  currentPlaybackPosition(): number {
    return this.cursor;
  }

  displayCurrentIndex(): number {
    if (this.cursor < 0 || this.cursor >= this.order.length) {
      return -1;
    }
    return this.order[this.cursor];
  }

  currentEntryId(): number | undefined {
    if (this.cursor < 0 || this.cursor >= this.order.length) {
      return undefined;
    }
    return this.items[this.order[this.cursor]].queueEntryId;
  }

  selectEntry(queueEntryId: number): QueueTrack | undefined {
    const selectedCursor = this.cursorByEntryId.get(queueEntryId);
    if (selectedCursor === undefined) {
      return undefined;
    }
    this.cursor = selectedCursor;
    return this.current();
  }

  playbackSnapshot(): PlaybackQueueSnapshot {
    const snapshotEntries: Array<QueueEntry> = [];
    this.order.forEach((itemIndex: number) => {
      snapshotEntries.push(this.items[itemIndex]);
    });
    return {
      entries: snapshotEntries,
      currentIndex: this.cursor
    };
  }

  displaySnapshot(): PlaybackQueueSnapshot {
    return {
      entries: this.items.slice(),
      currentIndex: this.displayCurrentIndex()
    };
  }

  stateSnapshot(): PlaybackQueueStateSnapshot {
    const playbackPositions = new Array<number>(this.items.length);
    this.order.forEach((itemIndex: number, playbackPosition: number): void => {
      playbackPositions[itemIndex] = playbackPosition;
    });
    return {
      items: this.items.map((entry: QueueEntry, position: number): PlaybackQueueStateItem => ({
        position: position,
        playbackPosition: playbackPositions[position],
        trackId: entry.track.id
      })),
      currentPosition: this.cursor
    };
  }

  next(repeatMode: RepeatMode, naturalCompletion: boolean): QueueTrack | undefined {
    if (this.cursor < 0 || this.order.length === 0) {
      return undefined;
    }
    if (naturalCompletion && repeatMode === RepeatMode.ONE) {
      return this.current();
    }
    if (this.cursor + 1 < this.order.length) {
      this.cursor += 1;
      return this.current();
    }
    if (repeatMode === RepeatMode.ALL) {
      this.cursor = 0;
      return this.current();
    }
    return undefined;
  }

  previous(): QueueTrack | undefined {
    if (this.cursor <= 0 || this.order.length === 0) {
      return undefined;
    }
    this.cursor -= 1;
    return this.current();
  }

  size(): number {
    return this.items.length;
  }

  insertNext(items: Array<QueueTrack>): void {
    if (items.length === 0 || this.cursor < 0) {
      return;
    }
    const currentItemIndex = this.order[this.cursor];
    const insertedEntries = items.map((item: QueueTrack): QueueEntry => this.createEntry(item));
    const insertedOrder = insertedEntries.map((_entry: QueueEntry, index: number): number =>
      currentItemIndex + index + 1);
    this.items.splice(currentItemIndex + 1, 0, ...insertedEntries);
    this.order = this.order.map((itemIndex: number): number =>
      itemIndex > currentItemIndex ? itemIndex + insertedEntries.length : itemIndex);
    this.order.splice(this.cursor + 1, 0, ...insertedOrder);
    this.rebuildIndexes();
  }

  append(items: Array<QueueTrack>): void {
    items.forEach((item: QueueTrack) => {
      this.order.push(this.items.length);
      this.items.push(this.createEntry(item));
    });
    this.rebuildIndexes();
  }

  removeEntries(entryIds: Array<number>): PlaybackQueueRemovalResult {
    if (entryIds.length === 0 || this.cursor < 0) {
      return { removedCurrent: false, current: this.current() };
    }
    const selectedIds = new Set<number>(entryIds);
    const orderedEntries = this.order.map((itemIndex: number): QueueEntry => this.items[itemIndex]);
    const currentEntry = orderedEntries[this.cursor];
    const remainingOrdered = orderedEntries.filter((entry: QueueEntry): boolean =>
      !selectedIds.has(entry.queueEntryId));
    const removedCurrent = currentEntry !== undefined && selectedIds.has(currentEntry.queueEntryId);
    if (remainingOrdered.length === 0) {
      this.clear();
      return { removedCurrent: removedCurrent };
    }
    let targetEntryId = currentEntry.queueEntryId;
    if (removedCurrent) {
      for (let index = this.cursor + 1; index < orderedEntries.length; index += 1) {
        if (!selectedIds.has(orderedEntries[index].queueEntryId)) {
          targetEntryId = orderedEntries[index].queueEntryId;
          break;
        }
      }
      if (selectedIds.has(targetEntryId)) {
        for (let index = this.cursor - 1; index >= 0; index -= 1) {
          if (!selectedIds.has(orderedEntries[index].queueEntryId)) {
            targetEntryId = orderedEntries[index].queueEntryId;
            break;
          }
        }
      }
    }
    this.items = this.items.filter((entry: QueueEntry): boolean =>
      !selectedIds.has(entry.queueEntryId));
    const itemIndexByEntryId = new Map<number, number>();
    this.items.forEach((entry: QueueEntry, itemIndex: number): void => {
      itemIndexByEntryId.set(entry.queueEntryId, itemIndex);
    });
    this.order = remainingOrdered.map((entry: QueueEntry): number =>
      itemIndexByEntryId.get(entry.queueEntryId) as number);
    this.cursor = remainingOrdered.findIndex((entry: QueueEntry): boolean =>
      entry.queueEntryId === targetEntryId);
    this.rebuildIndexes();
    return { removedCurrent: removedCurrent, current: this.current() };
  }

  playbackWindow(radius: number, repeatMode: RepeatMode): PlaybackQueueWindow {
    const result: Array<QueueTrack> = [];
    if (this.cursor < 0 || this.order.length === 0) {
      return { items: result, currentIndex: -1 };
    }
    if (repeatMode === RepeatMode.ALL && this.order.length > 1) {
      for (let offset = -radius; offset <= radius; offset += 1) {
        const index = (this.cursor + offset + this.order.length) % this.order.length;
        result.push(this.items[this.order[index]].track);
      }
      return { items: result, currentIndex: radius };
    }
    const start = Math.max(0, this.cursor - radius);
    const end = Math.min(this.order.length, this.cursor + radius + 1);
    for (let index = start; index < end; index += 1) {
      result.push(this.items[this.order[index]].track);
    }
    return {
      items: result,
      currentIndex: this.cursor - start
    };
  }

  updateArtworkPalette(reference: QueueTrack, primary: string, secondary: string,
    accent: string): Array<number> {
    const updatedItemIndices: Set<number> = new Set<number>();
    this.items.forEach((entry: QueueEntry, itemIndex: number): void => {
      if (!PlaybackQueue.sameArtwork(entry.track, reference) ||
        (entry.track.palettePrimary === primary &&
          entry.track.paletteSecondary === secondary &&
          entry.track.paletteAccent === accent)) {
        return;
      }
      entry.track.palettePrimary = primary;
      entry.track.paletteSecondary = secondary;
      entry.track.paletteAccent = accent;
      updatedItemIndices.add(itemIndex);
    });
    const updatedOrderIndices: Array<number> = [];
    this.order.forEach((itemIndex: number, orderIndex: number): void => {
      if (updatedItemIndices.has(itemIndex)) {
        updatedOrderIndices.push(orderIndex);
      }
    });
    return updatedOrderIndices;
  }

  clear(): void {
    this.items = [];
    this.order = [];
    this.cursor = -1;
    this.firstItemIndexById.clear();
    this.cursorByEntryId.clear();
  }

  private itemAtCursor(cursor: number): QueueTrack | undefined {
    if (cursor < 0 || cursor >= this.order.length) {
      return undefined;
    }
    return this.items[this.order[cursor]].track;
  }

  private rebuildIndexes(): void {
    this.rebuildItemIndex();
    this.rebuildCursorIndex();
  }

  private rebuildItemIndex(): void {
    this.firstItemIndexById.clear();
    this.items.forEach((entry: QueueEntry, itemIndex: number) => {
      if (!this.firstItemIndexById.has(entry.track.id)) {
        this.firstItemIndexById.set(entry.track.id, itemIndex);
      }
    });
  }

  private rebuildCursorIndex(): void {
    this.cursorByEntryId.clear();
    this.order.forEach((itemIndex: number, orderCursor: number) => {
      this.cursorByEntryId.set(this.items[itemIndex].queueEntryId, orderCursor);
    });
  }

  private createEntry(track: QueueTrack): QueueEntry {
    const entry: QueueEntry = {
      queueEntryId: this.nextEntryId,
      track: track
    };
    this.nextEntryId += 1;
    return entry;
  }

  private static sameArtwork(left: QueueTrack, right: QueueTrack): boolean {
    if (left.largeArtworkHash.length > 0 && right.largeArtworkHash.length > 0) {
      return left.largeArtworkHash === right.largeArtworkHash;
    }
    if (left.smallArtworkHash.length > 0 && right.smallArtworkHash.length > 0) {
      return left.smallArtworkHash === right.smallArtworkHash;
    }
    if (left.largeArtworkPath.length > 0 && right.largeArtworkPath.length > 0) {
      return left.largeArtworkPath === right.largeArtworkPath;
    }
    return left.smallArtworkPath.length > 0 &&
      left.smallArtworkPath === right.smallArtworkPath;
  }

  private buildOrder(currentIndex: number, shuffleEnabled: boolean): Array<number> {
    const remainder: Array<number> = [];
    for (let index = 0; index < this.items.length; index += 1) {
      if (index !== currentIndex) {
        remainder.push(index);
      }
    }
    if (shuffleEnabled) {
      for (let index = remainder.length - 1; index > 0; index -= 1) {
        const target = Math.floor(Math.random() * (index + 1));
        const temporary = remainder[index];
        remainder[index] = remainder[target];
        remainder[target] = temporary;
      }
    } else {
      const sequential: Array<number> = [];
      for (let index = 0; index < this.items.length; index += 1) {
        sequential.push(index);
      }
      return sequential;
    }
    return [currentIndex].concat(remainder);
  }

  private static isPermutation(positions: Array<number>): boolean {
    const seen = new Set<number>();
    for (let index = 0; index < positions.length; index += 1) {
      const position = positions[index];
      if (!Number.isInteger(position) || position < 0 || position >= positions.length ||
        seen.has(position)) {
        return false;
      }
      seen.add(position);
    }
    return seen.size === positions.length;
  }
}
