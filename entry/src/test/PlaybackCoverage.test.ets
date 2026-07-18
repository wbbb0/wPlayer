import { describe, it, expect } from '@ohos/hypium';
import {
  PlaybackCompletionEvaluation,
  PlaybackCoverageSnapshot,
  PlaybackCoverageTracker
} from '../main/ets/playback/history/PlaybackCoverageTracker';

export default function playbackCoverageTest() {
  describe('PlaybackCoverageTracker', () => {
    it('uses the stricter default threshold on both sides of five minutes', 0, () => {
      expect(PlaybackCoverageTracker.defaultRequiredCoverageMs(60000)).assertEqual(54000);
      expect(PlaybackCoverageTracker.defaultRequiredCoverageMs(300000)).assertEqual(270000);
      expect(PlaybackCoverageTracker.defaultRequiredCoverageMs(600000)).assertEqual(570000);
      expect(PlaybackCoverageTracker.defaultRequiredCoverageMs(1)).assertEqual(1);
      expect(PlaybackCoverageTracker.defaultRequiredCoverageMs(0)).assertEqual(0);
    });

    it('qualifies continuous playback that naturally reaches the end', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(41, 100000);
      tracker.advanceTo(40000);
      tracker.advanceTo(89999);
      const result = tracker.finishNaturally();

      expect(result.trackId).assertEqual(41);
      expect(result.coveredMs).assertEqual(100000);
      expect(result.requiredCoverageMs).assertEqual(90000);
      expect(result.naturallyCompleted).assertTrue();
      expect(result.qualifies).assertTrue();
    });

    it('requires natural completion even after enough audio was covered', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(1, 100000);
      tracker.advanceTo(95000);
      const result = tracker.finishInterrupted();

      expect(result.thresholdReached).assertTrue();
      expect(result.naturallyCompleted).assertFalse();
      expect(result.qualifies).assertFalse();
    });

    it('does not let a stale completion event revive an interrupted attempt', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(1, 100000);
      tracker.advanceTo(95000);
      tracker.finishInterrupted();
      const staleCompletion = tracker.finishNaturally();

      expect(staleCompletion.naturallyCompleted).assertFalse();
      expect(staleCompletion.qualifies).assertFalse();
      expect(staleCompletion.positionMs).assertEqual(95000);
    });

    it('does not count a forward seek as played coverage', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(2, 100000);
      tracker.advanceTo(10000);
      tracker.seekTo(95000);
      const result = tracker.finishNaturally();

      expect(result.coveredMs).assertEqual(15000);
      expect(result.qualifies).assertFalse();
    });

    it('fills missing coverage after a backwards seek without double counting', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(3, 100000);
      tracker.advanceTo(50000);
      tracker.seekTo(20000);
      tracker.advanceTo(70000);
      tracker.seekTo(65000);
      tracker.advanceTo(100000);
      const result = tracker.finishNaturally();

      expect(result.coveredMs).assertEqual(100000);
      expect(result.intervalCount).assertEqual(1);
      expect(result.qualifies).assertTrue();
    });

    it('keeps coverage across pause and resume without counting a resume jump', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(4, 100000);
      tracker.recordPause(40000);
      tracker.recordResume(60000);
      tracker.advanceTo(100000);
      const result = tracker.finishNaturally();

      expect(result.coveredMs).assertEqual(80000);
      expect(result.qualifies).assertFalse();
    });

    it('does not count a resumed prefix from an earlier application session', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(5, 100000, 40000);
      const result = tracker.finishNaturally();

      expect(result.coveredMs).assertEqual(60000);
      expect(result.qualifies).assertFalse();
    });

    it('resets all attempt state when a different track begins', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(6, 100000);
      tracker.advanceTo(75000);
      tracker.begin(7, 200000, 50000);
      const current = tracker.snapshot();

      expect(current.trackId).assertEqual(7);
      expect(current.positionMs).assertEqual(50000);
      expect(current.coveredMs).assertEqual(0);
      expect(current.intervalCount).assertEqual(0);
      expect(current.requiredCoverageMs).assertEqual(180000);
    });

    it('locks the exact threshold boundary for a short track', 0, () => {
      const below = new PlaybackCoverageTracker();
      below.begin(8, 10000);
      below.seekTo(1001);
      const belowResult = below.finishNaturally();
      expect(belowResult.coveredMs).assertEqual(8999);
      expect(belowResult.qualifies).assertFalse();

      const exact = new PlaybackCoverageTracker();
      exact.begin(8, 10000);
      exact.seekTo(1000);
      const exactResult = exact.finishNaturally();
      expect(exactResult.coveredMs).assertEqual(9000);
      expect(exactResult.qualifies).assertTrue();
    });

    it('locks the thirty-second boundary for a long track', 0, () => {
      const below = new PlaybackCoverageTracker();
      below.begin(9, 600000);
      below.seekTo(30001);
      const belowResult = below.finishNaturally();
      expect(belowResult.requiredCoverageMs).assertEqual(570000);
      expect(belowResult.coveredMs).assertEqual(569999);
      expect(belowResult.qualifies).assertFalse();

      const exact = new PlaybackCoverageTracker();
      exact.begin(9, 600000);
      exact.seekTo(30000);
      const exactResult = exact.finishNaturally();
      expect(exactResult.coveredMs).assertEqual(570000);
      expect(exactResult.qualifies).assertTrue();
    });

    it('clamps invalid positions and ignores backwards progress without an explicit seek', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(10, 10000);
      tracker.advanceTo(4000);
      tracker.advanceTo(2000);
      tracker.advanceTo(Number.NaN);
      tracker.advanceTo(20000);
      const current = tracker.snapshot();

      expect(current.positionMs).assertEqual(10000);
      expect(current.coveredMs).assertEqual(10000);
    });

    it('bounds fragmented interval memory without inventing coverage', 0, () => {
      const tracker = new PlaybackCoverageTracker(2);
      tracker.begin(11, 100000);
      tracker.advanceTo(10000);
      tracker.seekTo(20000);
      tracker.advanceTo(30000);
      tracker.seekTo(40000);
      tracker.advanceTo(90000);
      tracker.seekTo(95000);
      const result = tracker.finishNaturally();

      expect(result.intervalCount).assertEqual(2);
      expect(result.capacityExceeded).assertTrue();
      expect(result.coveredMs).assertEqual(20000);
      expect(result.qualifies).assertFalse();
    });

    it('returns immutable values rather than exposing interval storage', 0, () => {
      const tracker = new PlaybackCoverageTracker();
      tracker.begin(12, 20000);
      tracker.advanceTo(5000);
      const first: PlaybackCoverageSnapshot = tracker.snapshot();
      tracker.advanceTo(10000);
      const second: PlaybackCompletionEvaluation = tracker.finishInterrupted();

      expect(first.coveredMs).assertEqual(5000);
      expect(second.coveredMs).assertEqual(10000);
    });
  });
}
