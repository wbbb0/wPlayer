import { M3uEncodingConfidence, M3uEncodingDecision } from './M3uModels';

export class M3uEncoding {
  private static readonly LEGACY_FALLBACKS: Array<string> =
    ['gb18030', 'big5', 'shift_jis', 'windows-1252'];

  static detect(bytes: Uint8Array): M3uEncodingDecision {
    if (M3uEncoding.hasPrefix(bytes, [0xEF, 0xBB, 0xBF])) {
      return M3uEncoding.decision('utf-8', 3, M3uEncodingConfidence.CERTAIN, true);
    }
    if (M3uEncoding.hasPrefix(bytes, [0xFF, 0xFE])) {
      return M3uEncoding.decision('utf-16le', 2, M3uEncodingConfidence.CERTAIN, true);
    }
    if (M3uEncoding.hasPrefix(bytes, [0xFE, 0xFF])) {
      return M3uEncoding.decision('utf-16be', 2, M3uEncodingConfidence.CERTAIN, true);
    }

    const utf16Label = M3uEncoding.detectBomlessUtf16(bytes);
    if (utf16Label.length > 0) {
      return M3uEncoding.decision(utf16Label, 0, M3uEncodingConfidence.LIKELY, true);
    }
    if (M3uEncoding.isValidUtf8(bytes)) {
      return M3uEncoding.decision('utf-8', 0, M3uEncodingConfidence.LIKELY, true);
    }
    const legacyHint = M3uEncoding.legacyHint(bytes);
    return {
      label: '',
      bomLength: 0,
      confidence: M3uEncodingConfidence.UNDETERMINED,
      canDecodeDirectly: false,
      legacyHint: legacyHint,
      fallbackLabels: M3uEncoding.legacyFallbacks(legacyHint)
    };
  }

  static decode(bytes: Uint8Array, decision: M3uEncodingDecision = M3uEncoding.detect(bytes)): string {
    if (!decision.canDecodeDirectly) {
      throw new Error('The M3U byte encoding needs an external decoder');
    }
    const start = Math.min(Math.max(0, decision.bomLength), bytes.length);
    if (decision.label === 'utf-8') {
      return M3uEncoding.decodeUtf8(bytes, start);
    }
    if (decision.label === 'utf-16le') {
      return M3uEncoding.decodeUtf16(bytes, start, true);
    }
    if (decision.label === 'utf-16be') {
      return M3uEncoding.decodeUtf16(bytes, start, false);
    }
    throw new Error(`Unsupported direct M3U encoding: ${decision.label}`);
  }

  static encodeUtf8(text: string, includeBom: boolean = false): Uint8Array {
    let byteLength = includeBom ? 3 : 0;
    for (let index = 0; index < text.length; index += 1) {
      let codePoint = text.charCodeAt(index);
      if (codePoint >= 0xD800 && codePoint <= 0xDBFF && index + 1 < text.length) {
        const low = text.charCodeAt(index + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00);
          index += 1;
        }
      }
      if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
        codePoint = 0xFFFD;
      }
      byteLength += codePoint <= 0x7F ? 1 : codePoint <= 0x7FF ? 2 : codePoint <= 0xFFFF ? 3 : 4;
    }
    const output = new Uint8Array(byteLength);
    let outputIndex = 0;
    if (includeBom) {
      output[0] = 0xEF;
      output[1] = 0xBB;
      output[2] = 0xBF;
      outputIndex = 3;
    }
    for (let index = 0; index < text.length; index += 1) {
      let codePoint = text.charCodeAt(index);
      if (codePoint >= 0xD800 && codePoint <= 0xDBFF && index + 1 < text.length) {
        const low = text.charCodeAt(index + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00);
          index += 1;
        }
      }
      if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
        codePoint = 0xFFFD;
      }
      if (codePoint <= 0x7F) {
        output[outputIndex] = codePoint;
        outputIndex += 1;
      } else if (codePoint <= 0x7FF) {
        output[outputIndex] = 0xC0 | (codePoint >> 6);
        output[outputIndex + 1] = 0x80 | (codePoint & 0x3F);
        outputIndex += 2;
      } else if (codePoint <= 0xFFFF) {
        output[outputIndex] = 0xE0 | (codePoint >> 12);
        output[outputIndex + 1] = 0x80 | ((codePoint >> 6) & 0x3F);
        output[outputIndex + 2] = 0x80 | (codePoint & 0x3F);
        outputIndex += 3;
      } else {
        output[outputIndex] = 0xF0 | (codePoint >> 18);
        output[outputIndex + 1] = 0x80 | ((codePoint >> 12) & 0x3F);
        output[outputIndex + 2] = 0x80 | ((codePoint >> 6) & 0x3F);
        output[outputIndex + 3] = 0x80 | (codePoint & 0x3F);
        outputIndex += 4;
      }
    }
    return output;
  }

  static hasDecodingErrors(
    bytes: Uint8Array,
    decision: M3uEncodingDecision = M3uEncoding.detect(bytes)
  ): boolean {
    if (!decision.canDecodeDirectly) {
      return false;
    }
    const start = Math.min(Math.max(0, decision.bomLength), bytes.length);
    if (decision.label === 'utf-8') {
      return !M3uEncoding.isValidUtf8(bytes.subarray(start));
    }
    if (decision.label !== 'utf-16le' && decision.label !== 'utf-16be') {
      return true;
    }
    if ((bytes.length - start) % 2 !== 0) {
      return true;
    }
    const littleEndian = decision.label === 'utf-16le';
    let pendingHighSurrogate = false;
    for (let index = start; index < bytes.length; index += 2) {
      const codeUnit = littleEndian ?
        bytes[index] | (bytes[index + 1] << 8) :
        (bytes[index] << 8) | bytes[index + 1];
      if (pendingHighSurrogate) {
        if (codeUnit < 0xDC00 || codeUnit > 0xDFFF) {
          return true;
        }
        pendingHighSurrogate = false;
      } else if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
        pendingHighSurrogate = true;
      } else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        return true;
      }
    }
    return pendingHighSurrogate;
  }

  private static decision(label: string, bomLength: number, confidence: M3uEncodingConfidence,
    canDecodeDirectly: boolean): M3uEncodingDecision {
    return {
      label: label,
      bomLength: bomLength,
      confidence: confidence,
      canDecodeDirectly: canDecodeDirectly,
      legacyHint: '',
      fallbackLabels: M3uEncoding.LEGACY_FALLBACKS.slice()
    };
  }

  private static hasPrefix(bytes: Uint8Array, prefix: Array<number>): boolean {
    if (bytes.length < prefix.length) {
      return false;
    }
    for (let index = 0; index < prefix.length; index += 1) {
      if (bytes[index] !== prefix[index]) {
        return false;
      }
    }
    return true;
  }

  private static legacyHint(bytes: Uint8Array): string {
    const sampleLength = Math.min(bytes.length, 4096);
    let ascii = '';
    for (let index = 0; index < sampleLength; index += 1) {
      const value = bytes[index];
      ascii += value >= 0x20 && value <= 0x7E ? String.fromCharCode(value) : '\n';
    }
    const match = /#EXTENC\s*:\s*([A-Za-z0-9_-]+)/i.exec(ascii);
    if (match === null) {
      return '';
    }
    return M3uEncoding.normalizeLegacyLabel(match[1]);
  }

  private static legacyFallbacks(hint: string): Array<string> {
    const fallbacks: Array<string> = [];
    if (hint.length > 0) {
      fallbacks.push(hint);
    }
    for (let index = 0; index < M3uEncoding.LEGACY_FALLBACKS.length; index += 1) {
      const label = M3uEncoding.LEGACY_FALLBACKS[index];
      if (label !== hint) {
        fallbacks.push(label);
      }
    }
    return fallbacks;
  }

  private static normalizeLegacyLabel(label: string): string {
    const normalized = label.toLowerCase().replace(/_/g, '-');
    if (normalized === 'gbk' || normalized === 'gb2312' || normalized === 'gb-2312' ||
      normalized === 'gb18030') {
      return 'gb18030';
    }
    if (normalized === 'big5' || normalized === 'big-5') {
      return 'big5';
    }
    if (normalized === 'shift-jis' || normalized === 'shiftjis' || normalized === 'sjis') {
      return 'shift_jis';
    }
    if (normalized === 'windows-1252' || normalized === 'cp1252') {
      return 'windows-1252';
    }
    return '';
  }

  private static detectBomlessUtf16(bytes: Uint8Array): string {
    const sampleLength = Math.min(bytes.length - (bytes.length % 2), 4096);
    if (sampleLength < 2) {
      return '';
    }
    if (sampleLength === 2) {
      if (bytes[0] !== 0 && bytes[1] === 0) {
        return 'utf-16le';
      }
      if (bytes[0] === 0 && bytes[1] !== 0) {
        return 'utf-16be';
      }
      return '';
    }
    let evenZeroCount = 0;
    let oddZeroCount = 0;
    let pairCount = 0;
    for (let index = 0; index < sampleLength; index += 2) {
      if (bytes[index] === 0) {
        evenZeroCount += 1;
      }
      if (bytes[index + 1] === 0) {
        oddZeroCount += 1;
      }
      pairCount += 1;
    }
    const evenRatio = evenZeroCount / pairCount;
    const oddRatio = oddZeroCount / pairCount;
    const hasLikelyLittleEndianAscii = oddZeroCount >= 2 && oddZeroCount >= evenZeroCount * 3;
    const hasLikelyBigEndianAscii = evenZeroCount >= 2 && evenZeroCount >= oddZeroCount * 3;
    if ((oddRatio >= 0.30 && evenRatio <= 0.10) || hasLikelyLittleEndianAscii) {
      return 'utf-16le';
    }
    if ((evenRatio >= 0.30 && oddRatio <= 0.10) || hasLikelyBigEndianAscii) {
      return 'utf-16be';
    }
    return '';
  }

  private static isValidUtf8(bytes: Uint8Array): boolean {
    let index = 0;
    while (index < bytes.length) {
      const first = bytes[index];
      if (first <= 0x7F) {
        index += 1;
        continue;
      }
      let continuationCount = 0;
      let minimumCodePoint = 0;
      let codePoint = 0;
      if (first >= 0xC2 && first <= 0xDF) {
        continuationCount = 1;
        minimumCodePoint = 0x80;
        codePoint = first & 0x1F;
      } else if (first >= 0xE0 && first <= 0xEF) {
        continuationCount = 2;
        minimumCodePoint = 0x800;
        codePoint = first & 0x0F;
      } else if (first >= 0xF0 && first <= 0xF4) {
        continuationCount = 3;
        minimumCodePoint = 0x10000;
        codePoint = first & 0x07;
      } else {
        return false;
      }
      if (index + continuationCount >= bytes.length) {
        return false;
      }
      for (let offset = 1; offset <= continuationCount; offset += 1) {
        const next = bytes[index + offset];
        if ((next & 0xC0) !== 0x80) {
          return false;
        }
        codePoint = (codePoint << 6) | (next & 0x3F);
      }
      if (codePoint < minimumCodePoint || codePoint > 0x10FFFF ||
        (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
        return false;
      }
      index += continuationCount + 1;
    }
    return true;
  }

  private static decodeUtf8(bytes: Uint8Array, start: number): string {
    const chunks: Array<string> = [];
    let codeUnits: Array<number> = [];
    let index = start;
    while (index < bytes.length) {
      const first = bytes[index];
      if (first <= 0x7F) {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, first);
        index += 1;
        continue;
      }
      let continuationCount = 0;
      let codePoint = 0;
      if (first >= 0xC2 && first <= 0xDF) {
        continuationCount = 1;
        codePoint = first & 0x1F;
      } else if (first >= 0xE0 && first <= 0xEF) {
        continuationCount = 2;
        codePoint = first & 0x0F;
      } else if (first >= 0xF0 && first <= 0xF4) {
        continuationCount = 3;
        codePoint = first & 0x07;
      } else {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
        index += 1;
        continue;
      }
      if (index + continuationCount >= bytes.length) {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
        break;
      }
      let valid = true;
      for (let offset = 1; offset <= continuationCount; offset += 1) {
        const next = bytes[index + offset];
        if ((next & 0xC0) !== 0x80) {
          valid = false;
          break;
        }
        codePoint = (codePoint << 6) | (next & 0x3F);
      }
      const minimumCodePoint = continuationCount === 1 ? 0x80 :
        continuationCount === 2 ? 0x800 : 0x10000;
      if (!valid || codePoint < minimumCodePoint || codePoint > 0x10FFFF ||
        (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
        index += 1;
        continue;
      }
      if (codePoint <= 0xFFFF) {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, codePoint);
      } else {
        const adjusted = codePoint - 0x10000;
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xD800 + (adjusted >> 10));
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xDC00 + (adjusted & 0x3FF));
      }
      index += continuationCount + 1;
    }
    return M3uEncoding.finishCodeUnits(chunks, codeUnits);
  }

  private static decodeUtf16(bytes: Uint8Array, start: number, littleEndian: boolean): string {
    const chunks: Array<string> = [];
    let codeUnits: Array<number> = [];
    let pendingHighSurrogate = -1;
    for (let index = start; index + 1 < bytes.length; index += 2) {
      const codeUnit = littleEndian ?
        bytes[index] | (bytes[index + 1] << 8) :
        (bytes[index] << 8) | bytes[index + 1];
      if (pendingHighSurrogate >= 0) {
        if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
          codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, pendingHighSurrogate);
          codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, codeUnit);
          pendingHighSurrogate = -1;
          continue;
        }
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
        pendingHighSurrogate = -1;
      }
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
        pendingHighSurrogate = codeUnit;
      } else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
      } else {
        codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, codeUnit);
      }
    }
    if (pendingHighSurrogate >= 0) {
      codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
    }
    if ((bytes.length - start) % 2 !== 0) {
      codeUnits = M3uEncoding.appendCodeUnit(chunks, codeUnits, 0xFFFD);
    }
    return M3uEncoding.finishCodeUnits(chunks, codeUnits);
  }

  private static appendCodeUnit(chunks: Array<string>, codeUnits: Array<number>, value: number): Array<number> {
    codeUnits.push(value);
    if (codeUnits.length < 1024) {
      return codeUnits;
    }
    chunks.push(M3uEncoding.codeUnitsToString(codeUnits));
    return [];
  }

  private static finishCodeUnits(chunks: Array<string>, codeUnits: Array<number>): string {
    if (codeUnits.length > 0) {
      chunks.push(M3uEncoding.codeUnitsToString(codeUnits));
    }
    return chunks.join('');
  }

  private static codeUnitsToString(codeUnits: Array<number>): string {
    let chunk = '';
    for (let index = 0; index < codeUnits.length; index += 1) {
      chunk += String.fromCharCode(codeUnits[index]);
    }
    return chunk;
  }
}
