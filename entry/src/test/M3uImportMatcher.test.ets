import { describe, expect, it } from '@ohos/hypium';
import { PlaylistTransferTrack } from '../main/ets/library/model/LibraryModels';
import { M3uImportMatcher } from '../main/ets/playlist/m3u/M3uImportMatcher';
import { M3uEntry } from '../main/ets/playlist/m3u/M3uModels';

function track(id: number, uri: string, displayName: string, title: string,
  artist: string): PlaylistTransferTrack {
  return {
    trackId: id,
    uri: uri,
    displayName: displayName,
    title: title,
    artistDisplay: artist,
    durationMs: 1000,
    firstQualifiedAt: 0,
    lastQualifiedAt: 0
  };
}

function entry(resource: string, title: string | null = null, artist: string | null = null): M3uEntry {
  return {
    resource: resource,
    durationSeconds: null,
    displayTitle: null,
    artist: artist,
    title: title,
    firstCompletedAt: null,
    lastCompletedAt: null,
    duplicateOfIndex: null,
    sourceLine: 1
  };
}

export default function m3uImportMatcherTest() {
  describe('M3uImportMatcher', () => {
    it('prefers an exact opaque URI', 0, () => {
      const matcher = new M3uImportMatcher([
        track(1, 'file://library/first', 'same.mp3', 'First', 'Artist'),
        track(2, 'file://library/second', 'same.mp3', 'Second', 'Artist')
      ]);
      expect(matcher.match(entry('file://library/second'))?.trackId).assertEqual(2);
    });

    it('matches Windows and POSIX references by decoded file name', 0, () => {
      const matcher = new M3uImportMatcher([
        track(3, 'file://library/third', '你好 世界.flac', '你好', '歌手')
      ]);
      expect(matcher.match(entry('C:\\Music\\%E4%BD%A0%E5%A5%BD%20%E4%B8%96%E7%95%8C.flac'))?.trackId)
        .assertEqual(3);
      expect(matcher.match(entry('../Music/你好 世界.flac?source=m3u'))?.trackId).assertEqual(3);
    });

    it('uses title and artist to disambiguate duplicate file names', 0, () => {
      const matcher = new M3uImportMatcher([
        track(4, 'file://library/a', 'track01.mp3', 'Intro', 'Album A'),
        track(5, 'file://library/b', 'track01.mp3', 'Overture', 'Album B')
      ]);
      expect(matcher.match(entry('/backup/track01.mp3', 'Overture', 'Album B'))?.trackId).assertEqual(5);
    });

    it('rejects ambiguous and missing references conservatively', 0, () => {
      const matcher = new M3uImportMatcher([
        track(6, 'file://library/a', 'same.mp3', 'Same', 'Artist'),
        track(7, 'file://library/b', 'same.mp3', 'Same', 'Artist')
      ]);
      expect(matcher.match(entry('same.mp3', 'Same', 'Artist'))).assertUndefined();
      expect(matcher.match(entry('missing.mp3'))).assertUndefined();
    });
  });
}
