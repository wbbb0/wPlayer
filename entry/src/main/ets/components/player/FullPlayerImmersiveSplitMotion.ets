import { curves, FrameCallback } from '@kit.ArkUI';

export abstract class FullPlayerImmersiveSplitFrameHost {
  abstract postFrameCallback(callback: FrameCallback): void;
}

export class HarmonyFullPlayerImmersiveSplitFrameHost extends
  FullPlayerImmersiveSplitFrameHost {
  private readonly uiContext: UIContext;

  constructor(uiContext: UIContext) {
    super();
    this.uiContext = uiContext;
  }

  postFrameCallback(callback: FrameCallback): void {
    this.uiContext.postFrameCallback(callback);
  }
}

export interface FrameScalarMotionSample {
  value: number;
  finished: boolean;
}

export class FrameScalarMotionTimeline {
  private startFrameTimeInNano: number = -1;
  private readonly from: number;
  private readonly to: number;
  private readonly durationMs: number;
  private readonly interpolate: (fraction: number) => number;

  constructor(from: number, to: number, durationMs: number,
    interpolate: (fraction: number) => number) {
    this.from = from;
    this.to = to;
    this.durationMs = Math.max(1, durationMs);
    this.interpolate = interpolate;
  }

  sample(frameTimeInNano: number): FrameScalarMotionSample {
    if (this.startFrameTimeInNano < 0) {
      this.startFrameTimeInNano = frameTimeInNano;
      return { value: this.from, finished: false };
    }
    const elapsedMs = Math.max(0, frameTimeInNano - this.startFrameTimeInNano) / 1_000_000;
    const fraction = Math.max(0, Math.min(1, elapsedMs / this.durationMs));
    if (fraction >= 1) {
      return { value: this.to, finished: true };
    }
    const progress = this.interpolate(fraction);
    return {
      value: this.from + (this.to - this.from) * progress,
      finished: false
    };
  }
}

class ScalarMotionFrameCallback extends FrameCallback {
  private readonly callback: (frameTimeInNano: number) => void;

  constructor(callback: (frameTimeInNano: number) => void) {
    super();
    this.callback = callback;
  }

  onFrame(frameTimeInNano: number): void {
    this.callback(frameTimeInNano);
  }

  onIdle(_timeLeftInNano: number): void {}
}

@Observed
export class FullPlayerImmersiveSplitMotion {
  private static readonly CURVE_X1: number = 0.2;
  private static readonly CURVE_Y1: number = 0;
  private static readonly CURVE_X2: number = 0.2;
  private static readonly CURVE_Y2: number = 1;
  progress: number;
  private epoch: number = 0;
  private running: boolean = false;
  private targetProgress: number;

  constructor(initialProgress: number = 0) {
    this.progress = initialProgress;
    this.targetProgress = initialProgress;
  }

  isActive(): boolean {
    return this.running;
  }

  targets(progress: number): boolean {
    return Math.abs(this.targetProgress - progress) < 0.0001;
  }

  resolvedTarget(): number {
    return this.targetProgress;
  }

  animate(frameHost: FullPlayerImmersiveSplitFrameHost, target: number,
    durationMs: number): void {
    const from = this.progress;
    const to = target;
    this.cancel();
    if (Math.abs(from - to) < 0.0001) {
      this.complete(to);
      return;
    }
    const epoch = ++this.epoch;
    this.running = true;
    this.targetProgress = to;
    const curve = curves.cubicBezierCurve(
      FullPlayerImmersiveSplitMotion.CURVE_X1,
      FullPlayerImmersiveSplitMotion.CURVE_Y1,
      FullPlayerImmersiveSplitMotion.CURVE_X2,
      FullPlayerImmersiveSplitMotion.CURVE_Y2
    );
    const timeline = new FrameScalarMotionTimeline(
      from,
      to,
      durationMs,
      (fraction: number): number => curve.interpolate(fraction)
    );
    let frame: (frameTimeInNano: number) => void = (_frameTimeInNano: number): void => {};
    frame = (frameTimeInNano: number): void => {
      if (!this.running || epoch !== this.epoch) {
        return;
      }
      const sample = timeline.sample(frameTimeInNano);
      this.progress = sample.value;
      if (sample.finished) {
        this.running = false;
        this.progress = to;
        return;
      }
      frameHost.postFrameCallback(new ScalarMotionFrameCallback(frame));
    };
    frameHost.postFrameCallback(new ScalarMotionFrameCallback(frame));
  }

  cancel(): void {
    this.epoch += 1;
    this.running = false;
    this.targetProgress = this.progress;
  }

  complete(progress: number): void {
    this.epoch += 1;
    this.running = false;
    this.targetProgress = progress;
    this.progress = progress;
  }

  dispose(): void {
    this.cancel();
  }
}
