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
const requests: { url: string; navigate: boolean; prefetch?: string; status?: number }[] = [];
const open = async (path: string) => {
  const p = await ctx.newPage();
  p.on("console", (m) => {
    if (m.type() === "error" || m.text().includes("hydration mismatch")) problems.push(m.text());
  });
  p.on("pageerror", (e) => problems.push(String(e)));
  p.on("requestfailed", (r) => {
    if (r.failure()?.errorText !== "net::ERR_ABORTED") problems.push(`failed ${r.url()} ${r.failure()?.errorText}`);
  });
  p.on("request", (r) => requests.push({ url: r.url(), navigate: r.headers()["yuka-navigate"] !== undefined, prefetch: r.headers()["yuka-prefetch"] }));
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

const alive = (p: Page) => p.evaluate(() => (window as any).__marker as string | undefined);
const home = async () => {
  await A.locator(`.nav-link[href="${prefix}"]`).click();
  await A.waitForURL(site + prefix);
  await A.waitForSelector("yuka-outlet .row");
};

await step("b5. a streamed client navigation under the base", async () => {
  await home();
  await A.evaluate(() => ((window as any).__marker = "alive"));
  await A.route(`**${prefix}/issue/YUK-8`, (route) => route.continue({ url: route.request().url() + "?delay=600" }));
  const answer = A.waitForResponse((r) => new URL(r.url()).pathname === prefix + "/issue/YUK-8" && r.request().headers()["yuka-navigate"] !== undefined);
  await A.locator('.row[data-id="YUK-8"] .row-title').click();
  const r = await answer;
  await A.waitForURL(`**${prefix}/issue/YUK-8`);
  await A.waitForSelector("[class^=related-list_] li");
  await A.unroute(`**${prefix}/issue/YUK-8`);
  check("b5.1 the navigation streams from under the base and keeps the page", r.headers()["yuka-stream"] === "1" && (await alive(A)) === "alive", `${r.url()} stream=${r.headers()["yuka-stream"]} marker=${await alive(A)}`);
});

await step("b6. hover prefetch under the base", async () => {
  await home();
  const from = requests.length;
  const to = (path: string) => requests.slice(from).filter((q) => new URL(q.url).pathname === path);
  await A.locator('.row[data-id="YUK-5"] .row-title').hover();
  await A.waitForTimeout(400);
  const pre = to(prefix + "/issue/YUK-5");
  check("b6.1 hover sends one prefetch under the base", pre.length === 1 && pre[0].prefetch === "hover", JSON.stringify(pre));
  await A.locator('.row[data-id="YUK-5"] .row-title').click();
  await A.waitForURL(`**${prefix}/issue/YUK-5`);
  await A.waitForSelector(".comment-input");
  check("b6.2 the click uses the prefetch", to(prefix + "/issue/YUK-5").length === 1, String(to(prefix + "/issue/YUK-5").length));
});

await step("b7. GET forms under the base", async () => {
  await home();
  await A.evaluate(() => ((window as any).__marker = "alive"));
  await A.fill(".search input", "keyboard");
  await A.press(".search input", "Enter");
  await A.waitForURL((u) => u.pathname === prefix && u.search === "?q=keyboard");
  await A.waitForFunction(() => (document.querySelector(".filter") as HTMLInputElement | null)?.value === "keyboard").catch(() => {});
  const filter = await A.evaluate(() => (document.querySelector(".filter") as HTMLInputElement | null)?.value);
  check("b7.1 the sidebar search form is a client navigation under the base", (await alive(A)) === "alive" && filter === "keyboard", `marker=${await alive(A)} filter=${filter} ${A.url()}`);
  const C = await open(prefix);
  await C.evaluate(() => {
    (window as any).__marker = "alive";
    const f = document.createElement("form");
    f.action = "/elsewhere";
    f.innerHTML = '<button id="e2e-out" name="q" value="x">go</button>';
    document.body.prepend(f);
  });
  await C.locator("#e2e-out").click();
  await C.waitForURL((u) => u.pathname === "/elsewhere");
  await C.waitForLoadState("load");
  const asked = requests.filter((q) => q.navigate && new URL(q.url).pathname === "/elsewhere");
  check("b7.2 a GET form to a path outside the base is a full page load, with no client fetch", asked.length === 0 && (await alive(C)) === undefined && (await C.locator("p").first().textContent()) === "docs site", `${C.url()} marker=${await alive(C)} fetched=${asked.length}`);
  await C.close();
});

await step("b8. an overlay route under the base", async () => {
  await home();
  await A.evaluate(() => ((window as any).__marker = "alive"));
  const opened = A.waitForResponse((r) => new URL(r.url()).pathname === prefix + "/settings");
  await A.locator(`.nav-link[href="${prefix}/settings"]`).click();
  const answer = await opened;
  await A.waitForURL(`**${prefix}/settings`);
  await A.waitForSelector("yuka-overlay .overlay-dialog [data-settings]");
  const rows = await A.locator("yuka-outlet .row").count();
  check("b8.1 Settings opens as an overlay over the list", answer.headers()["yuka-layer"] === "overlay" && rows > 0 && (await alive(A)) === "alive", `layer=${answer.headers()["yuka-layer"]} rows=${rows}`);
  await A.goBack();
  await A.waitForSelector("yuka-overlay", { state: "detached" });
  check("b8.2 Back removes the overlay and returns to the base", new URL(A.url()).pathname === prefix && (await alive(A)) === "alive", A.url());
});

await step("b9. a draft blocks leaving under the base", async () => {
  const D = await open(prefix);
  const dialogs: string[] = [];
  D.on("dialog", (d) => {
    dialogs.push(`${d.type()}:${d.message()}`);
    void d.dismiss();
  });
  await D.locator(".new-issue-button").click();
  await D.waitForSelector(".dialog");
  await D.locator(".dialog-title").fill("Draft");
  await D.evaluate((href) => (document.querySelector(`.nav-link[href="${href}"]`) as HTMLElement).click(), prefix + "/my");
  await D.waitForTimeout(300);
  check("b9.1 a link click asks; Cancel stays", dialogs.join() === "confirm:Discard the new issue?" && new URL(D.url()).pathname === prefix && (await D.inputValue(".dialog-title")) === "Draft", JSON.stringify({ dialogs, url: D.url() }));
  await D.close();
});

await step("b10. a reload under the base restores the scroll position", async () => {
  const S = await open(prefix);
  await S.evaluate(() => window.scrollTo(0, 300));
  const y = await S.evaluate(() => Math.round(window.scrollY));
  await S.evaluate(() => ((window as any).__marker = "alive"));
  await S.reload({ waitUntil: "networkidle" });
  await S.waitForFunction((y) => Math.abs(Math.round(scrollY) - y) <= 2, y, { timeout: 5000 }).catch(() => {});
  const after = await S.evaluate(() => Math.round(window.scrollY));
  check("b10.1 the position comes back", y > 0 && (await alive(S)) === undefined && Math.abs(after - y) <= 2, `before=${y} after=${after}`);
  await S.close();
});

check("b4 no console errors, page errors, hydration mismatches or failed requests (an aborted fetch is not one)", problems.length === 0, problems.join(" | "));

await browser.close();
proxy.close();
console.log(failures === 0 ? "\nBASE ALL PASS" : `\n${failures} FAILED (base)`);
process.exit(failures === 0 ? 0 : 1);
