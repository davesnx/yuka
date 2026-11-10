import { build, type Metafile } from "esbuild";
import { readFileSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { gzipSync, constants } from "node:zlib";
import { parseArgs } from "node:util";

const { values: options } = parseArgs({
  options: {
    "build-dir": { type: "string", default: process.env.BUILD_DIR ?? "_build" },
    budget: { type: "string", default: "bench/size/budget.json" },
    modules: { type: "boolean", default: false },
  },
});

const root = resolve(import.meta.dirname, "../..");
const buildDir = resolve(root, options["build-dir"]!);
const outDir = join(buildDir, "size");

interface Budget {
  keyed_gzip: number;
}

interface Chunk {
  name: string;
  raw: number;
  gzip: number;
  inputs: Record<string, number>;
}

const gzip = (bytes: Uint8Array) =>
  gzipSync(bytes, { level: constants.Z_BEST_COMPRESSION }).length;

const short = (path: string) =>
  path.replace(/^.*?node_modules\//, "").replace(/^.*?\/out\//, "");

async function bundle(entry: string, out: string, esm: boolean): Promise<Chunk[]> {
  const result = await build({
    entryPoints: [entry],
    bundle: true,
    minify: true,
    define: { __YUKA_DEV__: "false" },
    format: esm ? "esm" : "iife",
    splitting: esm,
    outdir: out,
    write: true,
    metafile: true,
    logLevel: "warning",
  });
  const meta: Metafile = result.metafile;
  return Object.entries(meta.outputs)
    .filter(([file]) => file.endsWith(".js"))
    .map(([file, output]) => {
      const bytes = readFileSync(resolve(root, file));
      const inputs: Record<string, number> = {};
      for (const [input, { bytesInOutput }] of Object.entries(output.inputs))
        if (bytesInOutput > 0) inputs[short(input)] = bytesInOutput;
      return {
        name: file.slice(file.lastIndexOf("/") + 1),
        raw: bytes.length,
        gzip: gzip(bytes),
        inputs,
      };
    })
    .sort((a, b) => b.raw - a.raw);
}

function print(title: string, chunks: Chunk[]) {
  console.log(title);
  for (const c of chunks) {
    console.log(`  ${c.name.padEnd(28)} ${String(c.raw).padStart(8)} B  ${String(c.gzip).padStart(7)} B gzip`);
    if (options.modules)
      for (const [input, bytes] of Object.entries(c.inputs).sort((a, b) => b[1] - a[1]))
        console.log(`      ${input.padEnd(40)} ${String(bytes).padStart(7)} B`);
  }
}

const keyed = await bundle(
  join(buildDir, "default/bench/keyed/yuka/out/bench/keyed/yuka/main.js"),
  join(outDir, "keyed"),
  false,
);
const demo = await bundle(
  join(buildDir, "default/demo/client/out/demo/client/main.js"),
  join(outDir, "demo"),
  true,
);
mkdirSync(outDir, { recursive: true });

print("keyed benchmark app (iife)", keyed);
print("demo client (esm, split)", demo);
const total = demo.reduce((n, c) => n + c.raw, 0);
const totalGzip = demo.reduce((n, c) => n + c.gzip, 0);
console.log(`  ${"all demo chunks".padEnd(28)} ${String(total).padStart(8)} B  ${String(totalGzip).padStart(7)} B gzip`);

const budget: Budget = JSON.parse(readFileSync(resolve(root, options.budget!), "utf8"));
const app = keyed[0]!;
if (app.gzip > budget.keyed_gzip) {
  console.error(
    `size: the keyed benchmark app is ${app.gzip} B gzip, over the budget of ${budget.keyed_gzip} B (${options.budget})`,
  );
  process.exit(1);
}
const devOnly = [
  ...keyed.map((c) => join(outDir, "keyed", c.name)),
  ...demo.map((c) => join(outDir, "demo", c.name)),
].filter((file) => readFileSync(file, "utf8").includes("hydration mismatch"));
if (devOnly.length > 0) {
  console.error(`size: the hydration mismatch log is in a release bundle: ${devOnly.join(", ")}`);
  process.exit(1);
}
console.log(`size: keyed benchmark app ${app.gzip} B gzip, budget ${budget.keyed_gzip} B`);
