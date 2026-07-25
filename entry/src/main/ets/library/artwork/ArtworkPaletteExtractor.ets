import { image } from '@kit.ImageKit';

const SAMPLE_EDGE = 64;
const CLUSTER_COUNT = 8;
const ITERATION_COUNT = 10;
const DEFAULT_PRIMARY = '#FF7C4DFF';
const DEFAULT_SECONDARY = '#FFFF4D8D';
const DEFAULT_ACCENT = '#FFFFB347';
export const ARTWORK_PALETTE_VERSION: number = 12;
const DARK_PRIMARY_MIN_POPULATION = 0.50;
const DARK_PRIMARY_MAX_SOURCE_LIGHTNESS = 0.34;
const DARK_PRIMARY_MIN_LIGHTNESS = 0.12;
const DARK_PRIMARY_MAX_LIGHTNESS = 0.32;
const DARK_PRIMARY_MAX_CHROMA = 0.12;
const PRIMARY_MIN_POPULATION = 0.08;
const PRIMARY_MIN_SOURCE_LIGHTNESS = 0.20;
const PRIMARY_MAX_SOURCE_LIGHTNESS = 0.88;
const PRIMARY_MIN_SOURCE_CHROMA = 0.03;
const PRIMARY_POPULATION_TIE = 0.03;
const PRIMARY_FAMILY_HUE_DISTANCE = 20;
const PRIMARY_FAMILY_LIGHTNESS_DISTANCE = 0.15;
const PRIMARY_MIN_LIGHTNESS = 0.42;
const PRIMARY_MAX_LIGHTNESS = 0.68;
const PRIMARY_MIN_CHROMA = 0.10;
const PRIMARY_MAX_CHROMA = 0.22;
const SECONDARY_DARK_PRIMARY_THRESHOLD = 0.55;
const SECONDARY_LIGHT_MIN = 0.62;
const SECONDARY_LIGHT_MAX = 0.78;
const SECONDARY_DARK_MIN = 0.32;
const SECONDARY_DARK_MAX = 0.50;
const SECONDARY_MIN_LIGHTNESS_GAP = 0.18;
const SECONDARY_MIN_DISTANCE = 0.20;
const SECONDARY_MIN_POPULATION = 0.02;
const SECONDARY_MIN_SOURCE_CHROMA = 0.05;
const SECONDARY_MIN_HUE_DISTANCE = 20;
const SECONDARY_MAX_HUE_DISTANCE = 110;
const SECONDARY_MIN_CHROMA = 0.08;
const SECONDARY_MAX_CHROMA = 0.18;
const ACCENT_MIN_POPULATION = 0.012;
const ACCENT_MIN_SOURCE_CHROMA = 0.10;
const ACCENT_MIN_HUE_DISTANCE = 35;
const ACCENT_MIN_DISTANCE = 0.12;
const ACCENT_MIN_LIGHTNESS = 0.58;
const ACCENT_MAX_LIGHTNESS = 0.76;
const ACCENT_MIN_CHROMA = 0.14;
const ACCENT_MAX_CHROMA = 0.24;
const NEUTRAL_MAX_CHROMA = 0.025;
const NEUTRAL_PRIMARY_MIN_LIGHTNESS = 0.30;
const NEUTRAL_PRIMARY_MAX_LIGHTNESS = 0.72;
const NEUTRAL_ROLE_THRESHOLD = 0.55;
const NEUTRAL_LIGHT_SECONDARY = 0.72;
const NEUTRAL_LIGHT_ACCENT = 0.82;
const NEUTRAL_DARK_SECONDARY = 0.38;
const NEUTRAL_DARK_ACCENT = 0.30;

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

interface SecondaryAccentRoles {
  secondary: ColorCluster;
  accent: ColorCluster;
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
    const dominantDark = ArtworkPaletteExtractor.dominantDark(samples);
    if (dominantDark !== undefined) {
      return ArtworkPaletteExtractor.darkPalette(clusters, dominantDark);
    }
    const extractedPrimary = ArtworkPaletteExtractor.bestPrimary(clusters);
    if (extractedPrimary === undefined) {
      return ArtworkPaletteExtractor.neutralPalette(clusters);
    }
    const primary = ArtworkPaletteExtractor.normalizeColor(
      extractedPrimary,
      PRIMARY_MIN_LIGHTNESS,
      PRIMARY_MAX_LIGHTNESS,
      PRIMARY_MIN_CHROMA,
      PRIMARY_MAX_CHROMA
    );
    const extractedSecondary = ArtworkPaletteExtractor.bestSecondary(clusters, extractedPrimary) ??
      ArtworkPaletteExtractor.derive(primary, 30, 0.90, 0.06);
    const secondary = ArtworkPaletteExtractor.normalizeSecondary(extractedSecondary, primary);
    const extractedAccent = ArtworkPaletteExtractor.bestAccent(
      clusters, extractedPrimary, extractedSecondary
    ) ?? ArtworkPaletteExtractor.bestGamutDerived(primary, 60, 1.22, 0.10);
    const accent = ArtworkPaletteExtractor.normalizeColor(
      extractedAccent,
      ACCENT_MIN_LIGHTNESS,
      ACCENT_MAX_LIGHTNESS,
      ACCENT_MIN_CHROMA,
      ACCENT_MAX_CHROMA
    );
    return {
      primary: ArtworkPaletteExtractor.toColor(primary),
      secondary: ArtworkPaletteExtractor.toColor(secondary),
      accent: ArtworkPaletteExtractor.toColor(accent)
    };
  }

  private static darkPalette(clusters: Array<ColorCluster>,
    dominantDark: ColorCluster): ArtworkPalette {
    const primary = ArtworkPaletteExtractor.normalizeColor(
      dominantDark,
      DARK_PRIMARY_MIN_LIGHTNESS,
      DARK_PRIMARY_MAX_LIGHTNESS,
      0,
      DARK_PRIMARY_MAX_CHROMA
    );
    const extractedNeutral = ArtworkPaletteExtractor.neutralCenter(clusters);
    const neutral: ColorCluster = {
      l: extractedNeutral.l,
      a: 0,
      b: 0,
      population: extractedNeutral.population
    };
    const roles = ArtworkPaletteExtractor.secondaryAccentRoles(clusters, primary, neutral);
    return {
      primary: ArtworkPaletteExtractor.toColor(primary, DARK_PRIMARY_MIN_LIGHTNESS),
      secondary: ArtworkPaletteExtractor.toColor(roles.secondary),
      accent: ArtworkPaletteExtractor.toColor(roles.accent)
    };
  }

  private static neutralPalette(clusters: Array<ColorCluster>): ArtworkPalette {
    const neutral = ArtworkPaletteExtractor.neutralCenter(clusters);
    const primary = ArtworkPaletteExtractor.withLightness(
      neutral,
      ArtworkPaletteExtractor.clamp(
        neutral.l,
        NEUTRAL_PRIMARY_MIN_LIGHTNESS,
        NEUTRAL_PRIMARY_MAX_LIGHTNESS
      )
    );
    const roles = ArtworkPaletteExtractor.secondaryAccentRoles(clusters, primary, neutral);
    return {
      primary: ArtworkPaletteExtractor.toColor(primary),
      secondary: ArtworkPaletteExtractor.toColor(roles.secondary),
      accent: ArtworkPaletteExtractor.toColor(roles.accent)
    };
  }

  private static secondaryAccentRoles(clusters: Array<ColorCluster>, primary: ColorCluster,
    neutral: ColorCluster): SecondaryAccentRoles {
    const useLightRoles = primary.l < NEUTRAL_ROLE_THRESHOLD;
    const fallbackSecondary = ArtworkPaletteExtractor.withLightness(
      neutral,
      useLightRoles ? NEUTRAL_LIGHT_SECONDARY : NEUTRAL_DARK_SECONDARY
    );
    const fallbackAccent = ArtworkPaletteExtractor.withLightness(
      neutral,
      useLightRoles ? NEUTRAL_LIGHT_ACCENT : NEUTRAL_DARK_ACCENT
    );
    const secondarySource = ArtworkPaletteExtractor.bestChromaticRole(clusters);
    if (secondarySource === undefined) {
      return { secondary: fallbackSecondary, accent: fallbackAccent };
    }
    const secondary = ArtworkPaletteExtractor.normalizeSecondary(secondarySource, primary);
    const accentSource = ArtworkPaletteExtractor.bestIndependentAccent(
      clusters,
      secondary,
      secondarySource
    );
    const accent = accentSource === undefined ?
      ArtworkPaletteExtractor.normalizeColor(
        ArtworkPaletteExtractor.derive(secondary, 0, 1.30, -0.08),
        ACCENT_MIN_LIGHTNESS,
        ACCENT_MAX_LIGHTNESS,
        ACCENT_MIN_CHROMA,
        ACCENT_MAX_CHROMA
      ) :
      ArtworkPaletteExtractor.normalizeColor(
        accentSource,
        ACCENT_MIN_LIGHTNESS,
        ACCENT_MAX_LIGHTNESS,
        ACCENT_MIN_CHROMA,
        ACCENT_MAX_CHROMA
      );
    return { secondary: secondary, accent: accent };
  }

  private static neutralCenter(clusters: Array<ColorCluster>): ColorCluster {
    let sumL = 0;
    let sumA = 0;
    let sumB = 0;
    let population = 0;
    const hasNeutralClusters = clusters.some((cluster: ColorCluster): boolean =>
      ArtworkPaletteExtractor.chroma(cluster) < PRIMARY_MIN_SOURCE_CHROMA);
    clusters.forEach((cluster: ColorCluster) => {
      if (hasNeutralClusters &&
        ArtworkPaletteExtractor.chroma(cluster) >= PRIMARY_MIN_SOURCE_CHROMA) {
        return;
      }
      sumL += cluster.l * cluster.population;
      sumA += cluster.a * cluster.population;
      sumB += cluster.b * cluster.population;
      population += cluster.population;
    });
    const center: ColorCluster = population > 0 ? {
      l: sumL / population,
      a: sumA / population,
      b: sumB / population,
      population: population
    } : {
      l: 0.5,
      a: 0,
      b: 0,
      population: 1
    };
    return ArtworkPaletteExtractor.withChroma(
      center,
      Math.min(NEUTRAL_MAX_CHROMA, ArtworkPaletteExtractor.chroma(center))
    );
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

  private static bestPrimary(clusters: Array<ColorCluster>): ColorCluster | undefined {
    let best: ColorCluster | undefined = undefined;
    clusters.forEach((cluster: ColorCluster) => {
      if (cluster.l < PRIMARY_MIN_SOURCE_LIGHTNESS || cluster.l > PRIMARY_MAX_SOURCE_LIGHTNESS ||
        ArtworkPaletteExtractor.chroma(cluster) < PRIMARY_MIN_SOURCE_CHROMA) {
        return;
      }
      const family = ArtworkPaletteExtractor.familyCenter(clusters, cluster);
      if (family.population < PRIMARY_MIN_POPULATION) {
        return;
      }
      if (best === undefined || family.population > best.population + PRIMARY_POPULATION_TIE ||
        (Math.abs(family.population - best.population) <= PRIMARY_POPULATION_TIE &&
          ArtworkPaletteExtractor.chroma(family) > ArtworkPaletteExtractor.chroma(best))) {
        best = family;
      }
    });
    return best;
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
    return ArtworkPaletteExtractor.withChroma(
      ArtworkPaletteExtractor.withLightness(color, lightness),
      ArtworkPaletteExtractor.clamp(
        ArtworkPaletteExtractor.chroma(color),
        SECONDARY_MIN_CHROMA,
        SECONDARY_MAX_CHROMA
      )
    );
  }

  private static withLightness(color: ColorCluster, lightness: number): ColorCluster {
    return { l: lightness, a: color.a, b: color.b, population: color.population };
  }

  private static withChroma(color: ColorCluster, chroma: number): ColorCluster {
    const sourceChroma = ArtworkPaletteExtractor.chroma(color);
    if (sourceChroma <= 0.000001) {
      return color;
    }
    const scale = chroma / sourceChroma;
    return {
      l: color.l,
      a: color.a * scale,
      b: color.b * scale,
      population: color.population
    };
  }

  private static normalizeColor(color: ColorCluster, minimumLightness: number,
    maximumLightness: number, minimumChroma: number, maximumChroma: number): ColorCluster {
    const withLightness = ArtworkPaletteExtractor.withLightness(
      color,
      ArtworkPaletteExtractor.clamp(color.l, minimumLightness, maximumLightness)
    );
    return ArtworkPaletteExtractor.withChroma(
      withLightness,
      ArtworkPaletteExtractor.clamp(
        ArtworkPaletteExtractor.chroma(color),
        minimumChroma,
        maximumChroma
      )
    );
  }

  private static familyCenter(clusters: Array<ColorCluster>, seed: ColorCluster): ColorCluster {
    let sumL = 0;
    let sumA = 0;
    let sumB = 0;
    let population = 0;
    clusters.forEach((cluster: ColorCluster) => {
      if (ArtworkPaletteExtractor.chroma(cluster) < PRIMARY_MIN_SOURCE_CHROMA ||
        ArtworkPaletteExtractor.hueDistance(cluster, seed) > PRIMARY_FAMILY_HUE_DISTANCE ||
        Math.abs(cluster.l - seed.l) > PRIMARY_FAMILY_LIGHTNESS_DISTANCE) {
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

  private static bestSecondary(clusters: Array<ColorCluster>,
    primary: ColorCluster): ColorCluster | undefined {
    let best: ColorCluster | undefined = undefined;
    let bestScore = -1;
    clusters.forEach((cluster: ColorCluster) => {
      const hueDistance = ArtworkPaletteExtractor.hueDistance(cluster, primary);
      if (cluster.population < SECONDARY_MIN_POPULATION ||
        ArtworkPaletteExtractor.chroma(cluster) < SECONDARY_MIN_SOURCE_CHROMA ||
        hueDistance < SECONDARY_MIN_HUE_DISTANCE || hueDistance > SECONDARY_MAX_HUE_DISTANCE) {
        return;
      }
      const chroma = Math.min(1, ArtworkPaletteExtractor.chroma(cluster) / 0.24);
      const distinct = Math.min(1, ArtworkPaletteExtractor.distance(cluster, primary) / 0.30);
      const score = cluster.population * 0.50 + chroma * 0.30 + distinct * 0.20;
      if (score > bestScore) {
        best = cluster;
        bestScore = score;
      }
    });
    return best;
  }

  private static bestChromaticRole(clusters: Array<ColorCluster>): ColorCluster | undefined {
    let best: ColorCluster | undefined = undefined;
    clusters.forEach((cluster: ColorCluster) => {
      if (ArtworkPaletteExtractor.chroma(cluster) < SECONDARY_MIN_SOURCE_CHROMA) {
        return;
      }
      const family = ArtworkPaletteExtractor.familyCenter(clusters, cluster);
      if (family.population < SECONDARY_MIN_POPULATION) {
        return;
      }
      if (best === undefined || family.population > best.population + PRIMARY_POPULATION_TIE ||
        (Math.abs(family.population - best.population) <= PRIMARY_POPULATION_TIE &&
          ArtworkPaletteExtractor.chroma(family) > ArtworkPaletteExtractor.chroma(best))) {
        best = family;
      }
    });
    return best;
  }

  private static dominantDark(samples: Array<ColorSample>): ColorCluster | undefined {
    let totalWeight = 0;
    let darkWeight = 0;
    let sumL = 0;
    let sumA = 0;
    let sumB = 0;
    samples.forEach((sample: ColorSample) => {
      totalWeight += sample.weight;
      if (sample.l > DARK_PRIMARY_MAX_SOURCE_LIGHTNESS) {
        return;
      }
      darkWeight += sample.weight;
      sumL += sample.l * sample.weight;
      sumA += sample.a * sample.weight;
      sumB += sample.b * sample.weight;
    });
    if (totalWeight === 0 || darkWeight / totalWeight < DARK_PRIMARY_MIN_POPULATION) {
      return undefined;
    }
    return {
      l: sumL / darkWeight,
      a: sumA / darkWeight,
      b: sumB / darkWeight,
      population: darkWeight / totalWeight
    };
  }

  private static bestAccent(clusters: Array<ColorCluster>, primary: ColorCluster,
    secondary: ColorCluster): ColorCluster | undefined {
    let best: ColorCluster | undefined = undefined;
    let bestScore = -1;
    clusters.forEach((cluster: ColorCluster) => {
      const distinct = ArtworkPaletteExtractor.distance(cluster, primary);
      if (cluster.population < ACCENT_MIN_POPULATION ||
        ArtworkPaletteExtractor.chroma(cluster) < ACCENT_MIN_SOURCE_CHROMA ||
        ArtworkPaletteExtractor.hueDistance(cluster, primary) < ACCENT_MIN_HUE_DISTANCE ||
        distinct < ACCENT_MIN_DISTANCE ||
        ArtworkPaletteExtractor.distance(cluster, secondary) < 0.08) {
        return;
      }
      const chroma = Math.min(1, ArtworkPaletteExtractor.chroma(cluster) / 0.24);
      const distanceScore = Math.min(1, distinct / 0.30);
      const score = chroma * 0.50 + cluster.population * 0.30 + distanceScore * 0.20;
      if (score > bestScore) {
        best = cluster;
        bestScore = score;
      }
    });
    return best;
  }

  private static bestIndependentAccent(clusters: Array<ColorCluster>,
    secondary: ColorCluster, secondarySource: ColorCluster): ColorCluster | undefined {
    let best: ColorCluster | undefined = undefined;
    let bestScore = -1;
    clusters.forEach((cluster: ColorCluster) => {
      if (cluster.population < ACCENT_MIN_POPULATION ||
        ArtworkPaletteExtractor.chroma(cluster) < ACCENT_MIN_SOURCE_CHROMA ||
        ArtworkPaletteExtractor.hueDistance(cluster, secondarySource) <
          PRIMARY_FAMILY_HUE_DISTANCE ||
        ArtworkPaletteExtractor.distance(cluster, secondary) < 0.08) {
        return;
      }
      const chroma = Math.min(1, ArtworkPaletteExtractor.chroma(cluster) / 0.24);
      const score = chroma * 0.60 + cluster.population * 0.40;
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

  private static bestGamutDerived(source: LabColor, hueOffset: number, chromaScale: number,
    lightnessOffset: number): ColorCluster {
    const positive = ArtworkPaletteExtractor.derive(source, hueOffset, chromaScale, lightnessOffset);
    const negative = ArtworkPaletteExtractor.derive(source, -hueOffset, chromaScale, lightnessOffset);
    return ArtworkPaletteExtractor.gamutScale(positive) >= ArtworkPaletteExtractor.gamutScale(negative) ?
      positive : negative;
  }

  private static gamutScale(color: LabColor): number {
    const chroma = ArtworkPaletteExtractor.chroma(color);
    let scale = 1;
    let linear = ArtworkPaletteExtractor.oklabToLinearRgb(
      color.l, color.a, color.b
    );
    while (!ArtworkPaletteExtractor.inGamut(linear) && scale > 0.02) {
      scale *= 0.92;
      linear = ArtworkPaletteExtractor.oklabToLinearRgb(
        color.l, color.a * scale, color.b * scale
      );
    }
    return chroma * scale;
  }

  private static toColor(color: LabColor, minimumLightness: number = 0.30): string {
    const chroma = ArtworkPaletteExtractor.chroma(color);
    let scale = chroma === 0 ? 1 : Math.min(1, 0.30 / chroma);
    const lightness = ArtworkPaletteExtractor.clamp(color.l, minimumLightness, 0.82);
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

  private static hue(color: LabColor): number {
    const degrees = Math.atan2(color.b, color.a) * 180 / Math.PI;
    return degrees < 0 ? degrees + 360 : degrees;
  }

  private static hueDistance(left: LabColor, right: LabColor): number {
    const difference = Math.abs(
      ArtworkPaletteExtractor.hue(left) - ArtworkPaletteExtractor.hue(right)
    );
    return Math.min(difference, 360 - difference);
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
