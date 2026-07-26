export interface PlaybackPictureInPictureSize {
  width: number;
  height: number;
}

export class PlaybackPictureInPicturePolicy {
  static readonly DEFAULT_CONTENT_SIZE: number = 1000;

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

  static transportControlsEnabled(queueReady: boolean, queueSize: number): boolean {
    return queueReady && queueSize > 1;
  }
}
