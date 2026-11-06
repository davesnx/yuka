import { createServer } from "node:http";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, extname } from "node:path";
import { chromium } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";

const out: string = process.argv[2] ?? "_build_c/default/bench/out";
const packages: string[] = readdirSync(join(out, "node_modules"));
const imports: Record<string, string> = {};
for (const p of packages) imports[`${p}/`] = `/out/node_modules/${p}/`;

const page = `<!doctype html><html><head><meta charset="utf-8"><title>bench</title>
<script type="importmap">${JSON.stringify({ imports })}</script></head>
<body><script type="module" src="/out/bench/bench.js"></script></body></html>`;

const server = createServer((req, res) => {
  const url = (req.url ?? "/").split("?")[0];
  if (url === "/") {
    res.writeHead(200, { "content-type": "text/html" });
    res.end(page);
    return;
  }
  const file = join(out, url.replace(/^\/out\//, ""));
  try {
    if (!statSync(file).isFile()) throw new Error("not a file");
    res.writeHead(200, { "content-type": extname(file) === ".js" ? "text/javascript" : "text/plain" });
    res.end(readFileSync(file));
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
});

await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", () => resolve()));
const port = (server.address() as { port: number }).port;

const browser = await chromium.launch();
const context = await browser.newContext();
const tab = await context.newPage();
const lines: string[] = [];
const done = new Promise<void>((resolve) => {
  tab.on("console", (message) => {
    const text = message.text();
    lines.push(text);
    console.log(text);
    if (text === "DONE") resolve();
  });
  tab.on("pageerror", (error) => {
    console.log("PAGE ERROR " + error.message);
    resolve();
  });
});
await tab.goto(`http://127.0.0.1:${port}/`);
await Promise.race([done, new Promise((r) => setTimeout(r, 120000))]);
console.log("browser: " + browser.version());
await browser.close();
server.close();
