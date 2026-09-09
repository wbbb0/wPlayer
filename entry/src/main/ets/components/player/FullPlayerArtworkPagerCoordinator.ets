import { QueueEntry } from '../../playback/model/PlaybackModels';

export enum FullPlayerArtworkPagerPhase {
  IDLE,
  USER_SETTLING,
  PROGRAMMATIC,
  HIDDEN_REANCHOR
}

export enum FullPlayerArtworkPagerCommandKind {
  NONE,
  CHANGE_INDEX,
  SELECT_ENTRY
}

export enum FullPlayerArtworkPagerScrollMode {
  NONE,
  DEFAULT,
  FAST
}

export interface FullPlayerArtworkPagerCommand {
  kind: FullPlayerArtworkPagerCommandKind;
  index: number;
  queueEntryId: number;
  scrollMode: FullPlayerArtworkPagerScrollMode;
}

export class FullPlayerArtworkGestureSequence {
  private touchActive: boolean = false;
  private swipeFrameConsumed: boolean = false;

  onTouchDown(): void {
    this.touchActive = true;
    this.swipeFrameConsumed = false;
  }

  onTouchEnd(): void {
    this.touchActive = false;
  }

  consumeSwipeFrame(): boolean {
    if (this.swipeFrameConsumed) {
      return false;
    }
    this.swipeFrameConsumed = true;
    return true;
  }

  onAnimationEnd(): void {
    if (!this.touchActive) {
      this.swipeFrameConsumed = false;
    }
  }
}

@Observed
export class FullPlayerArtworkPagerCoordinator {
  phase: FullPlayerArtworkPagerPhase = FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR;
  pagerVisible: boolean = false;
  readyGeneration: number = 0;
  private semanticEntryId?: number;
  private expectedTargetEntryId?: number;
  private pendingExternalEntryId?: number;
  private awaitingAckEntryId?: number;
  private reanchorApplied: boolean = true;
  private targetReady: boolean = false;
  private userSettleArmed: boolean = false;

  initialize(entries: Array<QueueEntry>, currentIndex: number): void {
    const current = FullPlayerArtworkPagerCoordinator.entryAt(entries, currentIndex);
    this.pagerVisible = false;
    this.pendingExternalEntryId = undefined;
    this.awaitingAckEntryId = undefined;
    this.reanchorApplied = true;
    this.targetReady = false;
    this.userSettleArmed = false;
    this.readyGeneration += 1;
    if (current === undefined) {
      this.phase = FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR;
      this.semanticEntryId = undefined;
      this.expectedTargetEntryId = undefined;
      return;
    }
    this.phase = FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR;
    this.semanticEntryId = current.queueEntryId;
    this.expectedTargetEntryId = current.queueEntryId;
  }

  dispose(): void {
    this.phase = FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR;
    this.pagerVisible = false;
    this.semanticEntryId = undefined;
    this.expectedTargetEntryId = undefined;
    this.pendingExternalEntryId = undefined;
    this.awaitingAckEntryId = undefined;
    this.reanchorApplied = false;
    this.targetReady = false;
    this.userSettleArmed = false;
  }

  initialIndex(entries: Array<QueueEntry>, currentIndex: number): number {
    return FullPlayerArtworkPagerCoordinator.entryAt(entries, currentIndex) === undefined ?
      0 : currentIndex;
  }

  onProjectionChanged(entries: Array<QueueEntry>, currentIndex: number): FullPlayerArtworkPagerCommand {
    const current = FullPlayerArtworkPagerCoordinator.entryAt(entries, currentIndex);
    this.pagerVisible = false;
    this.pendingExternalEntryId = undefined;
    this.awaitingAckEntryId = undefined;
    this.reanchorApplied = false;
    this.targetReady = false;
    this.userSettleArmed = false;
    this.readyGeneration += 1;
    this.phase = FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR;
    if (current === undefined) {
      this.semanticEntryId = undefined;
      this.expectedTargetEntryId = undefined;
      return FullPlayerArtworkPagerCoordinator.none();
    }
    this.semanticEntryId = current.queueEntryId;
    this.expectedTargetEntryId = current.queueEntryId;
    return FullPlayerArtworkPagerCoordinator.changeIndex(
      currentIndex,
      current.queueEntryId,
      FullPlayerArtworkPagerScrollMode.NONE
    );
  }

  onQueueIndexChanged(entries: Array<QueueEntry>, currentIndex: number,
    looping: boolean = false): FullPlayerArtworkPagerCommand {
    const current = FullPlayerArtworkPagerCoordinator.entryAt(entries, currentIndex);
    if (current === undefined) {
      return this.onProjectionChanged(entries, currentIndex);
    }
    const entryId = current.queueEntryId;
    if (this.awaitingAckEntryId === entryId) {
      this.awaitingAckEntryId = undefined;
      this.semanticEntryId = entryId;
      return FullPlayerArtworkPagerCoordinator.none();
    }
    if (this.phase === FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR) {
      if (this.expectedTargetEntryId === entryId) {
        return FullPlayerArtworkPagerCoordinator.none();
      }
      return this.onProjectionChanged(entries, currentIndex);
    }
    if (this.phase === FullPlayerArtworkPagerPhase.USER_SETTLING) {
      this.pendingExternalEntryId = entryId;
      return FullPlayerArtworkPagerCoordinator.none();
    }
    if (this.phase === FullPlayerArtworkPagerPhase.PROGRAMMATIC) {
      this.pendingExternalEntryId = this.expectedTargetEntryId === entryId ?
        undefined : entryId;
      return FullPlayerArtworkPagerCoordinator.none();
    }
    if (this.semanticEntryId === entryId) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    return this.beginProgrammatic(entries, entryId, looping);
  }

  onAnimationStart(entries: Array<QueueEntry>, targetIndex: number): FullPlayerArtworkPagerCommand {
    if (this.phase === FullPlayerArtworkPagerPhase.PROGRAMMATIC ||
      this.phase === FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    const target = FullPlayerArtworkPagerCoordinator.entryAt(entries, targetIndex);
    if (target === undefined) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    this.phase = FullPlayerArtworkPagerPhase.USER_SETTLING;
    this.expectedTargetEntryId = target.queueEntryId;
    this.userSettleArmed = true;
    if (this.semanticEntryId === target.queueEntryId) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    this.semanticEntryId = target.queueEntryId;
    this.pendingExternalEntryId = undefined;
    this.awaitingAckEntryId = target.queueEntryId;
    return FullPlayerArtworkPagerCoordinator.selectEntry(target.queueEntryId);
  }

  onUserGesture(): void {
    if (this.phase === FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR) {
      return;
    }
    if (this.phase === FullPlayerArtworkPagerPhase.PROGRAMMATIC) {
      this.pendingExternalEntryId = this.expectedTargetEntryId;
    }
    this.phase = FullPlayerArtworkPagerPhase.USER_SETTLING;
    this.expectedTargetEntryId = undefined;
    this.userSettleArmed = false;
  }

  allowsUserSwipe(): boolean {
    return this.phase !== FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR;
  }

  isMotionActive(): boolean {
    return this.phase === FullPlayerArtworkPagerPhase.USER_SETTLING ||
      this.phase === FullPlayerArtworkPagerPhase.PROGRAMMATIC;
  }

  acceptsAnimationEnd(entries: Array<QueueEntry>, settledIndex: number): boolean {
    const settled = FullPlayerArtworkPagerCoordinator.entryAt(entries, settledIndex);
    if (settled === undefined) {
      return false;
    }
    if (this.phase === FullPlayerArtworkPagerPhase.USER_SETTLING) {
      return this.userSettleArmed;
    }
    return this.phase === FullPlayerArtworkPagerPhase.PROGRAMMATIC &&
      settled.queueEntryId === this.expectedTargetEntryId;
  }

  onAnimationEnd(entries: Array<QueueEntry>, settledIndex: number,
    looping: boolean = false): FullPlayerArtworkPagerCommand {
    const settled = FullPlayerArtworkPagerCoordinator.entryAt(entries, settledIndex);
    if (settled === undefined || !this.acceptsAnimationEnd(entries, settledIndex)) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    const settledEntryId = settled.queueEntryId;
    if (this.phase === FullPlayerArtworkPagerPhase.PROGRAMMATIC) {
      if (settledEntryId !== this.expectedTargetEntryId) {
        return FullPlayerArtworkPagerCoordinator.none();
      }
      this.phase = FullPlayerArtworkPagerPhase.IDLE;
      this.userSettleArmed = false;
      this.semanticEntryId = settledEntryId;
      this.expectedTargetEntryId = undefined;
      const pending = this.pendingExternalEntryId;
      this.pendingExternalEntryId = undefined;
      if (pending !== undefined && pending !== settledEntryId) {
        return this.beginProgrammatic(entries, pending, looping);
      }
      return FullPlayerArtworkPagerCoordinator.none();
    }
    if (this.phase !== FullPlayerArtworkPagerPhase.USER_SETTLING) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    const desiredEntryId = this.pendingExternalEntryId ?? this.expectedTargetEntryId;
    this.phase = FullPlayerArtworkPagerPhase.IDLE;
    this.userSettleArmed = false;
    this.expectedTargetEntryId = undefined;
    this.pendingExternalEntryId = undefined;
    this.semanticEntryId = settledEntryId;
    if (desiredEntryId !== undefined && desiredEntryId !== settledEntryId) {
      return this.beginProgrammatic(entries, desiredEntryId, looping);
    }
    return FullPlayerArtworkPagerCoordinator.none();
  }

  onPageReady(queueEntryId: number, generation: number): boolean {
    if (this.phase !== FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR ||
      generation !== this.readyGeneration ||
      queueEntryId !== this.expectedTargetEntryId) {
      return false;
    }
    this.targetReady = true;
    return this.revealReanchoredPageIfReady(queueEntryId);
  }

  onReanchorApplied(queueEntryId: number, generation: number): boolean {
    if (this.phase !== FullPlayerArtworkPagerPhase.HIDDEN_REANCHOR ||
      generation !== this.readyGeneration ||
      queueEntryId !== this.expectedTargetEntryId) {
      return false;
    }
    this.reanchorApplied = true;
    return this.revealReanchoredPageIfReady(queueEntryId);
  }

  private beginProgrammatic(entries: Array<QueueEntry>, entryId: number,
    looping: boolean): FullPlayerArtworkPagerCommand {
    const targetIndex = FullPlayerArtworkPagerCoordinator.indexOf(entries, entryId);
    if (targetIndex < 0) {
      return FullPlayerArtworkPagerCoordinator.none();
    }
    const currentIndex = this.semanticEntryId === undefined ?
      targetIndex : FullPlayerArtworkPagerCoordinator.indexOf(entries, this.semanticEntryId);
    this.phase = FullPlayerArtworkPagerPhase.PROGRAMMATIC;
    this.expectedTargetEntryId = entryId;
    this.pendingExternalEntryId = undefined;
    const distance = currentIndex < 0 ? entries.length : Math.abs(targetIndex - currentIndex);
    const adjacent = distance <= 1 ||
      (looping && entries.length > 1 && distance === entries.length - 1);
    const mode = adjacent ?
      FullPlayerArtworkPagerScrollMode.DEFAULT : FullPlayerArtworkPagerScrollMode.FAST;
    return FullPlayerArtworkPagerCoordinator.changeIndex(targetIndex, entryId, mode);
  }

  private revealReanchoredPageIfReady(queueEntryId: number): boolean {
    if (!this.reanchorApplied || !this.targetReady) {
      return false;
    }
    this.phase = FullPlayerArtworkPagerPhase.IDLE;
    this.semanticEntryId = queueEntryId;
    this.expectedTargetEntryId = undefined;
    this.pagerVisible = true;
    return true;
  }

  private static entryAt(entries: Array<QueueEntry>, index: number): QueueEntry | undefined {
    return index >= 0 && index < entries.length ? entries[index] : undefined;
  }

  private static indexOf(entries: Array<QueueEntry>, entryId: number): number {
    return entries.findIndex((entry: QueueEntry): boolean => entry.queueEntryId === entryId);
  }

  private static none(): FullPlayerArtworkPagerCommand {
    return {
      kind: FullPlayerArtworkPagerCommandKind.NONE,
      index: -1,
      queueEntryId: -1,
      scrollMode: FullPlayerArtworkPagerScrollMode.NONE
    };
  }

  private static changeIndex(index: number, queueEntryId: number,
    scrollMode: FullPlayerArtworkPagerScrollMode): FullPlayerArtworkPagerCommand {
    return {
      kind: FullPlayerArtworkPagerCommandKind.CHANGE_INDEX,
      index: index,
      queueEntryId: queueEntryId,
      scrollMode: scrollMode
    };
  }

  private static selectEntry(queueEntryId: number): FullPlayerArtworkPagerCommand {
    return {
      kind: FullPlayerArtworkPagerCommandKind.SELECT_ENTRY,
      index: -1,
      queueEntryId: queueEntryId,
      scrollMode: FullPlayerArtworkPagerScrollMode.NONE
    };
  }
}
