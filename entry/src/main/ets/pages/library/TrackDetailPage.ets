import { common } from '@kit.AbilityKit';
import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import {
  PageScrollBehavior,
  PageScrollContentBehavior
} from '../../components/layout/PageScrollBehavior';
import {
  ArtworkPictureType,
  AvailabilityState,
  CreditRole,
  EmbeddedArtwork,
  TrackCreditDetail,
  TrackDetail,
  TrackRawTag
} from '../../library/model/LibraryModels';
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

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) {
      return `${hours}:${minutes < 10 ? '0' : ''}${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
    }
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private fileSizeLabel(bytes: number): string {
    if (bytes <= 0) {
      return '未知';
    }
    const units: Array<string> = ['B', 'KB', 'MB', 'GB'];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return `${value >= 10 || unit === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unit]}`;
  }

  private dateTimeLabel(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '未知';
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

  private creditRoleLabel(role: CreditRole): string {
    const labels: Array<string> = ['艺人', '专辑艺人', '作曲', '作词', '指挥', '演奏/表演'];
    return labels[role] ?? `角色 ${role}`;
  }

  private valueOrUnknown(value: string): string {
    return value.trim().length > 0 ? value : '未知';
  }

  private numberPair(value: number, total: number, raw: string): string {
    if (raw.trim().length > 0) {
      return raw;
    }
    if (value <= 0) {
      return '未知';
    }
    return total > 0 ? `${value}/${total}` : `${value}`;
  }

  private channelLabel(count: number): string {
    if (count === 1) {
      return '1（单声道）';
    }
    if (count === 2) {
      return '2（立体声）';
    }
    return count > 0 ? `${count}` : '未知';
  }

  private availabilityLabel(value: AvailabilityState): string {
    if (value === AvailabilityState.AVAILABLE) {
      return '可用';
    }
    if (value === AvailabilityState.AUTHORIZATION_REVOKED) {
      return '文件授权已撤销';
    }
    if (value === AvailabilityState.CORRUPTED) {
      return '文件损坏';
    }
    return '文件不可用';
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
  private InformationRow(label: string, value: string) {
    Row({ space: 18 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(112)
      Text(value)
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
  private Card() {
    Column() {
      ForEach(this.state.detail === undefined ? [] : [this.state.detail], (detail: TrackDetail) => {
        this.InformationRow('标题', this.valueOrUnknown(detail.title))
        this.InformationRow('排序标题', this.valueOrUnknown(detail.sortTitle))
        this.InformationRow('艺人', this.valueOrUnknown(detail.artistDisplay))
        this.InformationRow('专辑', this.valueOrUnknown(detail.albumDisplay))
        this.InformationRow('专辑艺人', this.valueOrUnknown(detail.albumArtistDisplay))
        this.InformationRow('作曲', this.valueOrUnknown(detail.composerDisplay))
        this.InformationRow(
          '曲目',
          this.numberPair(detail.trackNumber, detail.totalTrackCount, detail.trackNumberRaw)
        )
        this.InformationRow(
          '碟片',
          this.numberPair(detail.discNumber, detail.totalDiscCount, detail.discNumberRaw)
        )
        this.InformationRow('发行日期', this.valueOrUnknown(detail.releaseDateRaw))
        this.InformationRow('原始发行日期', this.valueOrUnknown(detail.originalReleaseDateRaw))
        this.InformationRow('流派', detail.genres.length > 0 ? detail.genres.join('、') : '未知')
      })
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

  @Builder
  private Credits(detail: TrackDetail) {
    this.SectionTitle('人员与角色')
    Column() {
      if (detail.credits.length === 0) {
        this.InformationRow('人员', '没有可用信息')
      } else {
        ForEach(detail.credits, (credit: TrackCreditDetail) => {
          this.InformationRow(this.creditRoleLabel(credit.role), credit.name)
        }, (credit: TrackCreditDetail) => `${credit.role}:${credit.ordinal}:${credit.name}`)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  @Builder
  private FileAndAudio(detail: TrackDetail) {
    this.SectionTitle('文件与音频')
    Column() {
      this.InformationRow('文件名', detail.displayName)
      this.InformationRow('文件大小', this.fileSizeLabel(detail.fileSize))
      this.InformationRow('修改时间', this.dateTimeLabel(detail.modifiedAt))
      this.InformationRow('容器格式', detail.format.toUpperCase())
      this.InformationRow('MIME', this.valueOrUnknown(detail.mimeType))
      this.InformationRow('时长', this.durationLabel(detail.durationMs))
      this.InformationRow('采样率', detail.sampleRate > 0 ? `${detail.sampleRate} Hz` : '未知')
      this.InformationRow('声道', this.channelLabel(detail.channelCount))
      this.InformationRow('位深', detail.bitsPerSample > 0 ? `${detail.bitsPerSample} bit` : '未知')
      this.InformationRow('码率', detail.bitRate > 0 ? `${Math.round(detail.bitRate / 1000)} kbps` : '未知')
      this.InformationRow('文件状态', this.availabilityLabel(detail.availability))
      this.InformationRow('持久授权', detail.authorizationPersisted ? '已保留' : '未保留')
      this.InformationRow('URI', detail.uri.length > 0 ? detail.uri : '演示数据')
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  @Builder
  private RawTags(detail: TrackDetail) {
    this.SectionTitle(`原始标签（${detail.rawTags.length}）`)
    Column() {
      if (detail.rawTags.length === 0) {
        this.InformationRow('标签', '没有可用的原始标签')
      } else {
        ForEach(detail.rawTags, (tag: TrackRawTag) => {
          this.InformationRow(tag.key, tag.value)
        }, (tag: TrackRawTag) => `${tag.key}:${tag.ordinal}`)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        if (this.state.detail !== undefined) {
          this.Artworks(this.state.detail)
          this.SectionTitle('歌曲信息')
          this.Card()
          this.Credits(this.state.detail)
          this.FileAndAudio(this.state.detail)
          this.RawTags(this.state.detail)
        } else if (this.state.loading) {
          LoadingProgress().width(40).height(40).margin({ top: 72 })
        } else {
          Text(this.state.error.length > 0 ? this.state.error : '正在载入歌曲信息…')
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
