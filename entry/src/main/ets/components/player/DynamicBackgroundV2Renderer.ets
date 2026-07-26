import { image } from '@kit.ImageKit';
import drawing from '@ohos.graphics.drawing';
import { DynamicBackgroundV2Spec } from './DynamicBackgroundV2Spec';

interface DynamicBackgroundV2Sprite {
  sizeRatio: number;
  rotationPerReferenceFrame: number;
  centerX: number;
  centerY: number;
  rotationRadians: number;
}

export class DynamicBackgroundV2Renderer extends DrawModifier {
  private source?: image.PixelMap;
  private elapsedSeconds: number = 0;
  private speed: number = DynamicBackgroundV2Spec.DEFAULT_SPEED;

  update(source: image.PixelMap | undefined, elapsedSeconds: number, speed: number): void {
    this.source = source;
    this.elapsedSeconds = elapsedSeconds;
    this.speed = speed;
    this.invalidate();
  }

  drawBehind(drawContext: DrawContext): void {
    const source = this.source;
    if (source === undefined) {
      return;
    }

    const width = drawContext.sizeInPixel.width;
    const height = drawContext.sizeInPixel.height;
    if (width <= 0 || height <= 0) {
      return;
    }

    const density = drawContext.size.width > 0 ? width / drawContext.size.width : 1;
    const sprites = this.createSprites(width, height);
    const brush = new drawing.Brush();
    drawContext.canvas.attachBrush(brush);
    for (let index = 0; index < sprites.length; index += 1) {
      const sprite = sprites[index];
      drawContext.canvas.drawPixelMapMesh(
        source,
        DynamicBackgroundV2Spec.MESH_SEGMENTS,
        DynamicBackgroundV2Spec.MESH_SEGMENTS,
        this.createTwistedVertices(sprite, width, height,
          DynamicBackgroundV2Spec.TWIST_RADIUS * density),
        0,
        null,
        0
      );
    }
    drawContext.canvas.detachBrush();
  }

  private createSprites(width: number, height: number): Array<DynamicBackgroundV2Sprite> {
    const largeRotation = DynamicBackgroundV2Spec.rotationRadians(
      this.elapsedSeconds,
      DynamicBackgroundV2Spec.LARGE_ROTATION_PER_REFERENCE_FRAME,
      this.speed
    );
    const mediumRotation = DynamicBackgroundV2Spec.rotationRadians(
      this.elapsedSeconds,
      DynamicBackgroundV2Spec.MEDIUM_ROTATION_PER_REFERENCE_FRAME,
      this.speed
    );
    const smallRotation = DynamicBackgroundV2Spec.rotationRadians(
      this.elapsedSeconds,
      DynamicBackgroundV2Spec.SMALL_ROTATION_PER_REFERENCE_FRAME,
      this.speed
    );
    const tinyRotation = DynamicBackgroundV2Spec.rotationRadians(
      this.elapsedSeconds,
      DynamicBackgroundV2Spec.TINY_ROTATION_PER_REFERENCE_FRAME,
      this.speed
    );
    const orbitRadius = width * DynamicBackgroundV2Spec.ORBIT_RADIUS_RATIO;

    return [
      {
        sizeRatio: DynamicBackgroundV2Spec.LARGE_SPRITE_SIZE_RATIO,
        rotationPerReferenceFrame:
          DynamicBackgroundV2Spec.LARGE_ROTATION_PER_REFERENCE_FRAME,
        centerX: width / 2,
        centerY: height / 2,
        rotationRadians: largeRotation
      },
      {
        sizeRatio: DynamicBackgroundV2Spec.MEDIUM_SPRITE_SIZE_RATIO,
        rotationPerReferenceFrame:
          DynamicBackgroundV2Spec.MEDIUM_ROTATION_PER_REFERENCE_FRAME,
        centerX: width / 2.5,
        centerY: height / 2.5,
        rotationRadians: mediumRotation
      },
      {
        sizeRatio: DynamicBackgroundV2Spec.SMALL_SPRITE_SIZE_RATIO,
        rotationPerReferenceFrame:
          DynamicBackgroundV2Spec.SMALL_ROTATION_PER_REFERENCE_FRAME,
        centerX: width / 2 + orbitRadius *
          Math.cos(smallRotation * DynamicBackgroundV2Spec.ORBIT_ANGLE_RATIO),
        centerY: height / 2 + orbitRadius *
          Math.sin(smallRotation * DynamicBackgroundV2Spec.ORBIT_ANGLE_RATIO),
        rotationRadians: smallRotation
      },
      {
        sizeRatio: DynamicBackgroundV2Spec.TINY_SPRITE_SIZE_RATIO,
        rotationPerReferenceFrame:
          DynamicBackgroundV2Spec.TINY_ROTATION_PER_REFERENCE_FRAME,
        centerX: width / 2 + width * DynamicBackgroundV2Spec.TINY_ORBIT_OFFSET_RATIO +
          orbitRadius * Math.cos(tinyRotation * DynamicBackgroundV2Spec.ORBIT_ANGLE_RATIO),
        centerY: height / 2 + width * DynamicBackgroundV2Spec.TINY_ORBIT_OFFSET_RATIO +
          orbitRadius * Math.sin(tinyRotation * DynamicBackgroundV2Spec.ORBIT_ANGLE_RATIO),
        rotationRadians: tinyRotation
      }
    ];
  }

  private createTwistedVertices(sprite: DynamicBackgroundV2Sprite, width: number,
    height: number, twistRadius: number): Array<number> {
    const vertices: Array<number> = [];
    const segments = DynamicBackgroundV2Spec.MESH_SEGMENTS;
    const spriteSize = width * sprite.sizeRatio;
    const spriteCos = Math.cos(sprite.rotationRadians);
    const spriteSin = Math.sin(sprite.rotationRadians);
    const halfWidth = width / 2;
    const halfHeight = height / 2;

    for (let row = 0; row <= segments; row += 1) {
      const localY = (row / segments - 0.5) * spriteSize;
      for (let column = 0; column <= segments; column += 1) {
        const localX = (column / segments - 0.5) * spriteSize;
        const composedX = sprite.centerX + localX * spriteCos - localY * spriteSin;
        const composedY = sprite.centerY + localX * spriteSin + localY * spriteCos;
        const twistedPoint = this.inverseTwist(
          composedX,
          composedY,
          halfWidth,
          halfHeight,
          twistRadius
        );
        vertices.push(twistedPoint[0]);
        vertices.push(twistedPoint[1]);
      }
    }
    return vertices;
  }

  private inverseTwist(x: number, y: number, centerX: number, centerY: number,
    radius: number): Array<number> {
    const offsetX = x - centerX;
    const offsetY = y - centerY;
    const distance = Math.sqrt(offsetX * offsetX + offsetY * offsetY);
    if (distance >= radius || radius <= 0) {
      return [x, y];
    }

    const ratio = (radius - distance) / radius;
    const sourceAngle = ratio * ratio * DynamicBackgroundV2Spec.TWIST_ANGLE_RADIANS;
    const inverseAngle = -sourceAngle;
    const twistCos = Math.cos(inverseAngle);
    const twistSin = Math.sin(inverseAngle);
    return [
      centerX + offsetX * twistCos - offsetY * twistSin,
      centerY + offsetX * twistSin + offsetY * twistCos
    ];
  }
}
