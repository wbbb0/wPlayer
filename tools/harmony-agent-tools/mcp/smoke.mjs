import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { imageContent } from "./server.mjs";

const directory = await mkdtemp(path.join(os.tmpdir(), "harmony-agent-tools-mcp-"));
const imagePath = path.join(directory, "one-pixel.png");
await writeFile(
  imagePath,
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
    "base64",
  ),
);
const content = await imageContent(imagePath);
assert.equal(content.type, "image");
assert.equal(content.mimeType, "image/png");
assert.ok(content.data.length > 0);
process.stdout.write(`${JSON.stringify({ result: "PASS", checks: 3 })}\n`);
