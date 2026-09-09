import { LyricsParser, TimedLyricLine } from './LyricsParser';

export class LyricsSnapshot {
  readonly source: string;
  readonly lines: Array<TimedLyricLine>;

  constructor(source: string) {
    this.source = source;
    this.lines = LyricsParser.parse(source).lines;
  }
}

// Only the active queue window is retained; failed reads remain retryable.
export class LyricsWindowCache {
  private ids: Array<number> = [];
  private readonly ready: Map<number, LyricsSnapshot> = new Map();
  private readonly pending: Map<number, Promise<LyricsSnapshot>> = new Map();
  private generation: number = 0;
  private windowRevision: number = 0;

  get(id: number): LyricsSnapshot | undefined {
    return this.ready.get(id);
  }

  setWindow(ids: Array<number>): void {
    this.ids = ids.slice(0, 3);
    this.windowRevision += 1;
    this.ready.forEach((_value: LyricsSnapshot, id: number): void => {
      if (this.ids.indexOf(id) < 0) {
        this.ready.delete(id);
      }
    });
  }

  reset(): void {
    this.generation += 1;
    this.setWindow([]);
    this.pending.clear();
  }

  load(id: number, read: () => Promise<string>): Promise<LyricsSnapshot> {
    const cached = this.ready.get(id);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const existing = this.pending.get(id);
    if (existing !== undefined) {
      return existing;
    }
    const generation = this.generation;
    const work = read().then((source: string): LyricsSnapshot => {
      const result = new LyricsSnapshot(source);
      if (generation === this.generation && this.ids.indexOf(id) >= 0) {
        this.ready.set(id, result);
      }
      return result;
    }).finally((): void => {
      if (generation === this.generation) {
        this.pending.delete(id);
      }
    });
    this.pending.set(id, work);
    return work;
  }

  async prefetch(read: (id: number) => Promise<string>): Promise<void> {
    const revision = this.windowRevision;
    const ids = this.ids.slice();
    for (const id of ids) {
      if (revision !== this.windowRevision) {
        return;
      }
      try {
        await this.load(id, (): Promise<string> => read(id));
      } catch (error) {
        console.warn(`Unable to prefetch lyrics for track ${id}: ${error}`);
      }
    }
  }
}
