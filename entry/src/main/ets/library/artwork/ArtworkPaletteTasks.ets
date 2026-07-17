import { taskpool } from '@kit.ArkTS';
import { ArtworkPalette, ArtworkPaletteExtractor } from './ArtworkPaletteExtractor';

@Concurrent
function extractArtworkPaletteTask(pixelBuffer: ArrayBuffer): ArtworkPalette {
  return ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixelBuffer));
}

export function extractArtworkPaletteAsync(pixelBuffer: ArrayBuffer): Promise<ArtworkPalette> {
  try {
    return taskpool.execute(extractArtworkPaletteTask, pixelBuffer) as Promise<ArtworkPalette>;
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    return Promise.reject(new Error(`Unable to submit artwork palette task: ${message}`));
  }
}
