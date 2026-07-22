/** Playback-side capabilities needed by destructive library maintenance. */
export interface LibraryPlaybackBridge {
  prepareForLibraryClear(): Promise<void>;
  prepareForTrackRemoval(trackIds: Array<number>): Promise<void>;
  refreshCurrentTrackPalette(): Promise<void>;
}
