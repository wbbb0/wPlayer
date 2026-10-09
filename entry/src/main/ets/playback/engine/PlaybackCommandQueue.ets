import { RequestEpoch } from '../support/RequestEpoch';

/** Serializes native commands; only the source that submitted work may publish its failure. */
export class PlaybackCommandQueue {
  private tail: Promise<void> = Promise.resolve();
  private readonly epoch: RequestEpoch;
  private readonly onFailure: (error: Object) => void;
  private readonly canPublishFailure: (epoch: number) => boolean;

  constructor(epoch: RequestEpoch, onFailure: (error: Object) => void,
    canPublishFailure: (epoch: number) => boolean = (_epoch: number): boolean => true) {
    this.epoch = epoch;
    this.onFailure = onFailure;
    this.canPublishFailure = canPublishFailure;
  }

  enqueue(epoch: number, operation: () => Promise<void>): Promise<void> {
    const pending = this.tail.then(async (): Promise<void> => {
      if (!this.epoch.isCurrent(epoch)) {
        return;
      }
      try {
        await operation();
      } catch (error) {
        if (!this.epoch.isCurrent(epoch)) {
          return;
        }
        if (this.canPublishFailure(epoch)) {
          this.onFailure(error);
        }
        throw error instanceof Error ? error : new Error(`${error}`);
      }
    });
    this.tail = pending.catch((): void => {});
    return pending;
  }

  async flush(): Promise<void> {
    await this.tail;
  }
}
