export interface PlaybackPictureInPictureSize {
  width: number;
  height: number;
}

export class PlaybackPictureInPicturePolicy {
  static readonly DEFAULT_CONTENT_SIZE: number = 1000;
  static readonly DEMO_ARTWORK_SCHEME: string = 'demo-artwork://';

  static contentSize(width: number, height: number): PlaybackPictureInPictureSize {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return {
        width: PlaybackPictureInPicturePolicy.DEFAULT_CONTENT_SIZE,
        height: PlaybackPictureInPicturePolicy.DEFAULT_CONTENT_SIZE
      };
    }
    return {
      width: Math.max(1, Math.round(width)),
      height: Math.max(1, Math.round(height))
    };
  }

  static artworkUri(uri: string): string {
    return uri.startsWith(PlaybackPictureInPicturePolicy.DEMO_ARTWORK_SCHEME) ? '' : uri;
  }

  static transportControlsEnabled(queueReady: boolean, queueSize: number): boolean {
    return queueReady && queueSize > 1;
  }
}
