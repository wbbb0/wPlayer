/** Publishes transition outcomes only while the submitting Runtime request still owns them. */
export class PlaybackStopOperation {
  static async run(stop: () => Promise<void>, isCurrent: () => boolean,
    commit: () => void, onFailure: (error: Object) => void): Promise<void> {
    try {
      await stop();
    } catch (error) {
      if (isCurrent()) {
        onFailure(error);
      }
      throw error instanceof Error ? error : new Error(`${error}`);
    }
    if (!isCurrent()) {
      throw new Error('Playback stop superseded');
    }
    commit();
  }
}
