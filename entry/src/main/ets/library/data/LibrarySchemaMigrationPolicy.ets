export enum LibrarySchemaMigrationAction {
  CURRENT = 0,
  MIGRATE_PRODUCTION = 1,
  REJECT = 2
}

/** Supported production database path. Development-only schema shapes are intentionally excluded. */
export class LibrarySchemaMigrationPolicy {
  static readonly CURRENT_VERSION: number = 13;
  static readonly PRODUCTION_VERSION: number = 12;

  static actionFor(version: number): LibrarySchemaMigrationAction {
    if (version === LibrarySchemaMigrationPolicy.CURRENT_VERSION) {
      return LibrarySchemaMigrationAction.CURRENT;
    }
    if (version === LibrarySchemaMigrationPolicy.PRODUCTION_VERSION) {
      return LibrarySchemaMigrationAction.MIGRATE_PRODUCTION;
    }
    return LibrarySchemaMigrationAction.REJECT;
  }
}
