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
  private readonly cacheCount: number;

  constructor(cacheCount: number = PageLayoutSpec.VIRTUAL_LIST_CACHE_COUNT) {
    this.cacheCount = cacheCount;
  }

  applyNormalAttribute(instance: ListAttribute): void {
    instance
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      .cachedCount(this.cacheCount, true);
  }
}

export class PageGridBehavior implements AttributeModifier<GridAttribute> {
  private readonly cacheCount: number;

  constructor(cacheCount: number = PageLayoutSpec.ALBUM_GRID_CACHE_COUNT) {
    this.cacheCount = cacheCount;
  }

  applyNormalAttribute(instance: GridAttribute): void {
    instance
      .clip(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      .cachedCount(this.cacheCount, true);
  }
}
