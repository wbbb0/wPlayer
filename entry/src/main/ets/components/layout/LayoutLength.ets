export class LayoutLength {
  static toNumber(value: Length | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsedValue = Number.parseFloat(value);
      return Number.isNaN(parsedValue) ? fallback : parsedValue;
    }
    return fallback;
  }
}
