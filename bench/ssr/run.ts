import { spawn, execFileSync, type ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { loadavg } from "node:os";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const { values: options } = parseArgs({
  options: {
    "build-dir": { type: "string", default: process.env.BUILD_DIR ?? "_build" },
    rows: { type: "string", default: "100" },
    connections: { type: "string", default: "32" },
    threads: { type: "string", default: "4" },
    duration: { type: "string", default: "10" },
    warmup: { type: "string", default: "5" },
    rounds: { type: "string", default: "3" },
    port: { type: "string", default: "8210" },
    only: { type: "string", default: "" },
    interleave: { type: "boolean", default: false },
    "baseline-build-dir": { type: "string" },
    out: { type: "string" },
  },
});

const here = dirname(fileURLToPath(import.meta.url));
const ocaml = join(resolve(options["build-dir"]), "default/bench/ssr/ocaml");
const rows = Number(options.rows);
const rounds = Number(options.rounds);
const out = options.out ?? join(resolve(options["build-dir"]), "bench-ssr", "result.json");
const base = `http://127.0.0.1:${options.port}`;

interface Candidate {
  name: string;
  command: string;
  args: string[];
  path: string;
}

const node = (file: string): Pick<Candidate, "command" | "args"> => ({ command: process.execPath, args: [join(here, "node", file)] });
const candidates: Candidate[] = [
  { name: "dream-concat", command: join(ocaml, "dream_concat.exe"), args: [], path: "/" },
  { name: "yuka-page", command: join(ocaml, "yuka_ssr.exe"), args: [], path: "/" },
  { name: "yuka-stream", command: join(ocaml, "yuka_ssr.exe"), args: [], path: "/stream" },
  { name: "server-reason-react", command: join(ocaml, "srr.exe"), args: [], path: "/" },
  { name: "react-node", ...node("react.js"), path: "/" },
  { name: "solid-node", ...node("solid.js"), path: "/" },
  ...(options["baseline-build-dir"] === undefined
    ? []
    : ["page", "stream"].map((kind) => ({
        name: `yuka-${kind}-baseline`,
        command: join(resolve(options["baseline-build-dir"]!), "default/bench/ssr/ocaml/yuka_ssr.exe"),
        args: [],
        path: kind === "page" ? "/" : "/stream",
      }))),
].filter((c) => options.only === "" || options.only.split(",").includes(c.name));

interface Round {
  rps: number;
  p50: number;
  p99: number;
  errors: number;
  load: number[];
}

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 === 1 ? s[m] : (s[m - 1] + s[m]) / 2;
}

const toMs = (v: string, unit: string) => Number(v) * ({ us: 0.001, ms: 1, s: 1000 }[unit] ?? NaN);

function wrk(url: string, seconds: string): Round {
  const text = execFileSync("wrk", [`-t${options.threads}`, `-c${options.connections}`, `-d${seconds}s`, "--latency", url], { encoding: "utf8" });
  const rps = /Requests\/sec:\s+([\d.]+)/.exec(text);
  const p50 = /^\s+50%\s+([\d.]+)(us|ms|s)$/m.exec(text);
  const p99 = /^\s+99%\s+([\d.]+)(us|ms|s)$/m.exec(text);
  if (rps === null || p50 === null || p99 === null) throw new Error(`cannot read wrk output:\n${text}`);
  const non2xx = /Non-2xx or 3xx responses:\s+(\d+)/.exec(text);
  const socket = /Socket errors:.*?(\d+).*?(\d+).*?(\d+).*?(\d+)/.exec(text);
  const errors = Number(non2xx?.[1] ?? 0) + (socket === null ? 0 : socket.slice(1).reduce((s, x) => s + Number(x), 0));
  return { rps: Number(rps[1]), p50: toMs(p50[1], p50[2]), p99: toMs(p99[1], p99[2]), errors, load: loadavg() };
}

async function start(c: Candidate): Promise<{ child: ChildProcess; bytes: number }> {
  const child = spawn(c.command, [...c.args, "--port", options.port, "--rows", String(rows)], {
    stdio: "ignore",
    env: { ...process.env, NODE_ENV: "production" },
  });
  for (let i = 0; ; i++) {
    if (child.exitCode !== null) throw new Error(`${c.name} exited with ${child.exitCode}`);
    const body = await fetch(base + c.path).then((r) => (r.ok ? r.text() : null), () => null);
    if (body !== null) {
      const found = (body.match(/<li class="issue">/g) ?? []).length;
      if (found !== rows) throw new Error(`${c.name}: expected ${rows} rows, found ${found}`);
      return { child, bytes: Buffer.byteLength(body) };
    }
    if (i > 100) throw new Error(`${c.name} did not start`);
    await wait(100);
  }
}

const results: { name: string; bytes: number; rps: number; p50: number; p99: number; rounds: Round[] }[] = [];
const skipped: string[] = [];
const present = candidates.filter((c) => {
  if (existsSync(c.command)) return true;
  skipped.push(c.name);
  console.error(`${c.name}: skipped, ${c.command} not found`);
  return false;
});
const samples = new Map<string, { bytes: number; rounds: Round[] }>();
const measure = async (c: Candidate, count: number) => {
  const { child, bytes } = await start(c);
  try {
    wrk(base + c.path, options.warmup);
    const entry = samples.get(c.name) ?? { bytes, rounds: [] };
    for (let i = 0; i < count; i++) entry.rounds.push(wrk(base + c.path, options.duration));
    samples.set(c.name, entry);
  } finally {
    child.kill();
    await wait(300);
  }
};
if (options.interleave) for (let i = 0; i < rounds; i++) for (const c of present) await measure(c, 1);
else for (const c of present) await measure(c, rounds);
for (const c of present) {
  const { bytes, rounds: taken } = samples.get(c.name)!;
  results.push({
    name: c.name,
    bytes,
    rps: median(taken.map((s) => s.rps)),
    p50: median(taken.map((s) => s.p50)),
    p99: median(taken.map((s) => s.p99)),
    rounds: taken,
  });
  console.error(`${c.name}: ${taken.map((s) => s.rps.toFixed(0)).join(", ")} req/s`);
}

const floor = results.find((r) => r.name === "dream-concat")?.rps;
const row = (cols: string[]) => cols.map((c, i) => (i === 0 ? c.padEnd(22) : c.padStart(11))).join("");
const lines = [
  `${rows} rows, wrk -t${options.threads} -c${options.connections} -d${options.duration}s, ${rounds} rounds${options.interleave ? " interleaved" : ""}, median; load average 1 min per round in the JSON`,
  "",
  row(["candidate", "bytes", "req/s", "min", "max", "p50 ms", "p99 ms", "vs floor", "rps spread"]),
  ...results.map((r) => {
    const rps = r.rounds.map((s) => s.rps);
    const spread = (Math.max(...rps) - Math.min(...rps)) / r.rps;
    return row([r.name, String(r.bytes), r.rps.toFixed(0), Math.min(...rps).toFixed(0), Math.max(...rps).toFixed(0), r.p50.toFixed(2), r.p99.toFixed(2), floor === undefined ? "" : (r.rps / floor).toFixed(2), `${(spread * 100).toFixed(0)}%`]);
  }),
  ...(skipped.length > 0 ? ["", `skipped: ${skipped.join(", ")}`] : []),
];
console.log(lines.join("\n"));

mkdirSync(dirname(out), { recursive: true });
writeFileSync(
  out,
  JSON.stringify(
    { date: new Date().toISOString(), rows, threads: Number(options.threads), connections: Number(options.connections), duration: Number(options.duration), rounds, results, skipped },
    null,
    2,
  ) + "\n",
);
console.error(`wrote ${out}`);
