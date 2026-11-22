import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";
import { createServer, request } from "node:http";
import { connect } from "node:net";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = new URL(process.argv[2] ?? "http://127.0.0.1:8125");
const proxyPort = Number(process.argv[3] ?? "8126");
const prefix = process.argv[4] ?? "/mini-linear";

let failures = 0;
const check = (name: string, ok: boolean, evidence = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${evidence ? "  [" + evidence + "]" : ""}`);
};
const step = async (name: string, f: () => Promise<void>) => {
  try {
    await f();
  } catch (e) {
    check(name, false, "exception: " + String((e as Error).message).split("\n")[0]);
  }
};

const under = (path: string) => path === prefix || path.startsWith(prefix + "/") || path.startsWith(prefix + "?");
const proxied: string[] = [];
const proxy = createServer((req, res) => {
  const url = req.url ?? "/";
  if (!under(url)) {
    res.writeHead(200, { "content-type": "text/html" });
    res.end("<!doctype html><title>Docs</title><p>docs site</p>");
    return;
  }
  proxied.push(url);
  const out = request(
    { host: app.hostname, port: app.port, method: req.method, path: url, headers: req.headers },
    (answer) => {
      res.writeHead(answer.statusCode ?? 502, answer.headers);
      answer.pipe(res);
    },
  );
  out.on("error", () => {
    res.writeHead(502);
    res.end();
  });
  req.pipe(out);
});
proxy.on("upgrade", (req, socket, head) => {
  const url = req.url ?? "/";
  if (!under(url)) return socket.destroy();
  proxied.push("upgrade " + url);
  const upstream = connect(Number(app.port), app.hostname, () => {
    const lines = [`${req.method} ${url} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) lines.push(`${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}`);
    upstream.write(lines.join("\r\n") + "\r\n\r\n");
    upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
});
await new Promise<void>((resolve) => proxy.listen(proxyPort, "127.0.0.1", resolve));
const site = `http://127.0.0.1:${proxyPort}`;

const statusSlug = (c: string | null) => (c ?? "").replace(/.*status-/, "");
const statusIs = ([id, status]: string[]) =>
  !!document.querySelector(`.row[data-id="${id}"] button[aria-label="Change status"] svg`)?.getAttribute("class")?.includes("status-" + status);
const statusIn = async (p: Page, id: string) =>
  statusSlug(await p.locator(`.row[data-id="${id}"] button[aria-label="Change status"] svg`).first().getAttribute("class"));
const recordSockets = () => {
  const W = window.WebSocket;
  (window as any).__sockets = [];
  (window as any).WebSocket = class extends W {
    constructor(url: string | URL, protocols?: string | string[]) {
      super(url, protocols);
      (window as any).__sockets.push(this);
    }
  };
};
const liveOpen = (p: Page) =>
  p.waitForFunction(() => {
    const s = (window as any).__sockets as WebSocket[];
    return s.length > 0 && s[s.length - 1].readyState === 1;
  });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
await ctx.addInitScript(recordSockets);
const problems: string[] = [];
const requests: { url: string; navigate: boolean; status?: number }[] = [];
const open = async (path: string) => {
  const p = await ctx.newPage();
  p.on("console", (m) => {
    if (m.type() === "error" || m.text().includes("hydration mismatch")) problems.push(m.text());
  });
  p.on("pageerror", (e) => problems.push(String(e)));
  p.on("requestfailed", (r) => {
    if (r.failure()?.errorText !== "net::ERR_ABORTED") problems.push(`failed ${r.url()} ${r.failure()?.errorText}`);
  });
  p.on("request", (r) => requests.push({ url: r.url(), navigate: r.headers()["yuka-navigate"] !== undefined }));
  p.on("response", (r) => {
    const e = requests.find((q) => q.url === r.url() && q.status === undefined);
    if (e) e.status = r.status();
  });
  await p.goto(site + path, { waitUntil: "networkidle" });
  await p.waitForSelector(".row");
  await p.waitForFunction(() => {
    const islands = [...document.querySelectorAll("yuka-island")];
    return islands.length > 0 && islands.every((i) => (i as any).__yuka_started);
  });
  return p;
};

let A: Page;
await step("b1. the page loads under the base", async () => {
  A = await open(prefix);
  const meta = await A.locator('meta[name="yuka-base"]').getAttribute("content");
  check("b1.1 the page has the base", meta === prefix, String(meta));
  const local = requests.filter((r) => new URL(r.url).origin === site).map((r) => new URL(r.url).pathname);
  check("b1.2 every request of the page is under the base", local.length > 1 && local.every(under), local.filter((p) => !under(p)).join(" "));
  const bad = requests.filter((r) => (r.status ?? 0) >= 400);
  check("b1.3 no request failed", bad.length === 0, bad.map((r) => `${r.status} ${r.url}`).join(" "));
  const hrefs = await A.locator(".row .row-title").evaluateAll((as) => as.map((a) => a.closest("a")?.getAttribute("href") ?? ""));
  check("b1.4 typed links have the base", hrefs.length > 0 && hrefs.every((h) => h.startsWith(prefix + "/issue/")), hrefs.slice(0, 3).join(" "));
});

await step("b2. a click is a client navigation under the base", async () => {
  await A.evaluate(() => ((window as any).__marker = "alive"));
  const mark = requests.length;
  await A.locator('.row[data-id="YUK-8"] .row-title').click();
  await A.waitForURL(`**${prefix}/issue/YUK-8`);
  await A.waitForSelector(".comment-input");
  const nav = requests.slice(mark).filter((r) => r.navigate);
  check("b2.1 the page stays (no full load)", (await A.evaluate(() => (window as any).__marker)) === "alive");
  check("b2.2 the navigation request is under the base", nav.length >= 1 && nav.every((r) => under(new URL(r.url).pathname)), nav.map((r) => r.url).join(" "));
  await A.goBack();
  await A.waitForURL(site + prefix);
  await A.waitForSelector(".row");
  check("b2.3 Back returns to the base", new URL(A.url()).pathname === prefix, A.url());
});

await step("b3. an action and a live update across two pages", async () => {
  const B = await open(prefix + "/my");
  await liveOpen(A);
  await liveOpen(B);
  const sockets = await B.evaluate(() => ((window as any).__sockets as WebSocket[]).map((s) => s.url));
  check("b3.1 the live socket is under the base", sockets.length > 0 && sockets.every((u) => new URL(u).pathname === prefix + "/_yuka/live"), sockets.join(" "));
  const id = (await B.locator(".row").first().getAttribute("data-id")) ?? "";
  const before = await statusIn(B, id);
  const target = before === "done" ? "todo" : "done";
  const answered = A.waitForResponse((r) => new URL(r.url()).pathname === prefix + "/_yuka/action/demo_shared.Actions.update_issue");
  await A.locator(`.row[data-id="${id}"] button[aria-label="Change status"]`).click();
  await A.locator(".menu-item", { hasText: new RegExp(`^\\s*${target === "done" ? "Done" : "Todo"}\\s*$`) }).click();
  const r = await answered;
  check("b3.2 the action is posted under the base and succeeds", r.status() === 200, `${r.status()} ${r.url()}`);
  const seen = await B.waitForFunction(statusIs, [id, target], { timeout: 5000 }).then(() => true, () => false);
  check("b3.3 page B shows the change of page A through the live socket", seen, `${id} ${before} -> ${target}`);
  const upgrades = proxied.filter((u) => u.startsWith("upgrade "));
  check("b3.4 the socket went through the prefix proxy", upgrades.length >= 2, upgrades.join(" "));
});

check("b4 no console errors, page errors, hydration mismatches or failed requests (an aborted fetch is not one)", problems.length === 0, problems.join(" | "));

await browser.close();
proxy.close();
console.log(failures === 0 ? "\nBASE ALL PASS" : `\n${failures} FAILED (base)`);
process.exit(failures === 0 ? 0 : 1);
