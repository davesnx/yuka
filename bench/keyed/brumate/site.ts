import { copyFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";

interface Chunk {
  file: string;
  src?: string;
  imports?: string[];
}

const { values } = parseArgs({ options: { dist: { type: "string" }, out: { type: "string" } } });
if (values.dist === undefined || values.out === undefined) throw new Error("usage: site.ts --dist <vite client outDir> --out <dir>");
const dist = values.dist;
const out = values.out;
const base = "/brumate/";

const html = readFileSync(join(dist, "index.html"), "utf8");
const manifest = JSON.parse(readFileSync(join(dist, ".vite/manifest.json"), "utf8")) as Record<string, Chunk>;
const byFile = new Map(Object.entries(manifest).map(([key, chunk]) => [chunk.file, key]));

const keep = new Set<string>();
function add(key: string): void {
  if (keep.has(key)) return;
  const chunk = manifest[key];
  if (chunk === undefined) throw new Error(`${key} is not in the manifest`);
  keep.add(key);
  for (const k of chunk.imports ?? []) add(k);
}

for (const [, url] of html.matchAll(/(?:href|src|b-load)="([^"]+\.js)"/g)) {
  if (!url.startsWith(base)) throw new Error(`${url} is outside ${base}`);
  const key = byFile.get(url.slice(base.length));
  if (key === undefined) throw new Error(`${url} is not in the manifest`);
  add(key);
}

const files = ["index.html", ...[...keep].map((k) => manifest[k].file)];
for (const f of files) {
  mkdirSync(dirname(join(out, f)), { recursive: true });
  copyFileSync(join(dist, f), join(out, f));
}
console.log(files.join("\n"));
