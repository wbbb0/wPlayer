import { LibraryMaintenanceStatus } from '../../library/data/MusicRepositoryTypes';

@Component
export struct LibraryMaintenanceSheet {
  @Prop status: LibraryMaintenanceStatus = { items: [], total: 0 };
  onStart: () => void = (): void => {};
  onLater: () => void = (): void => {};

  build() {
    Column({ space: 18 }) {
      SymbolGlyph($r('sys.symbol.externaldrive_fill'))
        .fontSize(34)
        .fontColor([$r('app.color.text_primary')])

      Column({ space: 8 }) {
        Text('音乐库需要一次整理')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)

        Text('新版优化了封面色彩等音乐库信息。运行一次“检查音乐文件”，即可让已有内容使用新效果。')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .textAlign(TextAlign.Center)

        if (this.status.total > 0) {
          Text(`发现 ${this.status.total} 项内容可以更新`)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: 10 }) {
        Button('前往检查')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .onClick((): void => this.onStart())

        Button('稍后再说')
          .type(ButtonType.Normal)
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.onLater())
      }
      .width('100%')

      Text('暂不处理也不会影响播放；播放到相关音乐时，应用会在后台自动更新。原始音频文件不会被修改。')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .lineHeight(18)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26, bottom: 18 })
  }
}
