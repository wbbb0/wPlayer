import { describe, it, expect } from '@ohos/hypium';
import { ArtworkLayout } from '../main/ets/components/artwork/ArtworkLayout';
import { ResourceLeaseRegistry } from '../main/ets/playback/artwork/ResourceLeaseRegistry';
import { RequestEpoch } from '../main/ets/playback/support/RequestEpoch';
import { DuplicatePolicy } from '../main/ets/library/importer/DuplicatePolicy';
import { ImportConcurrencyPolicy } from '../main/ets/library/importer/ImportConcurrencyPolicy';
import { ImportDetailPolicy } from '../main/ets/library/importer/ImportDetailPolicy';
import {
  ImportItemDetailKind,
  ImportItemOutcome,
  ImportItemResult,
  ArtworkState
} from '../main/ets/library/model/LibraryModels';
import { ArtworkEncodingPolicy } from '../main/ets/library/artwork/ArtworkEncodingPolicy';
import { ArtworkRepairPolicy } from '../main/ets/library/artwork/ArtworkRepairPolicy';
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
import { LyricsParser, TimedLyricLine } from '../main/ets/playback/lyrics/LyricsParser';
import { LayoutLength } from '../main/ets/components/layout/LayoutLength';
import { AppShellLayoutSpec } from '../main/ets/components/layout/AppShellLayoutSpec';
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
      expect(DynamicColor.withOpacity('#FF336699', 0.60)).assertEqual('#99336699');
      expect(DynamicColor.withOpacity('#FF336699', 2)).assertEqual('#FF336699');
      expect(DynamicColor.withOpacity('invalid', 0.60)).assertEqual('invalid');
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
      expect(Math.round(FullPlayerPagerSpec.swipeCompletionDistance(360))).assertEqual(43);
      expect(FullPlayerPagerSpec.swipeCompletionDistance(800)).assertEqual(56);
    });

    it('keeps the expanded compact mini player clear of collapsed navigation', 0, () => {
      expect(AppShellLayoutSpec.compactExpandedMiniPlayerStart(440, 286)).assertEqual(77);
      expect(AppShellLayoutSpec.compactExpandedMiniPlayerStart(377, 258)).assertEqual(103);
    });

    it('selects a dedicated hidden-tab host only below the horizontal fit threshold', 0, () => {
      expect(AppShellLayoutSpec.hasResolvedRootSize(0, 0)).assertFalse();
      expect(AppShellLayoutSpec.hasResolvedRootSize(326, 0)).assertFalse();
      expect(AppShellLayoutSpec.hasResolvedRootSize(326, 980)).assertTrue();
      expect(AppShellLayoutSpec.usesCondensedCompactNavigation(326)).assertTrue();
      expect(AppShellLayoutSpec.compactTabsHostId(326))
        .assertEqual(AppShellLayoutSpec.CONDENSED_COMPACT_TABS_HOST_ID);
      expect(AppShellLayoutSpec.usesCondensedCompactNavigation(360)).assertFalse();
      expect(AppShellLayoutSpec.compactTabsHostId(377))
        .assertEqual(AppShellLayoutSpec.COMPACT_TABS_HOST_ID);
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
      expect(ImportConcurrencyPolicy.URI_PREFLIGHT_BATCH_SIZE)
        .assertLarger(ImportConcurrencyPolicy.IMPORT_WORK_BATCH_SIZE);
      expect(ImportConcurrencyPolicy.URI_PREFLIGHT_BATCH_SIZE)
        .assertLarger(ImportConcurrencyPolicy.FILE_PERMISSION_BATCH_SIZE);
      expect(ImportConcurrencyPolicy.FILE_CHECK_CLASSIFY_CHUNK_SIZE)
        .assertLess(512);
    });

    it('keeps explicit import detail categories and safely classifies legacy results', 0, () => {
      const uriDuplicate: ImportItemResult = {
        uri: 'uri',
        displayName: 'track',
        outcome: ImportItemOutcome.DUPLICATE,
        reason: 'duplicate',
        detailKind: ImportItemDetailKind.URI_DUPLICATE
      };
      const legacyFailure: ImportItemResult = {
        uri: 'bad',
        displayName: 'bad',
        outcome: ImportItemOutcome.FAILED,
        reason: 'failed'
      };
      expect(ImportDetailPolicy.kindOf(uriDuplicate)).assertEqual(ImportItemDetailKind.URI_DUPLICATE);
      expect(ImportDetailPolicy.kindOf(legacyFailure)).assertEqual(ImportItemDetailKind.FAILED);
      expect(ImportDetailPolicy.shouldRetain(uriDuplicate)).assertTrue();
      const imported: ImportItemResult = {
        uri: 'new',
        displayName: 'new',
        outcome: ImportItemOutcome.IMPORTED,
        reason: 'imported'
      };
      expect(ImportDetailPolicy.shouldRetain(imported)).assertFalse();
    });

    it('uses broadly supported JPEG files for persistent artwork variants', 0, () => {
      expect(ArtworkEncodingPolicy.MIME_TYPE).assertEqual('image/jpeg');
      expect(ArtworkEncodingPolicy.EXTENSION).assertEqual('jpg');
      expect(ArtworkEncodingPolicy.QUALITY).assertLarger(0);
      expect(ArtworkEncodingPolicy.QUALITY).assertLess(101);
    });

    it('repairs incomplete artwork without retrying confirmed absent sources', 0, () => {
      const now = 100_000_000;
      expect(ArtworkRepairPolicy.needsRepair(ArtworkState.ABSENT, false, false)).assertFalse();
      expect(ArtworkRepairPolicy.needsRepair(ArtworkState.PENDING, false, false)).assertTrue();
      expect(ArtworkRepairPolicy.needsRepair(ArtworkState.READY, true, true)).assertFalse();
      expect(ArtworkRepairPolicy.needsRepair(ArtworkState.READY, true, false)).assertTrue();
      expect(ArtworkRepairPolicy.needsRepair(
        ArtworkState.PROCESSING, false, false, 1, now - 1000, now
      )).assertFalse();
      expect(ArtworkRepairPolicy.needsRepair(
        ArtworkState.PROCESSING, false, false, 1, 0, now
      )).assertTrue();
      expect(ArtworkRepairPolicy.needsRepair(
        ArtworkState.FAILED, false, false, 3, now - 1000, now
      )).assertFalse();
      expect(ArtworkRepairPolicy.needsRepair(
        ArtworkState.FAILED, false, false, 3, now - 25 * 60 * 60 * 1000, now
      )).assertTrue();
      expect(ArtworkRepairPolicy.hasSuspiciousLargeVariant(
        256, 256, 25074, 512, 512, 27569
      )).assertTrue();
      expect(ArtworkRepairPolicy.hasSuspiciousLargeVariant(
        256, 256, 34722, 640, 640, 51610
      )).assertTrue();
      expect(ArtworkRepairPolicy.hasSuspiciousLargeVariant(
        256, 256, 28498, 768, 768, 154836
      )).assertFalse();
      expect(ArtworkRepairPolicy.hasOutdatedVariantDimensions(
        640, 640, 256, 256, 640, 640
      )).assertFalse();
      expect(ArtworkRepairPolicy.hasOutdatedVariantDimensions(
        640, 640, 192, 192, 640, 640
      )).assertTrue();
      expect(ArtworkRepairPolicy.shouldRebindSource(7, 8)).assertTrue();
      expect(ArtworkRepairPolicy.shouldRebindSource(7, 7)).assertFalse();
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

    it('parses whole-second and fractional lyric timestamps in milliseconds', 0, () => {
      const parsed = LyricsParser.parse(
        '[00:01]whole\n[00:02.3]tenths\n[00:03.45]hundredths\n[00:04.678]milliseconds'
      );
      expect(parsed.lines.length).assertEqual(4);
      expect(parsed.lines[0].timeMs).assertEqual(1000);
      expect(parsed.lines[1].timeMs).assertEqual(2300);
      expect(parsed.lines[2].timeMs).assertEqual(3450);
      expect(parsed.lines[3].timeMs).assertEqual(4678);
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
