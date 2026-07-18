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
import { M3uEncodingDecision, M3uExportEntry } from './M3uModels';
import { M3uImportMatcher } from './M3uImportMatcher';
import { FileIoSafety } from './FileIoSafety';

const MAX_M3U_BYTES: number = 32 * 1024 * 1024;

export enum M3uImportMode {
  MERGE = 0,
  REPLACE = 1
}

export class M3uImportReport {
  playlistId: number = -1;
  parsed: number = 0;
  matched: number = 0;
  unmatched: number = 0;
  inserted: number = 0;
  alreadyPresent: number = 0;
  issues: number = 0;
}

export class M3uTransferService {
  private readonly repository: MusicRepository;

  constructor(repository: MusicRepository) {
    this.repository = repository;
  }

  async importInto(context: common.UIAbilityContext, playlistId: number,
    mode: M3uImportMode): Promise<M3uImportReport | undefined> {
    const selected = await this.selectOne(context);
    if (selected.length === 0) {
      return undefined;
    }
    return this.importUri(selected, playlistId, mode);
  }

  async importAsNew(context: common.UIAbilityContext): Promise<M3uImportReport | undefined> {
    const selected = await this.selectOne(context);
    if (selected.length === 0) {
      return undefined;
    }
    const playlists = await this.repository.getPlaylists(PlaylistSortField.NAME, SortDirection.ASCENDING);
    const baseName = this.playlistNameOf(selected);
    const uniqueName = this.uniquePlaylistName(baseName, playlists);
    const playlist = await this.repository.createPlaylist(uniqueName);
    try {
      return await this.importUri(selected, playlist.id, M3uImportMode.MERGE);
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

  private async importUri(uri: string, playlistId: number, mode: M3uImportMode): Promise<M3uImportReport> {
    const parsed = M3uCodec.parse(await this.readText(uri));
    const catalog = await this.repository.getPlaylistTransferCatalog();
    const matcher = new M3uImportMatcher(catalog);
    const inputs: Array<PlaylistItemInput> = [];
    for (let index = 0; index < parsed.entries.length; index += 1) {
      const entry = parsed.entries[index];
      const track = matcher.match(entry);
      if (track !== undefined) {
        inputs.push({
          trackId: track.trackId,
          source: PlaylistItemSource.IMPORT,
          qualifiedAt: entry.lastCompletedAt ?? entry.firstCompletedAt ?? 0
        });
      }
    }
    if (mode === M3uImportMode.REPLACE && parsed.entries.length > 0 && inputs.length === 0) {
      throw new Error('文件中的歌曲均未在音乐库中匹配，已保留原播放列表');
    }
    const mutation = mode === M3uImportMode.REPLACE ?
      await this.repository.replacePlaylistItems(playlistId, inputs) :
      await this.repository.mergePlaylistItems(playlistId, inputs);
    const report = new M3uImportReport();
    report.playlistId = playlistId;
    report.parsed = parsed.entries.length;
    report.matched = inputs.length;
    report.unmatched = parsed.entries.length - inputs.length;
    report.inserted = mutation.inserted;
    report.alreadyPresent = mutation.alreadyPresent;
    report.issues = parsed.issues.length;
    return report;
  }

  private async selectOne(context: common.UIAbilityContext): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['M3U 播放列表|.m3u,.m3u8'];
    options.maxSelectNumber = 1;
    const uris = await new picker.DocumentViewPicker(context).select(options);
    return uris.length > 0 ? uris[0] : '';
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
