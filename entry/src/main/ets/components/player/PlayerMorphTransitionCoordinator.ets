export class PlayerMorphTransitionCoordinator {
  private transitionEpoch: number = 0;
  private lifecycleEpoch: number = 0;
  private attached: boolean = false;
  private uiContext?: UIContext;

  attach(uiContext: UIContext): void {
    this.lifecycleEpoch += 1;
    this.transitionEpoch += 1;
    this.attached = true;
    this.uiContext = uiContext;
  }

  dispose(): void {
    this.attached = false;
    this.lifecycleEpoch += 1;
    this.transitionEpoch += 1;
    this.uiContext = undefined;
  }

  context(): UIContext {
    if (this.uiContext === undefined) {
      throw new Error('PlayerMorphController is not attached to a UIContext');
    }
    return this.uiContext;
  }

  beginTransition(): number {
    this.transitionEpoch += 1;
    return this.transitionEpoch;
  }

  currentLifecycle(): number {
    return this.lifecycleEpoch;
  }

  isCurrentTransition(epoch: number): boolean {
    return this.attached && epoch === this.transitionEpoch;
  }

  isCurrentLifecycle(epoch: number): boolean {
    return this.attached && epoch === this.lifecycleEpoch;
  }
}
