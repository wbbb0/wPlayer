const ARTWORK_DIRECTORY = 'artwork';
const TEMP_FILE_SUFFIX = '.tmp';

export class ArtworkCleanupPolicy {
  static readonly DELETE_BATCH_SIZE: number = 16;

  static relativePath(entry: string): string {
    const normalized = ArtworkCleanupPolicy.normalizedEntry(entry);
    return normalized.length === 0 ? '' : `${ARTWORK_DIRECTORY}/${normalized}`;
  }

  static shouldDeleteOrphan(entry: string, isFile: boolean, referencedPaths: Set<string>): boolean {
    if (!isFile || ArtworkCleanupPolicy.isTemporary(entry)) {
      return false;
    }
    const relativePath = ArtworkCleanupPolicy.relativePath(entry);
    return relativePath.length > 0 && !referencedPaths.has(relativePath);
  }

  static shouldDeleteTemporary(entry: string, isFile: boolean): boolean {
    return isFile && ArtworkCleanupPolicy.isTemporary(entry) &&
      ArtworkCleanupPolicy.relativePath(entry).length > 0;
  }

  static batchEnd(start: number, total: number): number {
    if (start >= total) {
      return total;
    }
    return Math.min(total, start + ArtworkCleanupPolicy.DELETE_BATCH_SIZE);
  }

  static normalizedEntry(entry: string): string {
    const normalized = entry.replace(/\\/g, '/');
    const withoutRoot = normalized.startsWith('/') ? normalized.substring(1) : normalized;
    const segments = withoutRoot.split('/');
    if (withoutRoot.length === 0 || segments.some((segment: string) =>
      segment.length === 0 || segment === '.' || segment === '..')) {
      return '';
    }
    return withoutRoot;
  }

  private static isTemporary(entry: string): boolean {
    return ArtworkCleanupPolicy.normalizedEntry(entry).endsWith(TEMP_FILE_SUFFIX);
  }
}
