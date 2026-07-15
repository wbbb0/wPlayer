import { taskpool } from '@kit.ArkTS';
import { ArtworkPalette, ArtworkPaletteExtractor } from './ArtworkPaletteExtractor';

@Concurrent
function extractArtworkPaletteTask(pixelBuffer: ArrayBuffer): ArtworkPalette {
  return ArtworkPaletteExtractor.fromPixels(new Uint8Array(pixelBuffer));
}

export function extractArtworkPaletteAsync(pixelBuffer: ArrayBuffer): Promise<ArtworkPalette> {
  return taskpool.execute(extractArtworkPaletteTask, pixelBuffer) as Promise<ArtworkPalette>;
}
