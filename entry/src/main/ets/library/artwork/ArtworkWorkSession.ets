import { ParsedMetadata } from '../model/LibraryModels';

export interface ArtworkWorkRequest {
  trackId: number;
  uri: string;
  fileSize: number;
  modifiedAt: number;
  metadata?: ParsedMetadata;
}

export enum ArtworkWorkOutcome {
  COMPLETED = 'completed',
  FAILED = 'failed',
  SKIPPED = 'skipped',
  STALE = 'stale'
}

export interface ArtworkWorkResult {
  outcome: ArtworkWorkOutcome;
  sourceHasArtwork: boolean;
  errorMessage: string;
}

export interface ArtworkWorkCancellation {
  isCancelled(): boolean;
}

export type ArtworkWorkProcessor = (
  request: ArtworkWorkRequest,
  cancellation: ArtworkWorkCancellation
) => Promise<ArtworkWorkResult>;

interface QueuedArtworkWork {
  request: ArtworkWorkRequest;
  resolve: (result: ArtworkWorkResult) => void;
}

export class ArtworkWorkSession implements ArtworkWorkCancellation {
  private readonly processor: ArtworkWorkProcessor;
  private readonly queue: Array<QueuedArtworkWork> = [];
  private queueHead: number = 0;
  private readonly idleWaiters: Array<() => void> = [];
  private runningWorkers: number = 0;
  private cancelled: boolean = false;
  private processingEnabled: boolean;
  private readonly concurrency: number;

  constructor(processor: ArtworkWorkProcessor, startImmediately: boolean = true,
    concurrency: number = 1) {
    this.processor = processor;
    this.processingEnabled = startImmediately;
    this.concurrency = Math.max(1, concurrency);
  }

  enqueue(request: ArtworkWorkRequest): Promise<ArtworkWorkResult> {
    if (this.cancelled) {
      return Promise.resolve(ArtworkWorkSession.skipped());
    }
    return new Promise<ArtworkWorkResult>((resolve: (result: ArtworkWorkResult) => void) => {
      this.queue.push({ request: request, resolve: resolve });
      if (this.processingEnabled) {
        this.start();
      }
    });
  }

  startProcessing(): void {
    if (this.cancelled || this.processingEnabled) {
      return;
    }
    this.processingEnabled = true;
    this.start();
  }

  cancel(): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    for (let index = this.queueHead; index < this.queue.length; index += 1) {
      this.queue[index].resolve(ArtworkWorkSession.skipped());
    }
    this.queue.splice(0, this.queue.length);
    this.queueHead = 0;
    this.notifyIdleIfNeeded();
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  hasScheduledWork(): boolean {
    return this.runningWorkers > 0 || this.pendingCount() > 0;
  }

  waitForIdle(): Promise<void> {
    if (this.runningWorkers === 0 && this.pendingCount() === 0) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.idleWaiters.push(resolve);
    });
  }

  private start(): void {
    if (!this.processingEnabled || this.cancelled) {
      return;
    }
    while (this.runningWorkers < this.concurrency && this.pendingCount() > 0) {
      this.runningWorkers += 1;
      this.runWorker().catch((_error: Object): void => {
        this.cancel();
      }).finally((): void => {
        this.runningWorkers -= 1;
        this.start();
        this.notifyIdleIfNeeded();
      });
    }
  }

  private async runWorker(): Promise<void> {
    while (this.pendingCount() > 0 && !this.cancelled) {
      const item = this.takeNext();
      if (item === undefined) {
        return;
      }
      try {
        item.resolve(await this.processor(item.request, this));
      } catch (error) {
        item.resolve({
          outcome: ArtworkWorkOutcome.FAILED,
          sourceHasArtwork: false,
          errorMessage: error instanceof Error ? error.message : `${error}`
        });
      }
    }
  }

  private takeNext(): QueuedArtworkWork | undefined {
    if (this.queueHead >= this.queue.length) {
      return undefined;
    }
    const item = this.queue[this.queueHead];
    this.queueHead += 1;
    if (this.queueHead >= this.queue.length) {
      this.queue.splice(0, this.queue.length);
      this.queueHead = 0;
    } else if (this.queueHead >= 256 && this.queueHead * 2 >= this.queue.length) {
      this.queue.splice(0, this.queueHead);
      this.queueHead = 0;
    }
    return item;
  }

  private pendingCount(): number {
    return this.queue.length - this.queueHead;
  }

  private notifyIdleIfNeeded(): void {
    if (this.runningWorkers > 0 || this.pendingCount() > 0) {
      return;
    }
    const waiters = this.idleWaiters.splice(0, this.idleWaiters.length);
    waiters.forEach((resolve: () => void) => {
      resolve();
    });
  }

  private static skipped(): ArtworkWorkResult {
    return {
      outcome: ArtworkWorkOutcome.SKIPPED,
      sourceHasArtwork: false,
      errorMessage: ''
    };
  }
}
