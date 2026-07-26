export class DynamicBackgroundDebugSpec {
  static readonly FRAME_RATE: number = 30;
  static readonly LAYER_ONE_PERIOD_SECONDS: number = 24;
  static readonly LAYER_TWO_PERIOD_SECONDS: number = 31.5;
  static readonly LAYER_ONE_VERTICAL_RATIO: number = 0.33;
  static readonly LAYER_TWO_HORIZONTAL_RATIO: number = 0.40;
  static readonly LAYER_TWO_VERTICAL_RATIO: number = 0.95;
  static readonly LAYER_TWO_OPACITY_RATIO: number = 0.78;
  static readonly LAYER_ONE_ROTATION_RATIO: number = 1;
  static readonly LAYER_TWO_ROTATION_RATIO: number = 0.78;
  static readonly LAYER_ONE_TEXTURE_SCALE: number = 1.22;
  static readonly LAYER_TWO_TEXTURE_SCALE: number = 1.56;
  static readonly DEFAULT_SPEED: number = 1;
  static readonly DEFAULT_OPACITY: number = 0.39;
  static readonly DEFAULT_TRAVEL: number = 22;
  static readonly DEFAULT_ROTATION: number = 2;
  static readonly DEFAULT_TEXTURE_SCALE: number = 1.25;
  static readonly CONTROL_PANEL_MAX_WIDTH: number = 560;
  static readonly CONTROL_PANEL_MARGIN: number = 20;

  static phase(seconds: number, periodSeconds: number, speed: number): number {
    if (periodSeconds <= 0) {
      return 0;
    }
    return seconds * Math.PI * 2 * Math.max(0, speed) / periodSeconds;
  }

  static layerOneX(seconds: number, speed: number, travel: number): number {
    return Math.sin(DynamicBackgroundDebugSpec.phase(
      seconds,
      DynamicBackgroundDebugSpec.LAYER_ONE_PERIOD_SECONDS,
      speed
    )) * travel;
  }

  static layerOneY(seconds: number, speed: number, travel: number): number {
    const phase = DynamicBackgroundDebugSpec.phase(
      seconds,
      DynamicBackgroundDebugSpec.LAYER_ONE_PERIOD_SECONDS,
      speed
    );
    return Math.cos(phase * 0.47 + 0.61) *
      travel * DynamicBackgroundDebugSpec.LAYER_ONE_VERTICAL_RATIO;
  }

  static layerOneRotation(seconds: number, speed: number, rotation: number): number {
    const phase = DynamicBackgroundDebugSpec.phase(
      seconds,
      DynamicBackgroundDebugSpec.LAYER_ONE_PERIOD_SECONDS,
      speed
    );
    return Math.sin(phase * 0.41) * rotation *
      DynamicBackgroundDebugSpec.LAYER_ONE_ROTATION_RATIO;
  }

  static layerTwoX(seconds: number, speed: number, travel: number): number {
    const phase = -DynamicBackgroundDebugSpec.phase(
      seconds,
      DynamicBackgroundDebugSpec.LAYER_TWO_PERIOD_SECONDS,
      speed
    ) + 1.73;
    return Math.cos(phase * 0.63 + 0.38) *
      travel * DynamicBackgroundDebugSpec.LAYER_TWO_HORIZONTAL_RATIO;
  }

  static layerTwoY(seconds: number, speed: number, travel: number): number {
    const phase = -DynamicBackgroundDebugSpec.phase(
      seconds,
      DynamicBackgroundDebugSpec.LAYER_TWO_PERIOD_SECONDS,
      speed
    ) + 1.73;
    return Math.sin(phase) * travel *
      DynamicBackgroundDebugSpec.LAYER_TWO_VERTICAL_RATIO;
  }

  static layerTwoRotation(seconds: number, speed: number, rotation: number): number {
    const phase = -DynamicBackgroundDebugSpec.phase(
      seconds,
      DynamicBackgroundDebugSpec.LAYER_TWO_PERIOD_SECONDS,
      speed
    ) + 1.73;
    return -Math.sin(phase * 0.52 + 0.9) * rotation *
      DynamicBackgroundDebugSpec.LAYER_TWO_ROTATION_RATIO;
  }
}
