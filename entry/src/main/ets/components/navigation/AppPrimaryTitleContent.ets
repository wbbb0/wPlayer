export class AppPrimaryTitleParams {
  title: string;
  titleColor: string;

  constructor(title: string, titleColor: string) {
    this.title = title;
    this.titleColor = titleColor;
  }
}

@Builder
export function AppPrimaryTitleContent(params: AppPrimaryTitleParams) {
  Row() {
    Text(params.title)
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor(params.titleColor)
  }
  .width('100%')
  .height(44)
  .padding({ left: 32 })
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.Start)
}
