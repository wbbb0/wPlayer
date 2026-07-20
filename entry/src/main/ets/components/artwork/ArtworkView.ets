import { image } from '@kit.ImageKit';
import { curves } from '@kit.ArkUI';
import { DemoMusicLibrary } from '../../demo/DemoMusicLibrary';

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
  @Prop animateShadowChanges: boolean = false;
  @Prop shadowSpringResponse: number = 0.36;
  @Prop shadowSpringDamping: number = 0.72;
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

  private demoArtworkPath(): string {
    const providedSource = this.sourceProvider(this.sourceRevision);
    if (typeof providedSource === 'string' && DemoMusicLibrary.isArtworkPath(providedSource)) {
      return providedSource;
    }
    if (typeof this.source === 'string' && DemoMusicLibrary.isArtworkPath(this.source)) {
      return this.source;
    }
    return DemoMusicLibrary.isArtworkPath(this.sourcePath) ? this.sourcePath : '';
  }

  @Builder
  private DemoArtworkContent() {
    if (this.demoArtworkPath() === 'demo-artwork://coast') {
      Stack({ alignContent: Alignment.Center }) {
        Stack() {}
          .width('38%')
          .aspectRatio(1)
          .borderRadius(999)
          .backgroundColor('#FFFFD166')
          .translate({ x: 72, y: -72 })
        Stack() {}
          .width('125%')
          .height('25%')
          .borderRadius(999)
          .backgroundColor('#66FFFFFF')
          .rotate({ angle: -8 })
          .translate({ x: -20, y: 76 })
        Stack() {}
          .width('115%')
          .height('18%')
          .borderRadius(999)
          .backgroundColor('#5533E1D0')
          .rotate({ angle: 6 })
          .translate({ x: 28, y: 112 })
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 145,
        colors: [['#FF0B7285', 0], ['#FF67C7C5', 0.58], ['#FFF6E7B0', 1]]
      })
    } else if (this.demoArtworkPath() === 'demo-artwork://night') {
      Stack({ alignContent: Alignment.Center }) {
        Stack() {}
          .width('48%')
          .aspectRatio(1)
          .borderRadius(999)
          .backgroundColor('#FFE8DCF8')
          .translate({ x: -65, y: -66 })
        Stack() {}
          .width('46%')
          .aspectRatio(1)
          .borderRadius(999)
          .backgroundColor('#FF40365F')
          .translate({ x: -44, y: -82 })
        Stack() {}
          .width('130%')
          .height('13%')
          .borderRadius(999)
          .backgroundColor('#55FF8A65')
          .rotate({ angle: -28 })
          .translate({ x: 24, y: 80 })
        Stack() {}
          .width('92%')
          .height('8%')
          .borderRadius(999)
          .backgroundColor('#559B8FD0')
          .rotate({ angle: -28 })
          .translate({ x: 42, y: 118 })
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 155,
        colors: [['#FF211C35', 0], ['#FF463B69', 0.62], ['#FF766B9A', 1]]
      })
    } else {
      Stack({ alignContent: Alignment.Bottom }) {
        Row({ space: 10 }) {
          Stack() {}
            .width('18%')
            .height('48%')
            .borderRadius({ topLeft: 12, topRight: 12 })
            .backgroundColor('#667BC0D8')
          Stack() {}
            .width('22%')
            .height('70%')
            .borderRadius({ topLeft: 12, topRight: 12 })
            .backgroundColor('#88D7E4EC')
          Stack() {}
            .width('16%')
            .height('40%')
            .borderRadius({ topLeft: 12, topRight: 12 })
            .backgroundColor('#66FFC978')
          Stack() {}
            .width('20%')
            .height('58%')
            .borderRadius({ topLeft: 12, topRight: 12 })
            .backgroundColor('#77A9C5D6')
        }
        .width('82%')
        .height('58%')
        .alignItems(VerticalAlign.Bottom)
        Stack() {}
          .width('38%')
          .aspectRatio(1)
          .borderRadius(999)
          .backgroundColor('#55FFF1CC')
          .translate({ x: 74, y: -92 })
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 140,
        colors: [['#FF26394D', 0], ['#FF55758F', 0.62], ['#FFB7A184', 1]]
      })
    }
  }

  @Builder
  private ImageContent() {
    if (this.demoArtworkPath().length > 0) {
      Stack() {
        this.DemoArtworkContent()
      }
      .width('100%')
      .height('100%')
      .borderRadius(this.effectiveCornerRadius())
      .clip(true)
    } else {
      Image(this.imageSource())
        .width('100%')
        .height('100%')
        .draggable(false)
        .objectFit(ImageFit.Cover)
        .interpolation(this.interpolation)
        .borderRadius(this.effectiveCornerRadius())
        .clip(true)
    }
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
      .animation(this.animateShadowChanges ? {
        curve: curves.springMotion(
          this.shadowSpringResponse,
          this.shadowSpringDamping
        )
      } : { duration: 0 })
    }
    .width(this.slotWidth)
    .aspectRatio(this.slotAspectRatio)
  }
}
