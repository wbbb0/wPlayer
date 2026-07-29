import { LibraryTrackRowStyle } from './LibraryTrackRow';

@Reusable
@Component
export struct LibraryTrackRowPlaceholder {
  @Prop horizontalInset: number = 16;
  @Prop verticalInset: number = 8;
  @Prop minimumHeight: number = 0;
  @Prop artworkSize: number = 52;
  @Prop artworkCornerRadius: number = 10;
  @Prop selectionMode: boolean = false;

  @Builder
  private SelectionSlot() {
    Row()
      .width(this.selectionMode ? LibraryTrackRowStyle.SELECTION_WIDTH : 0)
      .height(LibraryTrackRowStyle.SELECTION_WIDTH)
      .opacity(0)
      .translate({ x: this.selectionMode ? 0 : -12 })
      .margin({ right: this.selectionMode ? LibraryTrackRowStyle.SELECTION_GAP : 0 })
      .clip(true)
      .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private IdentityPlaceholder() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      Row()
        .width(this.artworkSize)
        .height(this.artworkSize)
        .borderRadius(this.artworkCornerRadius)
        .backgroundColor($r('app.color.text_tertiary'))
        .opacity(0.12)
      Column({ space: 8 }) {
        Row()
          .width('58%')
          .height(12)
          .borderRadius(6)
          .backgroundColor($r('app.color.text_tertiary'))
          .opacity(0.14)
        Row()
          .width('38%')
          .height(10)
          .borderRadius(5)
          .backgroundColor($r('app.color.text_tertiary'))
          .opacity(0.1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .clip(true)
  }

  build() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.SelectionSlot()
      this.IdentityPlaceholder()
      Text('0:00')
        .fontSize(LibraryTrackRowStyle.DURATION_SIZE)
        .opacity(0)
      if (!this.selectionMode) {
        Row()
          .width(LibraryTrackRowStyle.ACTION_SIZE)
          .height(LibraryTrackRowStyle.ACTION_SIZE)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: this.minimumHeight })
    .padding({
      left: this.horizontalInset,
      right: this.horizontalInset,
      top: this.verticalInset,
      bottom: this.verticalInset
    })
  }
}
