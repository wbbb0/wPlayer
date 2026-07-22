import {
  M3uEntry,
  M3uExportEntry,
  M3uIssueKind,
  M3uParseIssue,
  M3uParseResult,
  M3uSerializeOptions
} from './M3uModels';

interface PendingMetadata {
  durationSeconds: number | null;
  displayTitle: string | null;
  artist: string | null;
  title: string | null;
  album: string | null;
  firstCompletedAt: number | null;
  lastCompletedAt: number | null;
}

interface ParsedExtInf {
  durationSeconds: number | null;
  displayTitle: string | null;
  artist: string | null;
  title: string | null;
  valid: boolean;
}

interface ParsedTimestamp {
  value: number | null;
  valid: boolean;
}

export class M3uCodec {
  static parse(source: string): M3uParseResult {
    const entries: Array<M3uEntry> = [];
    const issues: Array<M3uParseIssue> = [];
    const firstEntryByResource: Map<string, number> = new Map<string, number>();
    const rows = M3uCodec.normalizeSource(source).split('\n');
    let pending = M3uCodec.emptyPendingMetadata();
    let hadHeader = false;
    let duplicateCount = 0;
    let ignoredCommentCount = 0;

    for (let index = 0; index < rows.length; index += 1) {
      const lineNumber = index + 1;
      const line = rows[index].trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('#')) {
        const upper = line.toUpperCase();
        if (upper === '#EXTM3U') {
          hadHeader = true;
          continue;
        }
        if (upper.startsWith('#EXTINF')) {
          const parsed = M3uCodec.parseExtInf(line);
          pending.durationSeconds = parsed.durationSeconds;
          pending.displayTitle = parsed.displayTitle;
          pending.artist = parsed.artist;
          pending.title = parsed.title;
          if (!parsed.valid) {
            issues.push({ line: lineNumber, kind: M3uIssueKind.INVALID_EXTINF });
          }
          continue;
        }
        if (upper.startsWith('#WPLAYER-FIRST-COMPLETED-AT')) {
          const parsed = M3uCodec.parseTimestampDirective(line);
          pending.firstCompletedAt = parsed.value;
          if (!parsed.valid) {
            issues.push({ line: lineNumber, kind: M3uIssueKind.INVALID_TIMESTAMP });
          }
          continue;
        }
        if (upper.startsWith('#WPLAYER-LAST-COMPLETED-AT')) {
          const parsed = M3uCodec.parseTimestampDirective(line);
          pending.lastCompletedAt = parsed.value;
          if (!parsed.valid) {
            issues.push({ line: lineNumber, kind: M3uIssueKind.INVALID_TIMESTAMP });
          }
          continue;
        }
        if (upper.startsWith('#WPLAYER-ALBUM') || upper.startsWith('#EXTALB')) {
          pending.album = M3uCodec.parseTextDirective(line);
          continue;
        }
        ignoredCommentCount += 1;
        continue;
      }

      const resource = M3uCodec.parseResource(line);
      if (resource.length === 0 || M3uCodec.hasInvalidResourceCharacter(resource)) {
        issues.push({ line: lineNumber, kind: M3uIssueKind.INVALID_RESOURCE });
        pending = M3uCodec.emptyPendingMetadata();
        continue;
      }
      const duplicateOf = firstEntryByResource.has(resource) ?
        firstEntryByResource.get(resource) as number : null;
      if (duplicateOf === null) {
        firstEntryByResource.set(resource, entries.length);
      } else {
        duplicateCount += 1;
      }
      entries.push({
        resource: resource,
        durationSeconds: pending.durationSeconds,
        displayTitle: pending.displayTitle,
        artist: pending.artist,
        title: pending.title,
        album: pending.album,
        firstCompletedAt: pending.firstCompletedAt,
        lastCompletedAt: pending.lastCompletedAt,
        duplicateOfIndex: duplicateOf,
        sourceLine: lineNumber
      });
      pending = M3uCodec.emptyPendingMetadata();
    }
    return {
      entries: entries,
      issues: issues,
      hadHeader: hadHeader,
      duplicateCount: duplicateCount,
      ignoredCommentCount: ignoredCommentCount
    };
  }

  static serialize(entries: Array<M3uExportEntry>, options: M3uSerializeOptions = {}): string {
    const lineEnding = options.lineEnding ?? '\r\n';
    if (lineEnding !== '\r\n' && lineEnding !== '\n') {
      throw new Error('M3U line ending must be CRLF or LF');
    }
    const lines: Array<string> = ['#EXTM3U'];
    for (let index = 0; index < entries.length; index += 1) {
      const entry = entries[index];
      M3uCodec.validateExportResource(entry.resource);
      const firstCompletedAt = entry.firstCompletedAt ?? null;
      const lastCompletedAt = entry.lastCompletedAt ?? null;
      if (firstCompletedAt !== null) {
        lines.push(`#WPLAYER-FIRST-COMPLETED-AT:${M3uCodec.formatTimestamp(firstCompletedAt)}`);
      }
      if (lastCompletedAt !== null) {
        lines.push(`#WPLAYER-LAST-COMPLETED-AT:${M3uCodec.formatTimestamp(lastCompletedAt)}`);
      }
      const album = M3uCodec.cleanDisplayText(entry.album ?? '');
      if (album.length > 0) {
        lines.push(`#WPLAYER-ALBUM:${album}`);
      }
      const duration = M3uCodec.formatDuration(entry.durationSeconds ?? null);
      const displayTitle = M3uCodec.exportDisplayTitle(entry);
      lines.push(`#EXTINF:${duration},${displayTitle}`);
      lines.push(entry.resource);
    }
    return `${lines.join(lineEnding)}${lineEnding}`;
  }

  private static normalizeSource(source: string): string {
    let normalized = source;
    if (normalized.length > 0 && normalized.charCodeAt(0) === 0xFEFF) {
      normalized = normalized.substring(1);
    }
    return normalized.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  private static parseExtInf(line: string): ParsedExtInf {
    const colonIndex = line.indexOf(':');
    const payload = line.substring(colonIndex >= 0 ? colonIndex + 1 : 7).trim();
    const commaIndex = payload.indexOf(',');
    const durationText = (commaIndex >= 0 ? payload.substring(0, commaIndex) : payload).trim();
    const titleText = commaIndex >= 0 ? payload.substring(commaIndex + 1).trim() : '';
    let durationSeconds: number | null = null;
    let valid = colonIndex >= 0;
    const durationMatch = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)/.exec(durationText);
    if (durationMatch !== null) {
      const parsedDuration = Number(durationMatch[0]);
      if (Number.isFinite(parsedDuration)) {
        durationSeconds = parsedDuration < 0 ? null : parsedDuration;
      } else {
        valid = false;
      }
    } else {
      valid = false;
    }
    const parts = M3uCodec.splitArtistAndTitle(titleText);
    return {
      durationSeconds: durationSeconds,
      displayTitle: titleText.length > 0 ? titleText : null,
      artist: parts[0],
      title: parts[1],
      valid: valid
    };
  }

  private static splitArtistAndTitle(displayTitle: string): Array<string | null> {
    const separatorIndex = displayTitle.indexOf(' - ');
    if (separatorIndex <= 0 || separatorIndex + 3 >= displayTitle.length) {
      return [null, displayTitle.length > 0 ? displayTitle : null];
    }
    return [
      displayTitle.substring(0, separatorIndex).trim(),
      displayTitle.substring(separatorIndex + 3).trim()
    ];
  }

  private static parseTimestampDirective(line: string): ParsedTimestamp {
    const colonIndex = line.indexOf(':');
    if (colonIndex < 0) {
      return { value: null, valid: false };
    }
    const raw = line.substring(colonIndex + 1).trim();
    if (raw.length === 0) {
      return { value: null, valid: false };
    }
    const numeric = Number(raw);
    if (Number.isFinite(numeric) && numeric >= 0) {
      return { value: Math.round(numeric), valid: true };
    }
    const parsedDate = Date.parse(raw);
    if (Number.isFinite(parsedDate) && parsedDate >= 0) {
      return { value: parsedDate, valid: true };
    }
    return { value: null, valid: false };
  }

  private static parseTextDirective(line: string): string | null {
    const colonIndex = line.indexOf(':');
    if (colonIndex < 0) {
      return null;
    }
    const value = line.substring(colonIndex + 1).trim();
    return value.length > 0 ? value : null;
  }

  private static parseResource(line: string): string {
    if (line.length >= 2) {
      const first = line.charAt(0);
      const last = line.charAt(line.length - 1);
      if ((first === '"' && last === '"') || (first === '\'' && last === '\'')) {
        return line.substring(1, line.length - 1).trim();
      }
    }
    return line;
  }

  private static hasInvalidResourceCharacter(resource: string): boolean {
    for (let index = 0; index < resource.length; index += 1) {
      const code = resource.charCodeAt(index);
      if (code === 0 || (code < 0x20 && code !== 0x09)) {
        return true;
      }
    }
    return false;
  }

  private static emptyPendingMetadata(): PendingMetadata {
    return {
      durationSeconds: null,
      displayTitle: null,
      artist: null,
      title: null,
      album: null,
      firstCompletedAt: null,
      lastCompletedAt: null
    };
  }

  private static validateExportResource(resource: string): void {
    if (resource.trim().length === 0 || resource.startsWith('#') ||
      resource.includes('\r') || resource.includes('\n') ||
      M3uCodec.hasInvalidResourceCharacter(resource)) {
      throw new Error('M3U resource must be a non-empty single non-comment line');
    }
  }

  private static formatDuration(durationSeconds: number | null): string {
    if (durationSeconds === null || !Number.isFinite(durationSeconds) || durationSeconds < 0) {
      return '-1';
    }
    return `${Math.round(durationSeconds)}`;
  }

  private static exportDisplayTitle(entry: M3uExportEntry): string {
    const explicit = M3uCodec.cleanDisplayText(entry.displayTitle ?? '');
    if (explicit.length > 0) {
      return explicit;
    }
    const artist = M3uCodec.cleanDisplayText(entry.artist ?? '');
    const title = M3uCodec.cleanDisplayText(entry.title ?? '');
    if (artist.length > 0 && title.length > 0) {
      return `${artist} - ${title}`;
    }
    if (title.length > 0) {
      return title;
    }
    if (artist.length > 0) {
      return artist;
    }
    return M3uCodec.cleanDisplayText(entry.resource);
  }

  private static cleanDisplayText(value: string): string {
    return value.replace(/\r\n/g, ' ').replace(/\r/g, ' ').replace(/\n/g, ' ').trim();
  }

  private static formatTimestamp(value: number): string {
    if (!Number.isFinite(value) || value < 0) {
      throw new Error('M3U completion timestamp must be a non-negative number');
    }
    return `${Math.round(value)}`;
  }
}
