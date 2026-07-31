export class AppPrimaryTitleParams {
  title: string;
  searchExpanded: boolean = false;
  onCancelSearch: () => void = (): void => {};

  constructor(title: string) {
    this.title = title;
  }
}

@Builder
export function AppPrimaryTitleContent(params: AppPrimaryTitleParams) {
  Row() {
    if (params.searchExpanded) {
      Search({ placeholder: '搜索', value: '' })
        .height(40)
        .layoutWeight(1)
        .searchButton('取消')
        .onSubmit(params.onCancelSearch)
    } else {
      Text(params.title)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
    }
  }
  .width('100%')
  .height(44)
  .padding({ left: 32, right: 12 })
  .alignItems(VerticalAlign.Center)
  .justifyContent(FlexAlign.Start)
}
