import { ParsedDate, ParsedMetadata, ParsedNumberPair } from '../model/LibraryModels';

export class MetadataNormalizer {
  static normalizeKey(value: string): string {
    return value.normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase();
  }

  static splitValues(values: Array<string>): Array<string> {
    const result: Array<string> = [];
    const seen: Set<string> = new Set<string>();
    values.forEach((rawValue: string) => {
      rawValue.split(/\s*[;；、]\s*|\s+\/\s+/).forEach((candidate: string) => {
        const value = candidate.trim();
        const key = MetadataNormalizer.normalizeKey(value);
        if (value.length > 0 && !seen.has(key)) {
          seen.add(key);
          result.push(value);
        }
      });
    });
    return result;
  }

  static parseNumberPair(rawValue: string): ParsedNumberPair {
    const raw = rawValue.trim();
    const segments = raw.split('/');
    const value = MetadataNormalizer.parsePositiveInteger(segments[0]);
    const total = segments.length > 1 ? MetadataNormalizer.parsePositiveInteger(segments[1]) : undefined;
    return { value: value, total: total, raw: raw };
  }

  static parseDate(rawValue: string): ParsedDate {
    const raw = rawValue.trim();
    const match = /^(\d{4})(?:[-/.]?(\d{1,2}))?(?:[-/.]?(\d{1,2}))?/.exec(raw);
    if (match === null) {
      return { raw: raw, precision: 0 };
    }
    const year = Number.parseInt(match[1], 10);
    const month = match[2] === undefined ? undefined : Number.parseInt(match[2], 10);
    const day = match[3] === undefined ? undefined : Number.parseInt(match[3], 10);
    let precision = 1;
    if (month !== undefined && month >= 1 && month <= 12) {
      precision = 2;
    }
    if (day !== undefined && day >= 1 && day <= 31) {
      precision = 3;
    }
    return {
      raw: raw,
      year: year,
      month: precision >= 2 ? month : undefined,
      day: precision >= 3 ? day : undefined,
      precision: precision
    };
  }

  static first(tags: Map<string, Array<string>>, keys: Array<string>): string {
    for (let index = 0; index < keys.length; index += 1) {
      const values = tags.get(keys[index]);
      if (values !== undefined && values.length > 0 && values[0].trim().length > 0) {
        return values[0].trim();
      }
    }
    return '';
  }

  static values(tags: Map<string, Array<string>>, keys: Array<string>): Array<string> {
    const rawValues: Array<string> = [];
    keys.forEach((key: string) => {
      const values = tags.get(key);
      if (values !== undefined) {
        rawValues.push(...values);
      }
    });
    return MetadataNormalizer.splitValues(rawValues);
  }

  static albumIdentity(metadata: ParsedMetadata): string {
    if (metadata.album.length === 0) {
      return '';
    }
    const artistKey = metadata.albumArtists
      .map((artist: string) => MetadataNormalizer.normalizeKey(artist))
      .join('\u001F');
    return `${MetadataNormalizer.normalizeKey(metadata.album)}\u0000${artistKey}`;
  }

  private static parsePositiveInteger(value: string): number | undefined {
    const parsed = Number.parseInt(value.trim(), 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
  }
}
