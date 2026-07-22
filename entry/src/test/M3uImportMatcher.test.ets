import { describe, expect, it } from '@ohos/hypium';
import { PlaylistTransferTrack } from '../main/ets/library/model/LibraryModels';
import { M3uImportMatcher } from '../main/ets/playlist/m3u/M3uImportMatcher';
import { M3uEntry } from '../main/ets/playlist/m3u/M3uModels';

function track(id: number, uri: string, displayName: string, title: string,
  artist: string, album: string = '', durationMs: number = 1000): PlaylistTransferTrack {
  return {
    trackId: id,
    uri: uri,
    displayName: displayName,
    title: title,
    artistDisplay: artist,
    albumDisplay: album,
    durationMs: durationMs,
    firstQualifiedAt: 0,
    lastQualifiedAt: 0
  };
}

function entry(resource: string, title: string | null = null, artist: string | null = null,
  album: string | null = null, durationSeconds: number | null = null): M3uEntry {
  return {
    resource: resource,
    durationSeconds: durationSeconds,
    displayTitle: null,
    artist: artist,
    title: title,
    album: album,
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

    it('does not accept a single file name match when metadata conflicts', 0, () => {
      const matcher = new M3uImportMatcher([
        track(24, 'file://library/wrong', 'same.mp3', 'Wrong Song', 'Artist', 'Wrong Album', 211000),
        track(25, 'file://library/right', 'right.mp3', 'Right Song', 'Artist', 'Right Album', 211000)
      ]);
      expect(matcher.match(entry('/backup/same.mp3', 'Right Song', 'Artist', 'Right Album', 211))?.trackId)
        .assertEqual(25);
    });

    it('uses title and artist to disambiguate duplicate file names', 0, () => {
      const matcher = new M3uImportMatcher([
        track(4, 'file://library/a', 'track01.mp3', 'Intro', 'Album A'),
        track(5, 'file://library/b', 'track01.mp3', 'Overture', 'Album B')
      ]);
      expect(matcher.match(entry('/backup/track01.mp3', 'Overture', 'Album B'))?.trackId).assertEqual(5);
    });

    it('does not disambiguate duplicate file names by duration alone', 0, () => {
      const matcher = new M3uImportMatcher([
        track(20, 'file://library/a', 'track01.mp3', 'Intro', 'Artist A', 'Album A', 211000),
        track(21, 'file://library/b', 'track01.mp3', 'Overture', 'Artist B', 'Album B', 240000)
      ]);
      expect(matcher.match(entry('/backup/track01.mp3', null, null, null, 211))).assertUndefined();
    });

    it('does not let duration beat an album mismatch for duplicate file names', 0, () => {
      const matcher = new M3uImportMatcher([
        track(26, 'file://library/a', 'track01.mp3', 'Same Title', 'Artist', 'Album A', 211000),
        track(27, 'file://library/b', 'track01.mp3', 'Same Title', 'Artist', 'Album B', 240000)
      ]);
      expect(matcher.match(entry('/backup/track01.mp3', 'Same Title', 'Artist', 'Album B', 211))).assertUndefined();
    });

    it('uses duration only after metadata disambiguates duplicate file names', 0, () => {
      const matcher = new M3uImportMatcher([
        track(22, 'file://library/a', 'track01.mp3', 'Same Title', 'Artist', 'Album A', 211000),
        track(23, 'file://library/b', 'track01.mp3', 'Same Title', 'Artist', 'Album B', 240000)
      ]);
      expect(matcher.match(entry('/backup/track01.mp3', 'Same Title', 'Artist', 'Album A', 212))?.trackId)
        .assertEqual(22);
      expect(matcher.match(entry('/backup/track01.mp3', 'Same Title', 'Artist', 'Album A', 240))).assertUndefined();
    });

    it('rejects ambiguous and missing references conservatively', 0, () => {
      const matcher = new M3uImportMatcher([
        track(6, 'file://library/a', 'same.mp3', 'Same', 'Artist'),
        track(7, 'file://library/b', 'same.mp3', 'Same', 'Artist')
      ]);
      expect(matcher.match(entry('same.mp3', 'Same', 'Artist'))).assertUndefined();
      expect(matcher.match(entry('missing.mp3'))).assertUndefined();
    });

    it('falls back to title artist album and duration after path misses', 0, () => {
      const matcher = new M3uImportMatcher([
        track(8, 'file://library/studio', 'studio.m4a', 'Same Song', 'Artist', 'Studio', 210000),
        track(9, 'file://library/live', 'live.m4a', 'Same Song', 'Artist', 'Live', 210000)
      ]);
      expect(matcher.match(entry('/other-device/unknown.m4a', 'Same Song', 'Artist', 'Live', 211))?.trackId)
        .assertEqual(9);
    });

    it('uses title artist album without duration only when unique', 0, () => {
      const matcher = new M3uImportMatcher([
        track(10, 'file://library/a', 'a.m4a', 'Title', 'Artist', 'Album', 200000),
        track(11, 'file://library/b', 'b.m4a', 'Title', 'Artist', 'Album', 240000),
        track(12, 'file://library/c', 'c.m4a', 'Title', 'Artist', 'Other Album', 240000)
      ]);
      expect(matcher.match(entry('/missing/a.m4a', 'Title', 'Artist', 'Other Album'))?.trackId).assertEqual(12);
      expect(matcher.match(entry('/missing/b.m4a', 'Title', 'Artist', 'Album'))).assertUndefined();
    });

    it('does not ignore duration when title artist album is present', 0, () => {
      const matcher = new M3uImportMatcher([
        track(13, 'file://library/a', 'a.m4a', 'Title', 'Artist', 'Album', 200000),
        track(14, 'file://library/b', 'b.m4a', 'Title', 'Artist', 'Album', 240000)
      ]);
      expect(matcher.match(entry('/missing/a.m4a', 'Title', 'Artist', 'Album', 201))?.trackId).assertEqual(13);
      expect(matcher.match(entry('/missing/b.m4a', 'Title', 'Artist', 'Album', 220))).assertUndefined();
    });
  });
}
