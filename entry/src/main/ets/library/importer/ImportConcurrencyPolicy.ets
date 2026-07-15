export class ImportConcurrencyPolicy {
  static readonly FILE_PROBE_CONCURRENCY: number = 3;

  static needsFullFingerprint(candidateCount: number, currentBatchGroupSize: number): boolean {
    return candidateCount > 0 || currentBatchGroupSize > 1;
  }
}
