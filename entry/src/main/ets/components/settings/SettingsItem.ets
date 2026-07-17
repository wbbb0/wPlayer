@Component
export struct SettingsToggleItem {
  @Prop symbol: Resource;
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop isOn: boolean = false;
  onChange: (value: boolean) => void = (_value: boolean): void => {};

  build() {
    Row({ space: 14 }) {
      SymbolGlyph(this.symbol)
        .fontSize(23)
        .fontColor([$r('app.color.theme_accent')])
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.description)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor($r('app.color.theme_accent'))
        .accessibilityText(this.title)
        .onChange((value: boolean) => {
          this.onChange(value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 76 })
    .padding({ left: 18, right: 14, top: 12, bottom: 12 })
  }
}

@Component
export struct SettingsLinkItem {
  @Prop symbol: Resource;
  @Prop title: string = '';
  @Prop description: string = '';
  onActivate: () => void = (): void => {};

  build() {
    Row({ space: 14 }) {
      SymbolGlyph(this.symbol)
        .fontSize(23)
        .fontColor([$r('app.color.theme_accent')])
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.description)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .constraintSize({ minHeight: 76 })
    .padding({ left: 18, right: 18, top: 12, bottom: 12 })
    .onClick(() => {
      this.onActivate();
    })
  }
}
