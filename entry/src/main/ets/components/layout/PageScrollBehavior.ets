import { PageLayoutSpec } from './PageLayoutSpec';

export class PageScrollBehavior implements AttributeModifier<ScrollAttribute> {
  applyNormalAttribute(instance: ScrollAttribute): void {
    instance
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      .scrollBar(BarState.Auto);
  }
}

export enum PageContentAlignment {
  TOP = 0,
  CENTER = 1
}

export class PageScrollContentBehavior implements AttributeModifier<ColumnAttribute> {
  private readonly alignment: PageContentAlignment;

  constructor(alignment: PageContentAlignment = PageContentAlignment.TOP) {
    this.alignment = alignment;
  }

  applyNormalAttribute(instance: ColumnAttribute): void {
    instance
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(this.alignment === PageContentAlignment.CENTER ? FlexAlign.Center : FlexAlign.Start);
  }
}

export class PageListBehavior implements AttributeModifier<ListAttribute> {
  applyNormalAttribute(instance: ListAttribute): void {
    instance
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      .cachedCount(PageLayoutSpec.VIRTUAL_LIST_CACHE_COUNT, true);
  }
}

export class PageGridBehavior implements AttributeModifier<GridAttribute> {
  applyNormalAttribute(instance: GridAttribute): void {
    instance
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      .cachedCount(PageLayoutSpec.ALBUM_GRID_CACHE_COUNT, true);
  }
}
