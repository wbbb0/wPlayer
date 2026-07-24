import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import {
  PageScrollBehavior,
  PageScrollContentBehavior
} from '../../components/layout/PageScrollBehavior';
import {
  ArtworkPictureType,
  EmbeddedArtwork,
  TrackDetail
} from '../../library/model/LibraryModels';
import {
  DetailAction,
  DetailRenderer,
  DetailRowModel,
  DetailSectionModel,
  TrackDetailPresenter
} from '../../library/presentation/TrackDetailPresentation';
import {
  TrackArtworkPreviewState,
  TrackDetailState
} from '../../library/store/LibraryDetailState';
import { LibraryStore } from '../../library/store/LibraryStore';
import { EmbeddedArtworkService } from '../../library/artwork/EmbeddedArtworkService';

@Component
export struct TrackDetailPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink state: TrackDetailState;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop themeBackground: string = '#FF000000';
  @Prop reserveFloatingControls: boolean = true;
  scroller: Scroller = new Scroller();
  onOpenArtwork: (detail: TrackDetail, index: number) => void =
    (_detail: TrackDetail, _index: number): void => {};
  private service?: EmbeddedArtworkService;
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  aboutToAppear(): void {
    this.service = new EmbeddedArtworkService(
      this.getUIContext().getHostContext() as common.UIAbilityContext
    );
    this.state.load(this.store);
  }

  aboutToDisappear(): void {
    this.state.releasePreviews();
  }

  private pictureTypeLabel(type: ArtworkPictureType): string {
    const labels: Array<string> = [
      '其他', '文件图标', '其他文件图标', '正面封面', '背面封面', '内页',
      '介质', '主艺人', '艺人', '指挥', '乐队', '作曲者', '作词者',
      '录音地点', '录音期间', '演出期间', '视频截图', '亮色鱼',
      '插图', '乐队标志', '出版方标志'
    ];
    return labels[type] ?? `类型 ${type}`;
  }

  private async copyValue(value: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      await pasteboard.getSystemPasteboard().setData(data);
      this.message('已复制原始值');
    } catch (_) {
      this.message('复制失败');
    }
  }

  private message(value: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: value });
    } catch (error) {
      console.warn(`Unable to show detail action result: ${String(error)}`);
    }
  }

  private contentEndInset(): number {
    return this.reserveFloatingControls ? PageLayoutSpec.contentEnd(this.bottomInset) : 16;
  }

  @Builder
  private SectionTitle(value: string) {
    Text(value)
      .fontSize(19)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ top: 8, bottom: 2 })
  }

  @Builder
  private DefaultRow(row: DetailRowModel) {
    Row({ space: 18 }) {
      Text(row.label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(112)
      Text(row.displayValue)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  private MonospaceRow(row: DetailRowModel) {
    Row({ space: 18 }) {
      Text(row.label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(112)
      Text(row.displayValue)
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  private UriRow(row: DetailRowModel) {
    Row({ space: 10 }) {
      Text(row.label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(112)
      Text(row.displayValue)
        .fontSize(13)
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
      if (row.actions.indexOf(DetailAction.COPY_EXACT) >= 0) {
        Button() {
          SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(36)
        .height(36)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .backgroundColor(Color.Transparent)
        .accessibilityText('复制原始 URI')
        .onClick((): void => {
          this.copyValue(row.copyValue);
        })
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  private LyricsRow(row: DetailRowModel) {
    Row({ space: 18 }) {
      Text(row.label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(112)
      Text(row.displayValue)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .accessibilityText(`${row.label}，${row.displayValue}`)
  }

  @Builder
  private DetailRow(row: DetailRowModel) {
    if (row.renderer === DetailRenderer.URI) {
      this.UriRow(row)
    } else if (row.renderer === DetailRenderer.LYRICS) {
      this.LyricsRow(row)
    } else if (row.renderer === DetailRenderer.MONOSPACE) {
      this.MonospaceRow(row)
    } else {
      this.DefaultRow(row)
    }
  }

  @Builder
  private DetailSection(section: DetailSectionModel) {
    this.SectionTitle(section.title)
    Column() {
      ForEach(section.rows, (row: DetailRowModel) => {
        this.DetailRow(row)
      }, (row: DetailRowModel) => row.id)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  @Builder
  private ArtworkCard(
    detail: TrackDetail,
    preview: TrackArtworkPreviewState,
    index: number
  ) {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.state.previewRevision >= 0 && preview.pixelMap !== undefined) {
          Image(preview.pixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)
            .draggable(true)
            .onDragStart((event: DragEvent): DragItemInfo => {
              if (this.service !== undefined) {
                event.setDataLoadParams(EmbeddedArtworkService.dragDataLoadParams(
                  this.service,
                  detail,
                  preview.artwork
                ));
              }
              return {};
            })
        } else if (this.state.previewRevision >= 0 && preview.loading) {
          LoadingProgress().width(38).height(38)
        } else {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(42)
            .fontColor([$r('app.color.text_tertiary')])
        }
      }
      .width(190)
      .height(190)
      .borderRadius(18)
      .clip(true)
      .backgroundColor($r('app.color.glass_surface_strong'))
      .onAppear((): void => {
        if (this.service !== undefined) {
          preview.load(this.service, detail);
        }
      })
      .onClick((): void => this.onOpenArtwork(detail, index))

      Column({ space: 3 }) {
        Text(this.pictureTypeLabel(preview.artwork.pictureType))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text(`${preview.artwork.width} × ${preview.artwork.height} · ` +
          `${preview.artwork.mimeType.length > 0 ? preview.artwork.mimeType : '未知格式'}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
        if (preview.artwork.description.length > 0) {
          Text(preview.artwork.description)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
      }
      .width(190)
      .alignItems(HorizontalAlign.Start)
    }
    .width(190)
    .accessibilityText(`封面 ${index + 1}，${this.pictureTypeLabel(preview.artwork.pictureType)}`)
  }

  @Builder
  private Artworks(detail: TrackDetail) {
    this.SectionTitle(`内嵌封面（${detail.artworks.length}）`)
    if (detail.artworks.length > 0) {
      List({ space: 14 }) {
        ForEach(this.state.previews, (preview: TrackArtworkPreviewState, index: number) => {
          ListItem() {
            this.ArtworkCard(detail, preview, index)
          }
        }, (preview: TrackArtworkPreviewState) => `${preview.artwork.id}`)
      }
      .width('100%')
      .height(252)
      .listDirection(Axis.Horizontal)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    } else {
      Text('这首歌曲没有可导出的内嵌封面。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 12, bottom: 12 })
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        if (this.state.detail !== undefined) {
          this.Artworks(this.state.detail)
          ForEach(
            TrackDetailPresenter.present(this.state.detail).sections,
            (section: DetailSectionModel) => {
              this.DetailSection(section)
            },
            (section: DetailSectionModel) => section.id
          )
        } else if (this.state.loading) {
          LoadingProgress().width(40).height(40).margin({ top: 72 })
        } else {
          Text(this.state.error.length > 0 ? this.state.error : '正在载入文件信息…')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 72 })
        }
      }
      .padding({
        left: PageLayoutSpec.HORIZONTAL_INSET,
        right: PageLayoutSpec.HORIZONTAL_INSET,
        bottom: 16
      })
      .attributeModifier(this.contentBehavior)
    }
    .width('100%')
    .height('100%')
    .contentStartOffset(PageLayoutSpec.secondaryContentStart(this.topInset))
    .contentEndOffset(this.contentEndInset())
    .attributeModifier(this.scrollBehavior)
    .backgroundColor(this.themeBackground)
  }
}
