import { describe, it, expect } from '@ohos/hypium';
import { M3uCodec } from '../main/ets/playlist/m3u/M3uCodec';
import { M3uEncoding } from '../main/ets/playlist/m3u/M3uEncoding';
import { M3uEncodingConfidence, M3uIssueKind } from '../main/ets/playlist/m3u/M3uModels';

function utf16Bytes(text: string, littleEndian: boolean, includeBom: boolean): Uint8Array {
  const offset = includeBom ? 2 : 0;
  const result = new Uint8Array(offset + text.length * 2);
  if (includeBom) {
    result[0] = littleEndian ? 0xFF : 0xFE;
    result[1] = littleEndian ? 0xFE : 0xFF;
  }
  for (let index = 0; index < text.length; index += 1) {
    const value = text.charCodeAt(index);
    const byteIndex = offset + index * 2;
    result[byteIndex] = littleEndian ? value & 0xFF : value >> 8;
    result[byteIndex + 1] = littleEndian ? value >> 8 : value & 0xFF;
  }
  return result;
}

export default function m3uCodecTest() {
  describe('M3uCodec', () => {
    it('round trips extended M3U metadata and UTF-8 text', 0, () => {
      const serialized = M3uCodec.serialize([{
        resource: 'file://media/周杰伦/轨迹.m4a',
        durationSeconds: 213,
        artist: '周杰伦',
        title: '轨迹',
        album: '寻找周杰伦',
        firstCompletedAt: 1700000000123,
        lastCompletedAt: 1700009000456
      }]);
      expect(serialized.startsWith('#EXTM3U\r\n')).assertTrue();
      const bytes = M3uEncoding.encodeUtf8(serialized, true);
      const decision = M3uEncoding.detect(bytes);
      expect(decision.label).assertEqual('utf-8');
      expect(decision.bomLength).assertEqual(3);
      const parsed = M3uCodec.parse(M3uEncoding.decode(bytes, decision));
      expect(parsed.entries.length).assertEqual(1);
      expect(parsed.entries[0].resource).assertEqual('file://media/周杰伦/轨迹.m4a');
      expect(parsed.entries[0].artist).assertEqual('周杰伦');
      expect(parsed.entries[0].title).assertEqual('轨迹');
      expect(parsed.entries[0].album).assertEqual('寻找周杰伦');
      expect(parsed.entries[0].durationSeconds).assertEqual(213);
      expect(parsed.entries[0].firstCompletedAt).assertEqual(1700000000123);
      expect(parsed.entries[0].lastCompletedAt).assertEqual(1700009000456);
    });

    it('accepts headerless mixed line endings, quotes, unknown comments and common resources', 0, () => {
      const source = '#EXTVLCOPT:start-time=1\r' +
        '"C:\\Music\\one.mp3"\n' +
        '# a comment\r\n' +
        '\'../Music/two.flac\'\r' +
        'file:///data/storage/el2/base/haps/song.m4a\n' +
        '/storage/media/100/local/files/three.wav';
      const parsed = M3uCodec.parse(source);
      expect(parsed.hadHeader).assertFalse();
      expect(parsed.ignoredCommentCount).assertEqual(2);
      expect(parsed.entries.length).assertEqual(4);
      expect(parsed.entries[0].resource).assertEqual('C:\\Music\\one.mp3');
      expect(parsed.entries[1].resource).assertEqual('../Music/two.flac');
      expect(parsed.entries[2].resource).assertEqual('file:///data/storage/el2/base/haps/song.m4a');
      expect(parsed.entries[3].resource).assertEqual('/storage/media/100/local/files/three.wav');
    });

    it('tolerates non-standard EXTINF while reporting malformed duration', 0, () => {
      const source = '#EXTINF : 203.4 tvg-id="ignored", Artist - Title\nrelative.mp3\n' +
        '#EXTINF:not-a-number,Still usable\nother.mp3\n' +
        '#EXTINF:-1,Unknown duration\nlast.mp3';
      const parsed = M3uCodec.parse(source);
      expect(parsed.entries.length).assertEqual(3);
      expect(parsed.entries[0].durationSeconds).assertEqual(203.4);
      expect(parsed.entries[0].artist).assertEqual('Artist');
      expect(parsed.entries[0].title).assertEqual('Title');
      expect(parsed.entries[1].displayTitle).assertEqual('Still usable');
      expect(parsed.entries[1].durationSeconds === null).assertTrue();
      expect(parsed.entries[2].durationSeconds === null).assertTrue();
      expect(parsed.issues.length).assertEqual(1);
      expect(parsed.issues[0].kind).assertEqual(M3uIssueKind.INVALID_EXTINF);
    });

    it('parses completion timestamps in milliseconds and ISO format', 0, () => {
      const source = '#WPLAYER-FIRST-COMPLETED-AT:1700000000000\n' +
        '#WPLAYER-LAST-COMPLETED-AT:2024-01-02T03:04:05.000Z\nsong.mp3';
      const parsed = M3uCodec.parse(source);
      expect(parsed.entries[0].firstCompletedAt).assertEqual(1700000000000);
      expect(parsed.entries[0].lastCompletedAt).assertEqual(Date.parse('2024-01-02T03:04:05.000Z'));
    });

    it('parses album directives before resource rows', 0, () => {
      const parsed = M3uCodec.parse('#EXTM3U\n#EXTALB:Album A\nsong-a.mp3\n#WPLAYER-ALBUM:Album B\nsong-b.mp3');
      expect(parsed.entries[0].album).assertEqual('Album A');
      expect(parsed.entries[1].album).assertEqual('Album B');
    });

    it('preserves duplicate rows for upper policy and reports invalid resource rows', 0, () => {
      const source = '#EXTM3U\nsong.mp3\nsong.mp3\n""\ninvalid\u0000name.mp3\nother.mp3';
      const parsed = M3uCodec.parse(source);
      expect(parsed.entries.length).assertEqual(3);
      expect(parsed.duplicateCount).assertEqual(1);
      expect(parsed.entries[1].duplicateOfIndex).assertEqual(0);
      expect(parsed.issues.length).assertEqual(2);
      expect(parsed.issues[0].kind).assertEqual(M3uIssueKind.INVALID_RESOURCE);
      expect(parsed.entries[2].resource).assertEqual('other.mp3');
    });
  });

  describe('M3uEncoding', () => {
    it('detects and decodes UTF-8 with and without BOM', 0, () => {
      const source = '#EXTM3U\n歌曲.mp3';
      const plain = M3uEncoding.encodeUtf8(source);
      const withBom = M3uEncoding.encodeUtf8(source, true);
      expect(M3uEncoding.detect(plain).label).assertEqual('utf-8');
      expect(M3uEncoding.decode(plain)).assertEqual(source);
      expect(M3uEncoding.detect(withBom).bomLength).assertEqual(3);
      expect(M3uEncoding.decode(withBom)).assertEqual(source);
    });

    it('detects UTF-16LE and UTF-16BE BOM files', 0, () => {
      const source = '#EXTM3U\n歌曲.mp3';
      const little = utf16Bytes(source, true, true);
      const big = utf16Bytes(source, false, true);
      expect(M3uEncoding.detect(little).label).assertEqual('utf-16le');
      expect(M3uEncoding.detect(big).label).assertEqual('utf-16be');
      expect(M3uEncoding.decode(little)).assertEqual(source);
      expect(M3uEncoding.decode(big)).assertEqual(source);
    });

    it('recognizes BOM-less UTF-16 and exposes legacy decoder candidates', 0, () => {
      const source = '#EXTM3U\nC:\\Music\\song.mp3';
      const little = M3uEncoding.detect(utf16Bytes(source, true, false));
      const big = M3uEncoding.detect(utf16Bytes(source, false, false));
      expect(little.label).assertEqual('utf-16le');
      expect(big.label).assertEqual('utf-16be');
      expect(M3uEncoding.decode(utf16Bytes(source, true, false), little)).assertEqual(source);
      expect(M3uEncoding.decode(utf16Bytes(source, false, false), big)).assertEqual(source);
      expect(little.confidence).assertEqual(M3uEncodingConfidence.LIKELY);

      const legacy = M3uEncoding.detect(new Uint8Array([0x81, 0x30, 0x81, 0x30, 0xFF]));
      expect(legacy.canDecodeDirectly).assertFalse();
      expect(legacy.confidence).assertEqual(M3uEncodingConfidence.UNDETERMINED);
      expect(legacy.fallbackLabels[0]).assertEqual('gb18030');
      expect(legacy.fallbackLabels[1]).assertEqual('big5');

      const big5Hint = M3uEncoding.detect(new Uint8Array([
        0x23, 0x45, 0x58, 0x54, 0x45, 0x4E, 0x43, 0x3A, 0x42, 0x49, 0x47, 0x35, 0x0A, 0xFF
      ]));
      expect(big5Hint.fallbackLabels[0]).assertEqual('big5');
    });
  });
}
