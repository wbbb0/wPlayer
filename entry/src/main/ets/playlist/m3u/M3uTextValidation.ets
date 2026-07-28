export class M3uTextValidation {
  static errorMessage(value: string): string {
    const maxLineCodeUnits = 16 * 1024;
    const maxLineCount = 100000;
    const maxEntryCount = 50000;
    let lineCodeUnits = 0;
    let lineCount = 1;
    let entryCount = 0;
    let lineKindKnown = false;
    let lineIsEntry = false;
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code === 0 ||
        (code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D) ||
        (code >= 0x7F && code <= 0x9F)) {
        return '文件包含二进制或无效控制字符，不是可导入的 M3U 文本';
      }
      if (code === 0x0A || code === 0x0D) {
        if (!(code === 0x0A && index > 0 && value.charCodeAt(index - 1) === 0x0D)) {
          entryCount += lineIsEntry ? 1 : 0;
          if (entryCount > maxEntryCount) {
            return `M3U 文件包含超过 ${maxEntryCount} 个歌曲条目，已拒绝导入`;
          }
          lineCount += 1;
          if (lineCount > maxLineCount) {
            return `M3U 文件包含超过 ${maxLineCount} 行，已拒绝导入`;
          }
          lineCodeUnits = 0;
          lineKindKnown = false;
          lineIsEntry = false;
        }
        continue;
      }
      lineCodeUnits += 1;
      if (lineCodeUnits > maxLineCodeUnits) {
        return `M3U 文件单行超过 ${maxLineCodeUnits} 个字符，已拒绝导入`;
      }
      if (!lineKindKnown && code !== 0x20 && code !== 0x09) {
        lineKindKnown = true;
        lineIsEntry = code !== 0x23;
      }
      if (code >= 0xD800 && code <= 0xDBFF) {
        if (index + 1 >= value.length) {
          return '文件包含无效的 Unicode 文本';
        }
        const low = value.charCodeAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF) {
          return '文件包含无效的 Unicode 文本';
        }
        lineCodeUnits += 1;
        if (lineCodeUnits > maxLineCodeUnits) {
          return `M3U 文件单行超过 ${maxLineCodeUnits} 个字符，已拒绝导入`;
        }
        index += 1;
      } else if (code >= 0xDC00 && code <= 0xDFFF) {
        return '文件包含无效的 Unicode 文本';
      }
    }
    entryCount += lineIsEntry ? 1 : 0;
    if (entryCount > maxEntryCount) {
      return `M3U 文件包含超过 ${maxEntryCount} 个歌曲条目，已拒绝导入`;
    }
    return '';
  }
}
