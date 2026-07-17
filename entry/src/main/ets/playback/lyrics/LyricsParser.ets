export interface TimedLyricLine {
  timeMs: number;
  text: string;
}

export interface ParsedLyrics {
  lines: Array<TimedLyricLine>;
  timed: boolean;
}

export class LyricsParser {
  static parse(source: string): ParsedLyrics {
    const lines: Array<TimedLyricLine> = [];
    const rows = source.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    const timestamp = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
    let offsetMs = 0;
    for (let index = 0; index < rows.length; index += 1) {
      const offsetMatch = /^\[offset:([+-]?\d+)\]$/i.exec(rows[index].trim());
      if (offsetMatch !== null) {
        offsetMs = Number.parseInt(offsetMatch[1], 10);
      }
    }
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      const times: Array<number> = [];
      let match: RegExpExecArray | null = timestamp.exec(row);
      while (match !== null) {
        const fraction = match[3] ?? '';
        let fractionMs = 0;
        if (fraction.length === 1) {
          fractionMs = Number.parseInt(fraction, 10) * 100;
        } else if (fraction.length === 2) {
          fractionMs = Number.parseInt(fraction, 10) * 10;
        } else if (fraction.length === 3) {
          fractionMs = Number.parseInt(fraction, 10);
        }
        times.push(Number.parseInt(match[1], 10) * 60000 + Number.parseInt(match[2], 10) * 1000 + fractionMs + offsetMs);
        match = timestamp.exec(row);
      }
      timestamp.lastIndex = 0;
      if (times.length === 0) {
        continue;
      }
      const text = row.replace(timestamp, '').trim();
      if (text.length === 0) {
        continue;
      }
      for (let timeIndex = 0; timeIndex < times.length; timeIndex += 1) {
        lines.push({ timeMs: Math.max(0, times[timeIndex]), text: text });
      }
    }
    lines.sort((left: TimedLyricLine, right: TimedLyricLine) => left.timeMs - right.timeMs);
    return { lines: lines, timed: lines.length > 0 };
  }
}
