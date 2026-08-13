import { PlayerMorphPhase } from './PlayerMotion';

export enum PlayerArtworkPlaybackVisualAction {
  NONE = 0,
  ANIMATE_TO_TARGET = 1
}

@Observed
export class PlayerArtworkVisualBinding {
  progress: number = 1;
}

@Observed
export class PlayerArtworkImmersiveVisualBinding {
  progress: number = 0;
}

@Observed
export class PlayerArtworkSourceBinding {
  private state: PlayerArtworkSourceState = {
    artworkIdentity: '',
    sourceRevision: -1
  };

  sync(largeArtworkHash: string, largeArtworkPath: string, sourceRevision: number): void {
    if (this.state.sourceRevision === sourceRevision) {
      return;
    }
    this.state = {
      artworkIdentity: PlayerArtworkSourceBinding.identityOf(
        largeArtworkHash,
        largeArtworkPath
      ),
      sourceRevision: sourceRevision
    };
  }

  matches(largeArtworkHash: string, largeArtworkPath: string): boolean {
    return this.state.artworkIdentity === PlayerArtworkSourceBinding.identityOf(
      largeArtworkHash,
      largeArtworkPath
    );
  }

  actorRevision(queueEntryId: number, largeArtworkHash: string,
    largeArtworkPath: string, usesCurrentSource: boolean = true): number {
    if (usesCurrentSource && this.matches(largeArtworkHash, largeArtworkPath)) {
      return this.state.sourceRevision * 2 + 1;
    }
    return queueEntryId * 2;
  }

  private static identityOf(largeArtworkHash: string, largeArtworkPath: string): string {
    return largeArtworkHash.length > 0 ? `hash:${largeArtworkHash}` : `path:${largeArtworkPath}`;
  }
}

interface PlayerArtworkSourceState {
  artworkIdentity: string;
  sourceRevision: number;
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
