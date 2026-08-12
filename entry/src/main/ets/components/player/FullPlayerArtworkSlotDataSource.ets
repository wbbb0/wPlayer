import { QueuePositionSlot } from '../../playback/model/PlaybackModels';

export class FullPlayerArtworkSlotDataSource implements IDataSource {
  private slots: Array<QueuePositionSlot> = [];
  private readonly listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.slots.length;
  }

  getData(index: number): QueuePositionSlot {
    return this.slots[index];
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

  syncCount(count: number): void {
    const targetCount = Math.max(0, Math.floor(count));
    if (targetCount === this.slots.length) {
      return;
    }
    this.slots = Array.from({ length: targetCount },
      (_value: undefined, index: number): QueuePositionSlot => new QueuePositionSlot(index));
    const operations: Array<DataOperation> = [{ type: DataOperationType.RELOAD }];
    this.listeners.forEach((listener: DataChangeListener): void =>
      listener.onDatasetChange(operations));
  }
}
