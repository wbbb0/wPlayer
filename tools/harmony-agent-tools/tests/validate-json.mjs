import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(process.argv[2] || path.join(scriptDirectory, ".."));

function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const candidate = path.join(directory, entry.name);
    if (
      entry.isDirectory() &&
      entry.name !== "node_modules" &&
      entry.name !== "artifacts"
    ) {
      walk(candidate);
    } else if (entry.isFile() && candidate.endsWith(".json")) {
      JSON.parse(fs.readFileSync(candidate, "utf8"));
    }
  }
}

walk(root);
