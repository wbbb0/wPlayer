export class DynamicBackgroundV2Spec {
  static readonly FRAME_RATE: number = 15;
  static readonly MESH_SEGMENTS: number = 24;

  // Values below mirror aadishv/html-music bundle.ts at 4ef618e.
  static readonly LARGE_SPRITE_SIZE_RATIO: number = 1.25;
  static readonly MEDIUM_SPRITE_SIZE_RATIO: number = 0.80;
  static readonly SMALL_SPRITE_SIZE_RATIO: number = 0.50;
  static readonly TINY_SPRITE_SIZE_RATIO: number = 0.25;
  static readonly LARGE_ROTATION_PER_REFERENCE_FRAME: number = 0.003;
  static readonly MEDIUM_ROTATION_PER_REFERENCE_FRAME: number = -0.008;
  static readonly SMALL_ROTATION_PER_REFERENCE_FRAME: number = -0.006;
  static readonly TINY_ROTATION_PER_REFERENCE_FRAME: number = 0.004;
  static readonly REFERENCE_FRAMES_PER_SECOND: number = 30;
  static readonly ORBIT_ANGLE_RATIO: number = 0.75;
  static readonly ORBIT_RADIUS_RATIO: number = 0.25;
  static readonly TINY_ORBIT_OFFSET_RATIO: number = 0.05;
  static readonly TWIST_ANGLE_RADIANS: number = -3.25;
  static readonly TWIST_RADIUS: number = 900;
  static readonly BLUR_RADIUS: number = 100;
  static readonly SATURATION: number = 2.75;

  static readonly DEFAULT_SPEED: number = 1;
  static readonly CONTROL_PANEL_MAX_WIDTH: number = 560;
  static readonly CONTROL_PANEL_MARGIN: number = 20;

  static rotationRadians(seconds: number, rotationPerReferenceFrame: number,
    speed: number): number {
    return seconds * DynamicBackgroundV2Spec.REFERENCE_FRAMES_PER_SECOND *
      rotationPerReferenceFrame * Math.max(0, speed);
  }
}
