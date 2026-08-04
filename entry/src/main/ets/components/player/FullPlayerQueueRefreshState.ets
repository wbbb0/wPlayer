export enum FullPlayerQueueRefreshPhase {
  VISIBLE,
  UNMOUNTING,
  COMMITTING,
  REBUILDING_HIDDEN,
  REVEALING
}

@Observed
export class FullPlayerQueueRefreshState {
  phase: FullPlayerQueueRefreshPhase = FullPlayerQueueRefreshPhase.VISIBLE;
  token: number = 0;

  request(): number {
    if (this.phase !== FullPlayerQueueRefreshPhase.VISIBLE) {
      return -1;
    }
    this.token += 1;
    this.phase = FullPlayerQueueRefreshPhase.UNMOUNTING;
    return this.token;
  }

  markCommitting(token: number): boolean {
    return this.transition(token, FullPlayerQueueRefreshPhase.UNMOUNTING,
      FullPlayerQueueRefreshPhase.COMMITTING);
  }

  markRebuilding(token: number): boolean {
    return this.transition(token, FullPlayerQueueRefreshPhase.COMMITTING,
      FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN);
  }

  markRevealing(token: number): boolean {
    return this.transition(token, FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN,
      FullPlayerQueueRefreshPhase.REVEALING);
  }

  complete(token: number): boolean {
    if (token !== this.token || this.phase === FullPlayerQueueRefreshPhase.VISIBLE) {
      return false;
    }
    this.phase = FullPlayerQueueRefreshPhase.VISIBLE;
    return true;
  }

  isBusy(): boolean {
    return this.phase !== FullPlayerQueueRefreshPhase.VISIBLE;
  }

  showsLoading(): boolean {
    return this.phase === FullPlayerQueueRefreshPhase.UNMOUNTING ||
      this.phase === FullPlayerQueueRefreshPhase.COMMITTING;
  }

  mountsQueue(): boolean {
    return this.phase === FullPlayerQueueRefreshPhase.VISIBLE ||
      this.phase === FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN ||
      this.phase === FullPlayerQueueRefreshPhase.REVEALING;
  }

  queueVisible(): boolean {
    return this.phase === FullPlayerQueueRefreshPhase.VISIBLE;
  }

  canInteract(): boolean {
    return this.phase === FullPlayerQueueRefreshPhase.VISIBLE;
  }

  private transition(token: number, from: FullPlayerQueueRefreshPhase,
    to: FullPlayerQueueRefreshPhase): boolean {
    if (token !== this.token || this.phase !== from) {
      return false;
    }
    this.phase = to;
    return true;
  }
}
