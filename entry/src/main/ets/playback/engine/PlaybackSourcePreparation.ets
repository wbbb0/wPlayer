export type PlaybackSourceStep = () => void;
export type PlaybackSourceAsyncStep = () => Promise<void>;

/**
 * Runs the fallible portion of fd-backed source preparation and guarantees
 * that every unsuccessful attempt reaches the owning cleanup path.
 */
export class PlaybackSourcePreparation {
  static async run(initialized: Promise<void>,
    attach: PlaybackSourceStep,
    configure: PlaybackSourceStep,
    prepare: PlaybackSourceAsyncStep,
    ensureCurrent: PlaybackSourceStep,
    discard: PlaybackSourceAsyncStep): Promise<void> {
    try {
      attach();
      await initialized;
      ensureCurrent();
      configure();
      await prepare();
      ensureCurrent();
    } catch (error) {
      const initializedSettled = initialized.catch((): void => {});
      try {
        await discard();
      } catch (_) {
      }
      await initializedSettled;
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(`${error}`);
    }
  }
}
