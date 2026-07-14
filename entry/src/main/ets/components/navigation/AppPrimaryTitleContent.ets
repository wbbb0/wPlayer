export class AppPrimaryTitleParams {
  title: string;

  constructor(title: string) {
    this.title = title;
  }
}

@Builder
export function AppPrimaryTitleContent(params: AppPrimaryTitleParams) {
  Row() {
    Text(params.title)
      .fontSize(28)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
  }
  .width('100%')
  .height(44)
  .padding({ left: 32 })
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.Start)
}
