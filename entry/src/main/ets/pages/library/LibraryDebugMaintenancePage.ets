import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import {
  PageScrollBehavior,
  PageScrollContentBehavior
} from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct LibraryDebugMaintenancePage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  @Builder
  private DebugNotice() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(22)
        .fontColor([$r('app.color.message_error')])
      Column({ space: 5 }) {
        Text('仅供调试')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.message_error'))
        Text('日常使用不需要执行下列功能。仅在排查排序或封面颜色问题时使用。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .borderRadius(18)
    .backgroundColor($r('app.color.destructive_surface'))
  }

  @Builder
  private SortMaintenance() {
    Column({ space: 10 }) {
      Text('排序索引')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('根据当前音乐库元数据重新生成内部排序键。正常导入和文件检查会自动维护这些数据。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button(this.store.rebuildingSortIndexes ? '正在重建排序索引…' : '重建排序索引')
        .width('100%')
        .enabled(!this.store.importing && !this.store.loading && !this.store.rebuildingSortIndexes &&
          !this.store.refreshingPalettes && !this.store.checkingFiles &&
          this.store.statistics.trackCount > 0)
        .onClick(() => this.store.rebuildSortIndexes())
      if (this.store.sortIndexResult.length > 0) {
        Text(this.store.sortIndexResult)
          .fontSize(13)
          .fontColor($r('app.color.message_success'))
          .width('100%')
      } else if (this.store.sortIndexError.length > 0) {
        Text(this.store.sortIndexError)
          .fontSize(13)
          .fontColor($r('app.color.message_error'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  @Builder
  private PaletteMaintenance() {
    Column({ space: 10 }) {
      Text('封面调色板')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('重新分析已缓存封面的主题色。正常导入和文件更新会自动生成调色板。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if (this.store.refreshingPalettes) {
        Progress({
          value: this.store.paletteRefreshProcessed,
          total: Math.max(1, this.store.paletteRefreshTotal),
          type: ProgressType.Linear
        }).width('100%')
        Text(`${this.store.paletteRefreshProcessed} / ${this.store.paletteRefreshTotal}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('tnum')
          .width('100%')
      }
      Button(this.store.refreshingPalettes ? '正在刷新调色板…' : '刷新封面调色板')
        .width('100%')
        .enabled(!this.store.importing && !this.store.loading && !this.store.rebuildingSortIndexes &&
          !this.store.refreshingPalettes && !this.store.checkingFiles &&
          this.store.statistics.artworkCount > 0)
        .onClick(() => this.store.refreshArtworkPalettes())
      if (!this.store.refreshingPalettes && this.store.paletteRefreshResult.length > 0) {
        Text(this.store.paletteRefreshResult)
          .fontSize(13)
          .fontColor($r('app.color.message_success'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 18 }) {
        this.DebugNotice()
        this.SortMaintenance()
        this.PaletteMaintenance()
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: PageLayoutSpec.secondaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(this.contentBehavior)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .attributeModifier(this.scrollBehavior)
  }
}
