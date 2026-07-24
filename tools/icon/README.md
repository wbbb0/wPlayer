# wPlayer icon source

The launcher icon is intentionally drawn without an outer rounded rectangle. HarmonyOS applies the launcher mask;
adding a second rounded canvas here would produce a visible double border.

The foreground uses a simple blue optical disc rather than a letter, music note, or play glyph. A restrained material
gradient, one subtle groove and a luminous object-edge rim keep it dimensional while remaining legible at small sizes.

The white launcher background is kept as SVG source in `source/background.svg`. `source/browser-white-background.svg`
keeps the same browser-style white paper gradient as a named reference copy.

Regenerate all launcher resources from the SVG source:

```powershell
npm install --prefix tools/icon
npm run generate --prefix tools/icon
```

The script updates the `background.png` and `foreground.png` copies in both `AppScope` and `entry`, writes a transparent
256px `startIcon.png`, and writes a square preview to `tools/icon/preview`. The preview is not launcher-masked by design.
