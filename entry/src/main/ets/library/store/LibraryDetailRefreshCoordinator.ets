export interface LibraryDetailContentSource {
  libraryContentRevision: number;
  addContentChangeListener(listener: () => void): void;
  removeContentChangeListener(listener: () => void): void;
}

/** Keeps retained detail pages coherent with committed library revisions. */
export class LibraryDetailRefreshCoordinator<T> {
  private activeSource?: LibraryDetailContentSource;
  private cachedSource?: LibraryDetailContentSource;
  private cachedRevision: number = -1;
  private epoch: number = 0;
  private pending?: Promise<void>;
  private dirty: boolean = false;
  private read?: () => Promise<T>;
  private readonly commit: (value: T) => void;
  private readonly setLoading: (loading: boolean) => void;
  private readonly setError: (message: string) => void;
  private readonly listener: () => void = (): void => {
    this.dirty = true;
    this.request();
  };

  constructor(commit: (value: T) => void, setLoading: (loading: boolean) => void,
    setError: (message: string) => void) {
    this.commit = commit;
    this.setLoading = setLoading;
    this.setError = setError;
  }

  activate(source: LibraryDetailContentSource, read: () => Promise<T>): Promise<void> {
    if (this.activeSource !== source) {
      this.activeSource?.removeContentChangeListener(this.listener);
      this.epoch += 1;
      this.pending = undefined;
      this.activeSource = source;
      source.addContentChangeListener(this.listener);
    }
    this.read = read;
    return this.request();
  }

  refresh(source: LibraryDetailContentSource, read: () => Promise<T>): Promise<void> {
    this.dirty = true;
    return this.activate(source, read);
  }

  deactivate(source: LibraryDetailContentSource): void {
    if (this.activeSource === source) {
      source.removeContentChangeListener(this.listener);
      this.activeSource = undefined;
      this.read = undefined;
      this.epoch += 1;
      this.pending = undefined;
      this.dirty = false;
      this.setLoading(false);
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
    if (source === undefined || read === undefined) {
      return Promise.resolve();
    }
    if (this.pending !== undefined) {
      return this.pending;
    }
    if (!this.dirty && this.cachedSource === source && this.cachedRevision === source.libraryContentRevision) {
      return Promise.resolve();
    }
    const epoch = ++this.epoch;
    this.pending = this.load(source, read, epoch).finally((): void => {
      if (this.isCurrent(source, epoch)) {
        this.pending = undefined;
        this.setLoading(false);
        if (this.dirty) {
          this.request();
        }
      }
    });
    return this.pending;
  }

  private async load(source: LibraryDetailContentSource, read: () => Promise<T>, epoch: number): Promise<void> {
    this.setLoading(true);
    this.setError('');
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
        this.commit(value);
        this.cachedSource = source;
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
        this.setError(error instanceof Error ? error.message : `${error}`);
        return;
      }
    }
  }
}
