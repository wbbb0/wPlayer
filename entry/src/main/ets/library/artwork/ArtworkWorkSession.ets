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
  private readonly idleWaiters: Array<() => void> = [];
  private running: boolean = false;
  private cancelled: boolean = false;
  private processingEnabled: boolean;

  constructor(processor: ArtworkWorkProcessor, startImmediately: boolean = true) {
    this.processor = processor;
    this.processingEnabled = startImmediately;
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
    while (this.queue.length > 0) {
      this.queue.shift()?.resolve(ArtworkWorkSession.skipped());
    }
    this.notifyIdleIfNeeded();
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  hasScheduledWork(): boolean {
    return this.running || this.queue.length > 0;
  }

  waitForIdle(): Promise<void> {
    if (!this.running && this.queue.length === 0) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.idleWaiters.push(resolve);
    });
  }

  private start(): void {
    if (this.running) {
      return;
    }
    this.run().catch((_error: Object): void => {
      this.running = false;
      this.cancel();
      this.notifyIdleIfNeeded();
    });
  }

  private async run(): Promise<void> {
    this.running = true;
    try {
      while (this.queue.length > 0 && !this.cancelled) {
        const item = this.queue.shift();
        if (item === undefined) {
          continue;
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
      if (this.cancelled) {
        while (this.queue.length > 0) {
          this.queue.shift()?.resolve(ArtworkWorkSession.skipped());
        }
      }
    } finally {
      this.running = false;
      this.notifyIdleIfNeeded();
    }
  }

  private notifyIdleIfNeeded(): void {
    if (this.running || this.queue.length > 0) {
      return;
    }
    const waiters = this.idleWaiters.splice(0, this.idleWaiters.length);
    waiters.forEach((resolve: () => void) => resolve());
  }

  private static skipped(): ArtworkWorkResult {
    return {
      outcome: ArtworkWorkOutcome.SKIPPED,
      sourceHasArtwork: false,
      errorMessage: ''
    };
  }
}
