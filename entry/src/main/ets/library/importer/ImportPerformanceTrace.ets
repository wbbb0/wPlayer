import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImportPerformanceSummary, ImportStagePerformance } from '../model/LibraryModels';

const DOMAIN = 0x0000;
const TAG = 'wPlayerImport';
const FILE_LOG_SAMPLE_INTERVAL = 128;
const FILE_LOG_INITIAL_SAMPLE_COUNT = 8;

interface StageAccumulator {
  totalMs: number;
  sampleCount: number;
}

export class ImportPerformanceTrace {
  private static nextSessionId: number = 0;
  private static sessionId: number = 0;
  private static sessionStartedAt: number = 0;
  private static readonly fileIds: Map<string, number> = new Map();
  private static readonly stageAccumulators: Map<string, StageAccumulator> = new Map();

  static start(total: number): void {
    ImportPerformanceTrace.sessionId = ++ImportPerformanceTrace.nextSessionId;
    ImportPerformanceTrace.sessionStartedAt = Date.now();
    ImportPerformanceTrace.fileIds.clear();
    ImportPerformanceTrace.stageAccumulators.clear();
    ImportPerformanceTrace.write(`event=session_start total=${total}`);
  }

  static fileId(uri: string): number {
    const existing = ImportPerformanceTrace.fileIds.get(uri);
    if (existing !== undefined) {
      return existing;
    }
    const id = ImportPerformanceTrace.fileIds.size + 1;
    ImportPerformanceTrace.fileIds.set(uri, id);
    return id;
  }

  static mark(stage: string, startedAt: number, fileId: number = 0, details: string = ''): void {
    const elapsed = Math.max(0, Date.now() - startedAt);
    if (fileId > 0) {
      ImportPerformanceTrace.record(stage, elapsed, 1);
      if (!ImportPerformanceTrace.shouldWriteFileSample(fileId)) {
        return;
      }
    }
    const filePart = fileId > 0 ? ` file=${fileId}` : '';
    const detailPart = details.length > 0 ? ` ${details}` : '';
    ImportPerformanceTrace.write(`stage=${stage}${filePart} ms=${elapsed}${detailPart}`);
  }

  static markBatchAverage(stage: string, startedAt: number, fileCount: number,
    details: string = ''): void {
    const elapsed = Math.max(0, Date.now() - startedAt);
    if (fileCount > 0) {
      ImportPerformanceTrace.record(stage, elapsed, fileCount);
    }
    const detailPart = details.length > 0 ? ` ${details}` : '';
    ImportPerformanceTrace.write(
      `stage=${stage} ms=${elapsed} samples=${fileCount}${detailPart}`
    );
  }

  static event(name: string, fileId: number = 0, details: string = ''): void {
    if (fileId > 0 && !ImportPerformanceTrace.shouldWriteFileSample(fileId)) {
      return;
    }
    const filePart = fileId > 0 ? ` file=${fileId}` : '';
    const detailPart = details.length > 0 ? ` ${details}` : '';
    ImportPerformanceTrace.write(`event=${name}${filePart}${detailPart}`);
  }

  static finish(imported: number, duplicates: number, failed: number): ImportPerformanceSummary {
    const elapsed = Math.max(0, Date.now() - ImportPerformanceTrace.sessionStartedAt);
    ImportPerformanceTrace.write(
      `event=session_finish ms=${elapsed} imported=${imported} duplicates=${duplicates} failed=${failed}`
    );
    return {
      totalDurationMs: elapsed,
      stages: ImportPerformanceTrace.buildStageSummaries()
    };
  }

  private static record(stage: string, elapsedMs: number, sampleCount: number): void {
    const existing = ImportPerformanceTrace.stageAccumulators.get(stage);
    if (existing === undefined) {
      ImportPerformanceTrace.stageAccumulators.set(stage, {
        totalMs: elapsedMs,
        sampleCount: sampleCount
      });
      return;
    }
    existing.totalMs += elapsedMs;
    existing.sampleCount += sampleCount;
  }

  private static buildStageSummaries(): Array<ImportStagePerformance> {
    const summaries: Array<ImportStagePerformance> = [];
    ImportPerformanceTrace.stageLabels().forEach((label: string, stage: string) => {
      const accumulator = ImportPerformanceTrace.stageAccumulators.get(stage);
      if (accumulator === undefined || accumulator.sampleCount <= 0) {
        return;
      }
      summaries.push({
        stage: stage,
        label: label,
        averageMs: accumulator.totalMs / accumulator.sampleCount,
        sampleCount: accumulator.sampleCount
      });
    });
    return summaries;
  }

  private static stageLabels(): Map<string, string> {
    return new Map<string, string>([
      ['probe_total', '文件解析'],
      ['system_metadata', '系统元数据'],
      ['candidate_query', '重复候选查询'],
      ['foreground_hash', '完整指纹'],
      ['batch_hash', '批内完整指纹'],
      ['file_prepare_total', '导入准备总计'],
      ['artwork_read', '读取封面'],
      ['artwork_metadata_read', '封面任务元数据'],
      ['artwork_hash', '封面哈希'],
      ['artwork_cache_lookup', '封面缓存查询'],
      ['artwork_info', '封面信息解析'],
      ['artwork_small', '生成小封面'],
      ['artwork_large', '生成大封面'],
      ['artwork_total', '封面处理总计'],
      ['database_commit_per_file', '数据库写入']
    ]);
  }

  private static write(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', `session=${ImportPerformanceTrace.sessionId} ${message}`);
  }

  private static shouldWriteFileSample(fileId: number): boolean {
    return fileId <= FILE_LOG_INITIAL_SAMPLE_COUNT ||
      fileId % FILE_LOG_SAMPLE_INTERVAL === 0;
  }
}
