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
const READABLE_TEXT_CONTRAST = 4.5;
const VISIBLE_NON_TEXT_CONTRAST = 3;
const CONTRAST_SEARCH_ITERATIONS = 14;

export class DynamicColor {
  static foreground(background: string, _role: DynamicContainerRole): string {
    const rgb = DynamicColor.parseRgb(background);
    if (rgb.length !== 3) {
      return OPAQUE_WHITE;
    }
    const luminance = DynamicColor.luminance(rgb);
    const whiteContrast = 1.05 / (luminance + 0.05);
    const blackContrast = (luminance + 0.05) / 0.05;
    return blackContrast >= whiteContrast ? OPAQUE_BLACK : OPAQUE_WHITE;
  }

  static supportingForeground(background: string): string {
    return DynamicColor.foregroundForContrast(background, READABLE_TEXT_CONTRAST);
  }

  static nonTextForeground(background: string): string {
    return DynamicColor.foregroundForContrast(background, VISIBLE_NON_TEXT_CONTRAST);
  }

  static foregroundForContrast(background: string, minimumContrast: number): string {
    const backgroundRgb = DynamicColor.parseRgb(background);
    if (backgroundRgb.length !== 3) {
      return OPAQUE_WHITE;
    }
    const foreground = DynamicColor.foreground(background, DynamicContainerRole.PRIMARY);
    const foregroundRgb = DynamicColor.parseRgb(foreground);
    const target = Math.max(1, Math.min(21, minimumContrast));
    if (DynamicColor.rgbContrast(foregroundRgb, backgroundRgb) <= target) {
      return foreground;
    }
    let low = 0;
    let high = 1;
    for (let iteration = 0; iteration < CONTRAST_SEARCH_ITERATIONS; iteration += 1) {
      const amount = (low + high) / 2;
      const candidate = DynamicColor.mixRgb(backgroundRgb, foregroundRgb, amount);
      if (DynamicColor.rgbContrast(candidate, backgroundRgb) >= target) {
        high = amount;
      } else {
        low = amount;
      }
    }
    let amount = high;
    let candidate = DynamicColor.mixRgb(backgroundRgb, foregroundRgb, amount);
    while (amount < 1 && DynamicColor.rgbContrast(candidate, backgroundRgb) < target) {
      amount = Math.min(1, amount + 1 / 255);
      candidate = DynamicColor.mixRgb(backgroundRgb, foregroundRgb, amount);
    }
    return DynamicColor.opaqueColor(candidate);
  }

  static contrastRatio(foreground: string, background: string): number {
    const foregroundRgb = DynamicColor.parseRgb(foreground);
    const backgroundRgb = DynamicColor.parseRgb(background);
    if (foregroundRgb.length !== 3 || backgroundRgb.length !== 3) {
      return 1;
    }
    return DynamicColor.rgbContrast(foregroundRgb, backgroundRgb);
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
      alpha = '20';
    }
    return `#${alpha}${DynamicColor.hex(rgb[0])}${DynamicColor.hex(rgb[1])}${DynamicColor.hex(rgb[2])}`;
  }

  static withOpacity(color: string, opacity: number): string {
    const rgb = DynamicColor.parseRgb(color);
    if (rgb.length !== 3) {
      return color;
    }
    const alpha = DynamicColor.hex(Math.round(Math.max(0, Math.min(1, opacity)) * 255));
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

  private static luminance(rgb: Array<number>): number {
    return 0.2126 * DynamicColor.linear(rgb[0] / 255) +
      0.7152 * DynamicColor.linear(rgb[1] / 255) +
      0.0722 * DynamicColor.linear(rgb[2] / 255);
  }

  private static rgbContrast(left: Array<number>, right: Array<number>): number {
    const leftLuminance = DynamicColor.luminance(left);
    const rightLuminance = DynamicColor.luminance(right);
    return (Math.max(leftLuminance, rightLuminance) + 0.05) /
      (Math.min(leftLuminance, rightLuminance) + 0.05);
  }

  private static mixRgb(start: Array<number>, end: Array<number>, progress: number): Array<number> {
    return [
      DynamicColor.mix(start[0], end[0], progress),
      DynamicColor.mix(start[1], end[1], progress),
      DynamicColor.mix(start[2], end[2], progress)
    ];
  }

  private static opaqueColor(rgb: Array<number>): string {
    return `#FF${DynamicColor.hex(rgb[0])}${DynamicColor.hex(rgb[1])}${DynamicColor.hex(rgb[2])}`;
  }

  private static mix(start: number, end: number, progress: number): number {
    return Math.round(start + (end - start) * progress);
  }

  private static hex(value: number): string {
    return Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, '0').toUpperCase();
  }
}
