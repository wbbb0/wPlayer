import { image } from '@kit.ImageKit';

const SAMPLE_EDGE = 64;
const CLUSTER_COUNT = 8;
const ITERATION_COUNT = 10;
const PRIMARY_FAMILY_RADIUS = 0.14;
const PRIMARY_DENSITY_SIGMA = 0.075;
const DEFAULT_PRIMARY = '#FF7C4DFF';
const DEFAULT_SECONDARY = '#FFFF4D8D';
const DEFAULT_ACCENT = '#FFFFB347';
export const ARTWORK_PALETTE_VERSION: number = 5;
const PRIMARY_MIN_LIGHTNESS = 0.32;
const PRIMARY_MAX_LIGHTNESS = 0.72;
const SECONDARY_DARK_PRIMARY_THRESHOLD = 0.55;
const SECONDARY_LIGHT_MIN = 0.62;
const SECONDARY_LIGHT_MAX = 0.78;
const SECONDARY_DARK_MIN = 0.32;
const SECONDARY_DARK_MAX = 0.50;
const SECONDARY_MIN_LIGHTNESS_GAP = 0.18;
const SECONDARY_MIN_DISTANCE = 0.20;
const ACCENT_MIN_LIGHTNESS = 0.62;
const ACCENT_MAX_LIGHTNESS = 0.80;

export interface ArtworkPalette {
  primary: string;
  secondary: string;
  accent: string;
}

interface LabColor {
  l: number;
  a: number;
  b: number;
}

interface ColorSample extends LabColor {
  weight: number;
}

interface ColorCluster extends LabColor {
  population: number;
}

export class ArtworkPaletteExtractor {
  static fallback(): ArtworkPalette {
    return { primary: DEFAULT_PRIMARY, secondary: DEFAULT_SECONDARY, accent: DEFAULT_ACCENT };
  }

  static async readPixelBuffer(source: image.ImageSource, sourceSize: image.Size): Promise<ArrayBuffer> {
    const target = ArtworkPaletteExtractor.sampleSize(sourceSize);
    const pixelMap = await source.createPixelMap({
      desiredSize: target,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    try {
      const info = await pixelMap.getImageInfo();
      const stride = info.size.width * 4;
      const pixels = new ArrayBuffer(stride * info.size.height);
      await pixelMap.readPixels({
        pixels: pixels,
        offset: 0,
        stride: stride,
        region: { x: 0, y: 0, size: info.size }
      });
      return pixels;
    } finally {
      await pixelMap.release();
    }
  }

  static fromPixels(pixels: Uint8Array): ArtworkPalette {
    const samples: Array<ColorSample> = [];
    for (let offset = 0; offset + 3 < pixels.length; offset += 4) {
      const alpha = pixels[offset + 3] / 255;
      if (alpha < 0.5) {
        continue;
      }
      const lab = ArtworkPaletteExtractor.rgbToOklab(
        // PixelMap.readPixels(PositionArea) exposes BGRA bytes even when the requested
        // PixelMap format is RGBA_8888. Convert the buffer to logical RGB here.
        pixels[offset + 2] / 255,
        pixels[offset + 1] / 255,
        pixels[offset] / 255
      );
      samples.push({ l: lab.l, a: lab.a, b: lab.b, weight: alpha });
    }
    if (samples.length === 0) {
      return ArtworkPaletteExtractor.fallback();
    }
    const clusters = ArtworkPaletteExtractor.cluster(samples);
    if (clusters.length === 0) {
      return ArtworkPaletteExtractor.fallback();
    }
    const extractedPrimary = ArtworkPaletteExtractor.bestPrimary(clusters);
    const extractedSecondary = ArtworkPaletteExtractor.bestDistinct(clusters, extractedPrimary, false) ??
      ArtworkPaletteExtractor.derive(extractedPrimary, 28, 1.12, 0.06);
    const extractedAccent = ArtworkPaletteExtractor.bestDistinct(
      clusters, extractedPrimary, true, extractedSecondary
    ) ?? ArtworkPaletteExtractor.derive(extractedPrimary, -38, 1.25, 0.12);
    const primary = ArtworkPaletteExtractor.withLightness(
      extractedPrimary,
      ArtworkPaletteExtractor.clamp(extractedPrimary.l, PRIMARY_MIN_LIGHTNESS, PRIMARY_MAX_LIGHTNESS)
    );
    const secondary = ArtworkPaletteExtractor.normalizeSecondary(extractedSecondary, primary);
    const accent = ArtworkPaletteExtractor.withLightness(
      extractedAccent,
      ArtworkPaletteExtractor.clamp(extractedAccent.l, ACCENT_MIN_LIGHTNESS, ACCENT_MAX_LIGHTNESS)
    );
    return {
      primary: ArtworkPaletteExtractor.toColor(primary, 1.05),
      secondary: ArtworkPaletteExtractor.toColor(secondary, 1.18),
      accent: ArtworkPaletteExtractor.toColor(accent, 1.25)
    };
  }

  private static cluster(samples: Array<ColorSample>): Array<ColorCluster> {
    const sorted = samples.slice().sort((left: ColorSample, right: ColorSample) => {
      return ArtworkPaletteExtractor.chroma(right) - ArtworkPaletteExtractor.chroma(left);
    });
    const count = Math.min(CLUSTER_COUNT, sorted.length);
    const centers: Array<ColorCluster> = [];
    for (let index = 0; index < count; index++) {
      const sampleIndex = Math.min(sorted.length - 1, Math.floor(index * sorted.length / count));
      const sample = sorted[sampleIndex];
      centers.push({ l: sample.l, a: sample.a, b: sample.b, population: 0 });
    }
    for (let iteration = 0; iteration < ITERATION_COUNT; iteration++) {
      const sumL = new Array<number>(count).fill(0);
      const sumA = new Array<number>(count).fill(0);
      const sumB = new Array<number>(count).fill(0);
      const weights = new Array<number>(count).fill(0);
      samples.forEach((sample: ColorSample) => {
        let nearest = 0;
        let nearestDistance = Number.MAX_VALUE;
        for (let index = 0; index < count; index++) {
          const distance = ArtworkPaletteExtractor.distance(sample, centers[index]);
          if (distance < nearestDistance) {
            nearest = index;
            nearestDistance = distance;
          }
        }
        sumL[nearest] += sample.l * sample.weight;
        sumA[nearest] += sample.a * sample.weight;
        sumB[nearest] += sample.b * sample.weight;
        weights[nearest] += sample.weight;
      });
      for (let index = 0; index < count; index++) {
        if (weights[index] > 0) {
          centers[index].l = sumL[index] / weights[index];
          centers[index].a = sumA[index] / weights[index];
          centers[index].b = sumB[index] / weights[index];
          centers[index].population = weights[index] / samples.length;
        }
      }
    }
    return centers.filter((cluster: ColorCluster) => cluster.population >= 0.008);
  }

  private static bestPrimary(clusters: Array<ColorCluster>): ColorCluster {
    let best = clusters[0];
    let bestScore = -1;
    clusters.forEach((cluster: ColorCluster) => {
      const usableLightness = cluster.l < 0.10 || cluster.l > 0.94 ? 0.2 : 1;
      let density = 0;
      clusters.forEach((neighbor: ColorCluster) => {
        const distance = ArtworkPaletteExtractor.distance(cluster, neighbor);
        const kernel = Math.exp(-(distance * distance) /
          (2 * PRIMARY_DENSITY_SIGMA * PRIMARY_DENSITY_SIGMA));
        density += neighbor.population * kernel;
      });
      const chroma = Math.min(1, ArtworkPaletteExtractor.chroma(cluster) / 0.24);
      const score = usableLightness * (density * 0.90 + chroma * 0.10);
      if (score > bestScore) {
        best = cluster;
        bestScore = score;
      }
    });
    return ArtworkPaletteExtractor.familyCenter(clusters, best);
  }

  private static normalizeSecondary(color: ColorCluster, primary: ColorCluster): ColorCluster {
    const useLightRole = primary.l < SECONDARY_DARK_PRIMARY_THRESHOLD;
    const minimum = useLightRole ? SECONDARY_LIGHT_MIN : SECONDARY_DARK_MIN;
    const maximum = useLightRole ? SECONDARY_LIGHT_MAX : SECONDARY_DARK_MAX;
    let lightness = ArtworkPaletteExtractor.clamp(color.l, minimum, maximum);
    const candidate = ArtworkPaletteExtractor.withLightness(color, lightness);
    if (Math.abs(lightness - primary.l) < SECONDARY_MIN_LIGHTNESS_GAP ||
      ArtworkPaletteExtractor.distance(candidate, primary) < SECONDARY_MIN_DISTANCE) {
      lightness = useLightRole ?
        Math.min(maximum, primary.l + SECONDARY_MIN_LIGHTNESS_GAP) :
        Math.max(minimum, primary.l - SECONDARY_MIN_LIGHTNESS_GAP);
    }
    return ArtworkPaletteExtractor.withLightness(color, lightness);
  }

  private static withLightness(color: ColorCluster, lightness: number): ColorCluster {
    return { l: lightness, a: color.a, b: color.b, population: color.population };
  }

  private static familyCenter(clusters: Array<ColorCluster>, seed: ColorCluster): ColorCluster {
    let sumL = 0;
    let sumA = 0;
    let sumB = 0;
    let population = 0;
    clusters.forEach((cluster: ColorCluster) => {
      if (ArtworkPaletteExtractor.distance(cluster, seed) > PRIMARY_FAMILY_RADIUS) {
        return;
      }
      sumL += cluster.l * cluster.population;
      sumA += cluster.a * cluster.population;
      sumB += cluster.b * cluster.population;
      population += cluster.population;
    });
    if (population === 0) {
      return seed;
    }
    return {
      l: sumL / population,
      a: sumA / population,
      b: sumB / population,
      population: population
    };
  }

  private static bestDistinct(clusters: Array<ColorCluster>, primary: ColorCluster,
    preferChroma: boolean, excluded?: ColorCluster): ColorCluster | undefined {
    let best: ColorCluster | undefined = undefined;
    let bestScore = -1;
    clusters.forEach((cluster: ColorCluster) => {
      const distinct = ArtworkPaletteExtractor.distance(cluster, primary);
      if (cluster === primary || cluster === excluded || distinct < 0.10) {
        return;
      }
      const chroma = Math.min(1, ArtworkPaletteExtractor.chroma(cluster) / 0.24);
      const score = preferChroma ? chroma * 0.62 + cluster.population * 0.18 + distinct * 0.20 :
        cluster.population * 0.48 + chroma * 0.30 + distinct * 0.22;
      if (score > bestScore) {
        best = cluster;
        bestScore = score;
      }
    });
    return best;
  }

  private static derive(source: LabColor, hueOffset: number, chromaScale: number,
    lightnessOffset: number): ColorCluster {
    const hue = Math.atan2(source.b, source.a) + hueOffset * Math.PI / 180;
    const chroma = Math.max(0.08, ArtworkPaletteExtractor.chroma(source) * chromaScale);
    return {
      l: ArtworkPaletteExtractor.clamp(source.l + lightnessOffset, 0.35, 0.82),
      a: Math.cos(hue) * chroma,
      b: Math.sin(hue) * chroma,
      population: 0
    };
  }

  private static toColor(color: LabColor, chromaScale: number): string {
    const chroma = ArtworkPaletteExtractor.chroma(color);
    let scale = chroma === 0 ? 1 : Math.min(chromaScale, 0.30 / chroma);
    const lightness = ArtworkPaletteExtractor.clamp(color.l, 0.30, 0.82);
    let linear = ArtworkPaletteExtractor.oklabToLinearRgb(
      lightness, color.a * scale, color.b * scale
    );
    while (!ArtworkPaletteExtractor.inGamut(linear) && scale > 0.02) {
      scale *= 0.92;
      linear = ArtworkPaletteExtractor.oklabToLinearRgb(
        lightness, color.a * scale, color.b * scale
      );
    }
    const rgb = ArtworkPaletteExtractor.oklabToRgb(
      lightness, color.a * scale, color.b * scale
    );
    return `#FF${ArtworkPaletteExtractor.hex(rgb[0])}${ArtworkPaletteExtractor.hex(rgb[1])}` +
      `${ArtworkPaletteExtractor.hex(rgb[2])}`;
  }

  private static rgbToOklab(red: number, green: number, blue: number): LabColor {
    const r = ArtworkPaletteExtractor.linear(red);
    const g = ArtworkPaletteExtractor.linear(green);
    const b = ArtworkPaletteExtractor.linear(blue);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return {
      l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    };
  }

  private static oklabToRgb(l: number, a: number, b: number): Array<number> {
    const linear = ArtworkPaletteExtractor.oklabToLinearRgb(l, a, b);
    return [
      ArtworkPaletteExtractor.gamma(linear[0]),
      ArtworkPaletteExtractor.gamma(linear[1]),
      ArtworkPaletteExtractor.gamma(linear[2])
    ];
  }

  private static oklabToLinearRgb(l: number, a: number, b: number): Array<number> {
    const ll = Math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3);
    const mm = Math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3);
    const ss = Math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3);
    return [
      4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
      -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
      -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss
    ];
  }

  private static inGamut(rgb: Array<number>): boolean {
    return rgb[0] >= 0 && rgb[0] <= 1 && rgb[1] >= 0 && rgb[1] <= 1 && rgb[2] >= 0 && rgb[2] <= 1;
  }

  private static sampleSize(size: image.Size): image.Size {
    const scale = Math.min(1, SAMPLE_EDGE / Math.max(size.width, size.height));
    return {
      width: Math.max(1, Math.round(size.width * scale)),
      height: Math.max(1, Math.round(size.height * scale))
    };
  }

  private static distance(left: LabColor, right: LabColor): number {
    return Math.sqrt(Math.pow(left.l - right.l, 2) + Math.pow(left.a - right.a, 2) +
      Math.pow(left.b - right.b, 2));
  }

  private static chroma(color: LabColor): number {
    return Math.sqrt(color.a * color.a + color.b * color.b);
  }

  private static linear(value: number): number {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  }

  private static gamma(value: number): number {
    const clamped = ArtworkPaletteExtractor.clamp(value, 0, 1);
    return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * Math.pow(clamped, 1 / 2.4) - 0.055;
  }

  private static hex(value: number): string {
    return Math.round(ArtworkPaletteExtractor.clamp(value, 0, 1) * 255).toString(16).padStart(2, '0').toUpperCase();
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}
