export interface DynamicBackgroundV3NativeContext {
  setArtwork(buffer: ArrayBuffer, width: number, height: number, swapRedBlue: boolean): void;
  setPaused(paused: boolean): void;
  setSpeed(speed: number): void;
  setRenderScale(scale: number): void;
  setFrameRates(backgroundFps: number, transitionFps: number,
    transitionDurationSeconds: number, initialRevealDurationRatio: number): void;
  setWorkTextureSize(size: number): void;
  setBlurRadius(actualPixelRadius: number): void;
  setOverscan(overscan: number): void;
}
