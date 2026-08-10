export type AsyncWorkProcessor<T> = (work: T) => Promise<void>;

enum AsyncWorkQueueState {
  OPEN = 0,
  CLOSING = 1,
  CLOSED = 2
}

/**
 * One-shot bounded admission queue for asynchronous work.
 *
 * A slot is reserved before enqueue() yields, so concurrent producers cannot
 * over-admit work. Processor failures are retained until closeAndWait() while
 * later slots continue draining, allowing callers to publish every item-level
 * result before the operation terminates.
 */
export class BoundedAsyncWorkQueue<T> {
  private readonly processor: AsyncWorkProcessor<T>;
  private readonly slots: Array<Promise<void> | undefined>;
  private nextSlot: number = 0;
  private firstError?: Error;
  private state: AsyncWorkQueueState = AsyncWorkQueueState.OPEN;
  private closePromise?: Promise<void>;

  constructor(capacity: number, processor: AsyncWorkProcessor<T>) {
    this.processor = processor;
    this.slots = new Array<Promise<void> | undefined>(Math.max(1, capacity));
  }

  async enqueue(work: T): Promise<void> {
    if (this.state !== AsyncWorkQueueState.OPEN) {
      throw new Error('Cannot enqueue work after the queue starts closing');
    }
    const slot = this.nextSlot;
    this.nextSlot = (this.nextSlot + 1) % this.slots.length;
    const previous = this.slots[slot] ?? Promise.resolve();
    const operation = previous.then((): Promise<void> => this.processor(work))
      .catch((error: Object): void => {
        if (this.firstError === undefined) {
          this.firstError = BoundedAsyncWorkQueue.asError(error);
        }
      });
    // Reserve the slot before awaiting its previous owner. This is required
    // when several scan workers enqueue concurrently on the ArkTS event loop.
    this.slots[slot] = operation;
    await previous;
  }

  closeAndWait(): Promise<void> {
    if (this.closePromise !== undefined) {
      return this.closePromise;
    }
    this.state = AsyncWorkQueueState.CLOSING;
    const operations = this.slots.filter(
      (operation: Promise<void> | undefined): boolean => operation !== undefined
    ).map((operation: Promise<void> | undefined): Promise<void> => operation as Promise<void>);
    this.closePromise = this.finishClose(operations);
    return this.closePromise;
  }

  private async finishClose(operations: Array<Promise<void>>): Promise<void> {
    try {
      await Promise.all(operations);
      if (this.firstError !== undefined) {
        throw this.firstError;
      }
    } finally {
      this.state = AsyncWorkQueueState.CLOSED;
    }
  }

  private static asError(error: Object): Error {
    return error instanceof Error ? error : new Error(`${error}`);
  }
}
