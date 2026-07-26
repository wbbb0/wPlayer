import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const directory = path.dirname(fileURLToPath(import.meta.url));
const emulatorName = process.argv[2] || "Pura 90";
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(directory, "server.mjs")],
});
const client = new Client({
  name: "harmony-agent-tools-device-integration",
  version: "0.1.0",
});

try {
  await client.connect(transport);
  const result = await client.callTool({
    name: "harmony_screenshot",
    arguments: { emulatorName },
  });
  const image = result.content.find((item) => item.type === "image");
  assert.ok(
    image,
    `MCP response did not include image content: ${JSON.stringify(result)}`,
  );
  assert.equal(image.mimeType, "image/jpeg");
  assert.ok(image.data.length > 1000, "MCP image payload is unexpectedly small.");
  const tapResult = await client.callTool({
    name: "harmony_tap",
    arguments: {
      emulatorName,
      xRatio: 0.5,
      yRatio: 0.5,
      capture: true,
      captureDelayMs: 100,
    },
  });
  const tapImage = tapResult.content.find((item) => item.type === "image");
  assert.ok(
    tapImage,
    `Normalized tap response did not include image content: ${JSON.stringify(tapResult)}`,
  );
  assert.equal(tapImage.mimeType, "image/jpeg");
  process.stdout.write(
    `${JSON.stringify({
      result: "PASS",
      emulatorName,
      mimeType: image.mimeType,
      base64Bytes: image.data.length,
      normalizedTapImageBytes: tapImage.data.length,
    })}\n`,
  );
} finally {
  await transport.close();
}
