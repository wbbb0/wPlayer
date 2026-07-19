export class ImportConcurrencyPolicy {
  static readonly FILE_PROBE_CONCURRENCY: number = 3;
  static readonly URI_PREFLIGHT_BATCH_SIZE: number = 256;
  static readonly IMPORT_WORK_BATCH_SIZE: number = 16;

  static needsFullFingerprint(candidateCount: number, currentBatchGroupSize: number): boolean {
    return candidateCount > 0 || currentBatchGroupSize > 1;
  }
}
