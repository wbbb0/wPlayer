import { LayoutLength } from '../layout/LayoutLength';

export enum DragSelectionHitMode {
  ROW = 0,
  RECTANGLE = 1
}

export class DragSelectionRangePolicy {
  static includes(order: number, anchorOrder: number, currentOrder: number): boolean {
    return order >= Math.min(anchorOrder, currentOrder) &&
      order <= Math.max(anchorOrder, currentOrder);
  }
}

class DragSelectionTarget {
  readonly id: number;
  order: number;
  mode: DragSelectionHitMode;
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  isSelected: () => boolean;
  apply: (selected: boolean) => void;

  constructor(id: number, order: number, mode: DragSelectionHitMode,
    isSelected: () => boolean, apply: (selected: boolean) => void) {
    this.id = id;
    this.order = order;
    this.mode = mode;
    this.isSelected = isSelected;
    this.apply = apply;
  }

  update(area: Area): void {
    this.left = LayoutLength.toNumber(area.globalPosition.x, this.left);
    this.top = LayoutLength.toNumber(area.globalPosition.y, this.top);
    const width = LayoutLength.toNumber(area.width, Math.max(0, this.right - this.left));
    const height = LayoutLength.toNumber(area.height, Math.max(0, this.bottom - this.top));
    this.right = this.left + width;
    this.bottom = this.top + height;
  }

  contains(x: number, y: number): boolean {
    if (y < this.top || y > this.bottom) {
      return false;
    }
    return this.mode === DragSelectionHitMode.ROW || (x >= this.left && x <= this.right);
  }
}

export class DragSelectionController {
  private readonly publishPreview: (ids: Array<number>, selected: boolean) => void;
  private readonly onActiveChanged: (active: boolean) => void;
  private targets: Array<DragSelectionTarget> = [];
  private sessionTargets: Array<DragSelectionTarget> = [];
  private active: boolean = false;
  private targetSelected: boolean = true;
  private anchorOrder: number = -1;
  private currentOrder: number = -1;

  constructor(publishPreview: (ids: Array<number>, selected: boolean) => void =
      (_ids: Array<number>, _selected: boolean): void => {},
    onActiveChanged: (active: boolean) => void = (_active: boolean): void => {}) {
    this.publishPreview = publishPreview;
    this.onActiveChanged = onActiveChanged;
  }

  updateTarget(id: number, order: number, area: Area, mode: DragSelectionHitMode,
    isSelected: () => boolean, apply: (selected: boolean) => void): void {
    let target = this.targets.find((item: DragSelectionTarget): boolean => item.id === id);
    if (target === undefined) {
      target = new DragSelectionTarget(id, order, mode, isSelected, apply);
      this.targets.push(target);
    } else {
      target.order = order;
      target.mode = mode;
      target.isSelected = isSelected;
      target.apply = apply;
    }
    target.update(area);
    if (this.active) {
      const sessionTarget = this.sessionTargets.find(
        (item: DragSelectionTarget): boolean => item.id === id);
      if (sessionTarget === undefined) {
        this.sessionTargets.push(target);
      } else {
        sessionTarget.order = order;
        sessionTarget.mode = mode;
        sessionTarget.isSelected = isSelected;
        sessionTarget.apply = apply;
        sessionTarget.update(area);
      }
      this.publishCurrentPreview();
    }
  }

  removeTarget(id: number): void {
    this.targets = this.targets.filter((target: DragSelectionTarget): boolean => target.id !== id);
  }

  start(id: number): void {
    const target = this.targets.find((item: DragSelectionTarget): boolean => item.id === id);
    if (target === undefined) {
      return;
    }
    this.cancel();
    this.active = true;
    this.onActiveChanged(true);
    this.targetSelected = !target.isSelected();
    this.anchorOrder = target.order;
    this.currentOrder = target.order;
    this.sessionTargets = this.targets.slice();
    this.publishCurrentPreview();
  }

  update(pointerX: number, pointerY: number): void {
    if (!this.active) {
      return;
    }
    this.updatePointerTarget(pointerX, pointerY);
  }

  end(): void {
    if (this.active) {
      this.rangeTargets().forEach((target: DragSelectionTarget): void => {
        if (target.isSelected() !== this.targetSelected) {
          target.apply(this.targetSelected);
        }
      });
    }
    this.reset();
  }

  cancel(): void {
    this.reset();
  }

  private reset(): void {
    const wasActive = this.active;
    this.active = false;
    this.anchorOrder = -1;
    this.currentOrder = -1;
    this.sessionTargets = [];
    this.publishPreview([], true);
    if (wasActive) {
      this.onActiveChanged(false);
    }
  }

  private updatePointerTarget(pointerX: number, pointerY: number): void {
    const target = this.targets.find((item: DragSelectionTarget): boolean =>
      item.contains(pointerX, pointerY));
    if (target !== undefined) {
      if (this.currentOrder !== target.order) {
        this.currentOrder = target.order;
        this.publishCurrentPreview();
      }
    }
  }

  private rangeTargets(): Array<DragSelectionTarget> {
    return this.sessionTargets.filter((target: DragSelectionTarget): boolean =>
      DragSelectionRangePolicy.includes(target.order, this.anchorOrder, this.currentOrder));
  }

  private publishCurrentPreview(): void {
    this.publishPreview(
      this.rangeTargets().map((target: DragSelectionTarget): number => target.id),
      this.targetSelected
    );
  }

}
