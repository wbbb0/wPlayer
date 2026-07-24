import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  unifiedDataChannel,
  uniformTypeDescriptor
} from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import {
  EmbeddedArtwork,
  MediaFormat,
  TrackDetail
} from '../model/LibraryModels';
import { ensureReadPermission } from '../importer/MediaPickerService';
import { readAuthorizedArtworkBytesAsync } from '../metadata/MediaFileTasks';

export interface ExportedEmbeddedArtwork {
  path: string;
  uri: string;
  extension: string;
  mimeType: string;
}

export class EmbeddedArtworkService {
  private readonly context: common.UIAbilityContext;
  // Picker-backed document URIs can block when several taskpool workers open the
  // same authorized file concurrently. Keep original-byte reads ordered per page.
  private readTail: Promise<void> = Promise.resolve();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async decode(
    detail: TrackDetail,
    artwork: EmbeddedArtwork,
    maxEdge: number
  ): Promise<image.PixelMap> {
    const buffer = await this.read(detail, artwork);
    const source = image.createImageSource(buffer);
    try {
      const info = await source.getImageInfo();
      const longest = Math.max(info.size.width, info.size.height);
      const scale = longest > maxEdge ? maxEdge / longest : 1;
      return await source.createPixelMapUsingAllocator({
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      }, image.AllocatorType.SHARE_MEMORY);
    } catch (error) {
      throw new Error(`无法解码内嵌封面：${EmbeddedArtworkService.messageOf(error)}`);
    } finally {
      try {
        await source.release();
      } catch (error) {
        console.warn(`Unable to release embedded artwork image source: ` +
          `${EmbeddedArtworkService.messageOf(error)}`);
      }
    }
  }

  async exportOriginal(
    detail: TrackDetail,
    artwork: EmbeddedArtwork
  ): Promise<ExportedEmbeddedArtwork> {
    let file: fs.File | undefined;
    try {
      const buffer = await this.read(detail, artwork);
      const extension = EmbeddedArtworkService.extensionOf(artwork.mimeType, buffer);
      const directory = `${this.context.cacheDir.replace(/\\/g, '/')}/embedded_artwork_exports`;
      if (!await fs.access(directory)) {
        await fs.mkdir(directory, true);
      }
      const baseName = EmbeddedArtworkService.safeFileName(detail.title);
      const path = `${directory}/${baseName}-${detail.id}-${artwork.ordinal + 1}.${extension}`;
      file = await fs.open(
        path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      fs.writeSync(file.fd, buffer);
      return {
        path: path,
        uri: fileUri.getUriFromPath(path),
        extension: extension,
        mimeType: artwork.mimeType.length > 0 ? artwork.mimeType : `image/${extension}`
      };
    } catch (error) {
      throw new Error(`无法准备原始封面文件：${EmbeddedArtworkService.messageOf(error)}`);
    } finally {
      if (file !== undefined) {
        try {
          await fs.close(file);
        } catch (error) {
          console.warn(`Unable to close embedded artwork export: ` +
            `${EmbeddedArtworkService.messageOf(error)}`);
        }
      }
    }
  }

  async unifiedData(
    detail: TrackDetail,
    artwork: EmbeddedArtwork
  ): Promise<unifiedDataChannel.UnifiedData> {
    const exported = await this.exportOriginal(detail, artwork);
    const record = new unifiedDataChannel.Image();
    record.imageUri = exported.uri;
    return new unifiedDataChannel.UnifiedData(record);
  }

  async share(detail: TrackDetail, artwork: EmbeddedArtwork): Promise<void> {
    try {
      const exported = await this.exportOriginal(detail, artwork);
      const data = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.IMAGE,
        uri: exported.uri,
        title: `${detail.title} · 封面 ${artwork.ordinal + 1}`,
        description: artwork.description
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (error) {
      throw new Error(`无法打开系统分享：${EmbeddedArtworkService.messageOf(error)}`);
    }
  }

  async save(detail: TrackDetail, artwork: EmbeddedArtwork): Promise<void> {
    let sourceFile: fs.File | undefined;
    let destinationFile: fs.File | undefined;
    try {
      const exported = await this.exportOriginal(detail, artwork);
      const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const destinations = await helper.showAssetsCreationDialog(
        [exported.path],
        [{
          title: `${EmbeddedArtworkService.safeFileName(detail.title)}-封面-${artwork.ordinal + 1}`,
          fileNameExtension: exported.extension,
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }]
      );
      if (destinations.length > 0) {
        sourceFile = await fs.open(exported.path, fs.OpenMode.READ_ONLY);
        destinationFile = await fs.open(destinations[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(sourceFile.fd, destinationFile.fd);
      }
    } catch (error) {
      throw new Error(`无法保存封面：${EmbeddedArtworkService.messageOf(error)}`);
    } finally {
      if (sourceFile !== undefined) {
        await EmbeddedArtworkService.closeFile(sourceFile, 'source save file');
      }
      if (destinationFile !== undefined) {
        await EmbeddedArtworkService.closeFile(destinationFile, 'destination save file');
      }
    }
  }

  async copy(pixelMap: image.PixelMap): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
      await pasteboard.getSystemPasteboard().setData(data);
    } catch (error) {
      throw new Error(`无法写入剪贴板：${EmbeddedArtworkService.messageOf(error)}`);
    }
  }

  static dragDataLoadParams(
    service: EmbeddedArtworkService,
    detail: TrackDetail,
    artwork: EmbeddedArtwork
  ): unifiedDataChannel.DataLoadParams {
    return {
      loadHandler: (): unifiedDataChannel.UnifiedData | null => null,
      delayedDataLoadHandler: async (): Promise<unifiedDataChannel.UnifiedData | null> =>
        service.unifiedData(detail, artwork),
      dataLoadInfo: {
        types: new Set<string>([uniformTypeDescriptor.UniformDataType.IMAGE]),
        recordCount: 1
      }
    };
  }

  private read(detail: TrackDetail, artwork: EmbeddedArtwork): Promise<ArrayBuffer> {
    if (detail.uri.length === 0 || artwork.byteLength <= 0) {
      return Promise.reject(new Error('这张封面没有可读取的原始图片数据'));
    }
    const pending = this.readTail.then(async (): Promise<ArrayBuffer> => {
      // Persisting a Picker URI does not keep its read permission active for
      // every later process lifetime. Match playback by activating it before
      // opening the source file.
      if (!await ensureReadPermission(detail.uri)) {
        throw new Error('音乐文件授权已失效，请重新导入该文件');
      }
      return readAuthorizedArtworkBytesAsync(
        detail.uri,
        artwork.byteOffset,
        artwork.byteLength,
        artwork.payloadOffset,
        detail.format === MediaFormat.MP3 && artwork.unsynchronized
      );
    });
    this.readTail = pending.then((): void => {}, (): void => {});
    return pending;
  }

  private static safeFileName(value: string): string {
    const safe = value.trim().replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ');
    return safe.length > 0 ? safe.substring(0, 80) : '歌曲封面';
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private static async closeFile(file: fs.File, label: string): Promise<void> {
    try {
      await fs.close(file);
    } catch (error) {
      console.warn(`Unable to close embedded artwork ${label}: ${EmbeddedArtworkService.messageOf(error)}`);
    }
  }

  private static extensionOf(mimeType: string, buffer: ArrayBuffer): string {
    const normalized = mimeType.toLowerCase();
    if (normalized.includes('png')) {
      return 'png';
    }
    if (normalized.includes('webp')) {
      return 'webp';
    }
    if (normalized.includes('gif')) {
      return 'gif';
    }
    if (normalized.includes('heif') || normalized.includes('heic')) {
      return 'heic';
    }
    if (normalized.includes('bmp')) {
      return 'bmp';
    }
    if (normalized.includes('jpeg') || normalized.includes('jpg')) {
      return 'jpg';
    }
    const bytes = new Uint8Array(buffer);
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4E && bytes[3] === 0x47) {
      return 'png';
    }
    if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return 'gif';
    }
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
      bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'webp';
    }
    return 'jpg';
  }
}
