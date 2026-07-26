import { image } from '@kit.ImageKit';

@Component
export struct DynamicBackgroundTextureLayer {
  sourceProvider: (sourceRevision: number) => image.PixelMap | ResourceStr | undefined =
    (_sourceRevision: number): image.PixelMap | ResourceStr | undefined => undefined;
  @Prop sourceRevision: number = 0;
  @Prop textureScale: number = 1;
  @Prop mirrorX: boolean = false;

  private imageSource(): image.PixelMap | ResourceStr {
    return this.sourceProvider(this.sourceRevision) ?? $r('app.media.default_album_cover');
  }

  build() {
    Image(this.imageSource())
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
      .interpolation(ImageInterpolation.High)
      .draggable(false)
      .scale({
        x: this.mirrorX ? -this.textureScale : this.textureScale,
        y: this.textureScale
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
