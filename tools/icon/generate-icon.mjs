import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import sharp from 'sharp';

const toolDir = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(toolDir, '..', '..');
const sourceDir = path.join(toolDir, 'source');
const outputDir = path.join(toolDir, 'preview');
const resourceDirs = [
  path.join(rootDir, 'AppScope', 'resources', 'base', 'media'),
  path.join(rootDir, 'entry', 'src', 'main', 'resources', 'base', 'media')
];

const iconSize = 1024;
const startIconSize = 144;
const backgroundSvg = path.join(sourceDir, 'background.svg');
const foregroundSvg = path.join(sourceDir, 'foreground.svg');

await mkdir(outputDir, { recursive: true });

const background = await sharp(backgroundSvg, { density: 192 })
  .resize(iconSize, iconSize)
  .png()
  .toBuffer();
const foreground = await sharp(foregroundSvg, { density: 192 })
  .resize(iconSize, iconSize)
  .png()
  .toBuffer();
const composite = await sharp(background)
  .composite([{ input: foreground }])
  .png()
  .toBuffer();

for (const resourceDir of resourceDirs) {
  await sharp(background).toFile(path.join(resourceDir, 'background.png'));
  await sharp(foreground).toFile(path.join(resourceDir, 'foreground.png'));
}

await sharp(composite).toFile(path.join(outputDir, 'wplayer-icon-square.png'));
await sharp(composite)
  .resize(startIconSize, startIconSize)
  .png()
  .toFile(path.join(resourceDirs[1], 'startIcon.png'));

console.log('Generated wPlayer layered icons and startIcon.png.');
