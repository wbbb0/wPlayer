import { RequestEpoch } from '../support/RequestEpoch';

/**
 * Owns validity for asynchronous PiP work across reusable runtime lifecycles.
 */
export class PlaybackPictureInPictureLifecycle {
  private readonly epoch: RequestEpoch = new RequestEpoch();
  private disposing: boolean = false;

  current(): number {
    return this.epoch.current();
  }

  canStartOperation(): boolean {
    return !this.disposing;
  }

  isCurrent(epoch: number): boolean {
    return !this.disposing && this.epoch.isCurrent(epoch);
  }

  ownsController<T extends Object>(epoch: number, controller: T,
    currentController: T | undefined): boolean {
    return this.isCurrent(epoch) && controller === currentController;
  }

  beginDispose(): void {
    this.disposing = true;
    this.epoch.invalidate();
  }

  async runDisposal(pendingCreation: Promise<void> | undefined,
    pendingEnter: Promise<void> | undefined, pendingStop: Promise<void> | undefined,
    cleanup: (pendingStopSucceeded: boolean) => Promise<void>): Promise<void> {
    await this.settle(pendingCreation);
    await this.settle(pendingEnter);
    const pendingStopSucceeded = await this.settle(pendingStop);
    await cleanup(pendingStopSucceeded);
  }

  finishDispose(): void {
    this.disposing = false;
  }

  private async settle(operation: Promise<void> | undefined): Promise<boolean> {
    if (operation === undefined) {
      return false;
    }
    try {
      await operation;
      return true;
    } catch (_error) {
      // The operation owner reports its failure; disposal still has to continue.
      return false;
    }
  }
}
