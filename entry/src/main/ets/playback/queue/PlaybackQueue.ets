import { QueueBuildPhase, QueueEntry, QueueTrack, RepeatMode } from '../model/PlaybackModels';

export interface PlaybackQueueWindow {
  items: Array<QueueTrack>;
  currentIndex: number;
}

export interface PlaybackQueueSnapshot {
  entries: Array<QueueEntry>;
  currentIndex: number;
}

export class PlaybackQueue {
  private items: Array<QueueEntry> = [];
  private order: Array<number> = [];
  private cursor: number = -1;
  private nextEntryId: number = 0;
  private readonly firstItemIndexById: Map<number, number> = new Map<number, number>();
  private readonly firstCursorById: Map<number, number> = new Map<number, number>();

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

  setShuffle(enabled: boolean, currentTrackId: number): void {
    if (this.items.length === 0) {
      return;
    }
    const currentIndex = this.firstItemIndexById.get(currentTrackId);
    if (currentIndex === undefined) {
      return;
    }
    this.order = this.buildOrder(currentIndex, enabled);
    this.cursor = enabled ? 0 : currentIndex;
    this.rebuildCursorIndex();
  }

  current(): QueueTrack | undefined {
    return this.itemAtCursor(this.cursor);
  }

  select(trackId: number): QueueTrack | undefined {
    const selectedCursor = this.firstCursorById.get(trackId);
    if (selectedCursor === undefined) {
      return undefined;
    }
    this.cursor = selectedCursor;
    return this.current();
  }

  snapshot(): PlaybackQueueSnapshot {
    const snapshotEntries: Array<QueueEntry> = [];
    this.order.forEach((itemIndex: number) => {
      snapshotEntries.push(this.items[itemIndex]);
    });
    return {
      entries: snapshotEntries,
      currentIndex: this.cursor
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
    const insertedOrder: Array<number> = [];
    items.forEach((item: QueueTrack) => {
      insertedOrder.push(this.items.length);
      this.items.push(this.createEntry(item));
    });
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

  clear(): void {
    this.items = [];
    this.order = [];
    this.cursor = -1;
    this.firstItemIndexById.clear();
    this.firstCursorById.clear();
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
    this.firstCursorById.clear();
    this.order.forEach((itemIndex: number, orderCursor: number) => {
      const trackId = this.items[itemIndex].track.id;
      if (!this.firstCursorById.has(trackId)) {
        this.firstCursorById.set(trackId, orderCursor);
      }
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
}
