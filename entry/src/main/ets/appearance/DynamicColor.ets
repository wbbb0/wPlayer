export enum DynamicContainerRole {
  PRIMARY,
  SECONDARY,
  ACCENT
}

export enum ForegroundEmphasis {
  HIGH,
  MEDIUM,
  DISABLED
}

const OPAQUE_BLACK = '#FF000000';
const OPAQUE_WHITE = '#FFFFFFFF';

export class DynamicColor {
  static foreground(background: string, role: DynamicContainerRole): string {
    if (role === DynamicContainerRole.ACCENT) {
      return OPAQUE_WHITE;
    }
    const rgb = DynamicColor.parseRgb(background);
    if (rgb.length !== 3) {
      return OPAQUE_WHITE;
    }
    const luminance = 0.2126 * DynamicColor.linear(rgb[0] / 255) +
      0.7152 * DynamicColor.linear(rgb[1] / 255) +
      0.0722 * DynamicColor.linear(rgb[2] / 255);
    const whiteContrast = 1.05 / (luminance + 0.05);
    const blackContrast = (luminance + 0.05) / 0.05;
    return blackContrast >= whiteContrast ? OPAQUE_BLACK : OPAQUE_WHITE;
  }

  static withEmphasis(foreground: string, emphasis: ForegroundEmphasis): string {
    const rgb = DynamicColor.parseRgb(foreground);
    if (rgb.length !== 3) {
      return OPAQUE_WHITE;
    }
    let alpha = 'FF';
    if (emphasis === ForegroundEmphasis.MEDIUM) {
      alpha = 'B8';
    } else if (emphasis === ForegroundEmphasis.DISABLED) {
      alpha = '61';
    }
    return `#${alpha}${DynamicColor.hex(rgb[0])}${DynamicColor.hex(rgb[1])}${DynamicColor.hex(rgb[2])}`;
  }

  static blendOpaque(start: string, end: string, progress: number): string {
    const startRgb = DynamicColor.parseRgb(start);
    const endRgb = DynamicColor.parseRgb(end);
    if (startRgb.length !== 3 || endRgb.length !== 3) {
      return progress >= 0.5 ? end : start;
    }
    const amount = Math.max(0, Math.min(1, progress));
    return `#FF${DynamicColor.hex(DynamicColor.mix(startRgb[0], endRgb[0], amount))}` +
      `${DynamicColor.hex(DynamicColor.mix(startRgb[1], endRgb[1], amount))}` +
      `${DynamicColor.hex(DynamicColor.mix(startRgb[2], endRgb[2], amount))}`;
  }

  private static parseRgb(color: string): Array<number> {
    const value = color.startsWith('#') ? color.substring(1) : color;
    const rgb = value.length === 8 ? value.substring(2) : value;
    if (rgb.length !== 6) {
      return [];
    }
    const red = Number.parseInt(rgb.substring(0, 2), 16);
    const green = Number.parseInt(rgb.substring(2, 4), 16);
    const blue = Number.parseInt(rgb.substring(4, 6), 16);
    if (Number.isNaN(red) || Number.isNaN(green) || Number.isNaN(blue)) {
      return [];
    }
    return [red, green, blue];
  }

  private static linear(value: number): number {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  }

  private static mix(start: number, end: number, progress: number): number {
    return Math.round(start + (end - start) * progress);
  }

  private static hex(value: number): string {
    return Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, '0').toUpperCase();
  }
}
