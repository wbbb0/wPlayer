/** Bounds caller-supplied random-access page parameters before they reach SQL. */
export class LibraryQueryPagingPolicy {
  static readonly MAX_PAGE_SIZE: number = 256;

  static offset(value: number): number {
    return value > 0 ? Math.floor(value) : 0;
  }

  static limit(value: number): number {
    if (!(value > 0)) {
      return 1;
    }
    return Math.max(
      1,
      Math.min(LibraryQueryPagingPolicy.MAX_PAGE_SIZE, Math.floor(value))
    );
  }
}
