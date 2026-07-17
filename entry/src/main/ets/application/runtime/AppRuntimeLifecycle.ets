export interface RuntimeActivation {
  lease: number;
  completion: Promise<void>;
}

/**
 * Serializes the process-wide runtime lifecycle independently of UIAbility instances.
 * A newer activation invalidates shutdown work queued by an older ability generation.
 */
export class AppRuntimeLifecycle {
  private operationTail: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private activeLease: number = 0;

  activate(initialize: () => Promise<void>): RuntimeActivation {
    const lease = ++this.generation;
    this.activeLease = lease;
    const completion = this.enqueue(async (): Promise<void> => {
      if (this.activeLease !== lease) {
        return;
      }
      await initialize();
    });
    return { lease: lease, completion: completion };
  }

  deactivate(lease: number, shutdown: () => Promise<void>): Promise<void> {
    if (lease <= 0) {
      return Promise.resolve();
    }
    if (this.activeLease === lease) {
      this.activeLease = 0;
    }
    return this.enqueue(async (): Promise<void> => {
      if (this.generation !== lease || this.activeLease !== 0) {
        return;
      }
      await shutdown();
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const pending = this.operationTail.then(operation);
    this.operationTail = pending.catch((_error: Object) => {
      // Keep the lifecycle queue usable after the caller observes a failed operation.
    });
    return pending;
  }
}

export const appRuntimeLifecycle: AppRuntimeLifecycle = new AppRuntimeLifecycle();
