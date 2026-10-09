export interface PlaybackSessionResource {
  activate(): Promise<void>;
  deactivate(): Promise<void>;
  destroy(): Promise<void>;
}

/** Owns unpublished resources too, including failed or interrupted initialization. */
export class PlaybackSessionLifecycle<T extends PlaybackSessionResource> {
  private resource?: T;
  private initializing?: Promise<T | undefined>;
  private closing: boolean = false;
  private shutdownPromise?: Promise<void>;
  private readonly reportCleanupFailure: (error: Object) => void;

  constructor(reportCleanupFailure: (error: Object) => void) {
    this.reportCleanupFailure = reportCleanupFailure;
  }

  current(): T | undefined {
    return this.resource;
  }

  initialize(create: () => Promise<T>, configure: (resource: T) => Promise<void>): Promise<T | undefined> {
    if (this.closing) {
      return Promise.resolve(undefined);
    }
    if (this.resource !== undefined) {
      return Promise.resolve(this.resource);
    }
    if (this.initializing === undefined) {
      this.initializing = this.createResource(create, configure).finally((): void => {
        this.initializing = undefined;
      });
    }
    return this.initializing;
  }

  shutdown(): Promise<void> {
    if (this.shutdownPromise === undefined) {
      this.closing = true;
      this.shutdownPromise = this.closeResource();
    }
    return this.shutdownPromise;
  }

  private async createResource(create: () => Promise<T>, configure: (resource: T) => Promise<void>):
    Promise<T | undefined> {
    const resource = await create();
    let activated = false;
    try {
      if (!this.closing) {
        await configure(resource);
        if (!this.closing) {
          await resource.activate();
          activated = true;
        }
      }
      if (this.closing) {
        await this.dispose(resource, activated);
        return undefined;
      }
      this.resource = resource;
      return resource;
    } catch (error) {
      await this.dispose(resource, activated);
      throw error instanceof Error ? error : new Error(`${error}`);
    }
  }

  private async closeResource(): Promise<void> {
    try {
      await this.initializing;
    } catch (_) {
      // Initialization already disposed its unpublished resource.
    }
    const resource = this.resource;
    this.resource = undefined;
    if (resource !== undefined) {
      await this.dispose(resource, true);
    }
  }

  private async dispose(resource: T, activated: boolean): Promise<void> {
    if (activated) {
      try {
        await resource.deactivate();
      } catch (error) {
        this.reportCleanupFailure(error);
      }
    }
    try {
      await resource.destroy();
    } catch (error) {
      this.reportCleanupFailure(error);
    }
  }
}
