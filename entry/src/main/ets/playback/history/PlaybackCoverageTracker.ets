export interface PlaybackCoverageSnapshot {
  trackId: number;
  durationMs: number;
  positionMs: number;
  coveredMs: number;
  requiredCoverageMs: number;
  coverageRatio: number;
  thresholdReached: boolean;
  intervalCount: number;
  capacityExceeded: boolean;
}

export interface PlaybackCompletionEvaluation extends PlaybackCoverageSnapshot {
  naturallyCompleted: boolean;
  qualifies: boolean;
}

interface PlaybackCoverageInterval {
  startMs: number;
  endMs: number;
}

/**
 * Tracks the positions that were actually played during one playback attempt.
 *
 * Call advanceTo() only for ordinary, continuous playback progress. A seek or
 * any other discontinuous position change must use discontinuityTo(), because
 * moving the playhead is not evidence that the skipped range was played.
 *
 * The tracker has no clock or platform dependency. Pausing therefore preserves
 * coverage naturally. recordPause()/recordResume() are convenience methods for
 * integrations that publish explicit pause boundaries.
 */
export class PlaybackCoverageTracker {
  static readonly DEFAULT_REQUIRED_RATIO: number = 0.9;
  static readonly DEFAULT_MAX_MISSING_MS: number = 30000;
  static readonly DEFAULT_MAX_INTERVALS: number = 256;

  private readonly maxIntervals: number;
  private intervals: Array<PlaybackCoverageInterval> = [];
  private activeTrackId: number = -1;
  private durationMs: number = 0;
  private positionMs: number = 0;
  private coveredMs: number = 0;
  private requiredCoverageMs: number = 0;
  private finished: boolean = false;
  private naturallyCompleted: boolean = false;
  private capacityExceeded: boolean = false;

  constructor(maxIntervals: number = PlaybackCoverageTracker.DEFAULT_MAX_INTERVALS) {
    this.maxIntervals = Number.isFinite(maxIntervals) && maxIntervals > 0 ?
      Math.max(1, Math.floor(maxIntervals)) : PlaybackCoverageTracker.DEFAULT_MAX_INTERVALS;
  }

  /**
   * Starts a new playback attempt and discards all coverage from the old track.
   * A non-zero initial position is a resume/seek position and does not imply
   * that the preceding portion was played in this attempt.
   */
  begin(trackId: number, durationMs: number, initialPositionMs: number = 0): void {
    this.intervals = [];
    this.activeTrackId = trackId;
    this.durationMs = PlaybackCoverageTracker.validDuration(durationMs);
    this.positionMs = this.clampPosition(initialPositionMs);
    this.coveredMs = 0;
    this.requiredCoverageMs = PlaybackCoverageTracker.defaultRequiredCoverageMs(this.durationMs);
    this.finished = false;
    this.naturallyCompleted = false;
    this.capacityExceeded = false;
  }

  /**
   * Records continuous playback from the last playhead position to positionMs.
   * Backwards values are ignored: callers must explicitly identify a backwards
   * seek with discontinuityTo() before subsequent progress can fill that range.
   */
  advanceTo(positionMs: number): void {
    if (!this.isActive()) {
      return;
    }
    const target = this.clampPosition(positionMs);
    if (target <= this.positionMs) {
      return;
    }
    this.addCoveredInterval(this.positionMs, target);
    this.positionMs = target;
  }

  /**
   * Moves the playhead without marking the crossed range as played.
   * Use this for both explicit seeks and position discontinuities reported by
   * the playback engine.
   */
  discontinuityTo(positionMs: number): void {
    if (!this.isActive()) {
      return;
    }
    this.positionMs = this.clampPosition(positionMs);
  }

  seekTo(positionMs: number): void {
    this.discontinuityTo(positionMs);
  }

  /**
   * Captures the final continuous progress callback before a pause.
   */
  recordPause(positionMs: number): void {
    this.advanceTo(positionMs);
  }

  /**
   * Resumes without connecting two positions across the paused interval.
   * Existing coverage remains intact.
   */
  recordResume(positionMs: number): void {
    this.discontinuityTo(positionMs);
  }

  /**
   * Evaluates a natural AVPlayer completion. The final tail is continuous
   * playback, so a missing final position callback is safely completed here.
   */
  finishNaturally(finalPositionMs: number = this.durationMs): PlaybackCompletionEvaluation {
    if (this.finished) {
      return this.completionEvaluation(this.naturallyCompleted);
    }
    this.advanceTo(finalPositionMs);
    this.finished = true;
    this.naturallyCompleted = true;
    return this.completionEvaluation(true);
  }

  /**
   * Ends an attempt because of stop, track switching, or an error. It can never
   * qualify, even when its covered range happens to meet the numeric threshold.
   */
  finishInterrupted(finalPositionMs: number = this.positionMs): PlaybackCompletionEvaluation {
    if (this.finished) {
      return this.completionEvaluation(this.naturallyCompleted);
    }
    this.advanceTo(finalPositionMs);
    this.finished = true;
    this.naturallyCompleted = false;
    return this.completionEvaluation(false);
  }

  snapshot(): PlaybackCoverageSnapshot {
    const ratio = this.durationMs > 0 ? this.coveredMs / this.durationMs : 0;
    return {
      trackId: this.activeTrackId,
      durationMs: this.durationMs,
      positionMs: this.positionMs,
      coveredMs: this.coveredMs,
      requiredCoverageMs: this.requiredCoverageMs,
      coverageRatio: ratio,
      thresholdReached: this.requiredCoverageMs > 0 && this.coveredMs >= this.requiredCoverageMs,
      intervalCount: this.intervals.length,
      capacityExceeded: this.capacityExceeded
    };
  }

  static defaultRequiredCoverageMs(durationMs: number): number {
    const duration = PlaybackCoverageTracker.validDuration(durationMs);
    if (duration === 0) {
      return 0;
    }
    const ratioRequirement = Math.ceil(duration * PlaybackCoverageTracker.DEFAULT_REQUIRED_RATIO);
    const missingTimeRequirement = Math.max(0, duration - PlaybackCoverageTracker.DEFAULT_MAX_MISSING_MS);
    return Math.max(ratioRequirement, missingTimeRequirement);
  }

  private completionEvaluation(naturallyCompleted: boolean): PlaybackCompletionEvaluation {
    const current = this.snapshot();
    return {
      trackId: current.trackId,
      durationMs: current.durationMs,
      positionMs: current.positionMs,
      coveredMs: current.coveredMs,
      requiredCoverageMs: current.requiredCoverageMs,
      coverageRatio: current.coverageRatio,
      thresholdReached: current.thresholdReached,
      intervalCount: current.intervalCount,
      capacityExceeded: current.capacityExceeded,
      naturallyCompleted: naturallyCompleted,
      qualifies: naturallyCompleted && current.thresholdReached
    };
  }

  private addCoveredInterval(startMs: number, endMs: number): void {
    if (endMs <= startMs) {
      return;
    }
    const first = this.firstMergeCandidate(startMs);

    let mergedStart = startMs;
    let mergedEnd = endMs;
    let afterLast = first;
    let removedCoverage = 0;
    while (afterLast < this.intervals.length && this.intervals[afterLast].startMs <= mergedEnd) {
      const interval = this.intervals[afterLast];
      mergedStart = Math.min(mergedStart, interval.startMs);
      mergedEnd = Math.max(mergedEnd, interval.endMs);
      removedCoverage += interval.endMs - interval.startMs;
      afterLast += 1;
    }

    const removedCount = afterLast - first;
    if (removedCount === 0 && this.intervals.length >= this.maxIntervals) {
      // Conservative bounded-memory fallback: ignore an additional disjoint
      // range instead of bridging an unplayed gap and producing a false positive.
      this.capacityExceeded = true;
      return;
    }

    const merged: PlaybackCoverageInterval = {
      startMs: mergedStart,
      endMs: mergedEnd
    };
    this.intervals.splice(first, removedCount, merged);
    this.coveredMs += mergedEnd - mergedStart - removedCoverage;
  }

  private firstMergeCandidate(startMs: number): number {
    let low = 0;
    let high = this.intervals.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.intervals[middle].endMs < startMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  private isActive(): boolean {
    return this.activeTrackId >= 0 && this.durationMs > 0 && !this.finished;
  }

  private clampPosition(positionMs: number): number {
    if (!Number.isFinite(positionMs)) {
      return 0;
    }
    return Math.max(0, Math.min(this.durationMs, Math.floor(positionMs)));
  }

  private static validDuration(durationMs: number): number {
    if (!Number.isFinite(durationMs) || durationMs <= 0) {
      return 0;
    }
    return Math.floor(durationMs);
  }
}
