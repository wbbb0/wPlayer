import { RequestEpoch } from '../support/RequestEpoch';

export type ArtworkPrefetchContinuation = () => boolean;
export type ArtworkPrefetchWork = (
  shouldContinue: ArtworkPrefetchContinuation
) => Promise<void>;
export type ArtworkPrefetchScheduler = (callback: () => void, delayMs: number) => number;
export type ArtworkPrefetchCanceller = (timerId: number) => void;

export class ArtworkPrefetchCoordinator {
  private readonly delayMs: number;
  private readonly scheduler: ArtworkPrefetchScheduler;
  private readonly canceller: ArtworkPrefetchCanceller;
  private readonly epoch: RequestEpoch = new RequestEpoch();
  private timerId?: number;

  constructor(delayMs: number,
    scheduler: ArtworkPrefetchScheduler = (callback: () => void, delay: number): number =>
      setTimeout(callback, delay),
    canceller: ArtworkPrefetchCanceller = (timerId: number): void => clearTimeout(timerId)) {
    this.delayMs = Math.max(0, delayMs);
    this.scheduler = scheduler;
    this.canceller = canceller;
  }

  schedule(work: ArtworkPrefetchWork): void {
    this.invalidate();
    const token = this.epoch.current();
    this.timerId = this.scheduler((): void => {
      this.timerId = undefined;
      if (!this.epoch.isCurrent(token)) {
        return;
      }
      work((): boolean => this.epoch.isCurrent(token)).catch((): void => {});
    }, this.delayMs);
  }

  invalidate(): void {
    this.epoch.invalidate();
    if (this.timerId !== undefined) {
      this.canceller(this.timerId);
      this.timerId = undefined;
    }
  }
}
