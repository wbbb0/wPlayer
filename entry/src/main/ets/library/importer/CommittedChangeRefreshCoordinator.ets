export type CommittedChangeRefresh = () => Promise<void>;

/** Serializes and coalesces projection refreshes while a long-running task keeps committing results. */
export class CommittedChangeRefreshCoordinator {
  private readonly refresh: CommittedChangeRefresh;
  private readonly batchSize: number;
  private committedRevision: number = 0;
  private requestedRevision: number = 0;
  private publishedRevision: number = 0;
  private pump?: Promise<void>;

  constructor(refresh: CommittedChangeRefresh, batchSize: number) {
    this.refresh = refresh;
    this.batchSize = Math.max(1, batchSize);
  }

  recordCommitted(count: number = 1): void {
    if (count <= 0) {
      return;
    }
    this.committedRevision += count;
    if (this.requestedRevision === 0 ||
      this.committedRevision - this.requestedRevision >= this.batchSize) {
      this.requestedRevision = this.committedRevision;
      this.ensurePump();
    }
  }

  async flush(): Promise<void> {
    if (this.committedRevision > this.requestedRevision) {
      this.requestedRevision = this.committedRevision;
    }
    this.ensurePump();
    if (this.pump !== undefined) {
      await this.pump;
    }
  }

  private ensurePump(): void {
    if (this.pump !== undefined || this.requestedRevision <= this.publishedRevision) {
      return;
    }
    const operation = this.runPump();
    this.pump = operation;
    operation.then((): void => {
      this.completePump(operation, true);
    }, (): void => {
      this.completePump(operation, false);
    });
  }

  private async runPump(): Promise<void> {
    while (this.publishedRevision < this.requestedRevision) {
      const targetRevision = this.requestedRevision;
      await this.refresh();
      this.publishedRevision = targetRevision;
    }
  }

  private completePump(operation: Promise<void>, continuePending: boolean): void {
    if (this.pump !== operation) {
      return;
    }
    this.pump = undefined;
    if (continuePending) {
      this.ensurePump();
    }
  }
}
