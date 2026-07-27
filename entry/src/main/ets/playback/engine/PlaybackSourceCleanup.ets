export type PlaybackSourceCleanupOperation = () => Promise<void>;
export type PlaybackSourceCloseOperation = () => void;

export interface PlaybackSourceCleanupResult {
  resetError?: Object;
  releaseError?: Object;
  closeError?: Object;
}

/**
 * Enforces the teardown order required by an fd-backed AVPlayer source.
 */
export class PlaybackSourceCleanup {
  static async run(reset: PlaybackSourceCleanupOperation,
    release: PlaybackSourceCleanupOperation,
    close: PlaybackSourceCloseOperation): Promise<PlaybackSourceCleanupResult> {
    const result: PlaybackSourceCleanupResult = {};
    try {
      await reset();
    } catch (error) {
      result.resetError = error;
      try {
        await release();
      } catch (releaseError) {
        result.releaseError = releaseError;
      }
    }
    try {
      close();
    } catch (closeError) {
      result.closeError = closeError;
    }
    return result;
  }
}
