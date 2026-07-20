export class ImportConcurrencyPolicy {
  static readonly FILE_PROBE_CONCURRENCY: number = 3;
  static readonly FILE_CHECK_BATCH_SIZE: number = 32;
  static readonly FILE_CHECK_CLASSIFY_CHUNK_SIZE: number = 512;
  static readonly FULL_FINGERPRINT_CONCURRENCY: number = 2;
  static readonly URI_PREFLIGHT_BATCH_SIZE: number = 256;
  static readonly IMPORT_WORK_BATCH_SIZE: number = 16;
  static readonly ARTWORK_PROCESS_CONCURRENCY: number = 3;
  static readonly ARTWORK_PROCESS_BATCH_SIZE: number = 12;

  static needsFullFingerprint(candidateCount: number, currentBatchGroupSize: number): boolean {
    return candidateCount > 0 || currentBatchGroupSize > 1;
  }
}
