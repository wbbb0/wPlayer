import { PlaylistTransferTrack } from '../../library/model/LibraryModels';
import { M3uEntry } from './M3uModels';

const DURATION_TOLERANCE_SECONDS: number = 2;
const MAX_WEAK_TITLE_CANDIDATES: number = 20;

class M3uIndexedTrack {
  readonly track: PlaylistTransferTrack;
  readonly fileName: string;
  readonly title: string;
  readonly artist: string;
  readonly album: string;
  readonly durationSeconds: number;

  constructor(track: PlaylistTransferTrack) {
    this.track = track;
    this.fileName = M3uImportMatcher.normalized(track.displayName);
    this.title = M3uImportMatcher.normalized(track.title);
    this.artist = M3uImportMatcher.normalized(track.artistDisplay);
    this.album = M3uImportMatcher.normalized(track.albumDisplay);
    this.durationSeconds = Math.round(Math.max(0, track.durationMs) / 1000);
  }
}

class M3uMatchIndex {
  readonly byUri: Map<string, M3uIndexedTrack> = new Map<string, M3uIndexedTrack>();
  readonly byFileName: Map<string, Array<M3uIndexedTrack>> =
    new Map<string, Array<M3uIndexedTrack>>();
  readonly byTitleArtistAlbum: Map<string, Array<M3uIndexedTrack>> =
    new Map<string, Array<M3uIndexedTrack>>();
  readonly byTitleArtist: Map<string, Array<M3uIndexedTrack>> =
    new Map<string, Array<M3uIndexedTrack>>();
  readonly byTitleAlbum: Map<string, Array<M3uIndexedTrack>> =
    new Map<string, Array<M3uIndexedTrack>>();
  readonly byTitle: Map<string, Array<M3uIndexedTrack>> =
    new Map<string, Array<M3uIndexedTrack>>();
}

class NormalizedM3uEntry {
  readonly fileName: string;
  readonly title: string;
  readonly artist: string;
  readonly album: string;
  readonly durationSeconds: number | null;

  constructor(entry: M3uEntry) {
    this.fileName = M3uImportMatcher.normalizedFileName(entry.resource);
    this.title = M3uImportMatcher.normalized(entry.title ?? '');
    this.artist = M3uImportMatcher.normalized(entry.artist ?? '');
    this.album = M3uImportMatcher.normalized(entry.album ?? '');
    this.durationSeconds = entry.durationSeconds === null ? null : Math.round(entry.durationSeconds);
  }
}

export class M3uImportMatcher {
  private readonly index: M3uMatchIndex = new M3uMatchIndex();

  constructor(catalog: Array<PlaylistTransferTrack>) {
    for (let cursor = 0; cursor < catalog.length; cursor += 1) {
      const indexed = new M3uIndexedTrack(catalog[cursor]);
      this.index.byUri.set(indexed.track.uri, indexed);
      M3uImportMatcher.addIndexed(this.index.byFileName, indexed.fileName, indexed);
      M3uImportMatcher.addIndexed(this.index.byTitle, indexed.title, indexed);
      if (indexed.title.length > 0 && indexed.artist.length > 0) {
        M3uImportMatcher.addIndexed(this.index.byTitleArtist, `${indexed.title}\n${indexed.artist}`, indexed);
      }
      if (indexed.title.length > 0 && indexed.album.length > 0) {
        M3uImportMatcher.addIndexed(this.index.byTitleAlbum, `${indexed.title}\n${indexed.album}`, indexed);
      }
      if (indexed.title.length > 0 && indexed.artist.length > 0 && indexed.album.length > 0) {
        M3uImportMatcher.addIndexed(
          this.index.byTitleArtistAlbum,
          `${indexed.title}\n${indexed.artist}\n${indexed.album}`,
          indexed
        );
      }
    }
  }

  match(entry: M3uEntry): PlaylistTransferTrack | undefined {
    const exact = this.index.byUri.get(entry.resource);
    if (exact !== undefined) {
      return exact.track;
    }
    const normalized = new NormalizedM3uEntry(entry);
    const pathMatch = this.matchFileName(normalized);
    if (pathMatch !== undefined) {
      return pathMatch.track;
    }
    return this.matchMetadata(normalized)?.track;
  }

  private matchFileName(entry: NormalizedM3uEntry): M3uIndexedTrack | undefined {
    const candidates = this.index.byFileName.get(entry.fileName) ?? [];
    if (this.hasAmbiguousTitleArtistAlbumWithoutDuration(entry)) {
      return undefined;
    }
    if (candidates.length === 1) {
      return this.fileNameCandidateMatches(candidates[0], entry) ? candidates[0] : undefined;
    }
    return this.uniqueBest(candidates, entry, entry.durationSeconds !== null, true);
  }

  private matchMetadata(entry: NormalizedM3uEntry): M3uIndexedTrack | undefined {
    if (entry.title.length === 0) {
      return undefined;
    }
    if (entry.artist.length > 0 && entry.album.length > 0) {
      const candidates = this.index.byTitleArtistAlbum.get(`${entry.title}\n${entry.artist}\n${entry.album}`) ?? [];
      if (entry.durationSeconds !== null) {
        return this.uniqueDurationMatch(candidates, entry.durationSeconds);
      }
      return candidates.length === 1 ? candidates[0] : undefined;
    }
    if (entry.artist.length > 0 && entry.durationSeconds !== null) {
      const candidates = this.index.byTitleArtist.get(`${entry.title}\n${entry.artist}`) ?? [];
      return this.uniqueDurationMatch(candidates, entry.durationSeconds);
    }
    if (entry.album.length > 0 && entry.durationSeconds !== null) {
      const candidates = this.index.byTitleAlbum.get(`${entry.title}\n${entry.album}`) ?? [];
      return this.uniqueDurationMatch(candidates, entry.durationSeconds);
    }
    if (entry.durationSeconds !== null) {
      const candidates = this.index.byTitle.get(entry.title) ?? [];
      if (candidates.length > MAX_WEAK_TITLE_CANDIDATES) {
        return undefined;
      }
      return this.uniqueDurationMatch(candidates, entry.durationSeconds);
    }
    return undefined;
  }

  private uniqueBest(
    candidates: Array<M3uIndexedTrack>,
    entry: NormalizedM3uEntry,
    requireDuration: boolean,
    requireTextualMatch: boolean
  ): M3uIndexedTrack | undefined {
    let selected: M3uIndexedTrack | undefined;
    let selectedScore = 0;
    let tied = false;
    for (let index = 0; index < candidates.length; index += 1) {
      if (!this.fileNameCandidateMatches(candidates[index], entry)) {
        continue;
      }
      const score = this.metadataScore(candidates[index], entry, requireDuration, requireTextualMatch);
      if (score > selectedScore) {
        selected = candidates[index];
        selectedScore = score;
        tied = false;
      } else if (score > 0 && score === selectedScore) {
        tied = true;
      }
    }
    return tied ? undefined : selected;
  }

  private fileNameCandidateMatches(track: M3uIndexedTrack, entry: NormalizedM3uEntry): boolean {
    if (entry.title.length > 0 && entry.title !== track.title) {
      return false;
    }
    if (entry.artist.length > 0 && entry.artist !== track.artist) {
      return false;
    }
    if (entry.album.length > 0 && entry.album !== track.album) {
      return false;
    }
    if (entry.durationSeconds !== null && !M3uImportMatcher.durationClose(track, entry.durationSeconds)) {
      return false;
    }
    return true;
  }

  private hasAmbiguousTitleArtistAlbumWithoutDuration(entry: NormalizedM3uEntry): boolean {
    if (entry.durationSeconds !== null ||
      entry.title.length === 0 ||
      entry.artist.length === 0 ||
      entry.album.length === 0) {
      return false;
    }
    const candidates = this.index.byTitleArtistAlbum.get(`${entry.title}\n${entry.artist}\n${entry.album}`) ?? [];
    return candidates.length > 1;
  }

  private metadataScore(
    track: M3uIndexedTrack,
    entry: NormalizedM3uEntry,
    requireDuration: boolean,
    requireTextualMatch: boolean
  ): number {
    let textualScore = 0;
    if (entry.title.length > 0 && entry.title === track.title) {
      textualScore += 4;
    }
    if (entry.artist.length > 0 && entry.artist === track.artist) {
      textualScore += 3;
    }
    if (entry.album.length > 0 && entry.album === track.album) {
      textualScore += 3;
    }
    if (requireTextualMatch && textualScore === 0) {
      return 0;
    }
    let score = textualScore;
    if (entry.durationSeconds !== null && M3uImportMatcher.durationClose(track, entry.durationSeconds)) {
      score += 2;
    } else if (requireDuration) {
      return 0;
    }
    return score;
  }

  private uniqueDurationMatch(
    candidates: Array<M3uIndexedTrack>,
    durationSeconds: number
  ): M3uIndexedTrack | undefined {
    let selected: M3uIndexedTrack | undefined;
    for (let index = 0; index < candidates.length; index += 1) {
      if (!M3uImportMatcher.durationClose(candidates[index], durationSeconds)) {
        continue;
      }
      if (selected !== undefined) {
        return undefined;
      }
      selected = candidates[index];
    }
    return selected;
  }

  private static durationClose(track: M3uIndexedTrack, durationSeconds: number): boolean {
    return Math.abs(track.durationSeconds - durationSeconds) <= DURATION_TOLERANCE_SECONDS;
  }

  private static addIndexed(
    map: Map<string, Array<M3uIndexedTrack>>,
    key: string,
    track: M3uIndexedTrack
  ): void {
    if (key.length === 0) {
      return;
    }
    const candidates = map.get(key);
    if (candidates === undefined) {
      map.set(key, [track]);
    } else {
      candidates.push(track);
    }
  }

  static normalizedFileName(resource: string): string {
    const withoutQuery = resource.split(/[?#]/)[0];
    const segments = withoutQuery.split(/[\\/]/);
    const raw = segments.length > 0 ? segments[segments.length - 1] : withoutQuery;
    try {
      return M3uImportMatcher.normalized(decodeURIComponent(raw));
    } catch (_) {
      return M3uImportMatcher.normalized(raw);
    }
  }

  static normalized(value: string): string {
    return value.trim().toLocaleLowerCase().replace(/\s+/g, ' ');
  }
}
