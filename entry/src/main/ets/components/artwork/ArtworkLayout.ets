export interface ArtworkSize {
  width: number;
  height: number;
}

export class ArtworkLayout {
  static containedSize(sourceWidth: number, sourceHeight: number,
    slotWidth: number, slotHeight: number): ArtworkSize {
    if (sourceWidth <= 0 || sourceHeight <= 0 || slotWidth <= 0 || slotHeight <= 0) {
      return { width: Math.max(0, slotWidth), height: Math.max(0, slotHeight) };
    }
    const scale = Math.min(slotWidth / sourceWidth, slotHeight / sourceHeight);
    return {
      width: sourceWidth * scale,
      height: sourceHeight * scale
    };
  }

  static containedSizeWithSquareFallback(sourceWidth: number, sourceHeight: number,
    slotWidth: number, slotHeight: number): ArtworkSize {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      const side = Math.max(0, Math.min(slotWidth, slotHeight));
      return { width: side, height: side };
    }
    return ArtworkLayout.containedSize(sourceWidth, sourceHeight, slotWidth, slotHeight);
  }
}
