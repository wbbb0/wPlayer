import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { systemBarStyleController } from '../../appearance/SystemBarStyleController';
import { LayoutLength } from '../../components/layout/LayoutLength';
import { EmbeddedArtworkService } from '../../library/artwork/EmbeddedArtworkService';
import {
  ArtworkPictureType,
  EmbeddedArtwork,
  TrackDetail
} from '../../library/model/LibraryModels';
import { TrackArtworkViewerState } from '../../library/store/LibraryDetailState';

class ArtworkViewerMotionSpec {
  // TODO: Tune scale and offset resistance after broader phone and foldable gesture testing.
  static readonly MIN_SCALE: number = 1;
  static readonly MAX_SCALE: number = 6;
  static readonly MIN_ELASTIC_SCALE: number = 0.88;
  static readonly MAX_ELASTIC_SCALE: number = 6.4;
  static readonly ELASTIC_RESISTANCE: number = 0.18;
  static readonly OFFSET_ELASTIC_RESISTANCE: number = 0.22;
  static readonly MAX_OFFSET_OVERSHOOT: number = 72;
  static readonly SETTLE_SPRING_RESPONSE: number = 0.38;
  static readonly SETTLE_SPRING_DAMPING: number = 0.84;
}

@Component
export struct TrackArtworkViewer {
  @ObjectLink state: TrackArtworkViewerState;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  onClose: () => void = (): void => {};
  @State viewerScale: number = 1;
  @State baseScale: number = 1;
  @State translateX: number = 0;
  @State translateY: number = 0;
  @State baseTranslateX: number = 0;
  @State baseTranslateY: number = 0;
  @State actionBusy: boolean = false;
  @State chromeVisible: boolean = true;
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  private pinchStartTranslateX: number = 0;
  private pinchStartTranslateY: number = 0;
  private service?: EmbeddedArtworkService;

  aboutToAppear(): void {
    systemBarStyleController.setFullscreenOverlayStyle(true, true);
    this.service = new EmbeddedArtworkService(
      this.getUIContext().getHostContext() as common.UIAbilityContext
    );
    this.state.load(this.service).catch((error: Object): void => {
      console.warn(`Unable to load full embedded artwork: ${TrackArtworkViewer.messageOf(error)}`);
    });
  }

  aboutToDisappear(): void {
    systemBarStyleController.setFullscreenOverlayStyle(false, true);
    this.state.release();
  }

  private setChromeVisible(visible: boolean): void {
    if (this.chromeVisible === visible) {
      return;
    }
    this.chromeVisible = visible;
    systemBarStyleController.setFullscreenOverlayStyle(true, visible);
  }

  private toggleChrome(): void {
    this.setChromeVisible(!this.chromeVisible);
  }

  private syncChromeWithScale(scale: number): void {
    this.setChromeVisible(scale <= ArtworkViewerMotionSpec.MIN_SCALE);
  }

  private resetTransform(): void {
    this.viewerScale = ArtworkViewerMotionSpec.MIN_SCALE;
    this.baseScale = ArtworkViewerMotionSpec.MIN_SCALE;
    this.translateX = 0;
    this.translateY = 0;
    this.baseTranslateX = 0;
    this.baseTranslateY = 0;
    this.setChromeVisible(true);
  }

  private elasticScale(rawScale: number): number {
    if (rawScale < ArtworkViewerMotionSpec.MIN_SCALE) {
      return Math.max(
        ArtworkViewerMotionSpec.MIN_ELASTIC_SCALE,
        ArtworkViewerMotionSpec.MIN_SCALE -
          (ArtworkViewerMotionSpec.MIN_SCALE - rawScale) * ArtworkViewerMotionSpec.ELASTIC_RESISTANCE
      );
    }
    if (rawScale > ArtworkViewerMotionSpec.MAX_SCALE) {
      return Math.min(
        ArtworkViewerMotionSpec.MAX_ELASTIC_SCALE,
        ArtworkViewerMotionSpec.MAX_SCALE +
          (rawScale - ArtworkViewerMotionSpec.MAX_SCALE) * ArtworkViewerMotionSpec.ELASTIC_RESISTANCE
      );
    }
    return rawScale;
  }

  private baseImageSize(): SizeOptions {
    const artwork = this.current();
    if (artwork === undefined || artwork.width <= 0 || artwork.height <= 0 ||
      this.viewportWidth <= 0 || this.viewportHeight <= 0) {
      return { width: this.viewportWidth, height: this.viewportHeight };
    }
    const fitScale = Math.min(
      this.viewportWidth / artwork.width,
      this.viewportHeight / artwork.height
    );
    return {
      width: artwork.width * fitScale,
      height: artwork.height * fitScale
    };
  }

  private maxOffsetX(scale: number): number {
    const imageSize = this.baseImageSize();
    return Math.max(0, (Number(imageSize.width) * scale - this.viewportWidth) / 2);
  }

  private maxOffsetY(scale: number): number {
    const imageSize = this.baseImageSize();
    return Math.max(0, (Number(imageSize.height) * scale - this.viewportHeight) / 2);
  }

  private clampOffset(value: number, maximum: number): number {
    return Math.max(-maximum, Math.min(maximum, value));
  }

  private elasticOffset(value: number, maximum: number): number {
    const clamped = this.clampOffset(value, maximum);
    const overshoot = value - clamped;
    if (overshoot === 0) {
      return value;
    }
    const resistedOvershoot = Math.max(
      -ArtworkViewerMotionSpec.MAX_OFFSET_OVERSHOOT,
      Math.min(
        ArtworkViewerMotionSpec.MAX_OFFSET_OVERSHOOT,
        overshoot * ArtworkViewerMotionSpec.OFFSET_ELASTIC_RESISTANCE
      )
    );
    return clamped + resistedOvershoot;
  }

  private updateElasticTranslation(x: number, y: number): void {
    if (this.viewerScale <= ArtworkViewerMotionSpec.MIN_SCALE) {
      this.translateX = 0;
      this.translateY = 0;
      return;
    }
    this.translateX = this.elasticOffset(x, this.maxOffsetX(this.viewerScale));
    this.translateY = this.elasticOffset(y, this.maxOffsetY(this.viewerScale));
  }

  private settleTransform(): void {
    let targetScale = this.viewerScale;
    if (this.viewerScale < ArtworkViewerMotionSpec.MIN_SCALE) {
      targetScale = ArtworkViewerMotionSpec.MIN_SCALE;
    } else if (this.viewerScale > ArtworkViewerMotionSpec.MAX_SCALE) {
      targetScale = ArtworkViewerMotionSpec.MAX_SCALE;
    }
    const targetX = this.clampOffset(this.translateX, this.maxOffsetX(targetScale));
    const targetY = this.clampOffset(this.translateY, this.maxOffsetY(targetScale));
    if (targetScale === this.viewerScale &&
      targetX === this.translateX &&
      targetY === this.translateY) {
      this.baseScale = targetScale;
      this.baseTranslateX = targetX;
      this.baseTranslateY = targetY;
      this.syncChromeWithScale(targetScale);
      return;
    }
    this.getUIContext().animateTo({
      curve: curves.springMotion(
        ArtworkViewerMotionSpec.SETTLE_SPRING_RESPONSE,
        ArtworkViewerMotionSpec.SETTLE_SPRING_DAMPING
      )
    }, (): void => {
      this.viewerScale = targetScale;
      this.baseScale = targetScale;
      this.translateX = targetX;
      this.translateY = targetY;
      this.baseTranslateX = targetX;
      this.baseTranslateY = targetY;
      this.syncChromeWithScale(targetScale);
    });
  }

  private current(): EmbeddedArtwork | undefined {
    return this.state.currentArtwork();
  }

  private message(value: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: value });
    } catch (error) {
      console.warn(`Unable to show artwork action result: ${TrackArtworkViewer.messageOf(error)}`);
    }
  }

  private async move(offset: number): Promise<void> {
    if (this.service === undefined || this.state.loading) {
      return;
    }
    this.resetTransform();
    await this.state.move(this.service, offset);
  }

  private async save(): Promise<void> {
    const artwork = this.current();
    if (this.service === undefined || artwork === undefined || this.actionBusy) {
      return;
    }
    this.actionBusy = true;
    try {
      await this.service.save(this.state.detail, artwork);
      this.message('封面已保存');
    } catch (error) {
      this.message(TrackArtworkViewer.messageOf(error));
    } finally {
      this.actionBusy = false;
    }
  }

  private async share(): Promise<void> {
    const artwork = this.current();
    if (this.service === undefined || artwork === undefined || this.actionBusy) {
      return;
    }
    this.actionBusy = true;
    try {
      await this.service.share(this.state.detail, artwork);
    } catch (error) {
      this.message(TrackArtworkViewer.messageOf(error));
    } finally {
      this.actionBusy = false;
    }
  }

  private async copy(): Promise<void> {
    if (this.service === undefined || this.state.pixelMap === undefined || this.actionBusy) {
      return;
    }
    this.actionBusy = true;
    try {
      await this.service.copy(this.state.pixelMap);
      this.message('封面已复制到剪贴板');
    } catch (error) {
      this.message(TrackArtworkViewer.messageOf(error));
    } finally {
      this.actionBusy = false;
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private pictureTypeLabel(type: ArtworkPictureType): string {
    const labels: Array<string> = [
      '其他图片', '文件图标', '其他文件图标', '正面封面', '背面封面', '内页',
      '介质', '主艺人', '艺人', '指挥', '乐队', '作曲者', '作词者',
      '录音地点', '录音期间', '演出期间', '视频截图', '亮色鱼',
      '插图', '乐队标志', '出版方标志'
    ];
    return labels[type] ?? `图片类型 ${type}`;
  }

  private viewerTitle(): string {
    const artwork = this.current();
    return artwork === undefined ? '图片' : this.pictureTypeLabel(artwork.pictureType);
  }

  @Builder
  private CloseButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor(['#FFFFFFFF'])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor('#66000000')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .accessibilityText('关闭图片查看')
    .onClick((): void => this.onClose())
  }

  @Builder
  private ArtworkActionMenu() {
    Menu() {
      MenuItem({ content: '保存图片' })
        .enabled(!this.actionBusy && this.current() !== undefined)
        .onClick((): void => {
          this.save();
        })
      MenuItem({ content: '分享图片' })
        .enabled(!this.actionBusy && this.current() !== undefined)
        .onClick((): void => {
          this.share();
        })
      MenuItem({ content: '复制图片' })
        .enabled(!this.actionBusy && this.current() !== undefined)
        .onClick((): void => {
          this.copy();
        })
    }
    .width(200)
  }

  @Builder
  private MoreButton() {
    Stack() {
      Image($r('app.media.control_more'))
        .width(20)
        .height(20)
        .fillColor('#FFFFFFFF')
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor('#66000000')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText('更多操作')
    .bindMenu(this.ArtworkActionMenu(), { placement: Placement.BottomRight })
  }

  @Builder
  private TopBar() {
    Row() {
      this.CloseButton()
      Text(this.viewerTitle())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .margin({ left: 12, right: 12 })
      this.MoreButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ViewerImage() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.state.pixelMap !== undefined) {
        Image(this.state.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
          .draggable(false)
          .scale({ x: this.viewerScale, y: this.viewerScale })
          .translate({ x: this.translateX, y: this.translateY })
      } else if (this.state.loading) {
        LoadingProgress().width(44).height(44)
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(46)
            .fontColor(['#99FFFFFF'])
          Text(this.state.error.length > 0 ? this.state.error : '无法显示图片')
            .fontSize(14)
            .fontColor('#B3FFFFFF')
        }
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.viewportWidth = LayoutLength.toNumber(newValue.width, this.viewportWidth);
      this.viewportHeight = LayoutLength.toNumber(newValue.height, this.viewportHeight);
    })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        PinchGesture({ fingers: 2, distance: 1 })
          .onActionStart((): void => {
            this.baseScale = this.viewerScale;
            this.pinchStartTranslateX = this.translateX;
            this.pinchStartTranslateY = this.translateY;
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.viewerScale = this.elasticScale(this.baseScale * event.scale);
            this.syncChromeWithScale(this.viewerScale);
            this.updateElasticTranslation(
              this.pinchStartTranslateX + event.offsetX,
              this.pinchStartTranslateY + event.offsetY
            );
          })
          .onActionEnd((): void => this.settleTransform())
          .onActionCancel((): void => this.settleTransform()),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 2 })
          .onActionStart((): void => {
            this.baseTranslateX = this.translateX;
            this.baseTranslateY = this.translateY;
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.viewerScale > ArtworkViewerMotionSpec.MIN_SCALE) {
              this.updateElasticTranslation(
                this.baseTranslateX + event.offsetX,
                this.baseTranslateY + event.offsetY
              );
            }
          })
          .onActionEnd((event: GestureEvent): void => {
            if (this.viewerScale === ArtworkViewerMotionSpec.MIN_SCALE && Math.abs(event.offsetX) >= 64) {
              this.move(event.offsetX > 0 ? -1 : 1);
            } else {
              this.settleTransform();
            }
          })
          .onActionCancel((): void => this.settleTransform()),
        GestureGroup(
          GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction((): void => {
              if (this.viewerScale > ArtworkViewerMotionSpec.MIN_SCALE) {
                this.resetTransform();
              } else {
                this.viewerScale = 2.5;
                this.baseScale = 2.5;
                this.setChromeVisible(false);
              }
            }),
          TapGesture({ count: 1 })
            .onAction((): void => this.toggleChrome())
        )
      )
    )
  }

  @Builder
  private NavigationButton(symbol: Resource, offset: number, enabled: boolean) {
    Button() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor(['#FFFFFFFF'])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor(Color.Transparent)
    .enabled(enabled && !this.state.loading)
    .onClick((): void => {
      this.move(offset);
    })
  }

  @Builder
  private ViewerControls() {
    Row({ space: 16 }) {
      this.NavigationButton(
        $r('sys.symbol.chevron_left'),
        -1,
        this.state.currentIndex > 0
      )
      Column({ space: 2 }) {
        Text(`${this.state.currentIndex + 1} / ${this.state.detail.artworks.length}`)
          .fontSize(13)
          .fontColor('#FFFFFFFF')
        if (this.current() !== undefined) {
          Text(`${this.current()!.width} × ${this.current()!.height}`)
            .fontSize(11)
            .fontColor('#B3FFFFFF')
        }
      }
      .width(100)
      .alignItems(HorizontalAlign.Center)
      this.NavigationButton(
        $r('sys.symbol.chevron_right'),
        1,
        this.state.currentIndex < this.state.detail.artworks.length - 1
      )
    }
    .width(244)
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8, left: 12, right: 12 })
    .borderRadius(24)
    .backgroundColor('#66000000')
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
  }

  build() {
    Stack() {
      this.ViewerImage()

      Column() {
        Stack() {
          this.TopBar()
        }
        .width('100%')
        .opacity(this.chromeVisible ? 1 : 0)
        .hitTestBehavior(this.chromeVisible ? HitTestMode.Default : HitTestMode.None)

        Blank()

        Stack() {
          this.ViewerControls()
        }
        .opacity(this.chromeVisible ? 1 : 0)
        .hitTestBehavior(this.chromeVisible ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: 12,
        right: 12,
        top: Math.max(12, this.topInset + 8),
        bottom: Math.max(12, this.bottomInset + 8)
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF000000')
  }
}
