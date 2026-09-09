export interface FullPlayerImmersiveIntent {
  immersive: boolean;
  wideLyricsEnabled: boolean;
}

export class FullPlayerImmersiveIntentCoordinator {
  private artworkMotionActive: boolean = false;
  private pendingIntent?: FullPlayerImmersiveIntent;

  isArtworkMotionActive(): boolean {
    return this.artworkMotionActive;
  }

  request(immersive: boolean, wideLyricsEnabled: boolean): FullPlayerImmersiveIntent | undefined {
    const intent: FullPlayerImmersiveIntent = {
      immersive: immersive,
      wideLyricsEnabled: wideLyricsEnabled
    };
    if (this.artworkMotionActive) {
      this.pendingIntent = intent;
      return undefined;
    }
    this.pendingIntent = undefined;
    return intent;
  }

  updateArtworkMotion(active: boolean): FullPlayerImmersiveIntent | undefined {
    this.artworkMotionActive = active;
    if (active || this.pendingIntent === undefined) {
      return undefined;
    }
    const intent = this.pendingIntent;
    this.pendingIntent = undefined;
    return intent;
  }

  intendedImmersive(fallback: boolean): boolean {
    return this.pendingIntent?.immersive ?? fallback;
  }

  reset(): void {
    this.artworkMotionActive = false;
    this.pendingIntent = undefined;
  }
}
