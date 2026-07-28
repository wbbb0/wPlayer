import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  PlaylistItemInput,
  PlaylistItemSource,
  PlaylistMutationResult,
  PlaylistSortField,
  PlaylistSummary,
  SortDirection
} from '../../library/model/LibraryModels';
import { MusicRepository } from '../../library/data/MusicRepository';
import { M3uCodec } from './M3uCodec';
import { M3uEncoding } from './M3uEncoding';
import { M3uEncodingDecision, M3uExportEntry, M3uIssueKind, M3uParseIssue } from './M3uModels';
import { M3uImportPolicy } from './M3uImportPolicy';
import { MAX_M3U_REPORT_DETAILS_PER_SECTION } from './M3uImportReportPolicy';
import { M3uImportMatcher } from './M3uImportMatcher';
import { M3uTextValidation } from './M3uTextValidation';
import { FileIoSafety } from './FileIoSafety';

const MAX_M3U_BYTES: number = 4 * 1024 * 1024;
const MATCH_BATCH_SIZE: number = 128;
const CATALOG_PAGE_SIZE: number = 128;

export enum M3uImportMode {
  MERGE = 0,
  REPLACE = 1
}

export enum M3uImportNameConflictAction {
  REPLACE = 0,
  MERGE = 1,
  SAVE_AS_NEW = 2
}

export enum M3uImportStage {
  READING = 'reading',
  MATCHING = 'matching',
  WRITING = 'writing'
}

export class M3uImportSource {
  uri: string = '';
  suggestedName: string = '';
}

export class M3uImportDetail {
  key: string = '';
  status: string = '';
  title: string = '';
  reason: string = '';
  uri: string = '';
  secondaryUri?: string;
  matched: boolean = false;
  failed: boolean = false;
}

export class M3uImportReport {
  playlistId: number = -1;
  playlistName: string = '';
  mode: M3uImportMode = M3uImportMode.MERGE;
  parsed: number = 0;
  matched: number = 0;
  unmatched: number = 0;
  inserted: number = 0;
  alreadyPresent: number = 0;
  unavailable: number = 0;
  issues: number = 0;
  failed: boolean = false;
  errorMessage: string = '';
  matchedDetails: Array<M3uImportDetail> = [];
  unmatchedDetails: Array<M3uImportDetail> = [];
  issueDetails: Array<M3uImportDetail> = [];
  failureDetails: Array<M3uImportDetail> = [];
  detailsTruncated: boolean = false;
}

export type M3uImportProgressListener = (stage: M3uImportStage) => void;

export class M3uImportContext {
  private matcher?: M3uImportMatcher;
  private matcherPromise?: Promise<M3uImportMatcher>;

  getMatcher(factory: () => Promise<M3uImportMatcher>): Promise<M3uImportMatcher> {
    if (this.matcher !== undefined) {
      return Promise.resolve(this.matcher);
    }
    if (this.matcherPromise === undefined) {
      this.matcherPromise = factory().then((matcher: M3uImportMatcher): M3uImportMatcher => {
        this.matcher = matcher;
        return matcher;
      }).catch((error: Object): M3uImportMatcher => {
        this.matcherPromise = undefined;
        throw error instanceof Error ? error : new Error(`${error}`);
      });
    }
    return this.matcherPromise;
  }
}

class M3uPreparedImport {
  entryCount: number = 0;
  inputs: Array<PlaylistItemInput> = [];
  matchedDetails: Array<M3uImportDetail> = [];
  unmatchedDetails: Array<M3uImportDetail> = [];
  issues: Array<M3uParseIssue> = [];
  issueDetails: Array<M3uImportDetail> = [];
  detailsTruncated: boolean = false;
}

export class M3uTransferService {
  private readonly repository: MusicRepository;

  constructor(repository: MusicRepository) {
    this.repository = repository;
  }

  async importInto(context: common.UIAbilityContext, playlistId: number,
    mode: M3uImportMode, onProgress?: M3uImportProgressListener): Promise<M3uImportReport | undefined> {
    const selected = await this.selectOne(context);
    if (selected.length === 0) {
      return undefined;
    }
    return this.importSource({ uri: selected, suggestedName: this.playlistNameOf(selected) }, playlistId, mode,
      onProgress);
  }

  async selectImportSource(context: common.UIAbilityContext): Promise<M3uImportSource | undefined> {
    const selected = await this.selectOne(context);
    if (selected.length === 0) {
      return undefined;
    }
    return { uri: selected, suggestedName: this.playlistNameOf(selected) };
  }

  async selectImportSources(context: common.UIAbilityContext): Promise<Array<M3uImportSource>> {
    const selected = await this.selectMany(context);
    const sources: Array<M3uImportSource> = [];
    for (let index = 0; index < selected.length; index += 1) {
      sources.push({ uri: selected[index], suggestedName: this.playlistNameOf(selected[index]) });
    }
    return sources;
  }

  async importAsNew(context: common.UIAbilityContext): Promise<M3uImportReport | undefined> {
    const source = await this.selectImportSource(context);
    if (source === undefined) {
      return undefined;
    }
    return this.importSourceAsNew(source);
  }

  async importSourceAsNew(source: M3uImportSource,
    onProgress?: M3uImportProgressListener, importContext?: M3uImportContext): Promise<M3uImportReport> {
    const prepared = await this.prepareImport(source.uri, onProgress, importContext);
    this.requireImportAllowed(prepared, M3uImportMode.MERGE, true);
    onProgress?.(M3uImportStage.WRITING);
    const creation = await this.repository.createImportedPlaylistWithItems(
      source.suggestedName,
      prepared.inputs
    );
    const report = this.importReport(
      prepared,
      creation.playlist.id,
      M3uImportMode.MERGE,
      creation.mutation
    );
    report.playlistName = creation.playlist.name;
    return report;
  }

  async importSource(source: M3uImportSource, playlistId: number, mode: M3uImportMode,
    onProgress?: M3uImportProgressListener, importContext?: M3uImportContext): Promise<M3uImportReport> {
    const prepared = await this.prepareImport(source.uri, onProgress, importContext);
    this.requireImportAllowed(prepared, mode, false);
    onProgress?.(M3uImportStage.WRITING);
    const mutation = mode === M3uImportMode.REPLACE ?
      await this.repository.replaceImportedPlaylistItems(playlistId, prepared.inputs) :
      await this.repository.mergeImportedPlaylistItems(playlistId, prepared.inputs);
    const report = this.importReport(prepared, playlistId, mode, mutation);
    const playlists = await this.repository.getPlaylists(PlaylistSortField.NAME, SortDirection.ASCENDING);
    for (let index = 0; index < playlists.length; index += 1) {
      if (playlists[index].id === playlistId) {
        report.playlistName = playlists[index].name;
        break;
      }
    }
    return report;
  }

  failedImportReport(source: M3uImportSource, error: Object): M3uImportReport {
    const message = error instanceof Error ? error.message : `${error}`;
    const detail = new M3uImportDetail();
    detail.key = 'import_failed';
    detail.status = '导入失败';
    detail.title = source.suggestedName;
    detail.reason = message;
    detail.uri = source.uri;
    detail.failed = true;
    const report = new M3uImportReport();
    report.playlistName = source.suggestedName;
    report.failed = true;
    report.errorMessage = message;
    report.failureDetails = [detail];
    return report;
  }

  createImportContext(): M3uImportContext {
    return new M3uImportContext();
  }

  findNameConflict(source: M3uImportSource, playlists: Array<PlaylistSummary>): PlaylistSummary | undefined {
    for (let index = 0; index < playlists.length; index += 1) {
      if (this.normalized(playlists[index].name) === this.normalized(source.suggestedName)) {
        return playlists[index];
      }
    }
    return undefined;
  }

  async exportPlaylist(context: common.UIAbilityContext, playlist: PlaylistSummary): Promise<boolean> {
    const tracks = await this.repository.getPlaylistTransferTracks(playlist.id);
    const entries: Array<M3uExportEntry> = [];
    for (let index = 0; index < tracks.length; index += 1) {
      const track = tracks[index];
      entries.push({
        resource: track.uri,
        durationSeconds: Math.round(track.durationMs / 1000),
        artist: track.artistDisplay,
        title: track.title,
        album: track.albumDisplay,
        firstCompletedAt: track.firstQualifiedAt > 0 ? track.firstQualifiedAt : null,
        lastCompletedAt: track.lastQualifiedAt > 0 ? track.lastQualifiedAt : null
      });
    }
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`${this.safeFileName(playlist.name)}.m3u8`];
    options.fileSuffixChoices = ['M3U 播放列表|.m3u8,.m3u'];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) {
      return false;
    }
    const bytes = M3uEncoding.encodeUtf8(M3uCodec.serialize(entries), true);
    let file: fileIo.File | undefined;
    try {
      file = await fileIo.open(
        uris[0],
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      let offset = 0;
      while (offset < bytes.byteLength) {
        const chunk = bytes.slice(offset, Math.min(offset + 64 * 1024, bytes.byteLength));
        const written = await fileIo.write(file.fd, chunk.buffer, { length: chunk.byteLength });
        if (written <= 0) {
          throw new Error('播放列表文件未完整写入');
        }
        offset += written;
      }
    } catch (error) {
      throw FileIoSafety.operationError('无法导出播放列表', error);
    } finally {
      await FileIoSafety.close(file, 'playlist export file');
    }
    return true;
  }

  private async prepareImport(uri: string,
    onProgress?: M3uImportProgressListener, importContext?: M3uImportContext): Promise<M3uPreparedImport> {
    onProgress?.(M3uImportStage.READING);
    const parsed = await M3uCodec.parseResponsive(await this.readText(uri));
    const prepared = new M3uPreparedImport();
    prepared.entryCount = parsed.entries.length;
    prepared.issues = parsed.issues;
    prepared.issueDetails = this.issueDetails(parsed.issues, uri);
    if (prepared.issueDetails.length < parsed.issues.length) {
      prepared.detailsTruncated = true;
    }
    if (parsed.entries.length === 0) {
      return prepared;
    }
    onProgress?.(M3uImportStage.MATCHING);
    await this.yieldToUi();
    const sharedContext = importContext ?? this.createImportContext();
    const matcher = await sharedContext.getMatcher((): Promise<M3uImportMatcher> => this.createResponsiveMatcher());
    for (let index = 0; index < parsed.entries.length; index += 1) {
      const entry = parsed.entries[index];
      const track = await matcher.matchResponsive(entry);
      if (track !== undefined) {
        prepared.inputs.push({
          trackId: track.trackId,
          source: PlaylistItemSource.IMPORT,
          qualifiedAt: entry.lastCompletedAt ?? entry.firstCompletedAt ?? 0
        });
        if (prepared.matchedDetails.length < MAX_M3U_REPORT_DETAILS_PER_SECTION) {
          prepared.matchedDetails.push(
            this.matchedDetail(index, entry.resource, track.title, track.artistDisplay, track.uri)
          );
        } else {
          prepared.detailsTruncated = true;
        }
      } else {
        if (prepared.unmatchedDetails.length < MAX_M3U_REPORT_DETAILS_PER_SECTION) {
          prepared.unmatchedDetails.push(this.unmatchedDetail(index, entry.resource, entry.sourceLine));
        } else {
          prepared.detailsTruncated = true;
        }
      }
      if ((index + 1) % MATCH_BATCH_SIZE === 0) {
        await this.yieldToUi();
      }
    }
    return prepared;
  }

  private async createResponsiveMatcher(): Promise<M3uImportMatcher> {
    const matcher = new M3uImportMatcher([]);
    let afterTrackId = 0;
    while (true) {
      const page = await this.repository.getPlaylistTransferCatalogPage(afterTrackId, CATALOG_PAGE_SIZE);
      if (page.length === 0) {
        return matcher;
      }
      await matcher.addTracksResponsive(page);
      afterTrackId = page[page.length - 1].trackId;
      if (page.length < CATALOG_PAGE_SIZE) {
        return matcher;
      }
    }
  }

  private yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }

  private requireImportAllowed(prepared: M3uPreparedImport,
    mode: M3uImportMode, creatingPlaylist: boolean): void {
    const message = M3uImportPolicy.errorMessage(
      prepared.entryCount,
      prepared.inputs.length,
      mode === M3uImportMode.REPLACE,
      creatingPlaylist
    );
    if (message.length > 0) {
      throw new Error(message);
    }
  }

  private importReport(prepared: M3uPreparedImport, playlistId: number,
    mode: M3uImportMode, mutation: PlaylistMutationResult): M3uImportReport {
    const report = new M3uImportReport();
    report.playlistId = playlistId;
    report.mode = mode;
    report.parsed = prepared.entryCount;
    report.matched = prepared.inputs.length;
    report.unmatched = prepared.entryCount - prepared.inputs.length;
    report.inserted = mutation.inserted;
    report.alreadyPresent = mutation.alreadyPresent;
    report.unavailable = mutation.unavailable;
    report.issues = prepared.issues.length;
    report.matchedDetails = prepared.matchedDetails;
    report.unmatchedDetails = prepared.unmatchedDetails;
    report.issueDetails = prepared.issueDetails;
    if (mutation.unavailable > 0) {
      const detail = new M3uImportDetail();
      detail.key = 'commit_unavailable';
      detail.status = '写入跳过';
      detail.title = `${mutation.unavailable} 首歌曲已不可用`;
      detail.reason = '导入期间歌曲已从音乐库移除或变为不可用，未写入播放列表';
      detail.uri = '';
      detail.failed = true;
      report.failureDetails = [detail];
    }
    report.detailsTruncated = prepared.detailsTruncated;
    return report;
  }

  private matchedDetail(index: number, resource: string, title: string, artist: string,
    uri: string): M3uImportDetail {
    const detail = new M3uImportDetail();
    detail.key = `matched_${index}`;
    detail.status = '已匹配';
    detail.title = title;
    detail.reason = artist.length > 0 ? artist : '已在音乐库中找到对应歌曲';
    detail.uri = resource;
    detail.secondaryUri = uri;
    detail.matched = true;
    return detail;
  }

  private unmatchedDetail(index: number, resource: string, line: number): M3uImportDetail {
    const detail = new M3uImportDetail();
    detail.key = `unmatched_${index}`;
    detail.status = '未匹配';
    detail.title = this.normalizedFileName(resource).length > 0 ? this.normalizedFileName(resource) : resource;
    detail.reason = `第 ${line} 行未在音乐库中找到对应歌曲`;
    detail.uri = resource;
    return detail;
  }

  private issueDetails(issues: Array<M3uParseIssue>, uri: string): Array<M3uImportDetail> {
    const details: Array<M3uImportDetail> = [];
    const detailCount = Math.min(issues.length, MAX_M3U_REPORT_DETAILS_PER_SECTION);
    for (let index = 0; index < detailCount; index += 1) {
      const detail = new M3uImportDetail();
      detail.key = `issue_${index}`;
      detail.status = '解析问题';
      detail.title = `第 ${issues[index].line} 行`;
      detail.reason = this.issueReason(issues[index].kind);
      detail.uri = uri;
      detail.failed = true;
      details.push(detail);
    }
    return details;
  }

  private issueReason(kind: M3uIssueKind): string {
    if (kind === M3uIssueKind.INVALID_RESOURCE) {
      return '资源行为空或包含无效字符，已跳过';
    }
    if (kind === M3uIssueKind.INVALID_EXTINF) {
      return 'EXTINF 时长无法解析，歌曲条目仍会尝试匹配';
    }
    return '完成时间无法解析，歌曲条目仍会尝试匹配';
  }

  private async selectOne(context: common.UIAbilityContext): Promise<string> {
    const uris = await this.selectMany(context, 1);
    return uris.length > 0 ? uris[0] : '';
  }

  private async selectMany(context: common.UIAbilityContext, maxSelectNumber: number = 50): Promise<Array<string>> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['M3U 播放列表|.m3u,.m3u8'];
    options.maxSelectNumber = maxSelectNumber;
    return await new picker.DocumentViewPicker(context).select(options);
  }

  private async readText(uri: string): Promise<string> {
    let file: fileIo.File | undefined;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      if (stat.size > MAX_M3U_BYTES) {
        throw new Error('M3U 文件超过 4 MB，已拒绝导入');
      }
      const output = new Uint8Array(stat.size);
      let bytesRead = 0;
      while (bytesRead < stat.size) {
        const chunk = new Uint8Array(Math.min(64 * 1024, stat.size - bytesRead));
        const count = await fileIo.read(file.fd, chunk.buffer, { length: chunk.byteLength });
        if (count <= 0) {
          break;
        }
        output.set(chunk.subarray(0, count), bytesRead);
        bytesRead += count;
      }
      const bytes = output.subarray(0, bytesRead);
      const decision = M3uEncoding.detect(bytes);
      let text = '';
      if (decision.canDecodeDirectly) {
        if (M3uEncoding.hasDecodingErrors(bytes, decision)) {
          throw new Error('M3U 文件编码损坏，无法完整解码');
        }
        text = M3uEncoding.decode(bytes, decision);
      } else {
        text = this.decodeLegacy(bytes, decision);
      }
      const validationError = M3uTextValidation.errorMessage(text);
      if (validationError.length > 0) {
        throw new Error(validationError);
      }
      return text;
    } catch (error) {
      throw FileIoSafety.operationError('无法读取 M3U 文件', error);
    } finally {
      await FileIoSafety.close(file, 'playlist import file');
    }
  }

  private decodeLegacy(bytes: Uint8Array, decision: M3uEncodingDecision): string {
    if (decision.legacyHint.length > 0) {
      try {
        return util.TextDecoder.create(
          decision.legacyHint,
          { fatal: true, ignoreBOM: true }
        ).decodeToString(bytes);
      } catch (_) {
        throw new Error(`无法按文件声明的 ${decision.legacyHint} 编码读取 M3U`);
      }
    }
    let best = '';
    let bestPenalty = Number.MAX_SAFE_INTEGER;
    const equallyLikely = new Set<string>();
    for (let index = 0; index < decision.fallbackLabels.length; index += 1) {
      try {
        const text = util.TextDecoder.create(
          decision.fallbackLabels[index],
          { fatal: true, ignoreBOM: true }
        ).decodeToString(bytes);
        const penalty = this.decodePenalty(text);
        if (penalty < bestPenalty) {
          best = text;
          bestPenalty = penalty;
          equallyLikely.clear();
          equallyLikely.add(text);
        } else if (penalty === bestPenalty) {
          equallyLikely.add(text);
        }
      } catch (_) {
        // The device's ICU build may not include every legacy codec.
      }
    }
    if (best.length === 0 && bytes.length > 0) {
      throw new Error('无法识别 M3U 文件编码');
    }
    if (equallyLikely.size > 1) {
      throw new Error('无法可靠识别 M3U 文件编码，请转换为 UTF-8 或在文件中添加 #EXTENC');
    }
    return best;
  }

  private decodePenalty(value: string): number {
    let penalty = 0;
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code === 0xFFFD) {
        penalty += 20;
      } else if ((code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D) ||
        (code >= 0x7F && code <= 0x9F)) {
        penalty += 5;
      }
    }
    return penalty;
  }

  private normalizedFileName(resource: string): string {
    return M3uImportMatcher.normalizedFileName(resource);
  }

  private normalized(value: string): string {
    return value.trim().toLocaleLowerCase().replace(/\s+/g, ' ');
  }

  private playlistNameOf(uri: string): string {
    const normalizedUri = uri.replace(/\\/g, '/');
    const encodedFileName = normalizedUri.substring(normalizedUri.lastIndexOf('/') + 1);
    let fileName = encodedFileName;
    try {
      fileName = decodeURIComponent(encodedFileName);
    } catch (_) {
      // Keep the picker-provided name if it is not valid percent encoding.
    }
    const withoutExtension = fileName.replace(/\.m3u8?$/i, '').trim();
    return withoutExtension.length > 0 ? withoutExtension : '导入的播放列表';
  }

  private safeFileName(value: string): string {
    const sanitized = value.replace(/[\\/:*?"<>|]/g, '_').trim();
    return sanitized.length > 0 ? sanitized : '播放列表';
  }
}
