import { describe, it, expect } from '@ohos/hypium';
import { ArtworkLayout } from '../main/ets/components/artwork/ArtworkLayout';
import { ResourceLeaseRegistry } from '../main/ets/playback/artwork/ResourceLeaseRegistry';
import { RequestEpoch } from '../main/ets/playback/support/RequestEpoch';
import { DuplicatePolicy } from '../main/ets/library/importer/DuplicatePolicy';
import { ImportConcurrencyPolicy } from '../main/ets/library/importer/ImportConcurrencyPolicy';
import { ArtworkEncodingPolicy } from '../main/ets/library/artwork/ArtworkEncodingPolicy';
import { ImportPreparationPolicy, PreparedItemState } from
  '../main/ets/library/importer/ImportPreparationPolicy';
import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerMotionSpec
} from '../main/ets/components/player/PlayerMotion';
import { DynamicColor, DynamicContainerRole, ForegroundEmphasis } from
  '../main/ets/appearance/DynamicColor';
import { LyricTimeline } from '../main/ets/playback/lyrics/LyricTimeline';
import { TimedLyricLine } from '../main/ets/playback/lyrics/LyricsParser';
import { LayoutLength } from '../main/ets/components/layout/LayoutLength';
import { PlayerStore } from '../main/ets/playback/model/PlaybackModels';

class FakeResource {
  released: number = 0;
}

export default function riskRegressionTest() {
  describe('Risk regressions', () => {
    it('resolves semantic foregrounds for dynamic artwork colors', 0, () => {
      expect(DynamicColor.foreground('#FFFFFFFF', DynamicContainerRole.PRIMARY)).assertEqual('#FF000000');
      expect(DynamicColor.foreground('#FFFFE000', DynamicContainerRole.PRIMARY)).assertEqual('#FF000000');
      expect(DynamicColor.foreground('#FF111111', DynamicContainerRole.SECONDARY)).assertEqual('#FFFFFFFF');
      expect(DynamicColor.foreground('#111111', DynamicContainerRole.SECONDARY)).assertEqual('#FFFFFFFF');
      expect(DynamicColor.foreground('#FFFFFF00', DynamicContainerRole.ACCENT)).assertEqual('#FFFFFFFF');
      expect(DynamicColor.foreground('invalid', DynamicContainerRole.PRIMARY)).assertEqual('#FFFFFFFF');
      expect(DynamicColor.withEmphasis('#FF000000', ForegroundEmphasis.MEDIUM))
        .assertEqual('#B8000000');
    });

    it('blends the morph replacement surface with its capsule color', 0, () => {
      expect(DynamicColor.blendOpaque(PlayerMotionSpec.COLLAPSED_SURFACE_DARK, '#FF7C4DFF', 0))
        .assertEqual('#FF2B2B2B');
      expect(DynamicColor.blendOpaque('#FFFFFFFF', '#FF7C4DFF', 1)).assertEqual('#FF7C4DFF');
    });

    it('contains landscape and portrait artwork without changing the slot', 0, () => {
      const landscape = ArtworkLayout.containedSize(768, 432, 286, 286);
      const portrait = ArtworkLayout.containedSize(540, 768, 286, 286);
      expect(landscape.width).assertEqual(286);
      expect(Math.round(landscape.height)).assertEqual(161);
      expect(Math.round(portrait.width)).assertEqual(201);
      expect(portrait.height).assertEqual(286);
    });

    it('fades full-player controls between 20 and 80 percent collapse', 0, () => {
      expect(PlayerMotionSpec.fullContentOpacity(1)).assertEqual(1);
      expect(PlayerMotionSpec.fullContentOpacity(0.8)).assertEqual(1);
      expect(Math.abs(PlayerMotionSpec.fullContentOpacity(0.5) - 0.5) < 0.000001).assertTrue();
      expect(PlayerMotionSpec.fullContentOpacity(0.2)).assertEqual(0);
      expect(PlayerMotionSpec.fullContentOpacity(0)).assertEqual(0);
    });

    it('derives one or two full-player panes from measured geometry', 0, () => {
      expect(FullPlayerPagerSpec.paneCount(720, 1280)).assertEqual(1);
      expect(FullPlayerPagerSpec.paneCount(1280, 720)).assertEqual(2);
      expect(FullPlayerPagerSpec.pageSpan(1280, 2)).assertEqual(640);
      expect(FullPlayerPagerSpec.positionForPage(FullPlayerPage.QUEUE, 2)).assertEqual(0);
      expect(FullPlayerPagerSpec.positionForPage(FullPlayerPage.LYRICS, 2)).assertEqual(1);
    });

    it('reveals the artwork proxy only while a side page hands off', 0, () => {
      expect(FullPlayerPagerSpec.coverVisibility(FullPlayerPage.LYRICS, 1, 1)).assertEqual(0);
      expect(FullPlayerPagerSpec.coverVisibility(FullPlayerPage.QUEUE, 1, 1)).assertEqual(0);
      expect(FullPlayerPagerSpec.coverVisibility(FullPlayerPage.COVER, 1, 1)).assertEqual(1);
      expect(FullPlayerPagerSpec.coverVisibility(FullPlayerPage.LYRICS, 1, 0.7)).assertEqual(1);
      expect(FullPlayerPagerSpec.coverVisibility(1, 2, 1)).assertEqual(1);
    });

    it('removes the render-only pager offset from measured artwork geometry', 0, () => {
      const layoutX = 440;
      const pageSpan = 360;
      expect(FullPlayerPagerSpec.artworkTargetX(layoutX, FullPlayerPage.QUEUE, pageSpan)).assertEqual(440);
      expect(FullPlayerPagerSpec.artworkTargetX(layoutX, FullPlayerPage.COVER, pageSpan)).assertEqual(80);
      expect(FullPlayerPagerSpec.artworkTargetX(layoutX, FullPlayerPage.LYRICS, pageSpan)).assertEqual(-280);
      expect(FullPlayerPagerSpec.centeredArtworkTargetX(layoutX, pageSpan)).assertEqual(80);
      expect(FullPlayerPagerSpec.pagerArtworkTargetX(80, FullPlayerPage.QUEUE, pageSpan)).assertEqual(440);
      expect(FullPlayerPagerSpec.pagerArtworkTargetX(80, FullPlayerPage.COVER, pageSpan)).assertEqual(80);
      expect(FullPlayerPagerSpec.pagerArtworkTargetX(80, FullPlayerPage.LYRICS, pageSpan)).assertEqual(-280);
    });

    it('does not release an artwork while a transition lease is active', 0, () => {
      const registry = new ResourceLeaseRegistry<FakeResource>((resource: FakeResource) => {
        resource.released += 1;
      });
      const resource = new FakeResource();
      registry.acquire(resource);
      registry.requestRelease(resource);
      expect(resource.released).assertEqual(0);
      registry.release(resource);
      expect(resource.released).assertEqual(1);
    });

    it('invalidates stale playback requests immediately', 0, () => {
      const epoch = new RequestEpoch();
      const first = epoch.begin();
      epoch.invalidate();
      expect(epoch.isCurrent(first)).assertFalse();
      const second = epoch.begin();
      expect(epoch.isCurrent(second)).assertTrue();
    });

    it('never treats a quick fingerprint as final duplicate proof', 0, () => {
      expect(DuplicatePolicy.isConfirmedDuplicate('quick', 'quick', 'full-a', 'full-b')).assertFalse();
      expect(DuplicatePolicy.isConfirmedDuplicate('quick', 'quick', 'full-a', 'full-a')).assertTrue();
      expect(DuplicatePolicy.isConfirmedDuplicate('quick-a', 'quick-b', 'full-a', 'full-a')).assertTrue();
    });

    it('calculates a full fingerprint only when duplicate proof is needed', 0, () => {
      expect(ImportConcurrencyPolicy.needsFullFingerprint(0, 1)).assertFalse();
      expect(ImportConcurrencyPolicy.needsFullFingerprint(1, 1)).assertTrue();
      expect(ImportConcurrencyPolicy.needsFullFingerprint(0, 2)).assertTrue();
      expect(ImportConcurrencyPolicy.FILE_PROBE_CONCURRENCY).assertEqual(3);
    });

    it('uses broadly supported JPEG files for persistent artwork variants', 0, () => {
      expect(ArtworkEncodingPolicy.MIME_TYPE).assertEqual('image/jpeg');
      expect(ArtworkEncodingPolicy.EXTENSION).assertEqual('jpg');
      expect(ArtworkEncodingPolicy.QUALITY).assertLarger(0);
      expect(ArtworkEncodingPolicy.QUALITY).assertLess(101);
    });

    it('classifies an early duplicate without an import input as duplicate', 0, () => {
      expect(ImportPreparationPolicy.classify(false, true, false))
        .assertEqual(PreparedItemState.DUPLICATE);
    });

    it('finds the last active lyric line with duplicate timestamps', 0, () => {
      const lines: Array<TimedLyricLine> = [
        { timeMs: 1000, text: 'first' },
        { timeMs: 2000, text: 'second' },
        { timeMs: 2000, text: 'second duplicate' },
        { timeMs: 5000, text: 'last' }
      ];
      expect(LyricTimeline.activeIndexAt(lines, 999)).assertEqual(-1);
      expect(LyricTimeline.activeIndexAt(lines, 1000)).assertEqual(0);
      expect(LyricTimeline.activeIndexAt(lines, 2000)).assertEqual(2);
      expect(LyricTimeline.activeIndexAt(lines, 6000)).assertEqual(3);
    });

    it('keeps the lazy lyric data source synchronized with observable lyrics', 0, () => {
      const store = new PlayerStore();
      const lines: Array<TimedLyricLine> = [
        { timeMs: 100, text: 'one' },
        { timeMs: 200, text: 'two' }
      ];
      store.setTimedLyrics(lines);
      expect(store.timedLyrics.length).assertEqual(2);
      expect(store.lyricDataSource.totalCount()).assertEqual(2);
      expect(store.lyricDataSource.getData(1).text).assertEqual('two');
      store.setTimedLyrics([]);
      expect(store.lyricDataSource.totalCount()).assertEqual(0);
    });

    it('keeps high-frequency playback progress in an isolated state object', 0, () => {
      const store = new PlayerStore();
      store.progress.positionMs = 1500;
      store.progress.durationMs = 3000;
      expect(store.progress.positionMs).assertEqual(1500);
      expect(store.progress.durationMs).assertEqual(3000);
    });

    it('normalizes measured layout lengths without losing the fallback', 0, () => {
      expect(LayoutLength.toNumber(48, 12)).assertEqual(48);
      expect(LayoutLength.toNumber('56vp', 12)).assertEqual(56);
      expect(LayoutLength.toNumber('invalid', 12)).assertEqual(12);
      expect(LayoutLength.toNumber(undefined, 12)).assertEqual(12);
    });
  });
}
