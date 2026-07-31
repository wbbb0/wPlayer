import { AnimatorOptions, AnimatorResult } from '@kit.ArkUI';
import { PresentationMotionState } from './PresentationMotionState';

export class InterruptibleScalarMotion {
  private static readonly MIN_FRAME_RATE: number = 60;
  private static readonly TARGET_FRAME_RATE: number = 120;
  private animator?: AnimatorResult;
  private epoch: number = 0;
  private trackerRunning: boolean = false;
  private readonly state: PresentationMotionState;

  constructor(initialValue: number = 0) {
    this.state = new PresentationMotionState(initialValue);
  }

  private createAnimator(uiContext: UIContext, options: AnimatorOptions): AnimatorResult {
    const animator = uiContext.createAnimator(options);
    animator.setExpectedFrameRateRange({
      min: InterruptibleScalarMotion.MIN_FRAME_RATE,
      max: InterruptibleScalarMotion.TARGET_FRAME_RATE,
      expected: InterruptibleScalarMotion.TARGET_FRAME_RATE
    });
    return animator;
  }

  value(): number {
    return this.state.value();
  }

  setValue(value: number): void {
    this.state.reset(value);
  }

  isActive(): boolean {
    return this.state.isRenderSettling();
  }

  animate(uiContext: UIContext, from: number, to: number, duration: number,
    easing: string): void {
    this.cancel();
    const epoch = ++this.epoch;
    this.state.begin(from);
    const options: AnimatorOptions = {
      duration: Math.max(1, duration),
      easing: easing,
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: from,
      end: to
    };
    let animator = this.animator;
    if (animator === undefined) {
      animator = this.createAnimator(uiContext, options);
      this.animator = animator;
    } else {
      try {
        animator.reset(options);
      } catch (error) {
        console.warn(`Unable to reuse scalar animator: ${error}`);
        animator = this.createAnimator(uiContext, options);
        this.animator = animator;
      }
    }
    animator.onFrame = (value: number): void => {
      if (epoch !== this.epoch) {
        return;
      }
      this.state.sample(value);
    };
    animator.onFinish = (): void => {
      if (epoch !== this.epoch) {
        return;
      }
      this.trackerRunning = false;
      this.state.finishTracker();
    };
    animator.onCancel = (): void => {};
    this.trackerRunning = true;
    animator.play();
  }

  cancel(): void {
    this.epoch += 1;
    if (this.trackerRunning) {
      this.trackerRunning = false;
      this.animator?.cancel();
    }
    this.state.takeOver();
  }

  complete(value: number): void {
    this.epoch += 1;
    if (this.trackerRunning) {
      this.trackerRunning = false;
      this.animator?.cancel();
    }
    this.state.completeRender(value);
  }

  dispose(): void {
    this.cancel();
    this.animator = undefined;
  }
}
