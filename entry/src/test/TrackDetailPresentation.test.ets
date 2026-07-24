import { describe, expect, it } from '@ohos/hypium';
import {
  AvailabilityState,
  CreditRole,
  MediaFormat,
  TrackDetail
} from '../main/ets/library/model/LibraryModels';
import {
  DetailAction,
  DetailRenderer,
  TrackDetailPresenter
} from '../main/ets/library/presentation/TrackDetailPresentation';

function detailFixture(): TrackDetail {
  return {
    id: 7,
    title: 'Song',
    sortTitle: '',
    artistDisplay: 'Artist',
    albumDisplay: 'Album',
    albumArtistDisplay: 'Album Artist',
    composerDisplay: '',
    trackNumber: 2,
    totalTrackCount: 12,
    trackNumberRaw: '2/12',
    discNumber: 1,
    totalDiscCount: 1,
    discNumberRaw: '',
    releaseDateRaw: '2026',
    originalReleaseDateRaw: '',
    durationMs: 3723000,
    sampleRate: 48000,
    channelCount: 2,
    bitsPerSample: 24,
    bitRate: 960000,
    displayName: 'Song.flac',
    uri: 'file://media/Photo/%E9%9F%B3%E4%B9%90/Song.flac',
    fileSize: 1536,
    modifiedAt: 0,
    format: MediaFormat.FLAC,
    mimeType: 'audio/flac',
    authorizationPersisted: true,
    availability: AvailabilityState.AVAILABLE,
    artworkPath: '',
    artworkWidth: 0,
    artworkHeight: 0,
    palettePrimary: '#FF000000',
    credits: [
      {
        role: CreditRole.TRACK_ARTIST,
        name: 'Artist',
        ordinal: 0
      }
    ],
    genres: ['Rock', 'Pop'],
    rawTags: [
      { key: 'TIT2', ordinal: 0, value: 'Song' },
      { key: 'VENDOR_TAG', ordinal: 0, value: 'Vendor Value' }
    ],
    artworks: []
  };
}

export default function trackDetailPresentationTest() {
  describe('Track detail presentation', () => {
    it('normalizes compatibility forms without rewriting tag punctuation', 0, () => {
      expect(TrackDetailPresenter.normalizeTagKey(' ＴＩＴ２ ')).assertEqual('TIT2');
      expect(TrackDetailPresenter.normalizeTagKey('vendor-tag.name'))
        .assertEqual('VENDOR-TAG.NAME');
    });

    it('maps known tags and preserves unknown tag labels', 0, () => {
      const known = TrackDetailPresenter.rawTagRow({
        key: 'tit2',
        ordinal: 0,
        value: 'Song'
      });
      const unknown = TrackDetailPresenter.rawTagRow({
        key: 'VENDOR_TAG',
        ordinal: 1,
        value: '  raw value  '
      });
      expect(known === undefined).assertFalse();
      expect(unknown === undefined).assertFalse();
      if (known === undefined || unknown === undefined) {
        return;
      }
      expect(known.label).assertEqual('标题');
      expect(known.id).assertEqual('raw:TIT2:tit2:0');
      expect(known.sectionId).assertEqual('metadata-basic');
      expect(unknown.label).assertEqual('VENDOR_TAG');
      expect(unknown.sectionId).assertEqual('metadata-other');
      expect(unknown.displayValue).assertEqual('raw value');
      expect(unknown.copyValue).assertEqual('  raw value  ');
    });

    it('omits empty raw tags', 0, () => {
      const row = TrackDetailPresenter.rawTagRow({
        key: 'EMPTY',
        ordinal: 0,
        value: '   '
      });
      expect(row === undefined).assertTrue();
    });

    it('decodes valid URI text and keeps malformed URI text intact', 0, () => {
      expect(TrackDetailPresenter.displayUri('file://media/%E9%9F%B3%E4%B9%90/a.flac'))
        .assertEqual('file://media/音乐/a.flac');
      expect(TrackDetailPresenter.displayUri('file://media/%E9%ZZ/a.flac'))
        .assertEqual('file://media/%E9%ZZ/a.flac');
    });

    it('renders URI tags readably while preserving exact copy data', 0, () => {
      const row = TrackDetailPresenter.rawTagRow({
        key: 'URI',
        ordinal: 0,
        value: 'file://media/%E9%9F%B3%E4%B9%90/a.flac'
      });
      expect(row === undefined).assertFalse();
      if (row === undefined) {
        return;
      }
      expect(row.renderer).assertEqual(DetailRenderer.URI);
      expect(row.sectionId).assertEqual('metadata-technical');
      expect(row.displayValue).assertEqual('file://media/音乐/a.flac');
      expect(row.copyValue).assertEqual('file://media/%E9%9F%B3%E4%B9%90/a.flac');
      expect(row.actions[0]).assertEqual(DetailAction.COPY_EXACT);
    });

    it('builds stable sections and separates URI display from exact copy', 0, () => {
      const page = TrackDetailPresenter.present(detailFixture());
      expect(page.sections.length).assertEqual(3);
      expect(page.sections[0].id).assertEqual('metadata-basic');
      expect(page.sections[0].title).assertEqual('基础标签');
      expect(page.sections[0].rows[0].label).assertEqual('标题');
      expect(page.sections[1].title).assertEqual('其他标签（1）');
      expect(page.sections[1].rows[0].label).assertEqual('VENDOR_TAG');

      const fileRows = page.sections[2].rows;
      const uriRow = fileRows[fileRows.length - 1];
      expect(uriRow.renderer).assertEqual(DetailRenderer.URI);
      expect(uriRow.displayValue).assertEqual('file://media/Photo/音乐/Song.flac');
      expect(uriRow.copyValue)
        .assertEqual('file://media/Photo/%E9%9F%B3%E4%B9%90/Song.flac');
      expect(uriRow.actions[0]).assertEqual(DetailAction.COPY_EXACT);
    });

    it('omits dynamically generated sections when their providers have no rows', 0, () => {
      const detail = detailFixture();
      detail.rawTags = [];
      const page = TrackDetailPresenter.present(detail);
      expect(page.sections.length).assertEqual(1);
      expect(page.sections[0].id).assertEqual('file');
    });

    it('keeps specialized metadata renderers in their assigned category', 0, () => {
      const detail = detailFixture();
      detail.rawTags = [
        { key: 'ISRC', ordinal: 0, value: 'CN-A01-26-00001' }
      ];
      const page = TrackDetailPresenter.present(detail);
      expect(page.sections.length).assertEqual(2);
      expect(page.sections[0].id).assertEqual('metadata-identifiers');
      expect(page.sections[0].rows[0].renderer).assertEqual(DetailRenderer.MONOSPACE);
    });

    it('groups metadata by rule and summarizes lyrics as non-empty line count', 0, () => {
      const detail = detailFixture();
      detail.rawTags = [
        { key: 'TPE1', ordinal: 0, value: 'Artist' },
        { key: 'TDRC', ordinal: 0, value: '2026' },
        { key: 'USLT', ordinal: 0, value: 'line one\n\nline two\r\nline three' },
        { key: 'VENDOR_TAG', ordinal: 0, value: 'Vendor Value' }
      ];
      const page = TrackDetailPresenter.present(detail);
      expect(page.sections.length).assertEqual(5);
      expect(page.sections[0].id).assertEqual('metadata-people');
      expect(page.sections[1].id).assertEqual('metadata-release');
      expect(page.sections[2].id).assertEqual('metadata-content');
      expect(page.sections[2].rows[0].renderer).assertEqual(DetailRenderer.LYRICS);
      expect(page.sections[2].rows[0].displayValue).assertEqual('3 行');
      expect(page.sections[3].id).assertEqual('metadata-other');
      expect(page.sections[4].id).assertEqual('file');
      expect(TrackDetailPresenter.lyricLineCount('\nfirst\n \nsecond\n')).assertEqual(2);
    });

    it('formats duration and file size consistently', 0, () => {
      expect(TrackDetailPresenter.formatDuration(3723000)).assertEqual('1:02:03');
      expect(TrackDetailPresenter.formatDuration(65000)).assertEqual('1:05');
      expect(TrackDetailPresenter.formatFileSize(1536)).assertEqual('1.5 KB');
      expect(TrackDetailPresenter.formatFileSize(0)).assertEqual('未知');
    });
  });
}
