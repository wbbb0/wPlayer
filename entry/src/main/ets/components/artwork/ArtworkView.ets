import { image } from '@kit.ImageKit';

export enum ArtworkFitMode {
  COVER,
  CONTAIN
}

@Component
export struct ArtworkView {
  // Keep native PixelMap references unproxied so Image receives the original resource.
  source: image.PixelMap | ResourceStr | undefined = undefined;
  sourceProvider: (sourceRevision: number) => image.PixelMap | ResourceStr | undefined =
    (_sourceRevision: number): image.PixelMap | ResourceStr | undefined => undefined;
  @Prop sourceRevision: number = 0;
  @Prop sourcePixelMap: image.PixelMap | undefined = undefined;
  @Prop sourcePath: string = '';
  @Prop sourceWidth: number = 0;
  @Prop sourceHeight: number = 0;
  @Prop slotWidth: Length = '100%';
  @Prop slotAspectRatio: number = 1;
  @Prop fitMode: ArtworkFitMode = ArtworkFitMode.COVER;
  @Prop cornerRadius: number = 0;
  @Prop circularProgress: number = 0;
  @Prop resolvedCornerRadius: number = -1;
  @Prop shadowEnabled: boolean = false;
  @Prop shadowRadius: number = 14;
  @Prop shadowOffsetY: number = 5;
  @Prop interpolation: ImageInterpolation = ImageInterpolation.Medium;

  private containedImageWidth(): Length {
    if (this.fitMode !== ArtworkFitMode.CONTAIN || this.sourceWidth <= 0 || this.sourceHeight <= 0 ||
      this.slotAspectRatio <= 0) {
      return '100%';
    }
    const sourceRatio = this.sourceWidth / this.sourceHeight;
    return sourceRatio >= this.slotAspectRatio ? '100%' : `${sourceRatio / this.slotAspectRatio * 100}%`;
  }

  private containedImageHeight(): Length {
    if (this.fitMode !== ArtworkFitMode.CONTAIN || this.sourceWidth <= 0 || this.sourceHeight <= 0 ||
      this.slotAspectRatio <= 0) {
      return '100%';
    }
    const sourceRatio = this.sourceWidth / this.sourceHeight;
    return sourceRatio >= this.slotAspectRatio ? `${this.slotAspectRatio / sourceRatio * 100}%` : '100%';
  }

  private lengthValue(value: Length, fallback: number): number {
    if (typeof value === 'number') {
      return value;
    }
    const text = `${value}`;
    const parsed = Number.parseFloat(text);
    if (Number.isFinite(parsed) && text.endsWith('%')) {
      return fallback * parsed / 100;
    }
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private normalizedCircularProgress(): number {
    return Math.max(0, Math.min(1, this.circularProgress));
  }

  private squareSide(): number {
    return this.lengthValue(this.slotWidth, 0);
  }

  private imageWidth(): Length {
    const contained = this.containedImageWidth();
    const side = this.squareSide();
    const progress = this.normalizedCircularProgress();
    if (progress <= 0 || side <= 0) {
      return contained;
    }
    return this.lengthValue(contained, side) * (1 - progress) + side * progress;
  }

  private imageHeight(): Length {
    const contained = this.containedImageHeight();
    const side = this.squareSide();
    const progress = this.normalizedCircularProgress();
    if (progress <= 0 || side <= 0) {
      return contained;
    }
    return this.lengthValue(contained, side) * (1 - progress) + side * progress;
  }

  private effectiveCornerRadius(): number {
    if (this.resolvedCornerRadius >= 0) {
      return this.resolvedCornerRadius;
    }
    const progress = this.normalizedCircularProgress();
    const circularRadius = this.squareSide() / 2;
    if (progress <= 0 || circularRadius <= 0) {
      return this.cornerRadius;
    }
    return this.cornerRadius * (1 - progress) + circularRadius * progress;
  }

  private imageSource(): image.PixelMap | ResourceStr {
    const providedSource = this.sourceProvider(this.sourceRevision);
    if (providedSource !== undefined) {
      return providedSource;
    }
    if (this.source !== undefined) {
      return this.source;
    }
    if (this.sourcePath.length > 0) {
      return this.sourcePath;
    }
    if (this.sourcePixelMap !== undefined) {
      return this.sourcePixelMap;
    }
    return $r('app.media.default_album_cover');
  }

  @Builder
  private ImageContent() {
    Image(this.imageSource())
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
      .interpolation(this.interpolation)
      .borderRadius(this.effectiveCornerRadius())
      .clip(true)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {
        this.ImageContent()
      }
      .width(this.imageWidth())
      .height(this.imageHeight())
      .borderRadius(this.effectiveCornerRadius())
      .shadow({
        radius: this.shadowEnabled ? this.shadowRadius : 0,
        color: $r('app.color.artwork_shadow'),
        offsetY: this.shadowEnabled ? this.shadowOffsetY : 0
      })
    }
    .width(this.slotWidth)
    .aspectRatio(this.slotAspectRatio)
  }
}
