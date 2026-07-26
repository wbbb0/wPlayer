import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const execFileAsync = promisify(execFile);
const serverDirectory = path.dirname(fileURLToPath(import.meta.url));
const toolRoot = path.resolve(serverDirectory, "..");
const cliPath = path.join(toolRoot, "hdc-agent.ps1");
const artifactsRoot = path.join(toolRoot, "artifacts", "mcp");
const server = new McpServer({
  name: "harmony-agent-tools",
  version: "0.1.0",
});

function resolveHdcPath() {
  const candidates = [
    process.env.HDC_PATH,
    process.env.DEVECO_SDK_HOME &&
      path.join(process.env.DEVECO_SDK_HOME, "default", "openharmony", "toolchains", "hdc.exe"),
    "C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe",
  ].filter(Boolean);
  return candidates.find((candidate) => existsSync(candidate)) || "hdc";
}

const hdcPath = resolveHdcPath();

function deviceArguments(input) {
  if (input.target && input.emulatorName) {
    throw new Error("Specify either target or emulatorName, not both.");
  }
  if (input.target) {
    return ["-HdcPath", hdcPath, "-Target", input.target];
  }
  if (input.emulatorName) {
    return ["-HdcPath", hdcPath, "-EmulatorName", input.emulatorName];
  }
  return ["-HdcPath", hdcPath];
}

function pointArguments(input, prefix = "") {
  const pixelX = prefix ? `${prefix}X` : "x";
  const pixelY = prefix ? `${prefix}Y` : "y";
  const ratioX = prefix ? `${prefix}XRatio` : "xRatio";
  const ratioY = prefix ? `${prefix}YRatio` : "yRatio";
  const cliPrefix = prefix;
  const hasPixels = input[pixelX] !== undefined || input[pixelY] !== undefined;
  const hasRatios = input[ratioX] !== undefined || input[ratioY] !== undefined;
  if (hasPixels === hasRatios) {
    throw new Error(`Specify exactly one coordinate pair for ${prefix || "tap"}.`);
  }
  if (hasPixels) {
    if (input[pixelX] === undefined || input[pixelY] === undefined) {
      throw new Error(`Both ${pixelX} and ${pixelY} are required.`);
    }
    return [`-${cliPrefix}X`, String(input[pixelX]), `-${cliPrefix}Y`, String(input[pixelY])];
  }
  if (input[ratioX] === undefined || input[ratioY] === undefined) {
    throw new Error(`Both ${ratioX} and ${ratioY} are required.`);
  }
  return [
    `-${cliPrefix}XRatio`,
    String(input[ratioX]),
    `-${cliPrefix}YRatio`,
    String(input[ratioY]),
  ];
}

async function invokeCli(command, args = []) {
  try {
    const { stdout, stderr } = await execFileAsync(
      "powershell.exe",
      [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        cliPath,
        command,
        ...args,
      ],
      {
        cwd: toolRoot,
        windowsHide: true,
        maxBuffer: 16 * 1024 * 1024,
        env: {
          ...process.env,
          PATHEXT:
            process.env.PATHEXT ||
            ".COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC;.CPL",
        },
      },
    );
    if (stderr.trim()) {
      throw new Error(stderr.trim());
    }
    return JSON.parse(stdout);
  } catch (error) {
    const detail = error.stderr?.trim() || error.stdout?.trim() || error.message;
    throw new Error(`harmony-agent-tools ${command} failed: ${detail}`, { cause: error });
  }
}

function uniqueImagePath(prefix) {
  const timestamp = new Date().toISOString().replaceAll(/[:.]/g, "-");
  return path.join(artifactsRoot, `${prefix}-${timestamp}-${process.pid}.jpeg`);
}

function imageMimeType(imagePath) {
  return path.extname(imagePath).toLowerCase() === ".png" ? "image/png" : "image/jpeg";
}

async function imageContent(imagePath) {
  const absolutePath = path.resolve(imagePath);
  const data = await readFile(absolutePath);
  return {
    type: "image",
    data: data.toString("base64"),
    mimeType: imageMimeType(absolutePath),
  };
}

function resultText(result) {
  return {
    type: "text",
    text: JSON.stringify(result, null, 2),
  };
}

const targetSchema = {
  target: z.string().min(1).optional(),
  emulatorName: z.string().min(1).optional(),
};

const pointSchema = {
  x: z.number().int().nonnegative().optional(),
  y: z.number().int().nonnegative().optional(),
  xRatio: z.number().min(0).max(1).optional(),
  yRatio: z.number().min(0).max(1).optional(),
};

const movementSchema = {
  startX: z.number().int().optional(),
  startY: z.number().int().optional(),
  endX: z.number().int().optional(),
  endY: z.number().int().optional(),
  startXRatio: z.number().min(0).max(1).optional(),
  startYRatio: z.number().min(0).max(1).optional(),
  endXRatio: z.number().min(0).max(1).optional(),
  endYRatio: z.number().min(0).max(1).optional(),
  durationMs: z.number().int().min(1).max(15000).default(300),
  keepMs: z.number().int().min(0).max(60000).default(0),
};

server.registerTool(
  "harmony_display",
  {
    description: "Return the physical pixel dimensions of a connected HarmonyOS target.",
    inputSchema: targetSchema,
  },
  async (input) => {
    const result = await invokeCli("display", deviceArguments(input));
    return { content: [resultText(result)] };
  },
);

server.registerTool(
  "harmony_screenshot",
  {
    description: "Capture a HarmonyOS display and return the image directly.",
    inputSchema: {
      ...targetSchema,
      outputPath: z.string().min(1).optional(),
      delayMs: z.number().int().min(0).max(3600000).default(0),
    },
  },
  async (input) => {
    await mkdir(artifactsRoot, { recursive: true });
    const outputPath = path.resolve(input.outputPath || uniqueImagePath("screen"));
    const result = await invokeCli("screenshot", [
      ...deviceArguments(input),
      "-OutputPath",
      outputPath,
      "-DelayMs",
      String(input.delayMs),
    ]);
    return { content: [resultText(result), await imageContent(result.path)] };
  },
);

server.registerTool(
  "harmony_tap",
  {
    description: "Tap using pixel or normalized coordinates, optionally returning a screenshot.",
    inputSchema: {
      ...targetSchema,
      ...pointSchema,
      pressMs: z.number().int().min(1).max(450).default(100),
      capture: z.boolean().default(true),
      captureDelayMs: z.number().int().min(0).max(3600000).default(150),
    },
  },
  async (input) => {
    const selector = deviceArguments(input);
    const result = await invokeCli("tap", [
      ...selector,
      ...pointArguments(input),
      "-PressMs",
      String(input.pressMs),
    ]);
    const content = [resultText(result)];
    if (input.capture) {
      await mkdir(artifactsRoot, { recursive: true });
      const screenshot = await invokeCli("screenshot", [
        ...selector,
        "-OutputPath",
        uniqueImagePath("tap"),
        "-DelayMs",
        String(input.captureDelayMs),
      ]);
      content.push(resultText(screenshot), await imageContent(screenshot.path));
    }
    return { content };
  },
);

server.registerTool(
  "harmony_swipe",
  {
    description: "Swipe using pixel or normalized coordinates, optionally returning a screenshot.",
    inputSchema: {
      ...targetSchema,
      ...movementSchema,
      capture: z.boolean().default(true),
      captureDelayMs: z.number().int().min(0).max(3600000).default(150),
    },
  },
  async (input) => {
    const selector = deviceArguments(input);
    const result = await invokeCli("swipe", [
      ...selector,
      ...pointArguments(input, "start"),
      ...pointArguments(input, "end"),
      "-DurationMs",
      String(input.durationMs),
      "-KeepMs",
      String(input.keepMs),
    ]);
    const content = [resultText(result)];
    if (input.capture) {
      await mkdir(artifactsRoot, { recursive: true });
      const screenshot = await invokeCli("screenshot", [
        ...selector,
        "-OutputPath",
        uniqueImagePath("swipe"),
        "-DelayMs",
        String(input.captureDelayMs),
      ]);
      content.push(resultText(screenshot), await imageContent(screenshot.path));
    }
    return { content };
  },
);

server.registerTool(
  "harmony_gesture_capture",
  {
    description: "Perform a swipe and return images captured at requested millisecond offsets.",
    inputSchema: {
      ...targetSchema,
      ...movementSchema,
      captureAtMs: z.array(z.number().int().min(0).max(3600000)).min(1),
      prefix: z.string().min(1).default("gesture"),
      outputDirectory: z.string().min(1).optional(),
    },
  },
  async (input) => {
    const outputDirectory = path.resolve(
      input.outputDirectory || path.join(artifactsRoot, `gesture-${Date.now()}`),
    );
    const result = await invokeCli("gesture-capture", [
      ...deviceArguments(input),
      ...pointArguments(input, "start"),
      ...pointArguments(input, "end"),
      "-DurationMs",
      String(input.durationMs),
      "-KeepMs",
      String(input.keepMs),
      "-CaptureAtMs",
      input.captureAtMs.join(","),
      "-Prefix",
      input.prefix,
      "-OutputDirectory",
      outputDirectory,
    ]);
    return {
      content: [
        resultText(result),
        ...(await Promise.all(result.artifacts.map((artifact) => imageContent(artifact.path)))),
      ],
    };
  },
);

server.registerTool(
  "harmony_compare_images",
  {
    description: "Compare two images and return metrics plus an optional visual diff image.",
    inputSchema: {
      baselinePath: z.string().min(1),
      actualPath: z.string().min(1),
      differencePath: z.string().min(1).optional(),
      pixelTolerance: z.number().int().min(0).max(255).default(0),
      maxDifferenceRatio: z.number().min(0).max(1).default(0),
      maxMeanError: z.number().min(0).max(1).default(0),
    },
  },
  async (input) => {
    const differencePath = path.resolve(input.differencePath || uniqueImagePath("difference"));
    const result = await invokeCli("compare-images", [
      "-BaselinePath",
      path.resolve(input.baselinePath),
      "-ActualPath",
      path.resolve(input.actualPath),
      "-DifferencePath",
      differencePath,
      "-PixelTolerance",
      String(input.pixelTolerance),
      "-MaxDifferenceRatio",
      String(input.maxDifferenceRatio),
      "-MaxMeanError",
      String(input.maxMeanError),
    ]);
    return { content: [resultText(result), await imageContent(result.difference)] };
  },
);

export { imageContent, invokeCli };

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
