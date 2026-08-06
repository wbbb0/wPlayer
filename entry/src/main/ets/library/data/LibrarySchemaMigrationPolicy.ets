export enum LibrarySchemaMigrationAction {
  CURRENT = 0,
  MIGRATE = 1,
  REJECT = 2
}

/** Supported production database path. Development-only schema shapes are intentionally excluded. */
export class LibrarySchemaMigrationPolicy {
  static readonly CURRENT_VERSION: number = 14;
  static readonly PRODUCTION_VERSION: number = 12;

  static actionFor(version: number): LibrarySchemaMigrationAction {
    if (version === LibrarySchemaMigrationPolicy.CURRENT_VERSION) {
      return LibrarySchemaMigrationAction.CURRENT;
    }
    if (version >= LibrarySchemaMigrationPolicy.PRODUCTION_VERSION &&
      version < LibrarySchemaMigrationPolicy.CURRENT_VERSION) {
      return LibrarySchemaMigrationAction.MIGRATE;
    }
    return LibrarySchemaMigrationAction.REJECT;
  }
}
