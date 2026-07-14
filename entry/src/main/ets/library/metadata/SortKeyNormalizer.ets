import { i18n } from '@kit.LocalizationKit';
import { ParsedDate } from '../model/LibraryModels';

export interface NaturalSortValue {
  key: string;
  section: string;
}

export class SortKeyNormalizer {
  private static readonly transliterator: i18n.Transliterator =
    i18n.Transliterator.getInstance('Any-Latn;Latin-ASCII');

  static natural(value: string): NaturalSortValue {
    const stripped = SortKeyNormalizer.stripLeadingSymbols(value.normalize('NFKC'));
    if (stripped.length === 0) {
      return { key: '', section: '#' };
    }
    const latin = SortKeyNormalizer.transliterator.transform(stripped)
      .toLocaleLowerCase()
      .trim()
      .replace(/\s+/g, ' ');
    const section = latin.length > 0 && latin[0] >= 'a' && latin[0] <= 'z' ? latin[0].toUpperCase() : '#';
    return { key: SortKeyNormalizer.encodeNaturalNumbers(latin), section: section };
  }

  static date(date: ParsedDate): number {
    if (date.year === undefined) {
      return 0;
    }
    const month = date.month === undefined ? 0 : date.month;
    const day = date.day === undefined ? 0 : date.day;
    return date.year * 10000 + month * 100 + day;
  }

  static dateParts(year: number, month: number, day: number): number {
    return year <= 0 ? 0 : year * 10000 + Math.max(0, month) * 100 + Math.max(0, day);
  }

  private static stripLeadingSymbols(value: string): string {
    let index = 0;
    while (index < value.length) {
      const character = value[index];
      const type = i18n.Unicode.getType(character);
      if (type.indexOf('_LETTER') >= 0 || type.indexOf('_NUMBER') >= 0 ||
        type === 'U_DECIMAL_DIGIT_NUMBER') {
        break;
      }
      index += 1;
    }
    return value.substring(index);
  }

  private static encodeNaturalNumbers(value: string): string {
    let result = '';
    let index = 0;
    while (index < value.length) {
      const character = value[index];
      if (character < '0' || character > '9') {
        result += character;
        index += 1;
        continue;
      }
      const start = index;
      while (index < value.length && value[index] >= '0' && value[index] <= '9') {
        index += 1;
      }
      const raw = value.substring(start, index);
      const significant = raw.replace(/^0+/, '') || '0';
      result += `\u0001${significant.length.toString().padStart(8, '0')}:${significant}:` +
        raw.length.toString().padStart(8, '0');
    }
    return result;
  }
}
