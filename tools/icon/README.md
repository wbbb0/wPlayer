# wPlayer icon source

The launcher icon is intentionally drawn without an outer rounded rectangle. HarmonyOS applies the launcher mask;
adding a second rounded canvas here would produce a visible double border.

The foreground uses a blue optical disc rather than a letter, music note, or play glyph. Its top-left rim, concentric
tracks, spectral wedges, and hub highlights provide content-edge depth similar to the dimensional system icon treatment.

Regenerate all launcher resources from the SVG source:

```powershell
npm install --prefix tools/icon
npm run generate --prefix tools/icon
```

The script updates the `background.png` and `foreground.png` copies in both `AppScope` and `entry`, updates the
startup icon, and writes a square preview to `tools/icon/preview`. The preview is not launcher-masked by design.
