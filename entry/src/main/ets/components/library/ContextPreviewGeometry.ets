import { LayoutLength } from '../layout/LayoutLength';

export interface ContextPreviewFrame {
  width: number;
  height: number;
}

export class ContextPreviewGeometry {
  static animationOptions(): ContextMenuAnimationOptions {
    return {
      scale: [1, 1.1]
    };
  }

  static layoutRegionMargin(): Margin {
    return {
      left: 16,
      right: 16
    };
  }

  static fromGesture(event: GestureEvent): ContextPreviewFrame {
    return {
      width: Math.max(0, LayoutLength.toNumber(event.target.area.width, 0)),
      height: Math.max(0, LayoutLength.toNumber(event.target.area.height, 0))
    };
  }
}
