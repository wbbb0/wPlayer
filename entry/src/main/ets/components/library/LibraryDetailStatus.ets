import { PageLayoutSpec } from '../layout/PageLayoutSpec';

@Component
export struct LibraryDetailStatus {
  @Prop loading: boolean = false;
  @Prop message: string = '';
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');

  build() {
    Column({ space: PageLayoutSpec.DETAIL_STATUS_GAP }) {
      if (this.loading) {
        LoadingProgress()
          .width(PageLayoutSpec.DETAIL_STATUS_ICON_SIZE)
          .height(PageLayoutSpec.DETAIL_STATUS_ICON_SIZE)
          .color(this.primaryColor)
      }
      Text(this.message)
        .fontSize(15)
        .fontColor(this.secondaryColor)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: PageLayoutSpec.DETAIL_STATUS_MIN_HEIGHT })
    .padding(PageLayoutSpec.HORIZONTAL_INSET)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
