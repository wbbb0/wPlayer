import {
  LibraryMaintenanceAction,
  LibraryMaintenancePrompt,
  LibraryMaintenancePromptPolicy
} from '../../library/maintenance/LibraryMaintenancePromptPolicy';

@Component
export struct LibraryMaintenanceSheet {
  @Prop prompt: LibraryMaintenancePrompt =
    LibraryMaintenancePromptPolicy.fromStatus({ items: [], total: 0 });
  onStart: (action: LibraryMaintenanceAction) => void = (_action: LibraryMaintenanceAction): void => {};
  onLater: () => void = (): void => {};

  build() {
    Column({ space: 18 }) {
      SymbolGlyph($r('sys.symbol.externaldrive_fill'))
        .fontSize(34)
        .fontColor([$r('app.color.text_primary')])

      Column({ space: 8 }) {
        Text(this.prompt.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)

        Text(this.prompt.message)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .textAlign(TextAlign.Center)

        if (this.prompt.detail.length > 0) {
          Text(this.prompt.detail)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: 10 }) {
        Button(this.prompt.primaryActionLabel)
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .onClick((): void => this.onStart(this.prompt.primaryAction))

        Button(this.prompt.secondaryActionLabel)
          .type(ButtonType.Normal)
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick((): void => this.onLater())
      }
      .width('100%')

      Text(this.prompt.footer)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .lineHeight(18)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26, bottom: 18 })
  }
}
