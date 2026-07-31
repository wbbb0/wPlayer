import { curves } from '@kit.ArkUI';

export class TitleBarMotionSpec {
  private static readonly TRANSITION_RESPONSE: number = 0.32;
  private static readonly TRANSITION_DAMPING_FRACTION: number = 0.82;

  static transitionCurve(): ICurve {
    return curves.springMotion(
      TitleBarMotionSpec.TRANSITION_RESPONSE,
      TitleBarMotionSpec.TRANSITION_DAMPING_FRACTION,
      0
    );
  }
}
