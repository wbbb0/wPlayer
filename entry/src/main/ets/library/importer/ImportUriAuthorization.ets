import { ReadPermissionResult } from './MediaPickerService';

export interface ReauthorizationResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
  errorMessage: string;
}

/** Distinguishes new grants from authorizations already owned by library records. */
export class ImportUriAuthorization {
  private readonly existingUris: Set<string> = new Set<string>();
  private readonly activate: (uris: Array<string>) => Promise<ReadPermissionResult>;
  private readonly restore: (uris: Array<string>) => Promise<void>;
  private readonly isCancelled: () => boolean;

  constructor(activate: (uris: Array<string>) => Promise<ReadPermissionResult>,
    restore: (uris: Array<string>) => Promise<void>, isCancelled: () => boolean) {
    this.activate = activate;
    this.restore = restore;
    this.isCancelled = isCancelled;
  }

  retainExisting(uris: Array<string>): void {
    uris.forEach((uri: string): void => { this.existingUris.add(uri); });
  }

  existing(uris: Array<string>): Array<string> {
    return uris.filter((uri: string): boolean => this.existingUris.has(uri));
  }

  newUris(uris: Array<string>): Array<string> {
    return uris.filter((uri: string): boolean => !this.existingUris.has(uri));
  }

  async restoreExisting(uris: Array<string>): Promise<ReauthorizationResult> {
    const existing = this.existing(uris);
    if (existing.length === 0 || this.isCancelled()) {
      return { successfulUris: [], failedUris: [], errorMessage: '' };
    }
    const activated = await this.activate(existing);
    if (activated.cancelled || this.isCancelled()) {
      return { successfulUris: [], failedUris: [], errorMessage: '' };
    }
    try {
      if (activated.successfulUris.length > 0) {
        await this.restore(activated.successfulUris);
      }
      return {
        successfulUris: activated.successfulUris,
        failedUris: activated.failedUris,
        errorMessage: '无法激活文件读取授权'
      };
    } catch (error) {
      return {
        successfulUris: [],
        failedUris: existing,
        errorMessage: error instanceof Error ? error.message : `${error}`
      };
    }
  }
}
