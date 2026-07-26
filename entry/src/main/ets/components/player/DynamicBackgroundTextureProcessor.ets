import { taskpool } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { DynamicBackgroundTextureAlgorithm } from './DynamicBackgroundTextureAlgorithm';

@Concurrent
function processDynamicBackgroundTextureTask(sourceBuffer: ArrayBuffer, sourceWidth: number,
  sourceHeight: number, premultiplied: boolean): ArrayBuffer {
  return DynamicBackgroundTextureAlgorithm.process(
    sourceBuffer, sourceWidth, sourceHeight, premultiplied
  );
}

export class DynamicBackgroundTextureProcessor {
  static async process(source: image.PixelMap): Promise<image.PixelMap> {
    const info = await source.getImageInfo();
    const stride = info.size.width * 4;
    const sourceBuffer = new ArrayBuffer(stride * info.size.height);
    await source.readPixels({
      pixels: sourceBuffer,
      offset: 0,
      stride: stride,
      region: { x: 0, y: 0, size: info.size }
    });
    let processedBuffer: ArrayBuffer;
    try {
      processedBuffer = await taskpool.execute(
        processDynamicBackgroundTextureTask,
        sourceBuffer,
        info.size.width,
        info.size.height,
        info.alphaType === image.AlphaType.PREMUL
      ) as ArrayBuffer;
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      throw new Error(`Unable to process dynamic background texture: ${message}`);
    }
    return image.createPixelMap(processedBuffer, {
      size: {
        width: DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE,
        height: DynamicBackgroundTextureAlgorithm.TEXTURE_SIZE
      },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: false
    });
  }
}
