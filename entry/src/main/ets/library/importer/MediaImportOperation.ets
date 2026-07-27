import {
  MediaImportCancellation,
  MediaImportWorkQueue
} from './MediaImportContracts';

export type {
  MediaImportCancellation,
  MediaImportWorkQueue
} from './MediaImportContracts';

export class MediaImportOperation implements MediaImportCancellation {
  private cancelled: boolean = false;
  private queue?: MediaImportWorkQueue;

  isCancelled(): boolean {
    return this.cancelled;
  }

  throwIfCancelled(): void {
    if (this.cancelled) {
      throw new Error('Media import operation cancelled');
    }
  }

  attachQueue(queue: MediaImportWorkQueue): void {
    if (this.queue !== undefined && this.queue !== queue) {
      throw new Error('A different work queue is already attached');
    }
    this.queue = queue;
    if (this.cancelled) {
      queue.cancel();
    }
  }

  detachQueue(queue: MediaImportWorkQueue): void {
    if (this.queue === queue) {
      this.queue = undefined;
    }
  }

  cancel(): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.queue?.cancel();
  }

  async cancelAndWait(): Promise<void> {
    this.cancel();
    const queue = this.queue;
    if (queue !== undefined) {
      await queue.waitForIdle();
      this.detachQueue(queue);
    }
  }
}
