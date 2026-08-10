export interface NativeMediaTag {
  key: string;
  value: string;
}

export interface NativeMediaArtwork {
  pictureType: number;
  mimeType: string;
  description: string;
  width: number;
  height: number;
  colorDepth: number;
  byteOffset: number;
  byteLength: number;
  payloadOffset: number;
  ordinal: number;
  unsynchronized: boolean;
}

export interface NativeParsedMedia {
  format: string;
  durationMs: number;
  sampleRate: number;
  channelCount: number;
  bitsPerSample: number;
  tags: Array<NativeMediaTag>;
  artworks: Array<NativeMediaArtwork>;
}

export function parseMediaFile(fd: number, fileSize: number): NativeParsedMedia;

export function readArtworkBytes(
  fd: number,
  fileSize: number,
  byteOffset: number,
  byteLength: number,
  payloadOffset: number,
  unsynchronized: boolean
): ArrayBuffer;

export function encodeArtworkWebP(
  bgraSource: ArrayBuffer,
  width: number,
  height: number,
  premultiplied: boolean,
  quality: number,
  method: number,
  alphaQuality: number
): ArrayBuffer;

export interface NativeArtworkWebPVariants {
  large: ArrayBuffer;
  small: ArrayBuffer;
  paletteBgra: ArrayBuffer;
}

export function encodeArtworkWebPVariants(
  bgraSource: ArrayBuffer,
  width: number,
  height: number,
  premultiplied: boolean,
  smallWidth: number,
  smallHeight: number,
  paletteWidth: number,
  paletteHeight: number,
  quality: number,
  method: number,
  alphaQuality: number
): NativeArtworkWebPVariants;

export function hashArtworkSourceXXH3_128(source: ArrayBuffer): string;
