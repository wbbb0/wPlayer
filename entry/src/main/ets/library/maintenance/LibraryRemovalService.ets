import {
  LibraryRemovalCommit,
  LibraryRemovalRepository
} from '../data/MusicRepositoryTypes';
import { revokeReadPermissions } from '../importer/MediaPickerService';

export type ReadPermissionRevoker = (uris: Array<string>) => Promise<void>;

/**
 * Coordinates destructive library writes with Picker authorization cleanup.
 *
 * Database commit is the success boundary. Permissions are revoked only after
 * the corresponding records no longer exist, so a database rollback can never
 * leave retained records without their original file access.
 */
export class LibraryRemovalService {
  private readonly repository: LibraryRemovalRepository;
  private readonly revokePermissions: ReadPermissionRevoker;

  constructor(repository: LibraryRemovalRepository,
    revokePermissions: ReadPermissionRevoker = revokeReadPermissions) {
    this.repository = repository;
    this.revokePermissions = revokePermissions;
  }

  async clearLibrary(): Promise<LibraryRemovalCommit> {
    return this.revokeAfterCommit(await this.repository.commitClearLibrary());
  }

  async removeTracks(trackIds: Array<number>): Promise<LibraryRemovalCommit> {
    return this.revokeAfterCommit(await this.repository.commitRemoveTracks(trackIds));
  }

  private async revokeAfterCommit(commit: LibraryRemovalCommit): Promise<LibraryRemovalCommit> {
    if (commit.persistedUris.length > 0) {
      try {
        await this.revokePermissions(commit.persistedUris);
      } catch (error) {
        console.warn(`Library records were removed but file permission cleanup failed: ${error}`);
      }
    }
    return commit;
  }
}
