import {
  M3uImportDetail,
  M3uImportMode,
  M3uImportReport,
  M3uImportStage
} from '../../playlist/m3u/M3uTransferService';
import {
  MAX_M3U_REPORT_DETAILS_PER_SECTION,
  M3uImportReportPolicy
} from '../../playlist/m3u/M3uImportReportPolicy';
import {
  TaskResultDetailItem,
  TaskResultDetailSection,
  TaskResultDetails,
  TaskResultTone
} from './TaskResultDetails';

export enum PlaylistImportSheetKind {
  PROGRESS = 'progress',
  REPORT = 'report'
}

@Component
export struct PlaylistImportSheetContent {
  @Prop kind: PlaylistImportSheetKind = PlaylistImportSheetKind.PROGRESS;
  @Prop stage: M3uImportStage = M3uImportStage.READING;
  @Prop sourceName: string = '';
  @Prop reports: Array<M3uImportReport> = [];
  onClose: () => void = (): void => {};

  private stageText(): string {
    const prefix = this.sourceName.length > 0 ? `${this.sourceName}：` : '';
    if (this.stage === M3uImportStage.READING) {
      return `${prefix}正在读取 M3U 文件`;
    }
    if (this.stage === M3uImportStage.MATCHING) {
      return `${prefix}正在匹配音乐库歌曲`;
    }
    return `${prefix}正在写入播放列表`;
  }

  private reportTitle(): string {
    if (this.reports.length === 1) {
      const report = this.reports[0];
      if (report.failed) {
        return `“${report.playlistName}”导入失败`;
      }
      return report.playlistName.length > 0 ? `已导入“${report.playlistName}”` : '播放列表导入完成';
    }
    let failed = 0;
    for (let index = 0; index < this.reports.length; index += 1) {
      failed += this.reports[index].failed ? 1 : 0;
    }
    const succeeded = this.reports.length - failed;
    if (failed === 0) {
      return `已导入 ${succeeded} 个播放列表`;
    }
    if (succeeded === 0) {
      return `${failed} 个文件导入失败`;
    }
    return `已导入 ${succeeded} 个播放列表，${failed} 个失败`;
  }

  private reportSummary(): string {
    let parsed = 0;
    let matched = 0;
    let inserted = 0;
    let alreadyPresent = 0;
    let unmatched = 0;
    let unavailable = 0;
    let issues = 0;
    let failed = 0;
    let detailsTruncated = false;
    for (let index = 0; index < this.reports.length; index += 1) {
      parsed += this.reports[index].parsed;
      matched += this.reports[index].matched;
      inserted += this.reports[index].inserted;
      alreadyPresent += this.reports[index].alreadyPresent;
      unmatched += this.reports[index].unmatched;
      unavailable += this.reports[index].unavailable;
      issues += this.reports[index].issues;
      failed += this.reports[index].failed ? 1 : 0;
      detailsTruncated = detailsTruncated || this.reports[index].detailsTruncated;
    }
    detailsTruncated = detailsTruncated || this.aggregatedDetailsTruncated();
    if (this.reports.length === failed) {
      return '没有播放列表被修改，可在下方查看每个文件的失败原因';
    }
    const modeLabel = this.reports.length === 1 ?
      (this.reports[0].mode === M3uImportMode.REPLACE ? '替换' : '合并') : '导入';
    const unavailableNotice = unavailable > 0 ? `，写入时不可用 ${unavailable} 首` : '';
    const failedNotice = failed > 0 ? `，失败文件 ${failed} 个` : '';
    const detailNotice = detailsTruncated ? '；明细过多，仅显示每类前 500 项' : '';
    return `${modeLabel}完成：匹配 ${matched}/${parsed} 项，` +
      `写入 ${inserted} 首，已存在 ${alreadyPresent} 首，` +
      `未匹配 ${unmatched} 项，解析问题 ${issues} 项` +
      `${unavailableNotice}${failedNotice}${detailNotice}`;
  }

  private detailItem(
    detail: M3uImportDetail,
    tone: TaskResultTone,
    keyPrefix: string,
    playlistName: string
  ): TaskResultDetailItem {
    const item: TaskResultDetailItem = {
      key: `${keyPrefix}_${detail.key}`,
      status: detail.status,
      title: detail.title,
      reason: playlistName.length > 0 ? `${playlistName} · ${detail.reason}` : detail.reason,
      uri: detail.uri,
      tone: tone
    };
    if (detail.secondaryUri !== undefined) {
      item.secondaryUri = detail.secondaryUri;
    }
    return item;
  }

  private detailItems(
    selector: (report: M3uImportReport) => Array<M3uImportDetail>,
    tone: TaskResultTone
  ): Array<TaskResultDetailItem> {
    const items: Array<TaskResultDetailItem> = [];
    for (let reportIndex = 0; reportIndex < this.reports.length; reportIndex += 1) {
      const details = selector(this.reports[reportIndex]);
      const remaining = MAX_M3U_REPORT_DETAILS_PER_SECTION - items.length;
      const displayCount = M3uImportReportPolicy.displayCount(Math.min(details.length, remaining));
      for (let detailIndex = 0; detailIndex < displayCount; detailIndex += 1) {
        items.push(this.detailItem(
          details[detailIndex],
          tone,
          `report_${reportIndex}`,
          this.reports.length > 1 ? this.reports[reportIndex].playlistName : ''
        ));
      }
      if (items.length >= MAX_M3U_REPORT_DETAILS_PER_SECTION) {
        break;
      }
    }
    return items;
  }

  private aggregatedDetailsTruncated(): boolean {
    return this.detailTypeTruncated(
      (report: M3uImportReport): Array<M3uImportDetail> => report.matchedDetails
    ) || this.detailTypeTruncated(
      (report: M3uImportReport): Array<M3uImportDetail> => report.unmatchedDetails
    ) || this.detailTypeTruncated(
      (report: M3uImportReport): Array<M3uImportDetail> => report.issueDetails
    ) || this.detailTypeTruncated(
      (report: M3uImportReport): Array<M3uImportDetail> => report.failureDetails
    );
  }

  private detailTypeTruncated(
    selector: (report: M3uImportReport) => Array<M3uImportDetail>
  ): boolean {
    let total = 0;
    for (let reportIndex = 0; reportIndex < this.reports.length; reportIndex += 1) {
      total += selector(this.reports[reportIndex]).length;
      if (M3uImportReportPolicy.detailsTruncated(total)) {
        return true;
      }
    }
    return false;
  }

  private detailSections(): Array<TaskResultDetailSection> {
    return [{
      key: 'matched',
      title: '已匹配歌曲',
      emptyText: '没有匹配到音乐库中的歌曲',
      items: this.detailItems(
        (report: M3uImportReport): Array<M3uImportDetail> => report.matchedDetails,
        TaskResultTone.SUCCESS
      ),
      tone: TaskResultTone.SUCCESS
    }, {
      key: 'unmatched',
      title: '未匹配项目',
      emptyText: '所有项目均已匹配',
      items: this.detailItems(
        (report: M3uImportReport): Array<M3uImportDetail> => report.unmatchedDetails,
        TaskResultTone.ERROR
      ),
      tone: TaskResultTone.ERROR
    }, {
      key: 'issues',
      title: '解析问题',
      emptyText: '没有解析问题',
      items: this.detailItems(
        (report: M3uImportReport): Array<M3uImportDetail> => report.issueDetails,
        TaskResultTone.ERROR
      ),
      tone: TaskResultTone.ERROR
    }, {
      key: 'failures',
      title: '导入失败与写入跳过',
      emptyText: '没有导入失败或写入跳过',
      items: this.detailItems(
        (report: M3uImportReport): Array<M3uImportDetail> => report.failureDetails,
        TaskResultTone.ERROR
      ),
      tone: TaskResultTone.ERROR
    }];
  }

  @Builder
  private ProgressContent() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        LoadingProgress()
          .width(28)
          .height(28)
        Column({ space: 4 }) {
          Text('正在导入播放列表')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(this.stageText())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 26, bottom: 28 })
  }

  @Builder
  private ReportContent() {
    Column({ space: 16 }) {
      Text(this.reportTitle())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(this.reportSummary())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TaskResultDetails({
        title: '导入明细',
        emptyText: '没有可显示的明细',
        sections: this.detailSections()
      })
      .layoutWeight(1)
      Button('完成')
        .width('100%')
        .height(48)
        .onClick(this.onClose)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 24 })
  }

  build() {
    if (this.kind === PlaylistImportSheetKind.REPORT && this.reports.length > 0) {
      this.ReportContent()
    } else {
      this.ProgressContent()
    }
  }
}
