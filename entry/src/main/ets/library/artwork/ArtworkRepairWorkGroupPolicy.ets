import { ArtworkState } from '../model/LibraryModels';
import { ArtworkWorkOutcome, ArtworkWorkResult } from './ArtworkWorkSession';

export interface ArtworkRepairAttempt<T> {
  work: T;
  result: ArtworkWorkResult;
  attemptCount: number;
}

/** Plans source-identity-safe coalescing and fallback for artwork repair work. */
export class ArtworkRepairWorkGroupPolicy {
  static sharedSourceKey(state: ArtworkState, sourceId: number, sourceHash: string): string {
    if (state !== ArtworkState.READY || sourceId <= 0 || sourceHash.length === 0) {
      return '';
    }
    return `${sourceId}:${sourceHash}`;
  }

  static async run<T>(works: Array<T>,
    execute: (work: T) => Promise<ArtworkWorkResult>): Promise<ArtworkRepairAttempt<T> | undefined> {
    let lastAttempt: ArtworkRepairAttempt<T> | undefined;
    for (let index = 0; index < works.length; index += 1) {
      const work = works[index];
      const result = await execute(work);
      lastAttempt = { work: work, result: result, attemptCount: index + 1 };
      if (result.outcome === ArtworkWorkOutcome.COMPLETED ||
        result.outcome === ArtworkWorkOutcome.SKIPPED) {
        return lastAttempt;
      }
    }
    return lastAttempt;
  }
}
