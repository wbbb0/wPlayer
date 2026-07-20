import { ArtworkState } from '../model/LibraryModels';

export class ArtworkRepairPolicy {
  private static readonly PROCESSING_STALE_MS: number = 15 * 60 * 1000;
  private static readonly FAILED_FIRST_RETRY_MS: number = 60 * 60 * 1000;
  private static readonly FAILED_SECOND_RETRY_MS: number = 6 * 60 * 60 * 1000;
  private static readonly FAILED_LATER_RETRY_MS: number = 24 * 60 * 60 * 1000;

  static needsRepair(state: ArtworkState, smallAvailable: boolean, largeAvailable: boolean,
    attemptCount: number = 0, lastAttemptAt: number = 0, now: number = Date.now()): boolean {
    if (state === ArtworkState.ABSENT) {
      return false;
    }
    if (state === ArtworkState.READY) {
      return !smallAvailable || !largeAvailable;
    }
    if (state === ArtworkState.PROCESSING) {
      return ArtworkRepairPolicy.retryDue(
        lastAttemptAt, now, ArtworkRepairPolicy.PROCESSING_STALE_MS
      );
    }
    if (state === ArtworkState.FAILED) {
      return ArtworkRepairPolicy.retryDue(
        lastAttemptAt, now, ArtworkRepairPolicy.failedRetryDelay(attemptCount)
      );
    }
    return true;
  }

  static shouldRebindSource(existingAssetId: number, preparedAssetId: number): boolean {
    return existingAssetId !== preparedAssetId;
  }

  private static retryDue(lastAttemptAt: number, now: number, delayMs: number): boolean {
    return lastAttemptAt <= 0 || now - lastAttemptAt >= delayMs;
  }

  private static failedRetryDelay(attemptCount: number): number {
    if (attemptCount <= 1) {
      return ArtworkRepairPolicy.FAILED_FIRST_RETRY_MS;
    }
    if (attemptCount === 2) {
      return ArtworkRepairPolicy.FAILED_SECOND_RETRY_MS;
    }
    return ArtworkRepairPolicy.FAILED_LATER_RETRY_MS;
  }
}
