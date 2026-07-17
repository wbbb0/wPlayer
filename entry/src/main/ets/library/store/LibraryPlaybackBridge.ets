/** Playback-side capabilities needed by destructive library maintenance. */
export interface LibraryPlaybackBridge {
  prepareForLibraryClear(): Promise<void>;
  refreshCurrentTrackPalette(): Promise<void>;
}
