import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";

const { values: options } = parseArgs({
  options: {
    "build-dir": { type: "string", default: process.env.BUILD_DIR ?? "_build" },
    limits: { type: "string", default: "bench/gate/limits.json" },
    keyed: { type: "string" },
    ssr: { type: "string" },
    pages: { type: "string" },
    checks: { type: "string", default: "keyed,ssr,pages" },
  },
});

interface Limits {
  keyed: { max_yuka_solid_ratio: number };
  ssr: { candidate: string; min_ratio: Record<string, number> };
  pages: { max_lcp_ratio: number; max_tbt_over_plain_ms: number; max_js_raw: Record<string, number> };
}

interface KeyedResult {
  runs: number;
  yukaSolidRatio: number | null;
}

interface SsrResult {
  results: { name: string; rps: number; rounds: { errors: number }[] }[];
  skipped: string[];
}

interface Timing {
  lcp: number;
  tbt: number;
}

interface PagesResult {
  pages: { path: string; js: { total: { raw: number } }; page: Timing; plain: Timing }[];
  zeroJs: { path: string; ok: boolean; bytes: number }[];
}

const root = resolve(import.meta.dirname, "../..");
const buildDir = resolve(root, options["build-dir"]);
const limits = JSON.parse(readFileSync(resolve(root, options.limits), "utf8")) as Limits;
const paths = {
  keyed: options.keyed ?? join(buildDir, "bench-keyed/result.json"),
  ssr: options.ssr ?? join(buildDir, "bench-ssr/result.json"),
  pages: options.pages ?? join(buildDir, "measure-pages/result.json"),
};

const checks = options.checks.split(",");
for (const c of checks) if (!(c in paths)) throw new Error(`unknown check ${c}; known: ${Object.keys(paths).join(", ")}`);

let failed = false;
const report = (status: "PASS" | "FAIL" | "SKIP", text: string) => {
  if (status === "FAIL") failed = true;
  console.log(`${status}  ${text}`);
};
const check = (ok: boolean, text: string) => report(ok ? "PASS" : "FAIL", text);

function read<T>(name: keyof typeof paths): T | undefined {
  if (!checks.includes(name)) return undefined;
  const path = paths[name];
  if (existsSync(path)) return JSON.parse(readFileSync(path, "utf8")) as T;
  report("FAIL", `${name}: ${path} not found`);
  return undefined;
}

const keyed = read<KeyedResult>("keyed");
if (keyed !== undefined) {
  const ratio = keyed.yukaSolidRatio;
  const max = limits.keyed.max_yuka_solid_ratio;
  check(ratio !== null && ratio <= max, `keyed: yuka/solid weighted ratio ${ratio?.toFixed(3) ?? "missing"} <= ${max} (${keyed.runs} runs)`);
}

const ssr = read<SsrResult>("ssr");
if (ssr !== undefined) {
  const rps = (name: string) => ssr.results.find((r) => r.name === name)?.rps;
  const own = rps(limits.ssr.candidate);
  const errors = (name: string) => ssr.results.find((r) => r.name === name)?.rounds.reduce((sum, r) => sum + r.errors, 0) ?? 0;
  check(errors(limits.ssr.candidate) === 0, `ssr: ${limits.ssr.candidate} request errors ${errors(limits.ssr.candidate)} = 0`);
  for (const [reference, min] of Object.entries(limits.ssr.min_ratio)) {
    if (ssr.skipped.includes(reference)) {
      report("SKIP", `ssr: ${reference} was not built`);
      continue;
    }
    check(errors(reference) === 0, `ssr: ${reference} request errors ${errors(reference)} = 0`);
    const other = rps(reference);
    const ratio = own !== undefined && other !== undefined ? own / other : undefined;
    check(ratio !== undefined && ratio >= min, `ssr: ${limits.ssr.candidate}/${reference} req/s ${ratio?.toFixed(3) ?? "missing"} >= ${min}`);
  }
}

const pages = read<PagesResult>("pages");
if (pages !== undefined) {
  for (const z of pages.zeroJs) check(z.ok, `pages: 0 bytes of JavaScript files on ${z.path} (${z.bytes})`);
  const p = limits.pages;
  for (const path of Object.keys(p.max_js_raw))
    if (!pages.pages.some((r) => r.path === path)) report("FAIL", `pages: ${path} was not measured`);
  for (const r of pages.pages) {
    const max = p.max_js_raw[r.path];
    check(max !== undefined && r.js.total.raw <= max, `pages: ${r.path} JavaScript ${r.js.total.raw} bytes <= ${max ?? "no limit recorded"}`);
    const tbt = r.page.tbt - r.plain.tbt;
    check(tbt <= p.max_tbt_over_plain_ms, `pages: ${r.path} TBT ${r.page.tbt.toFixed(0)} ms, plain HTML ${r.plain.tbt.toFixed(0)} ms, over by ${tbt.toFixed(0)} <= ${p.max_tbt_over_plain_ms}`);
    const lcp = r.page.lcp / r.plain.lcp;
    check(lcp <= p.max_lcp_ratio, `pages: ${r.path} LCP ${r.page.lcp.toFixed(0)} ms / plain HTML ${r.plain.lcp.toFixed(0)} ms = ${lcp.toFixed(2)} <= ${p.max_lcp_ratio}`);
  }
}

process.exitCode = failed ? 1 : 0;
