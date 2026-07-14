import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct LibraryManagementPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清空音乐库？',
      message: '将移除应用中的曲目记录和封面缓存，不会删除原始音乐文件。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.destructive'),
        action: () => {
          this.store.clearLibrary();
        }
      }
    });
  }

  @Builder
  private LibraryStatistics() {
    Column({ space: 12 }) {
      Row() {
        Text('音乐').fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${this.store.statistics.trackCount} 首`).fontColor($r('app.color.text_secondary'))
      }.width('100%')
      Row() {
        Text('专辑').fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${this.store.statistics.albumCount} 张`).fontColor($r('app.color.text_secondary'))
      }.width('100%')
      Row() {
        Text('封面缓存').fontColor($r('app.color.text_primary')).layoutWeight(1)
        Text(`${this.store.statistics.artworkCount} 项`).fontColor($r('app.color.text_secondary'))
      }.width('100%')
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 18 }) {
        this.LibraryStatistics()

        Button(this.store.importing ? '正在导入…' : '添加音乐')
          .width('100%')
          .height(52)
          .enabled(!this.store.importing && !this.store.loading)
          .onClick(() => {
            this.store.selectAndImport();
          })

        if (this.store.importing) {
          Column({ space: 8 }) {
            Progress({
              value: this.store.importProgress.processed,
              total: Math.max(1, this.store.importProgress.total),
              type: ProgressType.Linear
            }).width('100%')
            Text(this.store.importProgress.currentName.length > 0 ?
              this.store.importProgress.currentName : '正在整理音乐库')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
            Text(`${this.store.importProgress.processed} / ${this.store.importProgress.total}` +
              `  ·  导入 ${this.store.importProgress.imported}` +
              `  ·  重复 ${this.store.importProgress.duplicates}` +
              `  ·  失败 ${this.store.importProgress.failed}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .fontFeature('tnum')
              .maxLines(1)
            Button('停止导入')
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .onClick(() => this.store.cancelImport())
          }
          .width('100%')
        }

        if (this.store.lastMessage.length > 0) {
          Text(this.store.lastMessage)
            .fontSize(13)
            .fontColor($r('app.color.message_success'))
        }
        if (this.store.errorMessage.length > 0) {
          Text(this.store.errorMessage)
            .fontSize(13)
            .fontColor($r('app.color.message_error'))
        }

        Button(this.store.rebuildingSortIndexes ? '正在重建排序索引…' : '重建排序索引')
          .width('100%')
          .height(48)
          .enabled(!this.store.importing && !this.store.loading && !this.store.rebuildingSortIndexes &&
            this.store.statistics.trackCount > 0)
          .onClick(() => this.store.rebuildSortIndexes())

        Button('清空音乐库')
          .width('100%')
          .height(48)
          .fontColor($r('app.color.destructive'))
          .backgroundColor($r('app.color.destructive_surface'))
          .enabled(!this.store.importing && this.store.statistics.trackCount > 0)
          .onClick(() => this.confirmClear())
      }
      .width('100%')
      .padding({
        left: 24, right: 24,
        top: PageLayoutSpec.secondaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(this.contentBehavior)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .attributeModifier(this.scrollBehavior)
  }
}
