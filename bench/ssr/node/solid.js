import { transformFileSync } from "@babel/core";
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const out = `${here}node_modules/.cache/solid.js`;
const { code } = transformFileSync(`${here}solid.jsx`, {
  cwd: here,
  babelrc: false,
  configFile: false,
  presets: [["babel-preset-solid", { generate: "ssr", hydratable: false }]],
});
mkdirSync(`${here}node_modules/.cache`, { recursive: true });
writeFileSync(out, code);
await import(pathToFileURL(out).href);
