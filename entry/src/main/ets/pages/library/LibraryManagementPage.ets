import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';
import {
  ImportItemDetailKind,
  ImportItemOutcome,
  ImportItemResult,
  ImportStagePerformance,
  FileCheckItemOutcome,
  FileCheckItemResult,
  UnavailableTrackItem
} from '../../library/model/LibraryModels';
import { LibraryListDataSource } from '../../library/store/LibraryListDataSource';
import { LibraryItemAvailability } from '../../components/library/LibraryItemAvailability';

class TaskReportLayoutSpec {
  static readonly TOP_PADDING: number = 20;
  static readonly HEADER_HEIGHT: number = 48;
  static readonly HEADER_TRAILING_SAFE_AREA: number = 56;
}

enum LibraryManagementSheet {
  TASK_REPORT = 0,
  UNAVAILABLE_FILES = 1
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
  @State showPageSheet: boolean = false;
  @State activeSheet: LibraryManagementSheet = LibraryManagementSheet.TASK_REPORT;
  @State expandedImportDetail?: ImportItemDetailKind = undefined;
  @State performanceExpanded: boolean = false;
  @State selectedUnavailableIds: Array<number> = [];
  scroller: Scroller = new Scroller();
  openDebugMaintenance: () => void = (): void => {};
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();

  private hasTaskReport(): boolean {
    return this.store.importing || this.store.lastImportResult !== undefined ||
      this.store.errorMessage.length > 0 ||
      this.store.checkingFiles || this.store.fileCheckResult.length > 0;
  }

  private openUnavailableFiles(): void {
    if (this.store.statistics.unavailableTrackCount <= 0) {
      return;
    }
    this.selectedUnavailableIds = [];
    this.store.loadUnavailableTracks().then((): void => {
      this.activeSheet = LibraryManagementSheet.UNAVAILABLE_FILES;
      this.showPageSheet = true;
    }).catch((error: Object): void => {
      console.warn(`Unable to load unavailable files: ${error instanceof Error ? error.message : `${error}`}`);
    });
  }

  private toggleUnavailableSelection(trackId: number): void {
    if (this.selectedUnavailableIds.indexOf(trackId) >= 0) {
      this.selectedUnavailableIds =
        this.selectedUnavailableIds.filter((id: number): boolean => id !== trackId);
    } else {
      this.selectedUnavailableIds = this.selectedUnavailableIds.concat([trackId]);
    }
  }

  private removeUnavailable(trackIds: Array<number>): void {
    this.store.removeUnavailableTracks(trackIds).then((): void => {
      this.selectedUnavailableIds = [];
      if (this.store.statistics.unavailableTrackCount === 0) {
        this.showPageSheet = false;
      }
    });
  }

  private openTaskReport(): void {
    this.activeSheet = LibraryManagementSheet.TASK_REPORT;
    this.performanceExpanded = false;
    this.showPageSheet = true;
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
      Text(this.store.checkingFiles ? '文件检查进度' :
        (this.store.lastTaskWasFileCheck ? '文件检查结果' :
          (this.store.importing ? '导入进度' : '任务结果')))
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
          Text(this.store.importProgress.metadataCompleted ?
            (this.store.importProgress.cancelled ?
              '音乐文件处理已停止' : '音乐文件处理完成') :
            '正在处理音乐文件')
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
          if (this.store.importProgress.metadataCompleted &&
            this.store.importProgress.artworkTotal > 0) {
            Divider()
              .color($r('app.color.text_secondary'))
              .opacity(0.2)
            Progress({
              value: this.store.importProgress.artworkProcessed,
              total: Math.max(1, this.store.importProgress.artworkTotal),
              type: ProgressType.Linear
            }).width('100%')
            Text(this.store.importProgress.artworkProcessed <
              this.store.importProgress.artworkTotal ? '正在处理封面' :
              (this.store.importProgress.artworkFailed > 0 ?
                '封面处理完成，但有失败项目' : '封面处理完成'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(`${this.store.importProgress.artworkProcessed} / ` +
              `${this.store.importProgress.artworkTotal}` +
              (this.store.importProgress.artworkSkipped > 0 ?
                `  ·  跳过 ${this.store.importProgress.artworkSkipped}` : '') +
              (this.store.importProgress.artworkFailed > 0 ?
                `  ·  失败 ${this.store.importProgress.artworkFailed}` : ''))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .fontFeature('tnum')
              .width('100%')
          }
          Button('停止导入')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick(() => this.store.cancelImport())
        }
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor($r('app.color.glass_surface'))
      }

      if (this.store.checkingFiles) {
        Column({ space: 10 }) {
          Progress({
            value: this.store.fileCheckProgress.processed,
            total: Math.max(1, this.store.fileCheckProgress.total),
            type: ProgressType.Linear
          }).width('100%')
          Text(this.store.fileCheckProgress.metadataCompleted ?
            (this.store.fileCheckProgress.cancelled ?
              '音乐文件检查已停止' : '音乐文件检查完成') :
            (this.store.fileCheckProgress.currentName.length > 0 ?
              this.store.fileCheckProgress.currentName : '正在检查音乐文件'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .width('100%')
          Text(`${this.store.fileCheckProgress.processed} / ${this.store.fileCheckProgress.total}` +
            `  ·  更新 ${this.store.fileCheckProgress.updated}` +
            `  ·  恢复 ${this.store.fileCheckProgress.recovered}` +
            `  ·  封面 ${this.store.fileCheckProgress.artworkRebuilt}` +
            `  ·  失效 ${this.store.fileCheckProgress.unavailable}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .fontFeature('tnum')
            .width('100%')
          if (this.store.fileCheckProgress.metadataCompleted &&
            this.store.fileCheckProgress.artworkTotal > 0) {
            Divider()
              .color($r('app.color.text_secondary'))
              .opacity(0.2)
            Progress({
              value: this.store.fileCheckProgress.artworkProcessed,
              total: Math.max(1, this.store.fileCheckProgress.artworkTotal),
              type: ProgressType.Linear
            }).width('100%')
            Text(this.store.fileCheckProgress.artworkProcessed <
              this.store.fileCheckProgress.artworkTotal ? '正在处理封面' :
              (this.store.fileCheckProgress.artworkFailed > 0 ?
                '封面处理完成，但有失败项目' : '封面处理完成'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(`${this.store.fileCheckProgress.artworkProcessed} / ` +
              `${this.store.fileCheckProgress.artworkTotal}` +
              (this.store.fileCheckProgress.artworkSkipped > 0 ?
                `  ·  跳过 ${this.store.fileCheckProgress.artworkSkipped}` : '') +
              (this.store.fileCheckProgress.artworkFailed > 0 ?
                `  ·  失败 ${this.store.fileCheckProgress.artworkFailed}` : ''))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .fontFeature('tnum')
              .width('100%')
          }
          Button('停止检查')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick(() => this.store.cancelFileCheck())
        }
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor($r('app.color.glass_surface'))
      } else if (this.store.fileCheckResult.length > 0) {
        Text(this.store.fileCheckResult)
          .fontColor(this.store.fileCheckProgress.artworkFailed > 0 ?
            $r('app.color.message_error') : $r('app.color.message_success'))
          .width('100%')
      }

      if (!this.store.lastTaskWasFileCheck && this.store.lastImportResult !== undefined) {
        Text(`已导入 ${this.store.lastImportResult.imported} 首  ·  ` +
          `重复 ${this.store.lastImportResult.duplicates} 首  ·  ` +
          `失败 ${this.store.lastImportResult.failed} 首` +
          (this.store.lastImportResult.artworkSkipped > 0 ?
            `  ·  跳过封面 ${this.store.lastImportResult.artworkSkipped} 个` : '') +
          (this.store.lastImportResult.artworkFailed > 0 ?
            `  ·  封面失败 ${this.store.lastImportResult.artworkFailed} 个` : ''))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('tnum')
          .width('100%')

        if (this.store.lastImportResult.performance !== undefined) {
          Column({ space: 8 }) {
            Button() {
              Row({ space: 10 }) {
                Text(`性能统计  ·  总耗时 ${this.formatDuration(
                  this.store.lastImportResult.performance.totalDurationMs
                )}`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([$r('app.color.text_tertiary')])
                  .rotate({ angle: this.performanceExpanded ? 90 : 0 })
              }
              .width('100%')
              .height(44)
            }
            .width('100%')
            .height(44)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .accessibilityText(this.performanceExpanded ? '收起性能统计' : '展开性能统计')
            .onClick(() => {
              this.performanceExpanded = !this.performanceExpanded;
            })
            if (this.performanceExpanded) {
              Scroll() {
                Column({ space: 8 }) {
                  ForEach(this.store.lastImportResult.performance.stages,
                    (stage: ImportStagePerformance) => {
                    Row() {
                      Text(stage.label)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)
                      Text(`平均 ${this.formatAverageMs(stage.averageMs)}  ·  ${stage.sampleCount} 个文件`)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .fontFeature('tnum')
                    }
                    .width('100%')
                  }, (stage: ImportStagePerformance) => stage.stage)
                }
                .width('100%')
              }
              .width('100%')
              .constraintSize({ maxHeight: 180 })
              .edgeEffect(EdgeEffect.Spring)
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor($r('app.color.glass_surface'))
        }
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

      if (this.store.lastTaskWasFileCheck && !this.store.checkingFiles &&
        this.store.fileCheckResult.length > 0) {
        if (this.store.fileCheckItems.length > 0) {
          Text('变化与问题明细')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          List({ space: 10 }) {
            ForEach(this.store.fileCheckItems, (item: FileCheckItemResult) => {
              ListItem() {
                FileCheckResultListItem({ item: item })
                  .reuseId('file_check_result')
              }
            }, (item: FileCheckItemResult) => `${item.trackId}:${item.outcome}`)
          }
          .width('100%')
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(PageLayoutSpec.VIRTUAL_LIST_CACHE_COUNT, true)
        } else {
          Text('所有文件均可访问，且文件大小和修改时间没有变化')
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
      } else if (!this.store.lastTaskWasFileCheck && this.store.importDetailCount > 0) {
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
      } else if (!this.store.lastTaskWasFileCheck && !this.store.importing &&
        this.store.lastImportResult !== undefined) {
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
      Row({ space: 8 }) {
        Text('失效文件')
          .fontColor(this.store.statistics.unavailableTrackCount > 0 ?
            $r('app.color.message_error') : $r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.store.statistics.unavailableTrackCount} 首`)
          .fontColor($r('app.color.text_secondary'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .opacity(this.store.statistics.unavailableTrackCount > 0 ? 1 : 0.55)
      .onClick(() => this.openUnavailableFiles())
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
              this.openTaskReport();
            });
          })

        Button(this.store.checkingFiles ? '正在检查音乐文件…' : '检查音乐文件')
          .width('100%')
          .height(48)
          .enabled(!this.store.importing && !this.store.loading && !this.store.rebuildingSortIndexes &&
            !this.store.refreshingPalettes && !this.store.checkingFiles &&
            this.store.statistics.trackCount > 0)
          .onClick(() => {
            this.store.checkMusicFiles();
            this.openTaskReport();
          })

        Button() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.gearshape_fill'))
              .fontSize(20)
              .fontColor([$r('app.color.text_secondary')])
            Column({ space: 3 }) {
              Text('调试维护')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
              Text('重建排序索引、刷新封面调色板')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width('100%')
        }
        .width('100%')
        .height(64)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor($r('app.color.glass_surface'))
        .borderRadius(18)
        .onClick(() => this.openDebugMaintenance())

        if (this.hasTaskReport() || this.store.lastMessage.length > 0 || this.store.errorMessage.length > 0) {
          Divider()
            .strokeWidth(1)
            .color($r('app.color.text_tertiary'))
            .opacity(0.22)

          if (this.hasTaskReport()) {
            Button(this.store.checkingFiles ? '查看文件检查进度' :
              (this.store.importing ? '查看导入进度' :
                (this.store.lastTaskWasFileCheck ? '查看文件检查结果' : '查看任务结果')))
              .width('100%')
              .height(48)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .onClick(() => this.openTaskReport())
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
    .bindSheet($$this.showPageSheet, this.ActiveSheet(), {
      height: SheetSize.LARGE,
      showClose: true,
      dragBar: true
    })
  }

  private formatAverageMs(value: number): string {
    if (value >= 1000) {
      return `${(value / 1000).toFixed(2)} s`;
    }
    return `${Math.round(value)} ms`;
  }

  private formatDuration(value: number): string {
    if (value >= 1000) {
      return `${(value / 1000).toFixed(2)} s`;
    }
    return `${Math.round(value)} ms`;
  }

  @Builder
  private ActiveSheet() {
    if (this.activeSheet === LibraryManagementSheet.UNAVAILABLE_FILES) {
      this.UnavailableFilesSheet()
    } else {
      this.TaskReportSheet()
    }
  }

  @Builder
  private UnavailableFilesSheet() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text('失效文件')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.selectedUnavailableIds.length > 0) {
          Button(`删除 ${this.selectedUnavailableIds.length} 项`)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor($r('app.color.destructive'))
            .onClick(() => this.removeUnavailable(this.selectedUnavailableIds))
        }
      }
      .width('100%')
      if (this.store.unavailableTracks.length > 0) {
        List({ space: 8 }) {
          ForEach(this.store.unavailableTracks, (item: UnavailableTrackItem) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph(this.selectedUnavailableIds.indexOf(item.trackId) >= 0 ?
                  $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
                  .fontSize(22)
                  .fontColor([this.selectedUnavailableIds.indexOf(item.trackId) >= 0 ?
                    $r('app.color.theme_accent') : $r('app.color.text_tertiary')])
                Column({ space: 4 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${LibraryItemAvailability.label(item.availability)}` +
                    (item.artistDisplay.length > 0 ? ` · ${item.artistDisplay}` : ''))
                    .fontSize(12)
                    .fontColor($r('app.color.message_error'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Button() {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(18)
                    .fontColor([$r('app.color.destructive')])
                }
                .width(40)
                .height(40)
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .accessibilityText(`删除 ${item.title}`)
                .onClick(() => this.removeUnavailable([item.trackId]))
              }
              .width('100%')
              .padding(12)
              .borderRadius(16)
              .backgroundColor($r('app.color.glass_surface'))
              .onClick(() => this.toggleUnavailableSelection(item.trackId))
            }
          }, (item: UnavailableTrackItem) => `${item.trackId}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        Button('一键清理所有失效记录')
          .width('100%')
          .fontColor($r('app.color.destructive'))
          .backgroundColor($r('app.color.destructive_surface'))
          .onClick(() => this.confirmClearUnavailable())
      } else {
        Text('当前没有失效文件')
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
  }

  private confirmClearUnavailable(): void {
    this.getUIContext().showAlertDialog({
      title: '清理所有失效记录？',
      message: '只会移除音乐库记录，不会删除设备上的原始文件。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清理',
        fontColor: $r('app.color.destructive'),
        action: () => this.store.clearAllUnavailableTracks()
      }
    });
  }
}

@Reusable
@Component
struct FileCheckResultListItem {
  @Prop item: FileCheckItemResult;

  private outcomeLabel(): string {
    switch (this.item.outcome) {
      case FileCheckItemOutcome.UPDATED:
        return '已更新';
      case FileCheckItemOutcome.RECOVERED:
        return '已恢复';
      case FileCheckItemOutcome.ARTWORK_REBUILT:
        return '封面已修复';
      case FileCheckItemOutcome.ARTWORK_ABSENT:
        return '无内嵌封面';
      case FileCheckItemOutcome.ARTWORK_FAILED:
        return '封面失败';
      case FileCheckItemOutcome.AUTHORIZATION_REVOKED:
        return '授权失效';
      case FileCheckItemOutcome.CORRUPTED:
        return '解析失败';
      default:
        return '不可用';
    }
  }

  private success(): boolean {
    return this.item.outcome === FileCheckItemOutcome.UPDATED ||
      this.item.outcome === FileCheckItemOutcome.RECOVERED ||
      this.item.outcome === FileCheckItemOutcome.ARTWORK_REBUILT ||
      this.item.outcome === FileCheckItemOutcome.ARTWORK_ABSENT;
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text(this.outcomeLabel())
          .fontSize(12)
          .fontColor(this.success() ?
            $r('app.color.message_success') : $r('app.color.message_error'))
        Text(this.item.displayName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      Text(this.item.reason)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text(this.item.uri)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(3)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_surface'))
  }
}
