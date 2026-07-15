export class RequestEpoch {
  private value: number = 0;

  begin(): number {
    this.value += 1;
    return this.value;
  }

  invalidate(): number {
    this.value += 1;
    return this.value;
  }

  current(): number {
    return this.value;
  }

  isCurrent(epoch: number): boolean {
    return epoch === this.value;
  }
}
