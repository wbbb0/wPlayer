interface DynamicBackgroundLabColor {
  l: number;
  a: number;
  b: number;
}

export class DynamicBackgroundTextureAlgorithm {
  static readonly TEXTURE_SIZE: number = 256;
  static readonly WARP_AMOUNT: number = 0.12;
  static readonly WARP_SEED: number = 3;
  static readonly BLUR_RADIUS: number = 8;
  static readonly COLOR_STRENGTH: number = 72;
  static readonly CONTRAST: number = 1.25;

  static process(sourceBuffer: ArrayBuffer, sourceWidth: number, sourceHeight: number,
    premultiplied: boolean): ArrayBuffer {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw new Error(`Invalid dynamic background source size: ${sourceWidth}x${sourceHeight}`);
    }
    const source = new Uint8Array(sourceBuffer);
    const resized = DynamicBackgroundTextureAlgorithm.resizeToSquare(
      source, sourceWidth, sourceHeight, premultiplied
    );
    const colorful = DynamicBackgroundTextureAlgorithm.enhanceChroma(
      resized, DynamicBackgroundTextureAlgorithm.COLOR_STRENGTH, false
    );
    const warped = DynamicBackgroundTextureAlgorithm.periodicWarp(
      colorful,
      DynamicBackgroundTextureAlgorithm.WARP_AMOUNT,
      DynamicBackgroundTextureAlgorithm.WARP_SEED
    );
    let texture = DynamicBackgroundTextureAlgorithm.boxBlurWrap(
      warped, DynamicBackgroundTextureAlgorithm.BLUR_RADIUS
    );
    texture = DynamicBackgroundTextureAlgorithm.boxBlurWrap(
      texture, Math.round(DynamicBackgroundTextureAlgorithm.BLUR_RADIUS * 0.58)
    );
    texture = DynamicBackgroundTextureAlgorithm.enhanceChroma(
      texture, DynamicBackgroundTextureAlgorithm.COLOR_STRENGTH, true
    );
    texture = DynamicBackgroundTextureAlgorithm.applyContrast(
      texture, DynamicBackgroundTextureAlgorithm.CONTRAST
    );
    return texture.buffer;
  }

  private static clamp01(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private static clampByte(value: number): number {
    return Math.max(0, Math.min(255, Math.round(value)));
  }

  private static smoothstep(edge0: number, edge1: number, value: number): number {
    const t = DynamicBackgroundTextureAlgorithm.clamp01(
      (value - edge0) / Math.max(0.000001, edge1 - edge0)
    );
    return t * t * (3 - 2 * t);
  }

  private static fract(value: number): number {
    return value - Math.floor(value);
  }

  private static fold(value: number): number {
    return 0.5 - 0.5 * Math.cos(Math.PI * 2 * value);
  }

  private static sourceColor(source: Uint8Array, pixelOffset: number, channel: number,
    premultiplied: boolean): number {
    const alpha = source[pixelOffset + 3];
    const sourceChannel = channel === 0 ? 2 : channel === 2 ? 0 : channel;
    const color = source[pixelOffset + sourceChannel];
    if (premultiplied) {
      return Math.min(255, color + 255 - alpha);
    }
    return color * alpha / 255 + 255 - alpha;
  }

  private static resizeToSquare(source: Uint8Array, sourceWidth: number, sourceHeight: number,
    premultiplied: boolean): Uint8Array {
    const size = DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE;
    const output = new Uint8Array(size * size * 4);
    for (let y = 0; y < size; y += 1) {
      const sourceY = y * (sourceHeight - 1) / (size - 1);
      const y0 = Math.floor(sourceY);
      const y1 = Math.min(sourceHeight - 1, y0 + 1);
      const ty = sourceY - y0;
      for (let x = 0; x < size; x += 1) {
        const sourceX = x * (sourceWidth - 1) / (size - 1);
        const x0 = Math.floor(sourceX);
        const x1 = Math.min(sourceWidth - 1, x0 + 1);
        const tx = sourceX - x0;
        const i00 = (y0 * sourceWidth + x0) * 4;
        const i10 = (y0 * sourceWidth + x1) * 4;
        const i01 = (y1 * sourceWidth + x0) * 4;
        const i11 = (y1 * sourceWidth + x1) * 4;
        const outputOffset = (y * size + x) * 4;
        for (let channel = 0; channel < 3; channel += 1) {
          const top =
            DynamicBackgroundTextureAlgorithm.sourceColor(source, i00, channel, premultiplied) * (1 - tx) +
            DynamicBackgroundTextureAlgorithm.sourceColor(source, i10, channel, premultiplied) * tx;
          const bottom =
            DynamicBackgroundTextureAlgorithm.sourceColor(source, i01, channel, premultiplied) * (1 - tx) +
            DynamicBackgroundTextureAlgorithm.sourceColor(source, i11, channel, premultiplied) * tx;
          output[outputOffset + channel] =
            DynamicBackgroundTextureAlgorithm.clampByte(top * (1 - ty) + bottom * ty);
        }
        output[outputOffset + 3] = 255;
      }
    }
    return output;
  }

  private static bilinearSample(source: Uint8Array, x: number, y: number,
    output: Uint8Array, outputOffset: number): void {
    const size = DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE;
    const sampleX = Math.max(0, Math.min(size - 1.001, x));
    const sampleY = Math.max(0, Math.min(size - 1.001, y));
    const x0 = Math.floor(sampleX);
    const y0 = Math.floor(sampleY);
    const x1 = Math.min(size - 1, x0 + 1);
    const y1 = Math.min(size - 1, y0 + 1);
    const tx = sampleX - x0;
    const ty = sampleY - y0;
    const i00 = (y0 * size + x0) * 4;
    const i10 = (y0 * size + x1) * 4;
    const i01 = (y1 * size + x0) * 4;
    const i11 = (y1 * size + x1) * 4;
    for (let channel = 0; channel < 4; channel += 1) {
      const top = source[i00 + channel] * (1 - tx) + source[i10 + channel] * tx;
      const bottom = source[i01 + channel] * (1 - tx) + source[i11 + channel] * tx;
      output[outputOffset + channel] =
        DynamicBackgroundTextureAlgorithm.clampByte(top * (1 - ty) + bottom * ty);
    }
  }

  private static periodicWarp(source: Uint8Array, amount: number, seed: number): Uint8Array {
    const size = DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE;
    const output = new Uint8Array(source.length);
    const phase = seed * 0.731;
    for (let y = 0; y < size; y += 1) {
      const v = y / (size - 1);
      for (let x = 0; x < size; x += 1) {
        const u = x / (size - 1);
        const dx = amount * (
          0.52 * Math.sin(2 * Math.PI * (v + phase)) +
          0.30 * Math.sin(2 * Math.PI * (2 * u - v + phase * 1.37)) +
          0.18 * Math.cos(2 * Math.PI * (u + 2 * v + phase * 0.53))
        );
        const dy = amount * (
          0.48 * Math.sin(2 * Math.PI * (u + phase * 0.81)) +
          0.34 * Math.sin(2 * Math.PI * (u + 2 * v - phase * 1.11)) +
          0.18 * Math.cos(2 * Math.PI * (2 * u - v + phase * 0.41))
        );
        const sampleU = DynamicBackgroundTextureAlgorithm.fold(
          DynamicBackgroundTextureAlgorithm.fract(u + dx)
        );
        const sampleV = DynamicBackgroundTextureAlgorithm.fold(
          DynamicBackgroundTextureAlgorithm.fract(v + dy)
        );
        DynamicBackgroundTextureAlgorithm.bilinearSample(
          source,
          sampleU * (size - 1),
          sampleV * (size - 1),
          output,
          (y * size + x) * 4
        );
      }
    }
    return output;
  }

  private static boxBlurWrap(source: Uint8Array, radius: number): Uint8Array {
    const size = DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE;
    const r = Math.max(0, Math.floor(radius));
    if (r === 0) {
      return new Uint8Array(source);
    }
    const temporary = new Float32Array(source.length);
    const output = new Uint8Array(source.length);
    const diameter = r * 2 + 1;
    for (let y = 0; y < size; y += 1) {
      for (let channel = 0; channel < 4; channel += 1) {
        let sum = 0;
        for (let k = -r; k <= r; k += 1) {
          const xx = (k + size) % size;
          sum += source[(y * size + xx) * 4 + channel];
        }
        for (let x = 0; x < size; x += 1) {
          temporary[(y * size + x) * 4 + channel] = sum / diameter;
          const removeX = (x - r + size) % size;
          const addX = (x + r + 1) % size;
          sum += source[(y * size + addX) * 4 + channel] -
            source[(y * size + removeX) * 4 + channel];
        }
      }
    }
    for (let x = 0; x < size; x += 1) {
      for (let channel = 0; channel < 4; channel += 1) {
        let sum = 0;
        for (let k = -r; k <= r; k += 1) {
          const yy = (k + size) % size;
          sum += temporary[(yy * size + x) * 4 + channel];
        }
        for (let y = 0; y < size; y += 1) {
          output[(y * size + x) * 4 + channel] =
            DynamicBackgroundTextureAlgorithm.clampByte(sum / diameter);
          const removeY = (y - r + size) % size;
          const addY = (y + r + 1) % size;
          sum += temporary[(addY * size + x) * 4 + channel] -
            temporary[(removeY * size + x) * 4 + channel];
        }
      }
    }
    return output;
  }

  private static srgbToLinear(value: number): number {
    const normalized = value / 255;
    return normalized <= 0.04045 ? normalized / 12.92 :
      Math.pow((normalized + 0.055) / 1.055, 2.4);
  }

  private static linearToSrgb(value: number): number {
    const converted = value <= 0.0031308 ? 12.92 * value :
      1.055 * Math.pow(value, 1 / 2.4) - 0.055;
    return DynamicBackgroundTextureAlgorithm.clampByte(
      DynamicBackgroundTextureAlgorithm.clamp01(converted) * 255
    );
  }

  private static rgbToOklab(red: number, green: number, blue: number): DynamicBackgroundLabColor {
    const r = DynamicBackgroundTextureAlgorithm.srgbToLinear(red);
    const g = DynamicBackgroundTextureAlgorithm.srgbToLinear(green);
    const b = DynamicBackgroundTextureAlgorithm.srgbToLinear(blue);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return {
      l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    };
  }

  private static oklabToRgb(lightness: number, a: number, b: number): Array<number> {
    const lBase = lightness + 0.3963377774 * a + 0.2158037573 * b;
    const mBase = lightness - 0.1055613458 * a - 0.0638541728 * b;
    const sBase = lightness - 0.0894841775 * a - 1.2914855480 * b;
    const l = lBase * lBase * lBase;
    const m = mBase * mBase * mBase;
    const s = sBase * sBase * sBase;
    return [
      DynamicBackgroundTextureAlgorithm.linearToSrgb(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
      ),
      DynamicBackgroundTextureAlgorithm.linearToSrgb(
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
      ),
      DynamicBackgroundTextureAlgorithm.linearToSrgb(
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
      )
    ];
  }

  private static enhanceChroma(source: Uint8Array, strengthPercent: number,
    finalPass: boolean): Uint8Array {
    const amount = strengthPercent / 100;
    if (amount <= 0) {
      return new Uint8Array(source);
    }
    const output = new Uint8Array(source);
    const bayer4: Array<Array<number>> = [
      [0, 8, 2, 10],
      [12, 4, 14, 6],
      [3, 11, 1, 9],
      [15, 7, 13, 5]
    ];
    const size = DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE;
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        const offset = (y * size + x) * 4;
        const lab = DynamicBackgroundTextureAlgorithm.rgbToOklab(
          output[offset], output[offset + 1], output[offset + 2]
        );
        const chroma = Math.hypot(lab.a, lab.b);
        let gain = 1 + 0.34 * amount;
        if (!finalPass) {
          const lowWeight = 1 - DynamicBackgroundTextureAlgorithm.smoothstep(0.018, 0.17, chroma);
          gain = 1 + 0.62 * amount + 1.22 * amount * lowWeight * lowWeight;
        }
        const target = Math.min(chroma * gain, finalPass ? 0.36 : 0.42);
        let nextA = lab.a;
        let nextB = lab.b;
        if (chroma > 0.0000001) {
          const scale = target / chroma;
          nextA *= scale;
          nextB *= scale;
        }
        const rgb = DynamicBackgroundTextureAlgorithm.oklabToRgb(lab.l, nextA, nextB);
        const dither = (bayer4[y & 3][x & 3] / 15 - 0.5) * (finalPass ? 0.7 : 0.45);
        output[offset] = DynamicBackgroundTextureAlgorithm.clampByte(rgb[0] + dither);
        output[offset + 1] = DynamicBackgroundTextureAlgorithm.clampByte(rgb[1] + dither);
        output[offset + 2] = DynamicBackgroundTextureAlgorithm.clampByte(rgb[2] + dither);
        output[offset + 3] = 255;
      }
    }
    return output;
  }

  private static applyContrast(source: Uint8Array, contrast: number): Uint8Array {
    const output = new Uint8Array(source.length);
    for (let offset = 0; offset < source.length; offset += 4) {
      const lab = DynamicBackgroundTextureAlgorithm.rgbToOklab(
        source[offset], source[offset + 1], source[offset + 2]
      );
      const lightness = DynamicBackgroundTextureAlgorithm.clamp01(
        (lab.l - 0.5) * contrast + 0.5
      );
      const rgb = DynamicBackgroundTextureAlgorithm.oklabToRgb(lightness, lab.a, lab.b);
      output[offset] = rgb[0];
      output[offset + 1] = rgb[1];
      output[offset + 2] = rgb[2];
      output[offset + 3] = 255;
    }
    return output;
  }
}
