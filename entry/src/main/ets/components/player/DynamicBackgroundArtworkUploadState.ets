export class DynamicBackgroundArtworkUploadTicket {
  readonly key: string;
  readonly nativeContextGeneration: number;
  readonly uploadGeneration: number;

  constructor(key: string, nativeContextGeneration: number, uploadGeneration: number) {
    this.key = key;
    this.nativeContextGeneration = nativeContextGeneration;
    this.uploadGeneration = uploadGeneration;
  }
}

export class DynamicBackgroundArtworkUploadState {
  private uploadedKey: string = '';
  private inProgressKey: string = '';
  private refreshPending: boolean = false;
  private uploadGeneration: number = 0;
  private nativeContextGeneration: number = 0;

  attachContext(): void {
    this.nativeContextGeneration += 1;
    this.uploadGeneration += 1;
    this.uploadedKey = '';
    this.inProgressKey = '';
    this.refreshPending = false;
  }

  detachContext(): void {
    this.nativeContextGeneration += 1;
    this.uploadGeneration += 1;
    this.uploadedKey = '';
    this.inProgressKey = '';
    this.refreshPending = false;
  }

  cancel(): void {
    this.uploadGeneration += 1;
    this.inProgressKey = '';
    this.refreshPending = false;
  }

  needsUpload(key: string): boolean {
    return key.length > 0 && key !== this.uploadedKey;
  }

  hasUploadInProgress(): boolean {
    return this.inProgressKey.length > 0;
  }

  noteDesiredKey(key: string): void {
    if (this.inProgressKey.length > 0 && key !== this.inProgressKey) {
      this.refreshPending = true;
    }
  }

  begin(key: string): DynamicBackgroundArtworkUploadTicket {
    this.refreshPending = false;
    this.inProgressKey = key;
    this.uploadGeneration += 1;
    return new DynamicBackgroundArtworkUploadTicket(
      key,
      this.nativeContextGeneration,
      this.uploadGeneration
    );
  }

  canCommit(ticket: DynamicBackgroundArtworkUploadTicket, currentKey: string,
    active: boolean, contextAvailable: boolean): boolean {
    return active && contextAvailable &&
      ticket.key === currentKey &&
      ticket.nativeContextGeneration === this.nativeContextGeneration &&
      ticket.uploadGeneration === this.uploadGeneration;
  }

  markUploaded(ticket: DynamicBackgroundArtworkUploadTicket): void {
    if (ticket.uploadGeneration === this.uploadGeneration) {
      this.uploadedKey = ticket.key;
    }
  }

  finish(ticket: DynamicBackgroundArtworkUploadTicket): boolean {
    if (ticket.uploadGeneration !== this.uploadGeneration) {
      return false;
    }
    const shouldRefresh = this.refreshPending;
    if (this.inProgressKey === ticket.key) {
      this.inProgressKey = '';
    }
    this.refreshPending = false;
    return shouldRefresh;
  }
}
