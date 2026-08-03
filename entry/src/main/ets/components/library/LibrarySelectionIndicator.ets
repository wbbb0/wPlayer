@Component
export struct LibrarySelectionIndicator {
  @Prop @Watch('onSelectionModeChanged') selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @Prop selectedColor: ResourceColor = $r('app.color.theme_accent');
  @Prop unselectedColor: ResourceColor = $r('app.color.text_tertiary');
  @Prop surfaceColor: ResourceColor = Color.Transparent;
  @Prop fontSize: number = 22;
  @Prop slotWidth: number = 30;
  @Prop trailingGap: number = 8;
  @Prop hiddenOffsetX: number = -12;
  @Prop cornerRadius: number = 0;
  @Prop collapseLayoutSpace: boolean = true;
  @State progress: number = 0;
  private appeared: boolean = false;

  aboutToAppear(): void {
    this.appeared = true;
    this.progress = this.selectionMode ? 1 : 0;
  }

  aboutToDisappear(): void {
    this.appeared = false;
  }

  private onSelectionModeChanged(): void {
    const target = this.selectionMode ? 1 : 0;
    if (!this.appeared) {
      this.progress = target;
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.progress = target;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(this.fontSize)
        .fontColor([this.selected ? this.selectedColor : this.unselectedColor])
        .backgroundColor(this.surfaceColor)
        .borderRadius(this.cornerRadius)
        .opacity(this.progress)
        .translate({ x: this.hiddenOffsetX * (1 - this.progress), y: 0 })
    }
    .width(this.slotWidth)
    .height(this.slotWidth)
    .margin({
      right: this.collapseLayoutSpace ?
        this.trailingGap * this.progress - this.slotWidth * (1 - this.progress) : 0
    })
  }
}
