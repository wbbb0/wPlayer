export class PresentationMotionState {
  private currentValue: number;
  private renderSettling: boolean = false;

  constructor(initialValue: number = 0) {
    this.currentValue = initialValue;
  }

  value(): number {
    return this.currentValue;
  }

  isRenderSettling(): boolean {
    return this.renderSettling;
  }

  begin(value: number): void {
    this.currentValue = value;
    this.renderSettling = true;
  }

  sample(value: number): void {
    if (this.renderSettling) {
      this.currentValue = value;
    }
  }

  finishTracker(): number {
    return this.currentValue;
  }

  completeRender(value: number): void {
    this.currentValue = value;
    this.renderSettling = false;
  }

  takeOver(): number {
    this.renderSettling = false;
    return this.currentValue;
  }

  reset(value: number): void {
    this.currentValue = value;
    this.renderSettling = false;
  }
}
