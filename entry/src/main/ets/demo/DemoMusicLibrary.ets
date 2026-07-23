import {
  AlbumDetail,
  AlbumListItem,
  AlbumReference,
  AlbumSortField,
  ArtistDetail,
  ArtistReference,
  AvailabilityState,
  LibraryIndexPresentation,
  LibrarySnapshot,
  LibraryStatistics,
  MediaFormat,
  PlaylistDetail,
  PlaylistItemSource,
  PlaylistKind,
  PlaylistSortField,
  PlaylistSummary,
  PlaylistTrackItem,
  PlaylistTrackSortField,
  SortDirection,
  TrackDetail,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField
} from '../library/model/LibraryModels';
import { PlaybackTrack, QueueTrack, ResumeState } from '../playback/model/PlaybackModels';

export const DEMO_ARTWORK_PREFIX: string = 'demo-artwork://';

const DEMO_ARTIST_LIN_YU: ArtistReference = { id: -2001, name: '林屿' };
const DEMO_ARTIST_DAYLIGHT: ArtistReference = { id: -2002, name: '白昼信号' };
const DEMO_ARTIST_NORTH_STATION: ArtistReference = { id: -2003, name: '北站' };

const DEMO_TRACKS: Array<TrackListItem> = [
  {
    id: -1001, title: '雨停之后', artistDisplay: '林屿', albumDisplay: '城市微光',
    durationMs: 222000, trackNumber: 1, discNumber: 1,
    smallArtworkHash: 'demo-city', smallArtworkPath: 'demo-artwork://city',
    artworkHash: 'demo-city', artworkPath: 'demo-artwork://city',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF4E6C89', paletteSecondary: '#FF91A8BD', paletteAccent: '#FFFFC978',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1002, title: '星光缓慢', artistDisplay: '林屿', albumDisplay: '城市微光',
    durationMs: 256000, trackNumber: 2, discNumber: 1,
    smallArtworkHash: 'demo-city', smallArtworkPath: 'demo-artwork://city',
    artworkHash: 'demo-city', artworkPath: 'demo-artwork://city',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF4E6C89', paletteSecondary: '#FF91A8BD', paletteAccent: '#FFFFC978',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1003, title: '风经过窗边', artistDisplay: '林屿', albumDisplay: '城市微光',
    durationMs: 176000, trackNumber: 3, discNumber: 1,
    smallArtworkHash: 'demo-city', smallArtworkPath: 'demo-artwork://city',
    artworkHash: 'demo-city', artworkPath: 'demo-artwork://city',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF4E6C89', paletteSecondary: '#FF91A8BD', paletteAccent: '#FFFFC978',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1004, title: '海岸公路', artistDisplay: '白昼信号', albumDisplay: '向海而行',
    durationMs: 248000, trackNumber: 1, discNumber: 1,
    smallArtworkHash: 'demo-coast', smallArtworkPath: 'demo-artwork://coast',
    artworkHash: 'demo-coast', artworkPath: 'demo-artwork://coast',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF117A8B', paletteSecondary: '#FF61B7BB', paletteAccent: '#FFFFD166',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1005, title: '蓝色清晨', artistDisplay: '白昼信号', albumDisplay: '向海而行',
    durationMs: 215000, trackNumber: 2, discNumber: 1,
    smallArtworkHash: 'demo-coast', smallArtworkPath: 'demo-artwork://coast',
    artworkHash: 'demo-coast', artworkPath: 'demo-artwork://coast',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF117A8B', paletteSecondary: '#FF61B7BB', paletteAccent: '#FFFFD166',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1006, title: '夏末回声', artistDisplay: '白昼信号', albumDisplay: '向海而行',
    durationMs: 198000, trackNumber: 3, discNumber: 1,
    smallArtworkHash: 'demo-coast', smallArtworkPath: 'demo-artwork://coast',
    artworkHash: 'demo-coast', artworkPath: 'demo-artwork://coast',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF117A8B', paletteSecondary: '#FF61B7BB', paletteAccent: '#FFFFD166',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1007, title: '凌晨列车', artistDisplay: '北站', albumDisplay: '夜航',
    durationMs: 207000, trackNumber: 1, discNumber: 1,
    smallArtworkHash: 'demo-night', smallArtworkPath: 'demo-artwork://night',
    artworkHash: 'demo-night', artworkPath: 'demo-artwork://night',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF3A315B', paletteSecondary: '#FF746D9C', paletteAccent: '#FFFF8A65',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1008, title: '无人站台', artistDisplay: '北站', albumDisplay: '夜航',
    durationMs: 231000, trackNumber: 2, discNumber: 1,
    smallArtworkHash: 'demo-night', smallArtworkPath: 'demo-artwork://night',
    artworkHash: 'demo-night', artworkPath: 'demo-artwork://night',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF3A315B', paletteSecondary: '#FF746D9C', paletteAccent: '#FFFF8A65',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  },
  {
    id: -1009, title: '灯火以北', artistDisplay: '北站', albumDisplay: '夜航',
    durationMs: 244000, trackNumber: 3, discNumber: 1,
    smallArtworkHash: 'demo-night', smallArtworkPath: 'demo-artwork://night',
    artworkHash: 'demo-night', artworkPath: 'demo-artwork://night',
    artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF3A315B', paletteSecondary: '#FF746D9C', paletteAccent: '#FFFF8A65',
    sectionKey: '#', availability: AvailabilityState.AVAILABLE
  }
];

const DEMO_ALBUMS: Array<AlbumListItem> = [
  {
    id: -1101, title: '城市微光', albumArtistDisplay: '林屿',
    trackCount: 3, totalDurationMs: 654000,
    artworkPath: 'demo-artwork://city', artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF4E6C89', paletteSecondary: '#FF91A8BD', paletteAccent: '#FFFFC978',
    sectionKey: '#', unavailableTrackCount: 0
  },
  {
    id: -1102, title: '向海而行', albumArtistDisplay: '白昼信号',
    trackCount: 3, totalDurationMs: 661000,
    artworkPath: 'demo-artwork://coast', artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF117A8B', paletteSecondary: '#FF61B7BB', paletteAccent: '#FFFFD166',
    sectionKey: '#', unavailableTrackCount: 0
  },
  {
    id: -1103, title: '夜航', albumArtistDisplay: '北站',
    trackCount: 3, totalDurationMs: 682000,
    artworkPath: 'demo-artwork://night', artworkWidth: 1024, artworkHeight: 1024,
    palettePrimary: '#FF3A315B', paletteSecondary: '#FF746D9C', paletteAccent: '#FFFF8A65',
    sectionKey: '#', unavailableTrackCount: 0
  }
];

const DEMO_PLAYLISTS: Array<PlaylistSummary> = [
  {
    id: -3001, kind: PlaylistKind.USER, name: '通勤途中',
    itemSortField: PlaylistTrackSortField.MANUAL, itemSortDirection: SortDirection.ASCENDING,
    trackCount: 5, totalDurationMs: 1099000,
    createdAt: 1751328000000, updatedAt: 1752700800000, lastPlayedAt: 1752700800000
  },
  {
    id: -3002, kind: PlaylistKind.USER, name: '安静的夜晚',
    itemSortField: PlaylistTrackSortField.MANUAL, itemSortDirection: SortDirection.ASCENDING,
    trackCount: 4, totalDurationMs: 953000,
    createdAt: 1751500800000, updatedAt: 1752797200000, lastPlayedAt: 1752797200000
  },
  {
    id: -3003, kind: PlaylistKind.COMPLETED_HISTORY, name: '播放完成',
    itemSortField: PlaylistTrackSortField.LAST_COMPLETED, itemSortDirection: SortDirection.DESCENDING,
    trackCount: 3, totalDurationMs: 652000,
    createdAt: 1751328000000, updatedAt: 1752883200000, lastPlayedAt: 1752883200000
  }
];

const DEMO_LYRICS: Map<number, string> = new Map<number, string>([
  [-1001,
    '[00:00.00]雨停之后\n[00:08.00]街灯在水面慢慢亮起\n[00:16.00]风把云推向更远的地方\n' +
    '[00:24.00]我们沿着安静的路前行\n[00:32.00]把喧闹留在身后\n[00:40.00]城市恢复温柔的呼吸\n' +
    '[00:48.00]此刻只剩下音乐和微光'],
  [-1002,
    '[00:00.00]星光缓慢\n[00:09.00]夜色落在窗台\n[00:18.00]遥远的灯一盏盏醒来\n' +
    '[00:27.00]让时间走得慢一些\n[00:36.00]让这一刻停在耳边\n[00:45.00]直到天边泛起微白'],
  [-1004,
    '[00:00.00]海岸公路\n[00:08.00]沿着海风驶向晴朗\n[00:16.00]浪花把旧日脚印收藏\n' +
    '[00:24.00]远方没有既定方向\n[00:32.00]只有阳光落在肩上\n[00:40.00]和我们一路轻声歌唱'],
  [-1007,
    '[00:00.00]凌晨列车\n[00:10.00]站台掠过无声的灯\n[00:20.00]车窗映出未眠的人\n' +
    '[00:30.00]下一站仍在夜色深处\n[00:40.00]铁轨替我们记住旅程\n[00:50.00]天亮以前继续前行']
]);

function cloneTrack(track: TrackListItem): TrackListItem {
  return {
    id: track.id, title: track.title, artistDisplay: track.artistDisplay,
    albumDisplay: track.albumDisplay, durationMs: track.durationMs,
    trackNumber: track.trackNumber, discNumber: track.discNumber,
    smallArtworkHash: track.smallArtworkHash, smallArtworkPath: track.smallArtworkPath,
    artworkHash: track.artworkHash, artworkPath: track.artworkPath,
    artworkWidth: track.artworkWidth, artworkHeight: track.artworkHeight,
    palettePrimary: track.palettePrimary, paletteSecondary: track.paletteSecondary,
    paletteAccent: track.paletteAccent, sectionKey: track.sectionKey,
    availability: track.availability
  };
}

function cloneAlbum(album: AlbumListItem): AlbumListItem {
  return {
    id: album.id, title: album.title, albumArtistDisplay: album.albumArtistDisplay,
    trackCount: album.trackCount, totalDurationMs: album.totalDurationMs,
    artworkPath: album.artworkPath, artworkWidth: album.artworkWidth,
    artworkHeight: album.artworkHeight, palettePrimary: album.palettePrimary,
    paletteSecondary: album.paletteSecondary, paletteAccent: album.paletteAccent,
    sectionKey: album.sectionKey, unavailableTrackCount: album.unavailableTrackCount
  };
}

function clonePlaylist(playlist: PlaylistSummary): PlaylistSummary {
  return {
    id: playlist.id, kind: playlist.kind, name: playlist.name,
    itemSortField: playlist.itemSortField, itemSortDirection: playlist.itemSortDirection,
    trackCount: playlist.trackCount, totalDurationMs: playlist.totalDurationMs,
    createdAt: playlist.createdAt, updatedAt: playlist.updatedAt, lastPlayedAt: playlist.lastPlayedAt
  };
}

function queueTrackOf(track: TrackListItem): QueueTrack {
  return {
    id: track.id, title: track.title, artistDisplay: track.artistDisplay,
    albumDisplay: track.albumDisplay, durationMs: track.durationMs,
    smallArtworkHash: track.smallArtworkHash, smallArtworkPath: track.smallArtworkPath,
    largeArtworkHash: track.artworkHash, largeArtworkPath: track.artworkPath,
    artworkWidth: track.artworkWidth, artworkHeight: track.artworkHeight,
    palettePrimary: track.palettePrimary, paletteSecondary: track.paletteSecondary,
    paletteAccent: track.paletteAccent
  };
}

function playlistTrackOf(track: TrackListItem, position: number): PlaylistTrackItem {
  const now = 1752883200000 - position * 86400000;
  return {
    id: track.id,
    title: track.title,
    artistDisplay: track.artistDisplay,
    albumDisplay: track.albumDisplay,
    durationMs: track.durationMs,
    trackNumber: track.trackNumber,
    discNumber: track.discNumber,
    smallArtworkHash: track.smallArtworkHash,
    smallArtworkPath: track.smallArtworkPath,
    artworkHash: track.artworkHash,
    artworkPath: track.artworkPath,
    artworkWidth: track.artworkWidth,
    artworkHeight: track.artworkHeight,
    palettePrimary: track.palettePrimary,
    paletteSecondary: track.paletteSecondary,
    paletteAccent: track.paletteAccent,
    sectionKey: track.sectionKey,
    availability: track.availability,
    position: position,
    addedAt: now,
    source: PlaylistItemSource.MANUAL,
    firstQualifiedAt: 0,
    lastQualifiedAt: 0,
    lastPlayedAt: now,
    lastCompletedAt: now
  };
}

export class DemoMusicLibrary {
  static isArtworkPath(path: string): boolean {
    return path.startsWith(DEMO_ARTWORK_PREFIX);
  }

  static tracks(field: TrackSortField, direction: SortDirection): Array<TrackListItem> {
    const tracks = DEMO_TRACKS.map((track: TrackListItem): TrackListItem => cloneTrack(track));
    tracks.sort((left: TrackListItem, right: TrackListItem): number => {
      let result = left.title.localeCompare(right.title);
      if (field === TrackSortField.ALBUM) {
        result = left.albumDisplay.localeCompare(right.albumDisplay) || left.trackNumber - right.trackNumber;
      } else if (field === TrackSortField.ARTIST) {
        result = left.artistDisplay.localeCompare(right.artistDisplay) || left.title.localeCompare(right.title);
      } else if (field === TrackSortField.RELEASE_DATE || field === TrackSortField.ADDED_AT) {
        result = left.id - right.id;
      }
      return direction === SortDirection.ASCENDING ? result : -result;
    });
    return tracks;
  }

  static trackDetail(trackId: number): TrackDetail | undefined {
    const track = DEMO_TRACKS.find((candidate: TrackListItem): boolean => candidate.id === trackId);
    if (track === undefined) {
      return undefined;
    }
    return {
      id: track.id,
      title: track.title,
      sortTitle: track.title,
      artistDisplay: track.artistDisplay,
      albumDisplay: track.albumDisplay,
      albumArtistDisplay: track.artistDisplay,
      composerDisplay: '',
      trackNumber: track.trackNumber,
      totalTrackCount: 3,
      trackNumberRaw: `${track.trackNumber}/3`,
      discNumber: track.discNumber,
      totalDiscCount: 1,
      discNumberRaw: '1/1',
      releaseDateRaw: '2026',
      originalReleaseDateRaw: '',
      durationMs: track.durationMs,
      sampleRate: 44100,
      channelCount: 2,
      bitsPerSample: 16,
      bitRate: 0,
      displayName: `${track.title}.flac`,
      uri: '',
      fileSize: 0,
      modifiedAt: 0,
      format: MediaFormat.FLAC,
      mimeType: 'audio/flac',
      authorizationPersisted: false,
      availability: track.availability,
      artworkPath: track.artworkPath,
      artworkWidth: track.artworkWidth,
      artworkHeight: track.artworkHeight,
      palettePrimary: track.palettePrimary,
      credits: [],
      genres: [],
      rawTags: [],
      artworks: []
    };
  }

  static trackSnapshot(field: TrackSortField, direction: SortDirection): LibrarySnapshot<TrackListItem> {
    return {
      items: DemoMusicLibrary.tracks(field, direction),
      sections: [],
      indexPresentation: LibraryIndexPresentation.SCROLLBAR
    };
  }

  static albums(field: AlbumSortField, direction: SortDirection): Array<AlbumListItem> {
    const albums = DEMO_ALBUMS.map((album: AlbumListItem): AlbumListItem => cloneAlbum(album));
    albums.sort((left: AlbumListItem, right: AlbumListItem): number => {
      let result = left.title.localeCompare(right.title);
      if (field === AlbumSortField.ALBUM_ARTIST) {
        result = left.albumArtistDisplay.localeCompare(right.albumArtistDisplay);
      } else if (field === AlbumSortField.RELEASE_DATE || field === AlbumSortField.ADDED_AT) {
        result = left.id - right.id;
      }
      return direction === SortDirection.ASCENDING ? result : -result;
    });
    return albums;
  }

  static albumSnapshot(field: AlbumSortField, direction: SortDirection): LibrarySnapshot<AlbumListItem> {
    return {
      items: DemoMusicLibrary.albums(field, direction),
      sections: [],
      indexPresentation: LibraryIndexPresentation.SCROLLBAR
    };
  }

  static statistics(): LibraryStatistics {
    return { trackCount: DEMO_TRACKS.length, albumCount: DEMO_ALBUMS.length,
      artworkCount: DEMO_ALBUMS.length, unavailableTrackCount: 0 };
  }

  static playbackTrack(trackId: number): PlaybackTrack | undefined {
    const track = DEMO_TRACKS.find((candidate: TrackListItem): boolean => candidate.id === trackId);
    if (track === undefined) {
      return undefined;
    }
    const queueTrack = queueTrackOf(track);
    return {
      id: queueTrack.id,
      title: queueTrack.title,
      artistDisplay: queueTrack.artistDisplay,
      albumDisplay: queueTrack.albumDisplay,
      durationMs: queueTrack.durationMs,
      smallArtworkHash: queueTrack.smallArtworkHash,
      smallArtworkPath: queueTrack.smallArtworkPath,
      largeArtworkHash: queueTrack.largeArtworkHash,
      largeArtworkPath: queueTrack.largeArtworkPath,
      artworkWidth: queueTrack.artworkWidth,
      artworkHeight: queueTrack.artworkHeight,
      palettePrimary: queueTrack.palettePrimary,
      paletteSecondary: queueTrack.paletteSecondary,
      paletteAccent: queueTrack.paletteAccent,
      uri: `demo-audio://${Math.abs(track.id)}`,
      fileSize: 4096,
      modifiedAt: 1752883200000,
      format: track.id % 2 === 0 ? MediaFormat.FLAC : MediaFormat.MP3,
      availability: AvailabilityState.AVAILABLE,
      authorizationPersisted: false
    };
  }

  static playbackQueueTracks(trackIds: Array<number>): Array<QueueTrack> {
    const result: Array<QueueTrack> = [];
    trackIds.forEach((trackId: number): void => {
      const track = DEMO_TRACKS.find((candidate: TrackListItem): boolean => candidate.id === trackId);
      if (track !== undefined) {
        result.push(queueTrackOf(track));
      }
    });
    return result;
  }

  static resumeState(trackId: number): ResumeState {
    const track = DemoMusicLibrary.playbackTrack(trackId);
    return { positionMs: track === undefined ? 0 : Math.min(42000, track.durationMs), durationMs: track?.durationMs ?? 0 };
  }

  static lyrics(trackId: number): string {
    return DEMO_LYRICS.get(trackId) ??
      '[00:00.00]纯音乐\n[00:12.00]让旋律陪伴此刻\n[00:24.00]继续安静聆听';
  }

  static defaultTrack(): TrackListItem {
    return cloneTrack(DEMO_TRACKS[0]);
  }

  static albumDetail(albumId: number): AlbumDetail | undefined {
    const album = DEMO_ALBUMS.find((candidate: AlbumListItem): boolean => candidate.id === albumId);
    if (album === undefined) {
      return undefined;
    }
    const albumArtists = DemoMusicLibrary.albumArtists(albumId);
    return {
      album: cloneAlbum(album),
      albumArtists: albumArtists,
      relatedAlbums: DEMO_ALBUMS.filter((candidate: AlbumListItem): boolean => candidate.id !== albumId)
        .map((candidate: AlbumListItem): AlbumListItem => cloneAlbum(candidate)),
      releaseYear: albumId === -1101 ? 2026 : 2025,
      genreDisplay: albumId === -1103 ? '氛围 / 电子' : '轻音乐',
      tracks: DEMO_TRACKS.filter((track: TrackListItem): boolean =>
        DemoMusicLibrary.albumIdForTrack(track.id) === albumId).map(cloneTrack)
    };
  }

  static albumArtists(albumId: number): Array<ArtistReference> {
    if (albumId === -1101) {
      return [{ id: DEMO_ARTIST_LIN_YU.id, name: DEMO_ARTIST_LIN_YU.name }];
    }
    if (albumId === -1102) {
      return [{ id: DEMO_ARTIST_DAYLIGHT.id, name: DEMO_ARTIST_DAYLIGHT.name }];
    }
    if (albumId === -1103) {
      return [{ id: DEMO_ARTIST_NORTH_STATION.id, name: DEMO_ARTIST_NORTH_STATION.name }];
    }
    return [];
  }

  static artistDetail(artistId: number): ArtistDetail | undefined {
    const albumId = artistId === -2001 ? -1101 : artistId === -2002 ? -1102 : artistId === -2003 ? -1103 : 0;
    if (albumId === 0) {
      return undefined;
    }
    const artist = DemoMusicLibrary.albumArtists(albumId)[0];
    const album = DEMO_ALBUMS.find((candidate: AlbumListItem): boolean => candidate.id === albumId)!;
    const tracks = DEMO_TRACKS.filter((track: TrackListItem): boolean =>
      DemoMusicLibrary.albumIdForTrack(track.id) === albumId).map(cloneTrack);
    return {
      artist: artist,
      albumCount: 1,
      trackCount: tracks.length,
      totalDurationMs: album.totalDurationMs,
      albums: [cloneAlbum(album)],
      tracks: tracks
    };
  }

  static navigationTargets(trackId: number): TrackNavigationTargets | undefined {
    const track = DEMO_TRACKS.find((candidate: TrackListItem): boolean => candidate.id === trackId);
    if (track === undefined) {
      return undefined;
    }
    const albumId = DemoMusicLibrary.albumIdForTrack(trackId);
    const album = DEMO_ALBUMS.find((candidate: AlbumListItem): boolean => candidate.id === albumId)!;
    const artists = DemoMusicLibrary.albumArtists(albumId);
    const albumReference: AlbumReference = {
      id: album.id,
      title: album.title,
      palettePrimary: album.palettePrimary
    };
    return { trackId: trackId, trackArtists: artists, albumArtists: artists, album: albumReference };
  }

  static playlists(field: PlaylistSortField, direction: SortDirection): Array<PlaylistSummary> {
    const playlists = DEMO_PLAYLISTS.map(clonePlaylist);
    playlists.sort((left: PlaylistSummary, right: PlaylistSummary): number => {
      let result = left.name.localeCompare(right.name);
      if (field === PlaylistSortField.LAST_PLAYED) {
        result = left.lastPlayedAt - right.lastPlayedAt;
      } else if (field === PlaylistSortField.UPDATED_AT) {
        result = left.updatedAt - right.updatedAt;
      } else if (field === PlaylistSortField.CREATED_AT) {
        result = left.createdAt - right.createdAt;
      } else if (field === PlaylistSortField.TRACK_COUNT) {
        result = left.trackCount - right.trackCount;
      } else if (field === PlaylistSortField.TOTAL_DURATION) {
        result = left.totalDurationMs - right.totalDurationMs;
      }
      return direction === SortDirection.ASCENDING ? result : -result;
    });
    return playlists;
  }

  static playlist(playlistId: number): PlaylistSummary | undefined {
    const playlist = DEMO_PLAYLISTS.find((candidate: PlaylistSummary): boolean => candidate.id === playlistId);
    return playlist === undefined ? undefined : clonePlaylist(playlist);
  }

  static completedPlaylist(): PlaylistSummary {
    return clonePlaylist(DEMO_PLAYLISTS[2]);
  }

  static playlistDetail(playlistId: number, offset: number, limit: number): PlaylistDetail | undefined {
    const playlist = DemoMusicLibrary.playlist(playlistId);
    if (playlist === undefined) {
      return undefined;
    }
    let indexes: Array<number> = [];
    if (playlistId === -3001) {
      indexes = [0, 3, 6, 1, 4];
    } else if (playlistId === -3002) {
      indexes = [6, 7, 8, 1];
    } else {
      indexes = [0, 3, 6];
    }
    const allItems = indexes.map((trackIndex: number, position: number): PlaylistTrackItem =>
      playlistTrackOf(DEMO_TRACKS[trackIndex], position));
    return {
      playlist: playlist,
      items: allItems.slice(offset, offset + limit),
      offset: offset,
      totalCount: allItems.length
    };
  }

  static playlistTrackIds(playlistId: number): Array<number> {
    return DemoMusicLibrary.playlistDetail(playlistId, 0, 100)?.items
      .map((item: PlaylistTrackItem): number => item.id) ?? [];
  }

  private static albumIdForTrack(trackId: number): number {
    if (trackId >= -1003) {
      return -1101;
    }
    if (trackId >= -1006) {
      return -1102;
    }
    return -1103;
  }
}
