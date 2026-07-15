import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'wPlayerImport';

export class ImportPerformanceTrace {
  private static nextSessionId: number = 0;
  private static sessionId: number = 0;
  private static sessionStartedAt: number = 0;
  private static readonly fileIds: Map<string, number> = new Map();

  static start(total: number): void {
    ImportPerformanceTrace.sessionId = ++ImportPerformanceTrace.nextSessionId;
    ImportPerformanceTrace.sessionStartedAt = Date.now();
    ImportPerformanceTrace.fileIds.clear();
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
    const filePart = fileId > 0 ? ` file=${fileId}` : '';
    const detailPart = details.length > 0 ? ` ${details}` : '';
    ImportPerformanceTrace.write(`stage=${stage}${filePart} ms=${elapsed}${detailPart}`);
  }

  static event(name: string, fileId: number = 0, details: string = ''): void {
    const filePart = fileId > 0 ? ` file=${fileId}` : '';
    const detailPart = details.length > 0 ? ` ${details}` : '';
    ImportPerformanceTrace.write(`event=${name}${filePart}${detailPart}`);
  }

  static finish(imported: number, duplicates: number, failed: number): void {
    const elapsed = Math.max(0, Date.now() - ImportPerformanceTrace.sessionStartedAt);
    ImportPerformanceTrace.write(
      `event=session_finish ms=${elapsed} imported=${imported} duplicates=${duplicates} failed=${failed}`
    );
  }

  private static write(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', `session=${ImportPerformanceTrace.sessionId} ${message}`);
  }
}
