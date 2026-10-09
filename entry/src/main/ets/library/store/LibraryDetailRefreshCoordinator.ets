export interface LibraryDetailContentSource {
  libraryContentRevision: number;
  addContentChangeListener(listener: () => void): void;
  removeContentChangeListener(listener: () => void): void;
}

export interface LibraryDetailRefreshTarget<T> {
  loading: boolean;
  error: string;
  commitDetail(value: T): void;
}

/** Keeps retained detail pages coherent with committed library revisions. */
export class LibraryDetailRefreshCoordinator<T> {
  private activeSource?: LibraryDetailContentSource;
  private activeTarget?: LibraryDetailRefreshTarget<T>;
  private cachedSource?: LibraryDetailContentSource;
  private cachedTarget?: LibraryDetailRefreshTarget<T>;
  private cachedRevision: number = -1;
  private epoch: number = 0;
  private pending?: Promise<void>;
  private dirty: boolean = false;
  private read?: () => Promise<T>;
  private readonly listener: () => void = (): void => {
    this.dirty = true;
    this.request();
  };

  activate(source: LibraryDetailContentSource, read: () => Promise<T>,
    target: LibraryDetailRefreshTarget<T>): Promise<void> {
    if (this.activeSource !== source || this.activeTarget !== target) {
      this.activeSource?.removeContentChangeListener(this.listener);
      if (this.activeTarget !== undefined) {
        this.activeTarget.loading = false;
      }
      this.epoch += 1;
      this.pending = undefined;
      this.activeSource = source;
      this.activeTarget = target;
      source.addContentChangeListener(this.listener);
    }
    this.read = read;
    return this.request();
  }

  refresh(source: LibraryDetailContentSource, read: () => Promise<T>,
    target: LibraryDetailRefreshTarget<T>): Promise<void> {
    this.dirty = true;
    return this.activate(source, read, target);
  }

  deactivate(source: LibraryDetailContentSource): void {
    if (this.activeSource === source) {
      source.removeContentChangeListener(this.listener);
      this.activeSource = undefined;
      this.read = undefined;
      this.epoch += 1;
      this.pending = undefined;
      this.dirty = false;
      if (this.activeTarget !== undefined) {
        this.activeTarget.loading = false;
      }
      this.activeTarget = undefined;
    }
  }

  currentEpoch(): number {
    return this.epoch;
  }

  isCurrent(source: LibraryDetailContentSource, epoch: number): boolean {
    return this.activeSource === source && this.epoch === epoch;
  }

  private request(): Promise<void> {
    const source = this.activeSource;
    const read = this.read;
    const target = this.activeTarget;
    if (source === undefined || read === undefined || target === undefined) {
      return Promise.resolve();
    }
    if (this.pending !== undefined) {
      return this.pending;
    }
    if (!this.dirty && this.cachedSource === source && this.cachedTarget === target &&
      this.cachedRevision === source.libraryContentRevision) {
      return Promise.resolve();
    }
    const epoch = ++this.epoch;
    this.pending = this.load(source, read, target, epoch).finally((): void => {
      if (this.isCurrent(source, epoch)) {
        this.pending = undefined;
        target.loading = false;
        if (this.dirty) {
          this.request();
        }
      }
    });
    return this.pending;
  }

  private async load(source: LibraryDetailContentSource, read: () => Promise<T>,
    target: LibraryDetailRefreshTarget<T>, epoch: number): Promise<void> {
    target.loading = true;
    target.error = '';
    while (this.isCurrent(source, epoch)) {
      const revision = source.libraryContentRevision;
      this.dirty = false;
      try {
        const value = await read();
        if (!this.isCurrent(source, epoch)) {
          return;
        }
        if (this.dirty || revision !== source.libraryContentRevision) {
          continue;
        }
        target.commitDetail(value);
        this.cachedSource = source;
        this.cachedTarget = target;
        this.cachedRevision = revision;
        return;
      } catch (error) {
        if (!this.isCurrent(source, epoch)) {
          return;
        }
        if (this.dirty || revision !== source.libraryContentRevision) {
          continue;
        }
        this.cachedRevision = -1;
        target.error = error instanceof Error ? error.message : `${error}`;
        return;
      }
    }
  }
}
