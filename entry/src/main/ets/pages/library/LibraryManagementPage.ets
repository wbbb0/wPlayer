import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';
import { ImportItemOutcome, ImportItemResult } from '../../library/model/LibraryModels';

class TaskReportLayoutSpec {
  static readonly TOP_PADDING: number = 20;
  static readonly HEADER_HEIGHT: number = 48;
  static readonly HEADER_TRAILING_SAFE_AREA: number = 56;
}

@Component
export struct LibraryManagementPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State showTaskReport: boolean = false;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  private hasTaskReport(): boolean {
    return this.store.importing || this.store.lastImportResult !== undefined ||
      this.store.rebuildingSortIndexes || this.store.sortIndexResult.length > 0 ||
      this.store.sortIndexError.length > 0 || this.store.errorMessage.length > 0;
  }

  private visibleDetailItems(): Array<ImportItemResult> {
    return this.store.importDetailItems;
  }

  private readableUri(uri: string): string {
    try {
      return decodeURIComponent(uri);
    } catch (_error) {
      return uri;
    }
  }

  @Builder
  private ImportDetailRow(item: ImportItemResult) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text(item.outcome === ImportItemOutcome.DUPLICATE ? '重复' : '失败')
          .fontSize(12)
          .fontColor(item.outcome === ImportItemOutcome.DUPLICATE ?
            $r('app.color.text_secondary') : $r('app.color.message_error'))
        Text(this.readableUri(item.displayName))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .layoutWeight(1)
      }.width('100%')
      if (item.reason.length > 0) {
        Text(item.reason)
          .fontSize(12)
          .fontColor(item.outcome === ImportItemOutcome.DUPLICATE ?
            $r('app.color.text_secondary') : $r('app.color.message_error'))
          .width('100%')
      }
      Text(`文件 URI：${this.readableUri(item.uri)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .maxLines(4)
      if (item.outcome === ImportItemOutcome.DUPLICATE && item.duplicateSourceUri !== undefined) {
        Text(`已有文件 URI：${this.readableUri(item.duplicateSourceUri)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(4)
      }
      if (item.outcome === ImportItemOutcome.DUPLICATE && item.duplicateTrackId !== undefined) {
        Text(`已有音乐库记录：#${item.duplicateTrackId}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_surface'))
  }

  @Builder
  private TaskReportSheet() {
    Column({ space: 16 }) {
      Text(this.store.importing ? '导入进度' : '任务结果')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .height(TaskReportLayoutSpec.HEADER_HEIGHT)
        .padding({ right: TaskReportLayoutSpec.HEADER_TRAILING_SAFE_AREA })

      if (this.store.importing) {
        Column({ space: 10 }) {
          Progress({
            value: this.store.importProgress.processed,
            total: Math.max(1, this.store.importProgress.total),
            type: ProgressType.Linear
          }).width('100%')
          Text(this.store.importProgress.currentName.length > 0 ?
            this.store.importProgress.currentName : '正在整理音乐库')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .width('100%')
          Text(`${this.store.importProgress.processed} / ${this.store.importProgress.total}` +
            `  ·  导入 ${this.store.importProgress.imported}` +
            `  ·  重复 ${this.store.importProgress.duplicates}` +
            `  ·  失败 ${this.store.importProgress.failed}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .fontFeature('tnum')
            .width('100%')
          Button('停止导入')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick(() => this.store.cancelImport())
        }
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor($r('app.color.glass_surface'))
      }

      if (this.store.lastImportResult !== undefined) {
        Text(`已导入 ${this.store.lastImportResult.imported} 首  ·  ` +
          `重复 ${this.store.lastImportResult.duplicates} 首  ·  ` +
          `失败 ${this.store.lastImportResult.failed} 首`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('tnum')
          .width('100%')
      }

      if (this.store.errorMessage.length > 0) {
        Column({ space: 6 }) {
          Text('操作失败')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.message_error'))
            .width('100%')
          Text(this.store.errorMessage)
            .fontSize(12)
            .fontColor($r('app.color.message_error'))
            .width('100%')
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.destructive_surface'))
      }

      if (this.store.rebuildingSortIndexes) {
        Text('正在重建排序索引…')
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.store.sortIndexResult.length > 0) {
        Text(this.store.sortIndexResult)
          .fontColor($r('app.color.message_success'))
          .width('100%')
      } else if (this.store.sortIndexError.length > 0) {
        Text(`排序索引重建失败：${this.store.sortIndexError}`)
          .fontColor($r('app.color.message_error'))
          .width('100%')
      }

      if (this.visibleDetailItems().length > 0) {
        Text('重复与错误明细')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        List({ space: 10 }) {
          ForEach(this.visibleDetailItems(), (item: ImportItemResult) => {
            ListItem() {
              this.ImportDetailRow(item)
            }
          }, (item: ImportItemResult) => `${item.outcome}:${item.uri}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      } else if (!this.store.importing && this.store.lastImportResult !== undefined) {
        Text('本次导入没有重复或错误')
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 20,
      right: 20,
      top: TaskReportLayoutSpec.TOP_PADDING,
      bottom: 24
    })
  }

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
            this.store.selectAndImport(() => {
              this.showTaskReport = true;
            });
          })

        Button(this.store.rebuildingSortIndexes ? '正在重建排序索引…' : '重建排序索引')
          .width('100%')
          .height(48)
          .enabled(!this.store.importing && !this.store.loading && !this.store.rebuildingSortIndexes &&
            this.store.statistics.trackCount > 0)
          .onClick(() => {
            this.store.rebuildSortIndexes();
            this.showTaskReport = true;
          })

        if (this.hasTaskReport() || this.store.lastMessage.length > 0 || this.store.errorMessage.length > 0) {
          Divider()
            .strokeWidth(1)
            .color($r('app.color.text_tertiary'))
            .opacity(0.22)

          if (this.hasTaskReport()) {
            Button(this.store.importing ? '查看导入进度' : '查看任务结果')
              .width('100%')
              .height(48)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .onClick(() => this.showTaskReport = true)
          }

          if (this.store.lastMessage.length > 0) {
            Text(this.store.lastMessage)
              .fontSize(13)
              .fontColor($r('app.color.message_success'))
              .width('100%')
          }
          if (this.store.errorMessage.length > 0) {
            Text(this.store.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.message_error'))
              .width('100%')
          }
        }

        Divider()
          .strokeWidth(1)
          .color($r('app.color.text_tertiary'))
          .opacity(0.22)

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
    .backgroundColor(Color.Transparent)
    .attributeModifier(this.scrollBehavior)
    .bindSheet($$this.showTaskReport, this.TaskReportSheet(), {
      height: SheetSize.LARGE,
      showClose: true,
      dragBar: true
    })
  }
}
