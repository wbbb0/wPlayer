import { image } from '@kit.ImageKit';
import { MusicRepository } from '../data/MusicRepository';
import {
  EmbeddedArtwork,
  SortDirection,
  TrackDetail,
  TrackSortField
} from '../model/LibraryModels';
import { encodeArtworkWebP } from '../metadata/MediaFileTasks';
import { ArtworkEncodingPolicy } from './ArtworkEncodingPolicy';
import { EmbeddedArtworkService } from './EmbeddedArtworkService';
import {
  ThumbnailBenchmarkMethod,
  ThumbnailBenchmarkOptions,
  ThumbnailBenchmarkPolicy
} from './ThumbnailBenchmarkPolicy';

export interface ThumbnailBenchmarkProgress {
  method: ThumbnailBenchmarkMethod;
  methodIndex: number;
  methodCount: number;
  completed: number;
  total: number;
}

export interface ThumbnailBenchmarkMethodResult {
  method: ThumbnailBenchmarkMethod;
  successCount: number;
  failureCount: number;
  averageTotalMs: number;
  averageEncodingMs: number;
}

export interface ThumbnailBenchmarkReport {
  requestedCount: number;
  sampledCount: number;
  maxEdge: number;
  averageReadMs: number;
  averageDecodeMs: number;
  averageScaleMs: number;
  averagePreparationMs: number;
  results: Array<ThumbnailBenchmarkMethodResult>;
}

interface ThumbnailBenchmarkSource {
  detail: TrackDetail;
  artwork?: EmbeddedArtwork;
}

interface ThumbnailBenchmarkAccumulator {
  method: ThumbnailBenchmarkMethod;
  successCount: number;
  failureCount: number;
  totalDurationMs: number;
  encodingDurationMs: number;
}

interface PreparedThumbnail {
  pixelMap: image.PixelMap;
  durationMs: number;
  readMs: number;
  decodeMs: number;
  scaleMs: number;
}

export class ThumbnailBenchmarkRunner {
  private readonly repository: MusicRepository;
  private readonly artworkService: EmbeddedArtworkService;

  constructor(repository: MusicRepository, artworkService: EmbeddedArtworkService) {
    this.repository = repository;
    this.artworkService = artworkService;
  }

  async run(options: ThumbnailBenchmarkOptions,
    onProgress?: (progress: ThumbnailBenchmarkProgress) => void): Promise<ThumbnailBenchmarkReport> {
    if (options.methods.length === 0) {
      throw new Error('请至少选择一种 thumbnail 类型');
    }
    if (!ThumbnailBenchmarkPolicy.isSupportedResolution(options.maxEdge)) {
      throw new Error(`不支持的 thumbnail 分辨率：${options.maxEdge}`);
    }
    const requestedCount = ThumbnailBenchmarkPolicy.normalizeSampleCount(options.sampleCount);
    const tracks = await this.repository.getTrackPlaybackOrder(
      TrackSortField.TITLE,
      SortDirection.ASCENDING
    );
    const sampledTracks = ThumbnailBenchmarkPolicy.sample(tracks, requestedCount);
    if (sampledTracks.length === 0) {
      throw new Error('音乐库里没有可测试的歌曲');
    }
    const sources: Array<ThumbnailBenchmarkSource> = [];
    for (let index = 0; index < sampledTracks.length; index += 1) {
      const detail = await this.repository.getTrackDetail(sampledTracks[index].id);
      if (detail !== undefined) {
        sources.push({ detail: detail, artwork: detail.artworks[0] });
      }
    }
    if (sources.length === 0) {
      throw new Error('随机歌曲样本无法读取');
    }

    const accumulators: Array<ThumbnailBenchmarkAccumulator> = options.methods.map(
      (method: ThumbnailBenchmarkMethod): ThumbnailBenchmarkAccumulator => ({
        method: method,
        successCount: 0,
        failureCount: 0,
        totalDurationMs: 0,
        encodingDurationMs: 0
      })
    );
    let preparationDurationMs = 0;
    let readDurationMs = 0;
    let decodeDurationMs = 0;
    let scaleDurationMs = 0;
    let preparationCount = 0;
    for (let sourceIndex = 0; sourceIndex < sources.length; sourceIndex += 1) {
      let prepared: PreparedThumbnail | undefined;
      try {
        const artwork = sources[sourceIndex].artwork;
        if (artwork === undefined) {
          throw new Error('歌曲没有内嵌封面');
        }
        prepared = await this.prepare(sources[sourceIndex].detail, artwork, options.maxEdge);
        preparationDurationMs += prepared.durationMs;
        readDurationMs += prepared.readMs;
        decodeDurationMs += prepared.decodeMs;
        scaleDurationMs += prepared.scaleMs;
        preparationCount += 1;
        for (let methodIndex = 0; methodIndex < accumulators.length; methodIndex += 1) {
          const encodingStartedAt = Date.now();
          try {
            await ThumbnailBenchmarkRunner.encode(
              accumulators[methodIndex].method,
              prepared.pixelMap
            );
            const encodingMs = Date.now() - encodingStartedAt;
            accumulators[methodIndex].successCount += 1;
            accumulators[methodIndex].encodingDurationMs += encodingMs;
            accumulators[methodIndex].totalDurationMs += prepared.durationMs + encodingMs;
          } catch (error) {
            accumulators[methodIndex].failureCount += 1;
            console.warn(`Thumbnail benchmark encoder failed: ${ThumbnailBenchmarkRunner.messageOf(error)}`);
          }
          onProgress?.({
            method: accumulators[methodIndex].method,
            methodIndex: methodIndex,
            methodCount: accumulators.length,
            completed: sourceIndex + 1,
            total: sources.length
          });
        }
      } catch (error) {
        console.warn(`Thumbnail benchmark preparation failed: ${ThumbnailBenchmarkRunner.messageOf(error)}`);
        for (let methodIndex = 0; methodIndex < accumulators.length; methodIndex += 1) {
          accumulators[methodIndex].failureCount += 1;
          onProgress?.({
            method: accumulators[methodIndex].method,
            methodIndex: methodIndex,
            methodCount: accumulators.length,
            completed: sourceIndex + 1,
            total: sources.length
          });
        }
      } finally {
        if (prepared !== undefined) {
          try {
            await prepared.pixelMap.release();
          } catch (error) {
            console.warn(`Unable to release benchmark PixelMap: ${ThumbnailBenchmarkRunner.messageOf(error)}`);
          }
        }
      }
    }
    const results: Array<ThumbnailBenchmarkMethodResult> = accumulators.map(
      (value: ThumbnailBenchmarkAccumulator): ThumbnailBenchmarkMethodResult => ({
        method: value.method,
        successCount: value.successCount,
        failureCount: value.failureCount,
        averageTotalMs: ThumbnailBenchmarkPolicy.average(value.totalDurationMs, value.successCount),
        averageEncodingMs: ThumbnailBenchmarkPolicy.average(
          value.encodingDurationMs,
          value.successCount
        )
      })
    );
    return {
      requestedCount: requestedCount,
      sampledCount: sources.length,
      maxEdge: options.maxEdge,
      averageReadMs: ThumbnailBenchmarkPolicy.average(readDurationMs, preparationCount),
      averageDecodeMs: ThumbnailBenchmarkPolicy.average(decodeDurationMs, preparationCount),
      averageScaleMs: ThumbnailBenchmarkPolicy.average(scaleDurationMs, preparationCount),
      averagePreparationMs: ThumbnailBenchmarkPolicy.average(
        preparationDurationMs,
        preparationCount
      ),
      results: results
    };
  }

  private async prepare(detail: TrackDetail, artwork: EmbeddedArtwork,
    maxEdge: number): Promise<PreparedThumbnail> {
    const startedAt = Date.now();
    const readStartedAt = Date.now();
    const sourceBytes = await this.artworkService.readOriginal(detail, artwork);
    const readMs = Date.now() - readStartedAt;
    const source = image.createImageSource(sourceBytes);
    let pixelMap: image.PixelMap | undefined;
    try {
      const info = await source.getImageInfo();
      const targetSize = ArtworkEncodingPolicy.targetSize(
        info.size.width,
        info.size.height,
        maxEdge
      );
      const decodeStartedAt = Date.now();
      pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const decodeMs = Date.now() - decodeStartedAt;
      const actualInfo = await pixelMap.getImageInfo();
      const scaleStartedAt = Date.now();
      if (actualInfo.size.width !== targetSize.width || actualInfo.size.height !== targetSize.height) {
        await pixelMap.scale(
          targetSize.width / actualInfo.size.width,
          targetSize.height / actualInfo.size.height,
          image.AntiAliasingLevel.HIGH
        );
      }
      const scaleMs = Date.now() - scaleStartedAt;
      const prepared: PreparedThumbnail = {
        pixelMap: pixelMap,
        durationMs: Date.now() - startedAt,
        readMs: readMs,
        decodeMs: decodeMs,
        scaleMs: scaleMs
      };
      pixelMap = undefined;
      return prepared;
    } catch (error) {
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
      throw new Error(ThumbnailBenchmarkRunner.messageOf(error));
    } finally {
      await source.release();
    }
  }

  private static encode(method: ThumbnailBenchmarkMethod, pixelMap: image.PixelMap): Promise<void> {
    return method === ThumbnailBenchmarkMethod.SYSTEM_JPEG ?
      ThumbnailBenchmarkRunner.encodeSystemJpeg(pixelMap) :
      ThumbnailBenchmarkRunner.encodeCppWebP(pixelMap);
  }

  private static async encodeSystemJpeg(pixelMap: image.PixelMap): Promise<void> {
    const packer = image.createImagePacker();
    try {
      const encoded = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: ArtworkEncodingPolicy.QUALITY
      });
      if (encoded.byteLength === 0) {
        throw new Error('系统 JPEG 编码器返回空数据');
      }
    } catch (error) {
      throw new Error(`系统 JPEG 编码失败：${ThumbnailBenchmarkRunner.messageOf(error)}`);
    } finally {
      await packer.release();
    }
  }

  private static async encodeCppWebP(pixelMap: image.PixelMap): Promise<void> {
    const info = await pixelMap.getImageInfo();
    const stride = info.size.width * 4;
    const pixels = new ArrayBuffer(stride * info.size.height);
    await pixelMap.readPixels({
      pixels: pixels,
      offset: 0,
      stride: stride,
      region: { x: 0, y: 0, size: info.size }
    });
    const encoded = await encodeArtworkWebP(
      pixels,
      info.size.width,
      info.size.height,
      info.alphaType === image.AlphaType.PREMUL,
      ArtworkEncodingPolicy.QUALITY,
      ArtworkEncodingPolicy.METHOD,
      ArtworkEncodingPolicy.ALPHA_QUALITY
    );
    if (encoded.byteLength === 0) {
      throw new Error('C++ WebP 编码器返回空数据');
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
