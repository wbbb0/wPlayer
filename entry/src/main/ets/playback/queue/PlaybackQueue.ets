import { QueueBuildPhase, QueueTrack, RepeatMode } from '../model/PlaybackModels';

export interface PlaybackQueueWindow {
  items: Array<QueueTrack>;
  currentIndex: number;
}

export class PlaybackQueue {
  private items: Array<QueueTrack> = [];
  private order: Array<number> = [];
  private cursor: number = -1;

  build(items: Array<QueueTrack>, currentTrackId: number, shuffleEnabled: boolean): QueueBuildPhase {
    if (items.length === 0) {
      this.clear();
      return QueueBuildPhase.EMPTY;
    }
    this.items = items.slice();
    const currentIndex = this.items.findIndex((item: QueueTrack) => item.id === currentTrackId);
    if (currentIndex < 0) {
      this.clear();
      return QueueBuildPhase.FAILED;
    }
    this.order = this.buildOrder(currentIndex, shuffleEnabled);
    this.cursor = shuffleEnabled ? 0 : currentIndex;
    return QueueBuildPhase.READY;
  }

  setShuffle(enabled: boolean, currentTrackId: number): void {
    if (this.items.length === 0) {
      return;
    }
    const currentIndex = this.items.findIndex((item: QueueTrack) => item.id === currentTrackId);
    if (currentIndex < 0) {
      return;
    }
    this.order = this.buildOrder(currentIndex, enabled);
    this.cursor = enabled ? 0 : currentIndex;
  }

  current(): QueueTrack | undefined {
    return this.itemAtCursor(this.cursor);
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

  playbackWindow(radius: number, repeatMode: RepeatMode): PlaybackQueueWindow {
    const result: Array<QueueTrack> = [];
    if (this.cursor < 0 || this.order.length === 0) {
      return { items: result, currentIndex: -1 };
    }
    if (repeatMode === RepeatMode.ALL && this.order.length > 1) {
      for (let offset = -radius; offset <= radius; offset += 1) {
        const index = (this.cursor + offset + this.order.length) % this.order.length;
        result.push(this.items[this.order[index]]);
      }
      return { items: result, currentIndex: radius };
    }
    const start = Math.max(0, this.cursor - radius);
    const end = Math.min(this.order.length, this.cursor + radius + 1);
    for (let index = start; index < end; index += 1) {
      result.push(this.items[this.order[index]]);
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
  }

  private itemAtCursor(cursor: number): QueueTrack | undefined {
    if (cursor < 0 || cursor >= this.order.length) {
      return undefined;
    }
    return this.items[this.order[cursor]];
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
