import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';
import {
  ImportItemDetailKind,
  ImportItemOutcome,
  ImportItemResult
} from '../../library/model/LibraryModels';
import { LibraryListDataSource } from '../../library/store/LibraryListDataSource';

class TaskReportLayoutSpec {
  static readonly TOP_PADDING: number = 20;
  static readonly HEADER_HEIGHT: number = 48;
  static readonly HEADER_TRAILING_SAFE_AREA: number = 56;
}

@Reusable
@Component
struct ImportDetailListItem {
  @Prop item: ImportItemResult;

  private readableUri(uri: string): string {
    try {
      return decodeURIComponent(uri);
    } catch (_error) {
      return uri;
    }
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text(this.item.outcome === ImportItemOutcome.DUPLICATE ? '重复' : '失败')
          .fontSize(12)
          .fontColor(this.item.outcome === ImportItemOutcome.DUPLICATE ?
            $r('app.color.text_secondary') : $r('app.color.message_error'))
        Text(this.readableUri(this.item.displayName))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .layoutWeight(1)
      }.width('100%')
      if (this.item.reason.length > 0) {
        Text(this.item.reason)
          .fontSize(12)
          .fontColor(this.item.outcome === ImportItemOutcome.DUPLICATE ?
            $r('app.color.text_secondary') : $r('app.color.message_error'))
          .width('100%')
      }
      Text(`文件 URI：${this.readableUri(this.item.uri)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .maxLines(4)
      if (this.item.outcome === ImportItemOutcome.DUPLICATE &&
        this.item.duplicateSourceUri !== undefined) {
        Text(`已有文件 URI：${this.readableUri(this.item.duplicateSourceUri)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(4)
      }
      if (this.item.outcome === ImportItemOutcome.DUPLICATE &&
        this.item.duplicateTrackId !== undefined) {
        Text(`已有音乐库记录：#${this.item.duplicateTrackId}`)
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
}

@Component
export struct LibraryManagementPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State showTaskReport: boolean = false;
  @State expandedImportDetail?: ImportItemDetailKind = undefined;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  private hasTaskReport(): boolean {
    return this.store.importing || this.store.lastImportResult !== undefined ||
      this.store.rebuildingSortIndexes || this.store.sortIndexResult.length > 0 ||
      this.store.refreshingPalettes || this.store.paletteRefreshResult.length > 0 ||
      this.store.sortIndexError.length > 0 || this.store.errorMessage.length > 0;
  }

  private detailCount(kind: ImportItemDetailKind): number {
    switch (kind) {
      case ImportItemDetailKind.URI_DUPLICATE:
        return this.store.uriDuplicateCount;
      case ImportItemDetailKind.CONTENT_DUPLICATE:
        return this.store.contentDuplicateCount;
      case ImportItemDetailKind.BATCH_DUPLICATE:
        return this.store.batchDuplicateCount;
      case ImportItemDetailKind.FAILED:
        return this.store.failedImportCount;
    }
  }

  private toggleImportDetail(kind: ImportItemDetailKind): void {
    this.expandedImportDetail = this.expandedImportDetail === kind ? undefined : kind;
  }

  @Builder
  private ImportDetailHeader(title: string, kind: ImportItemDetailKind) {
    Button() {
      Row({ space: 12 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(kind === ImportItemDetailKind.FAILED ?
            $r('app.color.message_error') : $r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        Text(`${this.detailCount(kind)}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('tnum')
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.expandedImportDetail === kind ? 90 : 0 })
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height(48)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('app.color.glass_surface'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
      adaptiveColor: AdaptiveColor.AVERAGE,
      policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
      scale: 1
    })
    .borderRadius(16)
    .accessibilityText(`${title}，${this.detailCount(kind)} 项`)
    .onClick(() => this.toggleImportDetail(kind))
  }

  @Builder
  private ImportDetailItems(kind: ImportItemDetailKind,
    dataSource: LibraryListDataSource<ImportItemResult>) {
    LazyForEach(dataSource, (item: ImportItemResult, index: number) => {
      ListItem() {
        ImportDetailListItem({ item: item })
          .reuseId('import_detail')
      }
    }, (item: ImportItemResult, index: number) => `${kind}:${index}:${item.uri}`)
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

      if (this.store.refreshingPalettes) {
        Column({ space: 10 }) {
          Progress({
            value: this.store.paletteRefreshProcessed,
            total: Math.max(1, this.store.paletteRefreshTotal),
            type: ProgressType.Linear
          }).width('100%')
          Text(`正在刷新封面调色板 ${this.store.paletteRefreshProcessed} / ` +
            `${this.store.paletteRefreshTotal}`)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
      } else if (this.store.paletteRefreshResult.length > 0) {
        Text(this.store.paletteRefreshResult)
          .fontColor($r('app.color.message_success'))
          .width('100%')
      }

      if (this.store.importDetailCount > 0) {
        Text('重复与错误明细')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        List({ space: 10 }) {
          if (this.store.uriDuplicateCount > 0) {
            ListItemGroup({
              header: this.ImportDetailHeader('URI 已存在', ImportItemDetailKind.URI_DUPLICATE)
            }) {
              if (this.expandedImportDetail === ImportItemDetailKind.URI_DUPLICATE) {
                this.ImportDetailItems(
                  ImportItemDetailKind.URI_DUPLICATE, this.store.uriDuplicateDataSource
                )
              }
            }
          }
          if (this.store.contentDuplicateCount > 0) {
            ListItemGroup({
              header: this.ImportDetailHeader('文件内容重复', ImportItemDetailKind.CONTENT_DUPLICATE)
            }) {
              if (this.expandedImportDetail === ImportItemDetailKind.CONTENT_DUPLICATE) {
                this.ImportDetailItems(
                  ImportItemDetailKind.CONTENT_DUPLICATE, this.store.contentDuplicateDataSource
                )
              }
            }
          }
          if (this.store.batchDuplicateCount > 0) {
            ListItemGroup({
              header: this.ImportDetailHeader('本次选择中重复', ImportItemDetailKind.BATCH_DUPLICATE)
            }) {
              if (this.expandedImportDetail === ImportItemDetailKind.BATCH_DUPLICATE) {
                this.ImportDetailItems(
                  ImportItemDetailKind.BATCH_DUPLICATE, this.store.batchDuplicateDataSource
                )
              }
            }
          }
          if (this.store.failedImportCount > 0) {
            ListItemGroup({
              header: this.ImportDetailHeader('导入失败', ImportItemDetailKind.FAILED)
            }) {
              if (this.expandedImportDetail === ImportItemDetailKind.FAILED) {
                this.ImportDetailItems(
                  ImportItemDetailKind.FAILED, this.store.failedImportDataSource
                )
              }
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .sticky(StickyStyle.Header)
        .cachedCount(PageLayoutSpec.VIRTUAL_LIST_CACHE_COUNT, true)
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
            this.expandedImportDetail = undefined;
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

        Button(this.store.refreshingPalettes ? '正在刷新调色板…' : '刷新封面调色板')
          .width('100%')
          .height(48)
          .enabled(!this.store.importing && !this.store.loading && !this.store.rebuildingSortIndexes &&
            !this.store.refreshingPalettes && this.store.statistics.artworkCount > 0)
          .onClick(() => {
            this.store.refreshArtworkPalettes();
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
          .enabled(!this.store.importing && !this.store.refreshingPalettes &&
            this.store.statistics.trackCount > 0)
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
