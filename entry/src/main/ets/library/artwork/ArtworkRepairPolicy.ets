import { ArtworkState } from '../model/LibraryModels';
import { ArtworkEncodingPolicy } from './ArtworkEncodingPolicy';

export class ArtworkRepairPolicy {
  private static readonly PROCESSING_STALE_MS: number = 15 * 60 * 1000;
  private static readonly FAILED_FIRST_RETRY_MS: number = 60 * 60 * 1000;
  private static readonly FAILED_SECOND_RETRY_MS: number = 6 * 60 * 60 * 1000;
  private static readonly FAILED_LATER_RETRY_MS: number = 24 * 60 * 60 * 1000;
  private static readonly SUSPICIOUS_LARGE_BYTE_RATIO: number = 2.0;

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

  static hasSuspiciousLargeVariant(smallWidth: number, smallHeight: number, smallByteSize: number,
    largeWidth: number, largeHeight: number, largeByteSize: number): boolean {
    if (smallWidth <= 0 || smallHeight <= 0 || smallByteSize <= 0 ||
      largeWidth <= 0 || largeHeight <= 0 || largeByteSize <= 0) {
      return false;
    }
    const smallPixels = smallWidth * smallHeight;
    const largePixels = largeWidth * largeHeight;
    return largePixels >= smallPixels * 4 &&
      largeByteSize <= Math.round(smallByteSize * ArtworkRepairPolicy.SUSPICIOUS_LARGE_BYTE_RATIO);
  }

  static hasOutdatedVariantDimensions(sourceWidth: number, sourceHeight: number,
    smallWidth: number, smallHeight: number, largeWidth: number, largeHeight: number): boolean {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return false;
    }
    const expectedSmall = ArtworkEncodingPolicy.targetSize(
      sourceWidth, sourceHeight, ArtworkEncodingPolicy.SMALL_MAX_EDGE
    );
    const expectedLarge = ArtworkEncodingPolicy.targetSize(
      sourceWidth, sourceHeight, ArtworkEncodingPolicy.LARGE_MAX_EDGE
    );
    return smallWidth !== expectedSmall.width || smallHeight !== expectedSmall.height ||
      largeWidth !== expectedLarge.width || largeHeight !== expectedLarge.height;
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
