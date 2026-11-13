import { bundle as release } from "../../scripts/bundle.ts";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { gzipSync, constants } from "node:zlib";
import { parseArgs } from "node:util";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import type { Metafile } from "esbuild";

const { values: options } = parseArgs({
  options: {
    "build-dir": { type: "string", default: process.env.BUILD_DIR ?? "_build" },
    budget: { type: "string", default: "bench/size/budget.json" },
    modules: { type: "boolean", default: false },
    pages: { type: "string", default: "/,/my,/new,/issue/YUK-1,/about,/insights" },
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
  file: string;
  raw: number;
  gzip: number;
  inputs: Record<string, number>;
}

interface Bundle {
  chunks: Chunk[];
  meta: Metafile;
}

const gzip = (bytes: Uint8Array) =>
  gzipSync(bytes, { level: constants.Z_BEST_COMPRESSION }).length;

const short = (path: string) =>
  path.replace(/^.*?node_modules\//, "").replace(/^.*?\/out\//, "");

async function bundle(entry: string, out: string, esm: boolean): Promise<Bundle> {
  const meta = await release({ entry, outdir: out, format: esm ? "esm" : "iife", splitting: esm, cwd: root });
  const chunks = Object.entries(meta.outputs)
    .filter(([file]) => file.endsWith(".js"))
    .map(([file, output]) => {
      const bytes = readFileSync(resolve(root, file));
      const inputs: Record<string, number> = {};
      for (const [input, { bytesInOutput }] of Object.entries(output.inputs))
        if (bytesInOutput > 0) inputs[short(input)] = bytesInOutput;
      return {
        name: file.slice(file.lastIndexOf("/") + 1),
        file,
        raw: bytes.length,
        gzip: gzip(bytes),
        inputs,
      };
    })
    .sort((a, b) => b.raw - a.raw);
  return { chunks, meta };
}

const row = (name: string, raw: number, gzip: number) =>
  `  ${name.padEnd(28)} ${String(raw).padStart(8)} B  ${String(gzip).padStart(7)} B gzip`;

function print(title: string, chunks: Chunk[]) {
  console.log(title);
  for (const c of chunks) {
    console.log(row(c.name, c.raw, c.gzip));
    if (options.modules)
      for (const [input, bytes] of Object.entries(c.inputs).sort((a, b) => b[1] - a[1]))
        console.log(`      ${input.padEnd(40)} ${String(bytes).padStart(7)} B`);
  }
}

function outputOf(b: Bundle, entry: string): string {
  const entryPoint = realpathSync(entry);
  const file = Object.entries(b.meta.outputs).find(
    ([, o]) => o.entryPoint !== undefined && realpathSync(resolve(root, o.entryPoint)) === entryPoint,
  )?.[0];
  if (file === undefined) throw new Error(`size: no output chunk for entry point ${entry}`);
  return file;
}

function startSet(b: Bundle, entryPoints: string[]): Chunk[] {
  const seen = new Set<string>();
  const queue = entryPoints.map((e) => outputOf(b, e));
  while (queue.length > 0) {
    const file = queue.pop()!;
    if (seen.has(file)) continue;
    seen.add(file);
    for (const i of b.meta.outputs[file]!.imports) if (i.kind === "import-statement") queue.push(i.path);
  }
  return b.chunks.filter((c) => seen.has(c.file));
}

const sum = (chunks: Chunk[]) => ({
  raw: chunks.reduce((n, c) => n + c.raw, 0),
  gzip: chunks.reduce((n, c) => n + c.gzip, 0),
  files: chunks.map((c) => c.name).join(" "),
});

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function freePort(): Promise<number> {
  return new Promise((ok, fail) => {
    const probe = createServer();
    probe.once("error", fail);
    probe.listen(0, "127.0.0.1", () => {
      const address = probe.address();
      const port = typeof address === "object" && address !== null ? address.port : 0;
      probe.close(() => (port > 0 ? ok(port) : fail(new Error("size: no free port"))));
    });
  });
}

async function get(url: string): Promise<Response> {
  try {
    return await fetch(url, { signal: AbortSignal.timeout(10_000) });
  } catch (e) {
    throw new Error(`size: GET ${url} failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}

async function pageScripts(paths: string[]): Promise<Map<string, string[]>> {
  const exe = join(buildDir, "default/demo/server/demo_server.exe");
  if (!existsSync(exe)) throw new Error(`size: ${exe} does not exist; build it with: dune build @demo/all`);
  const port = await freePort();
  const nonce = randomBytes(16).toString("hex");
  const staticDir = mkdtempSync(join(tmpdir(), "yuka-size-"));
  writeFileSync(join(staticDir, `${nonce}.txt`), nonce);
  const server = spawn(exe, ["--port", String(port), "--static-dir", staticDir], { stdio: "ignore" });
  let failure: Error | undefined;
  server.once("error", (e) => (failure = e));
  const stop = () => {
    if (server.exitCode === null && server.signalCode === null) server.kill();
  };
  const interrupt = () => {
    stop();
    process.exit(130);
  };
  process.once("exit", stop);
  process.once("SIGINT", interrupt);
  process.once("SIGTERM", interrupt);
  try {
    const deadline = Date.now() + 20_000;
    let base = "";
    while (base === "") {
      if (failure !== undefined) throw new Error(`size: cannot start ${exe}: ${failure.message}`);
      if (server.exitCode !== null) throw new Error(`size: demo server exited with ${server.exitCode}`);
      for (const host of ["127.0.0.1", "[::1]"]) {
        const own = await fetch(`http://${host}:${port}/static/${nonce}.txt`, { signal: AbortSignal.timeout(2_000) }).then(
          async (r) => r.ok && (await r.text()) === nonce,
          () => false,
        );
        if (own) {
          base = `http://${host}:${port}`;
          break;
        }
      }
      if (base !== "") break;
      if (Date.now() > deadline) throw new Error(`size: the demo server did not answer on port ${port} within 20 s`);
      await wait(100);
    }
    const result = new Map<string, string[]>();
    for (const path of paths) {
      const response = await get(base + path);
      if (!response.ok) throw new Error(`size: GET ${path} answered ${response.status}`);
      const html = await response.text();
      const urls = [
        ...[...html.matchAll(/<script\b[^>]*\btype="module"[^>]*\bsrc="([^"]+)"/g)].map((m) => m[1]!),
        ...[...html.matchAll(/<link\b[^>]*\brel="modulepreload"[^>]*\bhref="([^"]+)"/g)].map((m) => m[1]!),
      ];
      result.set(
        path,
        urls.map((u) => {
          const pathname = new URL(u, base).pathname;
          if (!pathname.startsWith("/_yuka/app/")) throw new Error(`size: ${path} loads ${u}, outside /_yuka/app/`);
          return join(buildDir, "default/demo/client/out", pathname.slice("/_yuka/app/".length));
        }),
      );
    }
    return result;
  } finally {
    stop();
    process.removeListener("exit", stop);
    process.removeListener("SIGINT", interrupt);
    process.removeListener("SIGTERM", interrupt);
    rmSync(staticDir, { recursive: true, force: true });
  }
}

const keyed = await bundle(
  join(buildDir, "default/bench/keyed/yuka/out/bench/keyed/yuka/main.js"),
  join(outDir, "keyed"),
  false,
);
const demoMain = join(buildDir, "default/demo/client/out/demo/client/main.js");
const demo = await bundle(demoMain, join(outDir, "demo"), true);
const fixtures = [
  { dir: "page", island: "counter", title: "page: counter island" },
  { dir: "codec_page", island: "tags", title: "page: Codec props island" },
  { dir: "remote_page", island: "items", title: "page: Remote island" },
];
const pages = [];
for (const f of fixtures) {
  const dir = join(buildDir, `default/bench/size/${f.dir}/client/out/bench/size/${f.dir}`);
  const b = await bundle(join(dir, "client/main.js"), join(outDir, f.dir), true);
  pages.push({ ...f, bundle: b, start: sum(startSet(b, [join(dir, "client/main.js"), join(dir, `shared/${f.island}.js`)])) });
}
mkdirSync(outDir, { recursive: true });

console.log("method: scripts/bundle.ts (esbuild --bundle --minify, then swc minify)");
print("keyed benchmark app (iife)", keyed.chunks);
print("demo client (esm, split)", demo.chunks);
const all = sum(demo.chunks);
console.log(row("all demo chunks", all.raw, all.gzip));

console.log("JavaScript loaded at start (each file gzip on its own, summed)");
for (const p of pages) console.log(`${row(p.title, p.start.raw, p.start.gzip)}  ${p.start.files}`);
const start = sum(startSet(demo, [demoMain]));
console.log(`${row("demo main and its imports", start.raw, start.gzip)}  ${start.files}`);
for (const [path, entries] of await pageScripts(options.pages!.split(","))) {
  const s = sum(startSet(demo, entries));
  console.log(`${row(`demo ${path}`, s.raw, s.gzip)}  ${s.files}`);
}

const budget: Budget = JSON.parse(readFileSync(resolve(root, options.budget!), "utf8"));
const app = keyed.chunks[0]!;
const remoteOnly = [
  "yuka/remote.js",
  "yuka/answers.js",
  "yuka/optimistic.js",
  "yuka/status.js",
  "yuka/form.js",
  "yuka/live.js",
  "yuka/live_server.js",
  "yuka/topic.js",
];
const leaked = remoteOnly.filter((m) => keyed.chunks.some((c) => m in c.inputs));
if (keyed.chunks.some((c) => readFileSync(join(outDir, "keyed", c.name), "utf8").includes("WebSocket")))
  leaked.push("WebSocket");
if (leaked.length > 0) {
  console.error(`size: the keyed app uses neither remote data, live data nor forms but contains ${leaked.join(", ")}`);
  process.exit(1);
}
const serverOnly = [...keyed.chunks, ...demo.chunks, ...pages.flatMap((p) => p.bundle.chunks)]
  .filter((c) => "yuka/printer.js" in c.inputs)
  .map((c) => c.name);
if (serverOnly.length > 0) {
  console.error(`size: the server printer is in a client chunk: ${serverOnly.join(", ")}`);
  process.exit(1);
}
if (app.gzip > budget.keyed_gzip) {
  console.error(
    `size: the keyed benchmark app is ${app.gzip} B gzip, over the budget of ${budget.keyed_gzip} B (${options.budget})`,
  );
  process.exit(1);
}
const devOnly = [
  ...keyed.chunks.map((c) => join(outDir, "keyed", c.name)),
  ...demo.chunks.map((c) => join(outDir, "demo", c.name)),
  ...pages.flatMap((p) => p.bundle.chunks.map((c) => join(outDir, p.dir, c.name))),
].filter((file) => readFileSync(file, "utf8").includes("hydration mismatch"));
if (devOnly.length > 0) {
  console.error(`size: the hydration mismatch log is in a release bundle: ${devOnly.join(", ")}`);
  process.exit(1);
}
console.log(`size: keyed benchmark app ${app.gzip} B gzip, budget ${budget.keyed_gzip} B`);
