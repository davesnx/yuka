import { createServer } from "node:http";
import { readFileSync, readdirSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { join, extname, dirname, resolve, relative, sep } from "node:path";
import { gzipSync, brotliCompressSync, constants as zlib } from "node:zlib";
import { parseArgs } from "node:util";
import { chromium, type Browser, type Page } from "playwright-core";

const allApps = ["vanillajs", "solid", "yuka"] as const;
type App = (typeof allApps)[number];

interface Bench {
  id: string;
  label: string;
  warmup: number;
  throttle: number;
  extraRuns: number;
  weight: number;
  init: (page: Page) => Promise<void>;
  run: (page: Page) => Promise<void>;
}

interface TraceEvent {
  name: string;
  ph: string;
  ts: number;
  dur?: number;
  pid: number;
  args?: { data?: { type?: string } };
}

interface Timed {
  type: string;
  ts: number;
  end: number;
  pid: number;
}

interface Sample {
  total: number;
  script: number;
  paint: number;
}

interface Size {
  files: string[];
  raw: number;
  gzip: number;
  brotli: number;
}

const { values: options } = parseArgs({
  options: {
    site: { type: "string", default: join(process.env.BUILD_DIR ?? "_build", "bench-keyed") },
    runs: { type: "string", default: "10" },
    apps: { type: "string", default: allApps.join(",") },
    benchmarks: { type: "string", default: "" },
    out: { type: "string" },
    chrome: { type: "string", default: process.env.CHROME_PATH ?? "" },
    headed: { type: "boolean", default: false },
  },
});

const runs = Number(options.runs);
if (!Number.isInteger(runs) || runs < 1) throw new Error(`--runs must be a positive integer, got ${options.runs}`);
const site = resolve(options.site);
if (!statSync(site, { throwIfNoEntry: false })?.isDirectory()) {
  throw new Error(`${site} is not a directory; build it with "make bench-keyed" or bench/keyed/build.sh`);
}
const apps: App[] = options.apps.split(",").map((a) => {
  const app = allApps.find((x) => x === a);
  if (!app) throw new Error(`unknown app ${a}; known: ${allApps.join(", ")}`);
  return app;
});

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

async function poll(what: string, check: () => Promise<boolean>): Promise<void> {
  for (let k = 0; k < 10; k++) {
    if (await check()) return;
    await wait(k < 3 ? 10 : 1000);
  }
  throw new Error(`timeout: ${what}`);
}

const exists = (page: Page, selector: string) =>
  poll(`${selector} exists`, () => page.evaluate((s) => document.querySelector(s) !== null, selector));

const notExists = (page: Page, selector: string) =>
  poll(`${selector} does not exist`, () => page.evaluate((s) => document.querySelector(s) === null, selector));

const hasText = (page: Page, selector: string, text: string) =>
  poll(`${selector} contains ${JSON.stringify(text)}`, () =>
    page.evaluate(
      ([s, t]) => {
        const e = document.querySelector<HTMLElement>(s);
        return e !== null && e.innerText.includes(t);
      },
      [selector, text] as const,
    ),
  );

const hasClass = (page: Page, selector: string, name: string) =>
  poll(`${selector} has class ${name}`, () =>
    page.evaluate(([s, c]) => document.querySelector(s)?.classList.contains(c) === true, [selector, name] as const),
  );

async function count(page: Page, selector: string, expected: number): Promise<void> {
  const n = await page.evaluate((s) => document.querySelectorAll(s).length, selector);
  if (n !== expected) throw new Error(`${selector}: expected ${expected} elements, found ${n}`);
}

async function click(page: Page, selector: string): Promise<void> {
  const point = await page.evaluate((s) => {
    const e = document.querySelector(s);
    if (e === null) return null;
    let r = e.getBoundingClientRect();
    if (r.top < 0 || r.bottom > window.innerHeight) {
      e.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
      r = e.getBoundingClientRect();
    }
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }, selector);
  if (point === null) throw new Error(`click: ${selector} not found`);
  await page.mouse.click(point.x, point.y);
}

const cell = (row: number, col: number) => `tbody>tr:nth-of-type(${row})>td:nth-of-type(${col})`;

async function createClearWarmup(page: Page, warmup: number): Promise<void> {
  await exists(page, "#run");
  for (let i = 0; i < warmup; i++) {
    await click(page, "#run");
    await hasText(page, cell(1, 1), (i * 1000 + 1).toFixed());
    await click(page, "#clear");
    await notExists(page, cell(1000, 1));
  }
}

const benchmarks: Bench[] = [
  {
    id: "01_run1k",
    label: "create 1,000 rows",
    warmup: 5,
    throttle: 1,
    extraRuns: 0,
    weight: 0.64280248137063,
    async init(page) {
      await createClearWarmup(page, this.warmup);
    },
    async run(page) {
      await click(page, "#run");
      await hasText(page, cell(1000, 1), ((this.warmup + 1) * 1000).toFixed());
    },
  },
  {
    id: "02_replace1k",
    label: "replace all 1,000 rows",
    warmup: 5,
    throttle: 1,
    extraRuns: 0,
    weight: 0.5607178150466176,
    async init(page) {
      await exists(page, "#run");
      for (let i = 0; i < this.warmup; i++) {
        await click(page, "#run");
        await hasText(page, cell(1, 1), (i * 1000 + 1).toFixed());
      }
    },
    async run(page) {
      await click(page, "#run");
      await hasText(page, cell(1, 1), `${this.warmup * 1000 + 1}`);
    },
  },
  {
    id: "03_update10th1k_x16",
    label: "partial update, every 10th of 1,000 rows",
    warmup: 3,
    throttle: 4,
    extraRuns: 0,
    weight: 0.5643800750716564,
    async init(page) {
      await exists(page, "#run");
      await click(page, "#run");
      await exists(page, cell(1000, 1));
      for (let i = 0; i < this.warmup; i++) {
        await click(page, "#update");
        await hasText(page, `${cell(991, 2)}>a`, " !!!".repeat(i + 1));
      }
    },
    async run(page) {
      await click(page, "#update");
      await hasText(page, `${cell(991, 2)}>a`, " !!!".repeat(this.warmup + 1));
    },
  },
  {
    id: "04_select1k",
    label: "select row",
    warmup: 5,
    throttle: 4,
    extraRuns: 10,
    weight: 0.1925635870170522,
    async init(page) {
      await exists(page, "#run");
      await click(page, "#run");
      await hasText(page, cell(1000, 1), "1000");
      await click(page, `${cell(5, 2)}>a`);
      await hasClass(page, "tbody>tr:nth-of-type(5)", "danger");
      await count(page, "tbody>tr.danger", 1);
    },
    async run(page) {
      await click(page, `${cell(2, 2)}>a`);
      await hasClass(page, "tbody>tr:nth-of-type(2)", "danger");
    },
  },
  {
    id: "05_swap1k",
    label: "swap rows",
    warmup: 5,
    throttle: 4,
    extraRuns: 0,
    weight: 0.13200612879341714,
    async init(page) {
      await exists(page, "#run");
      await click(page, "#run");
      await exists(page, cell(1000, 1));
      for (let i = 0; i <= this.warmup; i++) {
        await click(page, "#swaprows");
        await hasText(page, cell(999, 1), i % 2 === 0 ? "2" : "999");
      }
    },
    async run(page) {
      await click(page, "#swaprows");
      await hasText(page, cell(999, 1), this.warmup % 2 === 0 ? "999" : "2");
      await hasText(page, cell(2, 1), this.warmup % 2 === 0 ? "2" : "999");
    },
  },
  {
    id: "06_remove-one-1k",
    label: "remove row",
    warmup: 5,
    throttle: 2,
    extraRuns: 0,
    weight: 0.5277091212292658,
    async init(page) {
      const skip = 4;
      await exists(page, "#run");
      await click(page, "#run");
      await exists(page, cell(1000, 1));
      for (let i = 0; i < this.warmup; i++) {
        const row = this.warmup - i + skip;
        await hasText(page, cell(row, 1), row.toString());
        await click(page, `${cell(row, 3)}>a>span:nth-of-type(1)`);
        await hasText(page, cell(row, 1), `${skip + this.warmup + 1}`);
      }
      await hasText(page, cell(skip + 1, 1), `${skip + this.warmup + 1}`);
      await hasText(page, cell(skip, 1), `${skip}`);
      await hasText(page, cell(skip + 2, 1), `${skip + this.warmup + 2}`);
      await click(page, `${cell(skip + 2, 3)}>a>span:nth-of-type(1)`);
      await hasText(page, cell(skip + 2, 1), `${skip + this.warmup + 3}`);
    },
    async run(page) {
      const skip = 4;
      await click(page, `${cell(skip, 3)}>a>span:nth-of-type(1)`);
      await hasText(page, cell(skip, 1), `${skip + this.warmup + 1}`);
    },
  },
  {
    id: "07_create10k",
    label: "create 10,000 rows",
    warmup: 5,
    throttle: 1,
    extraRuns: 0,
    weight: 0.5644449600965534,
    async init(page) {
      await createClearWarmup(page, this.warmup);
    },
    async run(page) {
      await click(page, "#runlots");
      await exists(page, `${cell(10000, 2)}>a`);
    },
  },
  {
    id: "08_create1k-after1k_x2",
    label: "append 1,000 rows to 1,000",
    warmup: 5,
    throttle: 1,
    extraRuns: 0,
    weight: 0.5508359820582848,
    async init(page) {
      await createClearWarmup(page, this.warmup);
      await click(page, "#run");
      await exists(page, cell(1000, 1));
    },
    async run(page) {
      await click(page, "#add");
      await exists(page, cell(2000, 1));
    },
  },
  {
    id: "09_clear1k_x8",
    label: "clear 1,000 rows",
    warmup: 5,
    throttle: 4,
    extraRuns: 0,
    weight: 0.4225836631419211,
    async init(page) {
      await createClearWarmup(page, this.warmup);
      await click(page, "#run");
      await hasText(page, cell(1, 1), (this.warmup * 1000 + 1).toFixed());
    },
    async run(page) {
      await click(page, "#clear");
      await notExists(page, cell(1000, 1));
    },
  },
];

const selected = options.benchmarks === "" ? benchmarks : benchmarks.filter((b) => options.benchmarks.split(",").some((p) => b.id.startsWith(p)));
if (selected.length === 0) throw new Error(`no benchmark matches ${options.benchmarks}`);

const timelineEvents: Record<string, string> = {
  Layout: "layout",
  FunctionCall: "functioncall",
  HitTest: "hittest",
  Commit: "commit",
  Paint: "paint",
  FireAnimationFrame: "fireAnimationFrame",
};

function relevantEvents(entries: TraceEvent[]): Timed[] {
  const out: Timed[] = [];
  const add = (type: string, e: TraceEvent, dur: number) => out.push({ type, ts: e.ts, end: e.ts + dur, pid: e.pid });
  for (const e of entries) {
    if (e.name === "EventDispatch") {
      const type = e.args?.data?.type;
      if (type === "click") {
        add("startLogicEvent", e, e.dur ?? 0);
        add("click", e, e.dur ?? 0);
      } else if (type === "mousedown" || type === "pointerup") add(type, e, e.dur ?? 0);
    } else if (e.ph === "X" && e.name in timelineEvents) {
      add(timelineEvents[e.name], e, e.dur ?? 0);
    } else if (e.name === "TimerFire" && e.ph === "X") {
      add("timerFire", e, 0);
    } else if (e.name === "RequestAnimationFrame") {
      add("requestAnimationFrame", e, 0);
    }
  }
  return out.sort((a, b) => a.end - b.end);
}

class NotOneClick extends Error {}

function totalDuration(entries: TraceEvent[]): { start: number; end: number; duration: number } {
  const events = relevantEvents(entries);
  const clicks = events.filter((e) => e.type === "startLogicEvent");
  if (clicks.length !== 1) throw new NotOneClick(`exactly one click event is expected, found ${clicks.length}`);
  const click = clicks[0];
  const during = events.filter((e) => e.ts > click.end || e.type === "click");
  const main = during.filter((e) => e.pid === click.pid);
  const startFrom = main.filter((e) => ["click", "fireAnimationFrame", "timerFire", "layout", "functioncall"].includes(e.type)).at(-1);
  if (startFrom === undefined) throw new Error("no event after the click");
  const commits = main.filter((e) => e.type === "commit");
  const commit = commits.find((e) => e.ts > startFrom.end) ?? commits.at(-1);
  if (commit === undefined) throw new Error("no commit event after the click");
  let duration = (commit.end - click.ts) / 1000;
  const layouts = main.filter((e) => e.type === "layout");
  const rafs = events.filter((e) => e.type === "requestAnimationFrame" && e.ts >= click.ts && e.ts <= click.end);
  const fafs = events.filter((e) => e.type === "fireAnimationFrame" && e.ts >= click.ts && e.ts < commit.ts);
  if (rafs.length === 1 && fafs.length === 1) {
    const delay = (fafs[0].ts - click.end) / 1000;
    if (delay > 16 && !layouts.some((l) => l.ts < fafs[0].ts)) duration -= delay - 16;
  }
  return { start: click.ts, end: commit.end, duration };
}

const scriptEvents = ["EventDispatch", "EvaluateScript", "v8.evaluateModule", "FunctionCall", "TimerFire", "FireIdleCallback", "FireAnimationFrame", "RunMicrotasks", "V8.Execute"];
const paintEvents = ["UpdateLayoutTree", "Layout", "Commit", "Paint", "Layerize", "PrePaint"];

function busyTime(entries: TraceEvent[], start: number, end: number, names: string[], includeClick: boolean): number {
  const events: { start: number; end: number }[] = [];
  for (const e of entries) {
    if (e.name === "EventDispatch") {
      if (includeClick && e.args?.data?.type === "click") events.push({ start: e.ts, end: e.ts + (e.dur ?? 0) });
    } else if (names.includes(e.name) && e.ph === "X") events.push({ start: e.ts, end: e.ts + (e.dur ?? 0) });
  }
  let intervals: { start: number; end: number }[] = [];
  for (const e of events.filter((x) => x.start >= start && x.start <= end)) {
    const contained = intervals.some((iv) => e.start >= iv.start && e.end <= iv.end);
    const kept = intervals.filter((iv) => iv.start < e.start || iv.end > e.end);
    intervals = contained ? kept : [e, ...kept];
  }
  return intervals.reduce((sum, iv) => sum + (iv.end - iv.start), 0) / 1000;
}

const categories = ["disabled-by-default-v8.cpu_profiler", "blink.user_timing", "devtools.timeline", "disabled-by-default-devtools.timeline"];

async function measureOnce(browser: Browser, url: string, bench: Bench): Promise<Sample> {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  try {
    const page = await context.newPage();
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto(url, { waitUntil: "networkidle" });
    await bench.init(page);
    const cdp = await context.newCDPSession(page);
    if (bench.throttle > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: bench.throttle });
    await browser.startTracing(page, { categories, screenshots: false });
    await wait(50);
    await page.evaluate("window.gc({type:'major',execution:'sync',flavor:'last-resort'})");
    await bench.run(page);
    await wait(100);
    const trace = await browser.stopTracing();
    if (bench.throttle > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: 1 });
    if (errors.length > 0) throw new Error(`page error: ${errors.join("; ")}`);
    const entries = (JSON.parse(trace.toString("utf8")) as { traceEvents: TraceEvent[] }).traceEvents;
    const { start, end, duration } = totalDuration(entries);
    return {
      total: duration,
      script: busyTime(entries, start, end, scriptEvents, true),
      paint: busyTime(entries, start, end, paintEvents, false),
    };
  } finally {
    await context.close();
  }
}

async function measure(url: string, bench: Bench): Promise<Sample[]> {
  const browser = await chromium.launch({
    headless: !options.headed,
    executablePath: options.chrome === "" ? undefined : options.chrome,
    args: ["--js-flags=--expose-gc", "--no-default-browser-check", "--disable-sync", "--no-first-run", "--disable-extensions", "--disable-features=Translate,PrivacySandboxSettings4"],
  });
  try {
    const samples: Sample[] = [];
    let retries = 0;
    while (samples.length < runs + bench.extraRuns) {
      try {
        samples.push(await measureOnce(browser, url, bench));
      } catch (e) {
        if (!(e instanceof NotOneClick) || ++retries > 5) throw e;
      }
    }
    return samples;
  } finally {
    await browser.close();
  }
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 === 1 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function filesUnder(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = join(dir, e.name);
    return e.isDirectory() ? filesUnder(p) : [p];
  });
}

function sizeOf(app: App): Size {
  const files = filesUnder(join(site, app));
  let raw = 0;
  let gzip = 0;
  let brotli = 0;
  for (const f of files) {
    const data = readFileSync(f);
    raw += data.length;
    gzip += gzipSync(data, { level: 9 }).length;
    brotli += brotliCompressSync(data, { params: { [zlib.BROTLI_PARAM_QUALITY]: 11 } }).length;
  }
  return { files: files.map((f) => relative(site, f).split(sep).join("/")), raw, gzip, brotli };
}

const contentTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".css": "text/css",
  ".woff2": "font/woff2",
};

const server = createServer((req, res) => {
  const path = decodeURIComponent((req.url ?? "/").split("?")[0]);
  const file = join(site, path.endsWith("/") ? `${path}index.html` : path);
  if (!file.startsWith(site + sep) || !statSync(file, { throwIfNoEntry: false })?.isFile()) {
    res.writeHead(404);
    res.end();
    return;
  }
  res.writeHead(200, { "content-type": contentTypes[extname(file)] ?? "application/octet-stream", "cache-control": "no-store" });
  res.end(readFileSync(file));
});
await new Promise<void>((r) => server.listen(0, "127.0.0.1", () => r()));
const address = server.address();
if (address === null || typeof address === "string") throw new Error("server has no port");
const base = `http://127.0.0.1:${address.port}`;

const probe = await chromium.launch({ executablePath: options.chrome === "" ? undefined : options.chrome });
const browserVersion = probe.version();
await probe.close();

const results: Record<string, Partial<Record<App, Sample[]>>> = {};
try {
  for (const bench of selected) {
    results[bench.id] = {};
    for (const app of apps) {
      const samples = await measure(`${base}/${app}/index.html`, bench);
      results[bench.id][app] = samples;
      console.error(`${bench.id} ${app}: median total ${median(samples.map((s) => s.total)).toFixed(1)} ms (${samples.length} runs)`);
    }
  }
} finally {
  server.close();
}

const medians: Record<string, Partial<Record<App, Sample>>> = {};
for (const bench of selected) {
  medians[bench.id] = {};
  for (const app of apps) {
    const samples = results[bench.id][app] ?? [];
    medians[bench.id][app] = {
      total: median(samples.map((s) => s.total)),
      script: median(samples.map((s) => s.script)),
      paint: median(samples.map((s) => s.paint)),
    };
  }
}

const totalOf = (benchId: string, app: App): number => medians[benchId][app]?.total ?? NaN;

const geomean: Partial<Record<App, number>> = {};
const weightSum = selected.reduce((s, b) => s + b.weight, 0);
for (const app of apps) {
  let sum = 0;
  for (const bench of selected) {
    const best = Math.min(...apps.map((a) => totalOf(bench.id, a)));
    sum += bench.weight * Math.log(totalOf(bench.id, app) / best);
  }
  geomean[app] = Math.exp(sum / weightSum);
}

const sizes: Partial<Record<App, Size>> = {};
for (const app of apps) sizes[app] = sizeOf(app);

const ratio = geomean.yuka !== undefined && geomean.solid !== undefined ? geomean.yuka / geomean.solid : undefined;

const pad = (s: string, n: number) => s.padStart(n);
const lines: string[] = [];
lines.push(`browser ${browserVersion}, ${runs} runs (+10 for select), median total ms (script+paint, click to next commit)`);
lines.push("");
lines.push(`${"benchmark".padEnd(44)}${apps.map((a) => pad(a, 11)).join("")}`);
for (const bench of selected) {
  const label = `${bench.id}${bench.throttle > 1 ? ` (${bench.throttle}x)` : ""}`;
  lines.push(`${label.padEnd(44)}${apps.map((a) => pad(totalOf(bench.id, a).toFixed(1), 11)).join("")}`);
}
lines.push(`${"weighted geometric mean (vs best of these)".padEnd(44)}${apps.map((a) => pad((geomean[a] ?? NaN).toFixed(3), 11)).join("")}`);
lines.push("");
lines.push(`${"size".padEnd(44)}${apps.map((a) => pad(a, 11)).join("")}`);
lines.push(`${"raw bytes".padEnd(44)}${apps.map((a) => pad(String(sizes[a]?.raw), 11)).join("")}`);
lines.push(`${"gzip -9 bytes".padEnd(44)}${apps.map((a) => pad(String(sizes[a]?.gzip), 11)).join("")}`);
lines.push(`${"brotli q11 bytes".padEnd(44)}${apps.map((a) => pad(String(sizes[a]?.brotli), 11)).join("")}`);
if (ratio !== undefined) {
  lines.push("");
  lines.push(`yuka/solid weighted geometric mean ratio: ${ratio.toFixed(3)}`);
}
console.log(lines.join("\n"));

if (options.out !== undefined) {
  mkdirSync(dirname(resolve(options.out)), { recursive: true });
  writeFileSync(
    options.out,
    JSON.stringify(
      {
        date: new Date().toISOString(),
        browser: browserVersion,
        runs,
        benchmarks: selected.map(({ id, label, warmup, throttle, extraRuns, weight }) => ({ id, label, warmup, throttle, runs: runs + extraRuns, weight })),
        median: medians,
        samples: results,
        geomean,
        yukaSolidRatio: ratio ?? null,
        sizes,
      },
      null,
      2,
    ) + "\n",
  );
}
