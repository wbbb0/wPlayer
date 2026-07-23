import { common } from '@kit.AbilityKit';
import { EmbeddedArtworkService } from '../../library/artwork/EmbeddedArtworkService';
import {
  EmbeddedArtwork,
  TrackDetail
} from '../../library/model/LibraryModels';
import { TrackArtworkViewerState } from '../../library/store/LibraryDetailState';

@Component
export struct TrackArtworkViewerPage {
  @ObjectLink state: TrackArtworkViewerState;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @State viewerScale: number = 1;
  @State baseScale: number = 1;
  @State translateX: number = 0;
  @State translateY: number = 0;
  @State baseTranslateX: number = 0;
  @State baseTranslateY: number = 0;
  @State actionBusy: boolean = false;
  private service?: EmbeddedArtworkService;

  aboutToAppear(): void {
    this.service = new EmbeddedArtworkService(
      this.getUIContext().getHostContext() as common.UIAbilityContext
    );
    this.state.load(this.service).catch((error: Object): void => {
      console.warn(`Unable to load full embedded artwork: ${TrackArtworkViewerPage.messageOf(error)}`);
    });
  }

  aboutToDisappear(): void {
    this.state.release();
  }

  private resetTransform(): void {
    this.viewerScale = 1;
    this.baseScale = 1;
    this.translateX = 0;
    this.translateY = 0;
    this.baseTranslateX = 0;
    this.baseTranslateY = 0;
  }

  private current(): EmbeddedArtwork | undefined {
    return this.state.currentArtwork();
  }

  private message(value: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: value });
    } catch (error) {
      console.warn(`Unable to show artwork action result: ${TrackArtworkViewerPage.messageOf(error)}`);
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
      this.message(`无法保存封面：${TrackArtworkViewerPage.messageOf(error)}`);
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
      this.message(`无法分享封面：${TrackArtworkViewerPage.messageOf(error)}`);
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
      this.message(`无法复制封面：${TrackArtworkViewerPage.messageOf(error)}`);
    } finally {
      this.actionBusy = false;
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  @Builder
  private ActionButton(symbol: Resource, label: string, action: () => void) {
    Button() {
      Column({ space: 4 }) {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([$r('app.color.text_primary')])
        Text(label)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width(72)
    .height(58)
    .borderRadius(18)
    .backgroundColor($r('app.color.glass_surface_strong'))
    .enabled(!this.actionBusy && this.current() !== undefined)
    .onClick(action)
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
          .gesture(
            GestureGroup(
              GestureMode.Parallel,
              PinchGesture()
                .onActionStart((): void => {
                  this.baseScale = this.viewerScale;
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.viewerScale = Math.max(1, Math.min(6, this.baseScale * event.scale));
                  if (this.viewerScale <= 1) {
                    this.translateX = 0;
                    this.translateY = 0;
                  }
                }),
              PanGesture({ direction: PanDirection.All, distance: 2 })
                .onActionStart((): void => {
                  this.baseTranslateX = this.translateX;
                  this.baseTranslateY = this.translateY;
                })
                .onActionUpdate((event: GestureEvent): void => {
                  if (this.viewerScale > 1) {
                    this.translateX = this.baseTranslateX + event.offsetX;
                    this.translateY = this.baseTranslateY + event.offsetY;
                  }
                })
                .onActionEnd((event: GestureEvent): void => {
                  if (this.viewerScale === 1 && Math.abs(event.offsetX) >= 64) {
                    this.move(event.offsetX > 0 ? -1 : 1);
                  }
                }),
              TapGesture({ count: 2 })
                .onAction((): void => {
                  if (this.viewerScale > 1) {
                    this.resetTransform();
                  } else {
                    this.viewerScale = 2.5;
                    this.baseScale = 2.5;
                  }
                })
            )
          )
      } else if (this.state.loading) {
        LoadingProgress().width(44).height(44)
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(46)
            .fontColor([$r('app.color.text_tertiary')])
          Text(this.state.error.length > 0 ? this.state.error : '无法显示图片')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
  }

  @Builder
  private NavigationButton(symbol: Resource, offset: number, enabled: boolean) {
    Button() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor($r('app.color.glass_surface_strong'))
    .enabled(enabled && !this.state.loading)
    .onClick((): void => {
      this.move(offset);
    })
  }

  build() {
    Column({ space: 8 }) {
      this.ViewerImage()
      Row({ space: 16 }) {
        this.NavigationButton(
          $r('sys.symbol.chevron_left'),
          -1,
          this.state.currentIndex > 0
        )
        Column({ space: 2 }) {
          Text(`${this.state.currentIndex + 1} / ${this.state.detail.artworks.length}`)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          if (this.current() !== undefined) {
            Text(`${this.current()!.width} × ${this.current()!.height}`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
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
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Row({ space: 12 }) {
        this.ActionButton($r('sys.symbol.arrow_down_to_line'), '保存', (): void => {
          this.save();
        })
        this.ActionButton($r('sys.symbol.share'), '分享', (): void => {
          this.share();
        })
        this.ActionButton($r('sys.symbol.rectangle_on_rectangle'), '复制', (): void => {
          this.copy();
        })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 16,
      right: 16,
      top: 4,
      bottom: Math.max(12, this.bottomInset + 8)
    })
    .backgroundColor('#FF000000')
  }
}
