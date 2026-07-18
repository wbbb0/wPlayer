import { PlaylistTransferTrack } from '../../library/model/LibraryModels';
import { M3uEntry } from './M3uModels';

class M3uMatchIndex {
  readonly byUri: Map<string, PlaylistTransferTrack> = new Map<string, PlaylistTransferTrack>();
  readonly byFileName: Map<string, Array<PlaylistTransferTrack>> =
    new Map<string, Array<PlaylistTransferTrack>>();
}

export class M3uImportMatcher {
  private readonly index: M3uMatchIndex = new M3uMatchIndex();

  constructor(catalog: Array<PlaylistTransferTrack>) {
    for (let cursor = 0; cursor < catalog.length; cursor += 1) {
      const track = catalog[cursor];
      this.index.byUri.set(track.uri, track);
      const fileName = M3uImportMatcher.normalized(track.displayName);
      const candidates = this.index.byFileName.get(fileName);
      if (candidates === undefined) {
        this.index.byFileName.set(fileName, [track]);
      } else {
        candidates.push(track);
      }
    }
  }

  match(entry: M3uEntry): PlaylistTransferTrack | undefined {
    const exact = this.index.byUri.get(entry.resource);
    if (exact !== undefined) {
      return exact;
    }
    const candidates = this.index.byFileName.get(M3uImportMatcher.normalizedFileName(entry.resource)) ?? [];
    if (candidates.length === 1) {
      return candidates[0];
    }
    let selected: PlaylistTransferTrack | undefined;
    let selectedScore = 0;
    let tied = false;
    for (let index = 0; index < candidates.length; index += 1) {
      let score = 0;
      if (entry.title !== null &&
        M3uImportMatcher.normalized(entry.title) === M3uImportMatcher.normalized(candidates[index].title)) {
        score += 2;
      }
      if (entry.artist !== null &&
        M3uImportMatcher.normalized(entry.artist) ===
          M3uImportMatcher.normalized(candidates[index].artistDisplay)) {
        score += 1;
      }
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
