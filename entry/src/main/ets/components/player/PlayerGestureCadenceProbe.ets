class CadenceSamples {
  count: number = 0;
  firstTimeMs: number = 0;
  lastTimeMs: number = 0;
  intervalTotalMs: number = 0;
  minimumIntervalMs: number = Number.MAX_VALUE;
  maximumIntervalMs: number = 0;

  record(timeMs: number): void {
    if (this.count === 0) {
      this.firstTimeMs = timeMs;
    } else {
      const interval = Math.max(0, timeMs - this.lastTimeMs);
      this.intervalTotalMs += interval;
      this.minimumIntervalMs = Math.min(this.minimumIntervalMs, interval);
      this.maximumIntervalMs = Math.max(this.maximumIntervalMs, interval);
    }
    this.lastTimeMs = timeMs;
    this.count += 1;
  }

  durationMs(): number {
    return this.count > 1 ? Math.max(0, this.lastTimeMs - this.firstTimeMs) : 0;
  }

  frequencyHz(): number {
    const duration = this.durationMs();
    return this.count > 1 && duration > 0 ? (this.count - 1) * 1000 / duration : 0;
  }

  averageIntervalMs(): number {
    return this.count > 1 ? this.intervalTotalMs / (this.count - 1) : 0;
  }

  minimumObservedIntervalMs(): number {
    return this.count > 1 ? this.minimumIntervalMs : 0;
  }
}

export class PlayerGestureCadenceProbe {
  private active: boolean = false;
  private gestureSamples: CadenceSamples = new CadenceSamples();
  private startProgress: number = 0;

  startIfNeeded(progress: number): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.gestureSamples = new CadenceSamples();
    this.startProgress = progress;
  }

  recordGestureUpdate(): void {
    if (this.active) {
      this.gestureSamples.record(Date.now());
    }
  }

  finish(progress: number): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    console.info(
      `[PlayerGestureCadence] updates=${this.gestureSamples.count}, ` +
      `updateHz=${this.fixed(this.gestureSamples.frequencyHz())}, ` +
      `updateIntervalMs(avg/min/max)=` +
      `${this.fixed(this.gestureSamples.averageIntervalMs())}/` +
      `${this.fixed(this.gestureSamples.minimumObservedIntervalMs())}/` +
      `${this.fixed(this.gestureSamples.maximumIntervalMs)}, ` +
      `progress=${this.fixed(this.startProgress)}->${this.fixed(progress)}`
    );
  }

  cancel(): void {
    this.active = false;
  }

  private fixed(value: number): string {
    return value.toFixed(1);
  }
}
