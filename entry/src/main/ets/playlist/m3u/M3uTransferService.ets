import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  PlaylistItemInput,
  PlaylistItemSource,
  PlaylistSortField,
  PlaylistSummary,
  SortDirection
} from '../../library/model/LibraryModels';
import { MusicRepository } from '../../library/data/MusicRepository';
import { M3uCodec } from './M3uCodec';
import { M3uEncoding } from './M3uEncoding';
import { M3uEncodingDecision, M3uExportEntry, M3uIssueKind, M3uParseIssue } from './M3uModels';
import { M3uImportMatcher } from './M3uImportMatcher';
import { FileIoSafety } from './FileIoSafety';

const MAX_M3U_BYTES: number = 32 * 1024 * 1024;

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
  issues: number = 0;
  matchedDetails: Array<M3uImportDetail> = [];
  unmatchedDetails: Array<M3uImportDetail> = [];
  issueDetails: Array<M3uImportDetail> = [];
}

export type M3uImportProgressListener = (stage: M3uImportStage) => void;

export class M3uImportContext {
  readonly matcher: M3uImportMatcher;

  constructor(matcher: M3uImportMatcher) {
    this.matcher = matcher;
  }
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
    const playlists = await this.repository.getPlaylists(PlaylistSortField.NAME, SortDirection.ASCENDING);
    const baseName = source.suggestedName;
    const uniqueName = this.uniquePlaylistName(baseName, playlists);
    const playlist = await this.repository.createPlaylist(uniqueName);
    try {
      return await this.importSource(source, playlist.id, M3uImportMode.MERGE, onProgress, importContext);
    } catch (error) {
      try {
        await this.repository.deletePlaylist(playlist.id);
      } catch (cleanupError) {
        console.warn(`Unable to remove failed imported playlist: ` +
          `${cleanupError instanceof Error ? cleanupError.message : `${cleanupError}`}`);
      }
      const message = error instanceof Error ? error.message : `${error}`;
      throw new Error(message);
    }
  }

  async importSource(source: M3uImportSource, playlistId: number, mode: M3uImportMode,
    onProgress?: M3uImportProgressListener, importContext?: M3uImportContext): Promise<M3uImportReport> {
    const report = await this.importUri(source.uri, playlistId, mode, onProgress, importContext);
    const playlists = await this.repository.getPlaylists(PlaylistSortField.NAME, SortDirection.ASCENDING);
    for (let index = 0; index < playlists.length; index += 1) {
      if (playlists[index].id === playlistId) {
        report.playlistName = playlists[index].name;
        break;
      }
    }
    return report;
  }

  async createImportContext(): Promise<M3uImportContext> {
    const catalog = await this.repository.getPlaylistTransferCatalog();
    return new M3uImportContext(new M3uImportMatcher(catalog));
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

  private async importUri(uri: string, playlistId: number, mode: M3uImportMode,
    onProgress?: M3uImportProgressListener, importContext?: M3uImportContext): Promise<M3uImportReport> {
    onProgress?.(M3uImportStage.READING);
    const parsed = M3uCodec.parse(await this.readText(uri));
    onProgress?.(M3uImportStage.MATCHING);
    const matcher = importContext?.matcher ?? (await this.createImportContext()).matcher;
    const inputs: Array<PlaylistItemInput> = [];
    const matchedDetails: Array<M3uImportDetail> = [];
    const unmatchedDetails: Array<M3uImportDetail> = [];
    for (let index = 0; index < parsed.entries.length; index += 1) {
      const entry = parsed.entries[index];
      const track = matcher.match(entry);
      if (track !== undefined) {
        inputs.push({
          trackId: track.trackId,
          source: PlaylistItemSource.IMPORT,
          qualifiedAt: entry.lastCompletedAt ?? entry.firstCompletedAt ?? 0
        });
        matchedDetails.push(this.matchedDetail(index, entry.resource, track.title, track.artistDisplay, track.uri));
      } else {
        unmatchedDetails.push(this.unmatchedDetail(index, entry.resource, entry.sourceLine));
      }
    }
    if (mode === M3uImportMode.REPLACE && parsed.entries.length > 0 && inputs.length === 0) {
      throw new Error('文件中的歌曲均未在音乐库中匹配，已保留原播放列表');
    }
    onProgress?.(M3uImportStage.WRITING);
    const mutation = mode === M3uImportMode.REPLACE ?
      await this.repository.replacePlaylistItems(playlistId, inputs) :
      await this.repository.mergePlaylistItems(playlistId, inputs);
    const report = new M3uImportReport();
    report.playlistId = playlistId;
    report.mode = mode;
    report.parsed = parsed.entries.length;
    report.matched = inputs.length;
    report.unmatched = parsed.entries.length - inputs.length;
    report.inserted = mutation.inserted;
    report.alreadyPresent = mutation.alreadyPresent;
    report.issues = parsed.issues.length;
    report.matchedDetails = matchedDetails;
    report.unmatchedDetails = unmatchedDetails;
    report.issueDetails = this.issueDetails(parsed.issues, uri);
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
    for (let index = 0; index < issues.length; index += 1) {
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
        throw new Error('M3U 文件超过 32 MB，已拒绝导入');
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
      if (decision.canDecodeDirectly) {
        return M3uEncoding.decode(bytes, decision);
      }
      return this.decodeLegacy(bytes, decision);
    } catch (error) {
      throw FileIoSafety.operationError('无法读取 M3U 文件', error);
    } finally {
      await FileIoSafety.close(file, 'playlist import file');
    }
  }

  private decodeLegacy(bytes: Uint8Array, decision: M3uEncodingDecision): string {
    let best = '';
    let bestPenalty = Number.MAX_SAFE_INTEGER;
    for (let index = 0; index < decision.fallbackLabels.length; index += 1) {
      try {
        const text = util.TextDecoder.create(
          decision.fallbackLabels[index],
          { fatal: false, ignoreBOM: true }
        ).decodeToString(bytes);
        const penalty = this.decodePenalty(text);
        if (penalty < bestPenalty) {
          best = text;
          bestPenalty = penalty;
        }
      } catch (_) {
        // The device's ICU build may not include every legacy codec.
      }
    }
    if (best.length === 0 && bytes.length > 0) {
      throw new Error('无法识别 M3U 文件编码');
    }
    return best;
  }

  private decodePenalty(value: string): number {
    let penalty = 0;
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code === 0xFFFD) {
        penalty += 20;
      } else if (code < 0x20 && code !== 0x09 && code !== 0x0A && code !== 0x0D) {
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

  private uniquePlaylistName(base: string, playlists: Array<PlaylistSummary>): string {
    let candidate = base;
    let suffix = 2;
    while (playlists.some((playlist: PlaylistSummary): boolean =>
      this.normalized(playlist.name) === this.normalized(candidate))) {
      candidate = `${base} (${suffix})`;
      suffix += 1;
    }
    return candidate;
  }

  private safeFileName(value: string): string {
    const sanitized = value.replace(/[\\/:*?"<>|]/g, '_').trim();
    return sanitized.length > 0 ? sanitized : '播放列表';
  }
}
