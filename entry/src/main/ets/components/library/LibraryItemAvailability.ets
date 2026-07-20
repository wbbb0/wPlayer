import { AvailabilityState } from '../../library/model/LibraryModels';

/** Shared presentation policy for unavailable library rows and cards. */
export class LibraryItemAvailability {
  static unavailable(state: AvailabilityState | undefined): boolean {
    return state !== undefined && state !== AvailabilityState.AVAILABLE;
  }

  static opacity(state: AvailabilityState | undefined): number {
    return LibraryItemAvailability.unavailable(state) ? 0.46 : 1;
  }

  static label(state: AvailabilityState | undefined): string {
    switch (state) {
      case AvailabilityState.AUTHORIZATION_REVOKED:
        return '需要重新授权';
      case AvailabilityState.CORRUPTED:
        return '文件已损坏';
      case AvailabilityState.UNAVAILABLE:
        return '文件不可用';
      default:
        return '';
    }
  }
}
