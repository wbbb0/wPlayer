import { describe, expect, it } from '@ohos/hypium';
import { ArtworkPaletteExtractor } from '../main/ets/library/artwork/ArtworkPaletteExtractor';

interface TestColor {
  red: number;
  green: number;
  blue: number;
}

function appendPixels(target: Array<number>, color: TestColor, count: number): void {
  for (let index = 0; index < count; index += 1) {
    // ArtworkPaletteExtractor consumes the BGRA layout returned by PixelMap.readPixels.
    target.push(color.blue, color.green, color.red, 255);
  }
}

function component(color: string, offset: number): number {
  return Number.parseInt(color.substring(offset, offset + 2), 16);
}

function isBlueDominant(color: string): boolean {
  return component(color, 7) > component(color, 3) &&
    component(color, 7) > component(color, 5);
}

function isNeutral(color: string): boolean {
  const red = component(color, 3);
  const green = component(color, 5);
  const blue = component(color, 7);
  return Math.abs(red - green) <= 1 && Math.abs(green - blue) <= 1;
}

function isRedDominant(color: string): boolean {
  return component(color, 3) > component(color, 5) &&
    component(color, 3) > component(color, 7);
}

function isGreenDominant(color: string): boolean {
  return component(color, 5) > component(color, 3) &&
    component(color, 5) > component(color, 7);
}

function isVeryDark(color: string): boolean {
  return component(color, 3) < 45 &&
    component(color, 5) < 45 &&
    component(color, 7) < 45;
}

function isDark(color: string): boolean {
  return component(color, 3) < 90 &&
    component(color, 5) < 90 &&
    component(color, 7) < 90;
}

export default function artworkPaletteExtractorTest() {
  describe('ArtworkPaletteExtractor', () => {
    it('chooses the largest chromatic area instead of a larger neutral area', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 115, green: 115, blue: 115 }, 700);
      appendPixels(pixels, { red: 25, green: 95, blue: 235 }, 300);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isBlueDominant(palette.primary)).assertTrue();
    });

    it('does not promote a tiny vivid artifact to primary', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 38, green: 110, blue: 225 }, 970);
      appendPixels(pixels, { red: 255, green: 30, blue: 60 }, 10);
      appendPixels(pixels, { red: 80, green: 80, blue: 80 }, 20);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isBlueDominant(palette.primary)).assertTrue();
    });

    it('rejects a vivid color family below the minimum primary area', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 120, green: 120, blue: 120 }, 950);
      appendPixels(pixels, { red: 250, green: 25, blue: 45 }, 50);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isRedDominant(palette.primary)).assertFalse();
      expect(isRedDominant(palette.secondary)).assertTrue();
      expect(isRedDominant(palette.accent)).assertTrue();
    });

    it('accepts a large muted color below the previous chroma threshold', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 110, green: 120, blue: 140 }, 800);
      appendPixels(pixels, { red: 115, green: 115, blue: 115 }, 200);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isBlueDominant(palette.primary)).assertTrue();
    });

    it('uses dominant black as primary and preserves a small vivid accent', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 4, green: 5, blue: 5 }, 700);
      appendPixels(pixels, { red: 165, green: 165, blue: 165 }, 270);
      appendPixels(pixels, { red: 15, green: 245, blue: 80 }, 30);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isVeryDark(palette.primary)).assertTrue();
      expect(isGreenDominant(palette.secondary)).assertTrue();
      expect(isGreenDominant(palette.accent)).assertTrue();
      expect(palette.secondary === palette.accent).assertFalse();
    });

    it('prefers dominant black over a large red area and keeps red as accent', 0, () => {
      const pixels: Array<number> = [];
      // American Idiot's visually black background is actually a very dark navy.
      appendPixels(pixels, { red: 1, green: 2, blue: 17 }, 620);
      appendPixels(pixels, { red: 240, green: 240, blue: 235 }, 250);
      appendPixels(pixels, { red: 205, green: 45, blue: 48 }, 130);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isVeryDark(palette.primary)).assertTrue();
      expect(isRedDominant(palette.secondary)).assertTrue();
      expect(isRedDominant(palette.accent)).assertTrue();
    });

    it('uses the largest color family as secondary and a distinct family as accent', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 3, green: 4, blue: 12 }, 600);
      appendPixels(pixels, { red: 30, green: 105, blue: 235 }, 250);
      appendPixels(pixels, { red: 245, green: 120, blue: 25 }, 150);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isVeryDark(palette.primary)).assertTrue();
      expect(isBlueDominant(palette.secondary)).assertTrue();
      expect(isRedDominant(palette.accent)).assertTrue();
    });

    it('preserves the hue of a dominant dark brown background', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 55, green: 28, blue: 20 }, 600);
      appendPixels(pixels, { red: 220, green: 210, blue: 195 }, 300);
      appendPixels(pixels, { red: 235, green: 130, blue: 35 }, 100);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isDark(palette.primary)).assertTrue();
      expect(isRedDominant(palette.primary)).assertTrue();
    });

    it('does not let a minority dark area override the majority color', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 4, green: 12, blue: 30 }, 400);
      appendPixels(pixels, { red: 225, green: 180, blue: 35 }, 600);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(isVeryDark(palette.primary)).assertFalse();
    });

    it('derives layered neutral colors for a grayscale cover', 0, () => {
      const pixels: Array<number> = [];
      appendPixels(pixels, { red: 30, green: 30, blue: 30 }, 500);
      appendPixels(pixels, { red: 220, green: 220, blue: 220 }, 500);

      const palette = ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixels));

      expect(palette.primary === ArtworkPaletteExtractor.fallback().primary).assertFalse();
      expect(isNeutral(palette.primary)).assertTrue();
      expect(isNeutral(palette.secondary)).assertTrue();
      expect(isNeutral(palette.accent)).assertTrue();
      expect(palette.primary === palette.secondary).assertFalse();
      expect(palette.secondary === palette.accent).assertFalse();
    });
  });
}
