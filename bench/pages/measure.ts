import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { loadavg } from "node:os";
import { gzipSync } from "node:zlib";
import { parseArgs } from "node:util";
import { chromium, type Browser } from "playwright-core";

const { values: options } = parseArgs({
  options: {
    "build-dir": { type: "string", default: process.env.BUILD_DIR ?? "_build" },
    runs: { type: "string", default: "5" },
    throttle: { type: "string", default: "4" },
    port: { type: "string", default: "8124" },
    pages: { type: "string", default: "/,/my,/issue/YUK-1,/about" },
    out: { type: "string" },
    chrome: { type: "string", default: process.env.CHROME_PATH ?? "" },
  },
});

const runs = Number(options.runs);
const throttle = Number(options.throttle);
if (!Number.isInteger(runs) || runs < 1) throw new Error(`--runs must be a positive integer, got ${options.runs}`);
if (!(throttle >= 1)) throw new Error(`--throttle must be at least 1, got ${options.throttle}`);
const buildDir = resolve(options["build-dir"]);
const out = options.out ?? join(buildDir, "measure-pages", "result.json");
const paths = options.pages.split(",");
const base = `http://127.0.0.1:${options.port}`;

interface Bytes {
  raw: number;
  gzip: number;
}

interface Js {
  files: { url: string; raw: number; gzip: number }[];
  external: Bytes;
  inline: Bytes;
  total: Bytes;
}

interface Timing {
  lcp: number;
  tbt: number;
}

interface PageResult {
  path: string;
  islands: number;
  js: Js;
  page: Timing & { runs: Timing[] };
  plain: Timing & { runs: Timing[] };
}

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));
const gz = (s: Buffer | string) => gzipSync(s, { level: 9 }).length;

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 === 1 ? s[m] : (s[m - 1] + s[m]) / 2;
}

const executable = (attrs: string) => {
  const type = /\btype\s*=\s*["']?([^"'\s>]+)/i.exec(attrs)?.[1]?.toLowerCase();
  return type === undefined || type === "module" || type.includes("javascript");
};

function inlineScripts(html: string): string[] {
  return [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
    .filter(([, attrs, body]) => !/\bsrc\s*=/i.test(attrs) && executable(attrs) && body.length > 0)
    .map(([, , body]) => body);
}

const plainHtml = (html: string) =>
  html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "").replace(/<link\b[^>]*rel\s*=\s*["']?modulepreload["']?[^>]*>/gi, "");

async function jsBytes(browser: Browser, url: string, html: string): Promise<Js> {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  try {
    const page = await context.newPage();
    const pending: Promise<{ url: string; body: Buffer } | null>[] = [];
    page.on("response", (r) => {
      const type = r.headers()["content-type"] ?? "";
      if (r.request().resourceType() === "script" || type.includes("javascript"))
        pending.push(r.body().then((body) => ({ url: r.url(), body }), () => null));
    });
    await page.goto(url, { waitUntil: "networkidle" });
    await wait(1000);
    const seen = new Map<string, Buffer>();
    for (const r of await Promise.all(pending)) if (r !== null) seen.set(r.url, r.body);
    const files = [...seen].map(([u, body]) => ({ url: new URL(u).pathname, raw: body.length, gzip: gz(body) }));
    const inline = inlineScripts(html);
    const external = { raw: files.reduce((s, f) => s + f.raw, 0), gzip: files.reduce((s, f) => s + f.gzip, 0) };
    const inlineBytes = { raw: inline.reduce((s, b) => s + Buffer.byteLength(b), 0), gzip: inline.length === 0 ? 0 : gz(inline.join("")) };
    return {
      files,
      external,
      inline: inlineBytes,
      total: { raw: external.raw + inlineBytes.raw, gzip: external.gzip + inlineBytes.gzip },
    };
  } finally {
    await context.close();
  }
}

const observe = `
  window.__measure = { lcp: 0, fcp: 0, long: [] };
  new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__measure.lcp = e.startTime; })
    .observe({ type: "largest-contentful-paint", buffered: true });
  new PerformanceObserver((l) => { for (const e of l.getEntries()) if (e.name === "first-contentful-paint") window.__measure.fcp = e.startTime; })
    .observe({ type: "paint", buffered: true });
  new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__measure.long.push([e.startTime, e.duration]); })
    .observe({ type: "longtask", buffered: true });
`;

async function timing(browser: Browser, url: string, plain: string | null): Promise<Timing> {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  try {
    const page = await context.newPage();
    if (plain !== null)
      await page.route(url, (route) => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: plain }));
    await page.addInitScript(observe);
    const cdp = await context.newCDPSession(page);
    await cdp.send("Emulation.setCPUThrottlingRate", { rate: throttle });
    await page.goto(url, { waitUntil: "networkidle" });
    await wait(2000);
    const m = (await page.evaluate("window.__measure")) as { lcp: number; fcp: number; long: [number, number][] };
    const tbt = m.long.filter(([start]) => start >= m.fcp).reduce((s, [, d]) => s + Math.max(0, d - 50), 0);
    return { lcp: m.lcp, tbt };
  } finally {
    await context.close();
  }
}

async function timings(browser: Browser, url: string, plain: string | null): Promise<Timing & { runs: Timing[] }> {
  const samples: Timing[] = [];
  for (let i = 0; i < runs; i++) samples.push(await timing(browser, url, plain));
  return { lcp: median(samples.map((s) => s.lcp)), tbt: median(samples.map((s) => s.tbt)), runs: samples };
}

const server = spawn(join(buildDir, "default/demo/server/demo_server.exe"), ["--port", options.port, "--bundle"], { stdio: "ignore" });
const stop = () => server.kill();
process.on("exit", stop);
for (let i = 0; ; i++) {
  if (server.exitCode !== null) throw new Error(`demo server exited with ${server.exitCode}`);
  if (await fetch(`${base}/about`).then((r) => r.ok, () => false)) break;
  if (i > 100) throw new Error("demo server did not start");
  await wait(100);
}

const loadBefore = loadavg();
const browser = await chromium.launch({ executablePath: options.chrome === "" ? undefined : options.chrome });
const browserVersion = browser.version();
const results: PageResult[] = [];
try {
  for (const path of paths) {
    const url = base + path;
    const html = await (await fetch(url)).text();
    const js = await jsBytes(browser, url, html);
    const pageTiming = await timings(browser, url, null);
    const plainTiming = await timings(browser, url, plainHtml(html));
    results.push({ path, islands: (html.match(/<yuka-island\b/g) ?? []).length, js, page: pageTiming, plain: plainTiming });
    console.error(`${path}: done`);
  }
} finally {
  await browser.close();
  stop();
}
const loadAfter = loadavg();

const zeroJs = results.filter((r) => r.islands === 0);
const checks = zeroJs.map((r) => ({ path: r.path, ok: r.js.total.raw === 0, bytes: r.js.total.raw }));
if (checks.length === 0) checks.push({ path: "(no page without island)", ok: false, bytes: NaN });

const ms = (x: number) => x.toFixed(0);
const row = (cols: string[]) => cols.map((c, i) => (i === 0 ? c.padEnd(16) : c.padStart(12))).join("");
const lines = [
  `${browserVersion}, CPU throttle ${throttle}x, ${runs} runs, median ms; JS bytes are raw/gzip -9; load average ${loadBefore.map((x) => x.toFixed(0)).join(" ")} -> ${loadAfter.map((x) => x.toFixed(0)).join(" ")}`,
  "",
  row(["page", "islands", "JS files", "JS raw", "JS gzip", "inline raw", "TBT", "LCP", "plain LCP"]),
  ...results.map((r) =>
    row([r.path, String(r.islands), String(r.js.files.length), String(r.js.external.raw), String(r.js.external.gzip), String(r.js.inline.raw), ms(r.page.tbt), ms(r.page.lcp), ms(r.plain.lcp)]),
  ),
  "",
  ...checks.map((c) => `${c.ok ? "PASS" : "FAIL"}  0 bytes of JavaScript on ${c.path}${c.ok ? "" : ` (${c.bytes} bytes)`}`),
];
console.log(lines.join("\n"));

mkdirSync(dirname(resolve(out)), { recursive: true });
writeFileSync(
  out,
  JSON.stringify({ date: new Date().toISOString(), browser: browserVersion, throttle, runs, loadavg: { before: loadBefore, after: loadAfter }, pages: results, zeroJs: checks }, null, 2) + "\n",
);
console.error(`wrote ${out}`);
process.exitCode = checks.every((c) => c.ok) ? 0 : 1;
