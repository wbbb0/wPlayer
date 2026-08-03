import { PlayerMorphPhase } from './PlayerMotion';

export enum PlayerArtworkPlaybackVisualAction {
  NONE = 0,
  ANIMATE_TO_TARGET = 1
}

export class PlayerArtworkPlaybackVisualState {
  private appliedProgress: number = 1;
  private targetProgress: number = 1;

  reset(progress: number): void {
    const normalizedProgress = this.normalize(progress);
    this.appliedProgress = normalizedProgress;
    this.targetProgress = normalizedProgress;
  }

  updateTarget(progress: number, phase: PlayerMorphPhase): PlayerArtworkPlaybackVisualAction {
    this.targetProgress = this.normalize(progress);
    if (phase !== PlayerMorphPhase.OPEN) {
      return PlayerArtworkPlaybackVisualAction.NONE;
    }
    return this.applyPendingTarget();
  }

  updatePhase(phase: PlayerMorphPhase): PlayerArtworkPlaybackVisualAction {
    if (phase !== PlayerMorphPhase.OPEN) {
      return PlayerArtworkPlaybackVisualAction.NONE;
    }
    return this.applyPendingTarget();
  }

  value(): number {
    return this.appliedProgress;
  }

  private applyPendingTarget(): PlayerArtworkPlaybackVisualAction {
    if (this.appliedProgress === this.targetProgress) {
      return PlayerArtworkPlaybackVisualAction.NONE;
    }
    this.appliedProgress = this.targetProgress;
    return PlayerArtworkPlaybackVisualAction.ANIMATE_TO_TARGET;
  }

  private normalize(progress: number): number {
    return Math.max(0, Math.min(1, progress));
  }
}
