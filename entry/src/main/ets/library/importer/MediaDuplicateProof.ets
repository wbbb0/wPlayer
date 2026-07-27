import { DuplicateCandidate, TrackImportInput } from '../data/MusicRepository';
import { DuplicatePolicy } from './DuplicatePolicy';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';
import { MediaImportCancellation } from './MediaImportContracts';

export type DuplicateCandidateLookup = (
  fileSize: number,
  quickFingerprint: string
) => Promise<Array<DuplicateCandidate>>;
export type FullFingerprintCalculator = (uri: string) => Promise<string>;
export type CandidateFingerprintWriter = (
  trackId: number,
  fingerprint: string
) => Promise<void>;

export interface BatchDuplicatePartition {
  unique: Array<TrackImportInput>;
  duplicates: Array<BatchDuplicateMatch>;
}

export interface BatchDuplicateMatch {
  duplicate: TrackImportInput;
  source: TrackImportInput;
}

export class MediaDuplicateProof {
  private readonly cancellation: MediaImportCancellation;
  private readonly lookup: DuplicateCandidateLookup;
  private readonly calculate: FullFingerprintCalculator;
  private readonly persist: CandidateFingerprintWriter;
  private readonly candidateLookups: Map<string, Promise<Array<DuplicateCandidate>>> = new Map();
  private readonly candidateFingerprintTasks: Map<number, Promise<string>> = new Map();

  constructor(cancellation: MediaImportCancellation, lookup: DuplicateCandidateLookup,
    calculate: FullFingerprintCalculator, persist: CandidateFingerprintWriter) {
    this.cancellation = cancellation;
    this.lookup = lookup;
    this.calculate = calculate;
    this.persist = persist;
  }

  async findCandidates(fileSize: number,
    quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    const key = `${fileSize}:${quickFingerprint}`;
    const existing = this.candidateLookups.get(key);
    if (existing !== undefined) {
      const candidates = await existing;
      this.throwIfCancelled();
      return candidates;
    }
    const pending = this.lookup(fileSize, quickFingerprint);
    this.candidateLookups.set(key, pending);
    try {
      const candidates = await pending;
      this.throwIfCancelled();
      return candidates;
    } catch (error) {
      if (this.candidateLookups.get(key) === pending) {
        this.candidateLookups.delete(key);
      }
      throw new Error(MediaDuplicateProof.errorMessage(error));
    }
  }

  async ensureCandidateFingerprints(candidates: Array<DuplicateCandidate>): Promise<void> {
    for (let index = 0; index < candidates.length; index += 1) {
      this.throwIfCancelled();
      const candidate = candidates[index];
      if (candidate.fullFingerprint.length > 0) {
        continue;
      }
      let pending = this.candidateFingerprintTasks.get(candidate.trackId);
      if (pending === undefined) {
        pending = this.calculateAndPersist(candidate);
        this.candidateFingerprintTasks.set(candidate.trackId, pending);
      }
      try {
        candidate.fullFingerprint = await pending;
        this.throwIfCancelled();
      } catch (error) {
        if (this.candidateFingerprintTasks.get(candidate.trackId) === pending) {
          this.candidateFingerprintTasks.delete(candidate.trackId);
        }
        throw new Error(MediaDuplicateProof.errorMessage(error));
      }
    }
  }

  async ensureBatchProofs(inputs: Array<TrackImportInput>): Promise<void> {
    const groups: Map<string, Array<TrackImportInput>> = new Map();
    for (let index = 0; index < inputs.length; index += 1) {
      const input = inputs[index];
      const key = `${input.fileSize}:${input.quickFingerprint}`;
      const group = groups.get(key) ?? [];
      group.push(input);
      groups.set(key, group);
    }
    const pending: Array<TrackImportInput> = [];
    groups.forEach((group: Array<TrackImportInput>) => {
      if (ImportConcurrencyPolicy.needsFullFingerprint(0, group.length)) {
        group.forEach((input: TrackImportInput) => {
          if (input.fullFingerprint.length === 0) {
            pending.push(input);
          }
        });
      }
    });
    let nextIndex = 0;
    const consume = async (): Promise<void> => {
      while (nextIndex < pending.length) {
        this.throwIfCancelled();
        const input = pending[nextIndex++];
        input.fullFingerprint = await this.calculate(input.uri);
        this.throwIfCancelled();
      }
    };
    const workers: Array<Promise<void>> = [];
    const workerCount = Math.min(
      ImportConcurrencyPolicy.FULL_FINGERPRINT_CONCURRENCY,
      pending.length
    );
    for (let index = 0; index < workerCount; index += 1) {
      workers.push(consume());
    }
    await Promise.all(workers);
  }

  partitionBatchDuplicates(inputs: Array<TrackImportInput>): BatchDuplicatePartition {
    const unique: Array<TrackImportInput> = [];
    const duplicates: Array<BatchDuplicateMatch> = [];
    for (let index = 0; index < inputs.length; index += 1) {
      const input = inputs[index];
      const source = unique.find((existing: TrackImportInput) =>
        DuplicatePolicy.isConfirmedDuplicate(
          existing.quickFingerprint, input.quickFingerprint,
          existing.fullFingerprint, input.fullFingerprint
        ));
      if (source === undefined) {
        unique.push(input);
      } else {
        duplicates.push({ duplicate: input, source: source });
      }
    }
    return { unique: unique, duplicates: duplicates };
  }

  private async calculateAndPersist(candidate: DuplicateCandidate): Promise<string> {
    const fingerprint = await this.calculate(candidate.uri);
    this.throwIfCancelled();
    await this.persist(candidate.trackId, fingerprint);
    return fingerprint;
  }

  private throwIfCancelled(): void {
    if (this.cancellation.isCancelled()) {
      throw new Error('Media import operation cancelled');
    }
  }

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
