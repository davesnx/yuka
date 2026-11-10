import type { Page, Response } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const base = (process.argv[2] ?? "http://127.0.0.1:8123").replace(/\/$/, "");
const shots = join(dirname(fileURLToPath(import.meta.url)), "screenshots");
const bundleMode = process.argv[3] === "bundle";
const run = Date.now().toString(36);

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

const browser = await chromium.launch({ headless: true });
const page: Page = await browser.newPage({ viewport: { width: 1280, height: 800 } });

const consoleErrors: string[] = [];
const mismatches: string[] = [];
const pageErrors: string[] = [];
const failedRequests: string[] = [];
let expectedFailures = 0;
page.on("console", (m) => {
  if (m.type() === "error") consoleErrors.push(m.text());
  if (m.text().includes("hydration mismatch")) mismatches.push(m.text());
});
page.on("pageerror", (e) => pageErrors.push(String(e)));
page.on("requestfailed", (r) => failedRequests.push(`${r.method()} ${r.url()} ${r.failure()?.errorText}`));
const responses: Response[] = [];
page.on("response", (r) => {
  responses.push(r);
  if (r.status() >= 400 && r.status() !== expectedFailures) failedRequests.push(`${r.status()} ${r.url()}`);
});
const allRequests: { url: string; t: number; navigate: boolean; keys?: string }[] = [];
page.on("request", (r) =>
  allRequests.push({ url: r.url(), t: Date.now(), navigate: r.headers()["yuka-navigate"] !== undefined, keys: r.headers()["yuka-navigate"] }),
);
const chunkRe = /\/(issue_props|related|comments)(-[^/]*)?\.js$/;
const chunkRequests = (from: number) =>
  allRequests.slice(from).filter((r) => chunkRe.test(new URL(r.url).pathname)).map((r) => new URL(r.url).pathname);
const actionPosts: { url: string; status: number }[] = [];
page.on("response", (r) => {
  if (r.request().method() === "POST" && r.url().includes("/_yuka/action/"))
    actionPosts.push({ url: r.url(), status: r.status() });
});

const installProbes = () => {
  const tag = (n: Node) => {
    if (n.nodeType !== 1) return;
    const el = n as Element;
    const mark = (e: Element) => {
      if (e.matches(".row, .filter, .list, .toolbar, .new-issue-button, .comment-input, .comment, .props, .props select, .related, .related-list li"))
        (e as any).__tag = "server";
    };
    mark(el);
    el.querySelectorAll("*").forEach(mark);
  };
  const flush = (ms: MutationRecord[]) => ms.forEach((m) => m.addedNodes.forEach(tag));
  const observer = new MutationObserver(flush);
  observer.observe(document, { childList: true, subtree: true });
  document.addEventListener("readystatechange", () => {
    if (document.readyState === "loading") return;
    flush(observer.takeRecords());
    observer.disconnect();
  });
  const Orig = window.IntersectionObserver;
  (window as any).__ioFired = [];
  window.IntersectionObserver = class extends Orig {
    constructor(cb: IntersectionObserverCallback, opts?: IntersectionObserverInit) {
      super((entries, o) => {
        entries.forEach((e) => {
          if (e.isIntersecting)
            (window as any).__ioFired.push({ cls: (e.target as Element).className, t: Math.round(performance.now()) });
        });
        cb(entries, o);
      }, opts);
    }
  } as typeof IntersectionObserver;
};
await page.addInitScript(installProbes);

const statusOf = async (id: string) =>
  page.locator(`.row[data-id="${id}"] button[aria-label="Change status"] svg`).first().getAttribute("class");
const statusSlug = (c: string | null) => (c ?? "").replace(/.*status-/, "");

await step("1. load /", async () => {
  const mark = allRequests.length;
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  await page.waitForTimeout(300);
  check("1a no console errors", consoleErrors.length === 0, consoleErrors.join(" | "));
  check("1b no page errors", pageErrors.length === 0, pageErrors.join(" | "));
  check("1c no failed requests", failedRequests.length === 0, failedRequests.join(" | "));
  check("1d no yuka island error", !consoleErrors.some((e) => e.includes("yuka island")));
  const adoption = await page.evaluate(() => {
    const rows = [...document.querySelectorAll(".row")];
    const tagged = rows.filter((r) => (r as any).__tag === "server").length;
    const q = (s: string) => (document.querySelector(s) as any)?.__tag === "server";
    return {
      rows: rows.length,
      tagged,
      filter: q(".filter"),
      list: q(".list"),
      button: q(".new-issue-button"),
      started: document.querySelectorAll("yuka-island").length,
      hydrated: [...document.querySelectorAll("yuka-island")].filter((i) => (i as any).__yuka_started).length,
    };
  });
  check(
    "1e server nodes adopted",
    adoption.rows > 0 && adoption.tagged === adoption.rows && adoption.filter && adoption.list && adoption.button,
    JSON.stringify(adoption),
  );
  const early = chunkRequests(mark);
  check("1g no chunk request for issue_props, related, comments on /", early.length === 0, early.join(", "));
  check("1f all islands started", adoption.started > 0 && adoption.started === adoption.hydrated, `${adoption.hydrated}/${adoption.started}`);
});

await step("2. filter", async () => {
  const total = await page.locator(".row").count();
  await page.fill(".filter", "keyboard");
  await page.waitForTimeout(100);
  const some = await page.locator(".row").count();
  const titles = await page.locator(".row .row-title").allTextContents();
  check("2a typing filters rows", some > 0 && some < total && titles.every((t) => /keyboard/i.test(t)), `${total} -> ${some}`);
  await page.fill(".filter", "zzzzzz");
  await page.waitForTimeout(100);
  check("2b no match shows empty state", (await page.locator(".row").count()) === 0 && (await page.locator(".list-empty, p.empty").count()) === 1);
  await page.fill(".filter", "");
  await page.waitForTimeout(100);
  check("2c clearing restores rows", (await page.locator(".row").count()) === total);
  await page.locator(".filter").blur();
});

await step("3. keyboard", async () => {
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("j");
  const first = await page.locator(".row.selected").getAttribute("data-id");
  const order = await page.locator(".row").evaluateAll((els) => els.map((e) => e.getAttribute("data-id")));
  check("3a j selects first row", first === order[0], `selected=${first} first=${order[0]}`);
  await page.keyboard.press("j");
  const second = await page.locator(".row.selected").getAttribute("data-id");
  check("3b j moves down", second === order[1] && (await page.locator(".row.selected").count()) === 1, `selected=${second}`);
  await page.keyboard.press("k");
  check("3c k moves up", (await page.locator(".row.selected").getAttribute("data-id")) === order[0]);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  await page.click(".filter");
  await page.keyboard.type("ke");
  const selectedInFilter = await page.locator(".row.selected").count();
  const value = await page.inputValue(".filter");
  check("3d j/k typed in filter do not select", value === "ke" && selectedInFilter === 0, `value=${value} selected=${selectedInFilter}`);
  await page.fill(".filter", "");
  await page.locator(".filter").blur();
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("j");
  await page.keyboard.press("j");
  const target = await page.locator(".row.selected").getAttribute("data-id");
  await page.keyboard.press("Enter");
  await page.waitForURL(`**/issue/${target}`);
  check("3e Enter opens the issue page", page.url().endsWith("/issue/" + target), page.url());
  await page.goBack({ waitUntil: "networkidle" });
});

await step("3b. router", async () => {
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  await page.evaluate(() => ((window as any).__marker = "alive"));
  const marker = () => page.evaluate(() => (window as any).__marker as string | undefined);
  const titleBefore = await page.title();
  await page.evaluate(() => window.scrollTo(0, 250));
  const y = await page.evaluate(() => Math.round(window.scrollY));
  const mark = allRequests.length;
  await page.locator('.row[data-id="YUK-8"] .row-title').click();
  await page.waitForURL("**/issue/YUK-8");
  await page.waitForSelector(".comment-input");
  const navReq = allRequests.slice(mark).filter((r) => r.url.endsWith("/issue/YUK-8"));
  check("3b.1 click is a client navigation (marker survives)", (await marker()) === "alive", String(await marker()));
  check("3b.2 request has Yuka-Navigate with the outlet keys", navReq.length >= 1 && navReq.every((r) => r.keys === "L0"), JSON.stringify(navReq.map((r) => r.keys)));
  const titleAfter = await page.title();
  check("3b.3 URL and title changed", page.url().endsWith("/issue/YUK-8") && titleAfter !== titleBefore, `"${titleBefore}" -> "${titleAfter}"`);
  await page.locator(".props .property").first().hover();
  await page.waitForTimeout(300);
  await page.locator(".comment-input").fill("hello");
  const islands = await page.evaluate(() => ({
    props: !!(document.querySelector(".props select") as any)?.__yuka_change,
    comments: !!(document.querySelector(".comment-input") as any)?.__yuka_input,
    sendEnabled: !(document.querySelector(".comment-box button.primary") as HTMLButtonElement | null)?.disabled,
    count: document.querySelectorAll("yuka-island").length,
  }));
  check("3b.4 islands on the new page work (Issue_props, Comments)", islands.props && islands.comments && islands.sendEnabled, JSON.stringify(islands));
  await page.goBack();
  await page.waitForSelector(".row");
  await page.waitForTimeout(300);
  const back = await page.evaluate(() => ({ y: Math.round(window.scrollY), path: location.pathname }));
  check("3b.5 back returns to / with the marker", back.path === "/" && (await marker()) === "alive", JSON.stringify(back));
  check("3b.6 scroll restored", Math.abs(back.y - y) <= 2 && y > 0, `before=${y} after=${back.y}`);
  const total = await page.locator(".row").count();
  await page.fill(".filter", "keyboard");
  await page.waitForTimeout(100);
  const filtered = await page.locator(".row").count();
  await page.fill(".filter", "");
  check("3b.7 list works after back", total > 1 && filtered < total, `${total} -> ${filtered}`);
  await page.goForward();
  await page.waitForURL("**/issue/YUK-8");
  await page.waitForSelector(".comment-input");
  check("3b.8 forward works", page.url().endsWith("/issue/YUK-8") && (await marker()) === "alive");
  await page.goBack();
  await page.waitForSelector(".row");
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("j");
  const sel = await page.locator(".row.selected").getAttribute("data-id");
  await page.keyboard.press("Enter");
  await page.waitForURL(`**/issue/${sel}`);
  check("3b.9 Enter on a row navigates without a full load", (await marker()) === "alive" && page.url().endsWith("/issue/" + sel), `${sel} marker=${await marker()}`);
  await page.goBack();
  await page.waitForSelector(".row");
  const ctx = page.context();
  const [popup] = await Promise.all([
    ctx.waitForEvent("page"),
    page.locator('.row[data-id="YUK-2"] .row-title').click({ modifiers: ["Control"] }),
  ]);
  await popup.waitForLoadState();
  check("3b.10 ctrl-click is not intercepted (opens a new page)", popup.url().endsWith("/issue/YUK-2") && new URL(page.url()).pathname === "/", `${popup.url()} current=${page.url()}`);
  await popup.close();
  const reloadLinks = await page.locator("a[data-yuka-reload]").count();
  console.log(`SKIP  3b.11 data-yuka-reload: the demo has no such link (${reloadLinks} found)`);
});

await step("3c. partial navigation", async () => {
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  await page.evaluate(() => ((window as any).__marker = "alive"));
  const marker = () => page.evaluate(() => (window as any).__marker as string | undefined);
  const counter = page.locator(".counter-button");
  await page.waitForFunction(() => !!(document.querySelector(".counter-button") as any)?.__yuka_click, null, { timeout: 5000 });
  await counter.click();
  await counter.click();
  check("3c.1 counter counts", (await counter.textContent()) === "Clicks: 2", String(await counter.textContent()));
  const current = () => page.evaluate(() => [...document.querySelectorAll(".nav-link")].map((a) => `${a.getAttribute("href")}=${a.getAttribute("aria-current")}`).join(" "));
  check("3c.2 Issues link is current on /", (await current()) === "/=page /my=null", await current());
  const outlet = page.waitForResponse((r) => r.url().endsWith("/issue/YUK-3"));
  await page.locator('.row[data-id="YUK-3"] .row-title').click();
  const response = await outlet;
  await page.waitForURL("**/issue/YUK-3");
  await page.waitForSelector(".comment-input");
  check("3c.3 partial response for the shell outlet", response.headers()["yuka-outlet"] === "L0" && !(await response.text()).includes("<!DOCTYPE"), String(response.headers()["yuka-outlet"]));
  check("3c.4 sidebar counter kept its state", (await counter.textContent()) === "Clicks: 2" && (await marker()) === "alive", String(await counter.textContent()));
  check("3c.5 title changed", (await page.title()) === "YUK-3", await page.title());
  check("3c.6 no link is current on an issue page", (await current()) === "/=null /my=null", await current());
  await page.locator(".new-issue-button").click();
  await page.waitForSelector(".dialog", { timeout: 2000 });
  check("3c.7 New_issue in the kept sidebar still opens", (await page.locator(".dialog").count()) === 1);
  await page.keyboard.press("Escape");
  await page.locator('.nav-link[href="/my"]').click();
  await page.waitForURL("**/my");
  await page.waitForSelector(".row");
  check("3c.8 aria-current moves to My issues", (await current()) === "/=null /my=page", await current());
  check("3c.9 counter still kept", (await counter.textContent()) === "Clicks: 2");
  const y0 = await page.evaluate(() => Math.round(window.scrollY));
  check("3c.10 a new page starts at the top", y0 === 0, String(y0));
  await page.goBack();
  await page.waitForURL("**/issue/YUK-3");
  await page.waitForSelector(".comment-input");
  check("3c.11 back is partial too (counter kept)", (await counter.textContent()) === "Clicks: 2" && (await marker()) === "alive");
  await page.route("**/my", async (route) => {
    const real = await route.fetch();
    await route.fulfill({ response: real, headers: { ...real.headers(), "yuka-build": "changed" } });
  });
  await page.locator('.nav-link[href="/my"]').click();
  await page.waitForURL("**/my");
  await page.waitForSelector(".row");
  await page.unroute("**/my");
  check("3c.12 another Yuka-Build is a full page load", (await marker()) === undefined && (await counter.textContent()) === "Clicks: 0", `marker=${await marker()} ${await counter.textContent()}`);
});

await step("3d. a page with no island loads no script", async () => {
  const pg = await browser.newPage();
  const scripts: string[] = [];
  pg.on("request", (r) => { if (r.resourceType() === "script") scripts.push(r.url()); });
  await pg.goto(base + "/about", { waitUntil: "networkidle" });
  const inline = await pg.evaluate(() => [...document.querySelectorAll("script")].filter((s) => s.type !== "importmap").length);
  check("3d.1 /about requests no script and has no inline script", scripts.length === 0 && inline === 0, `${scripts.join(",")} inline=${inline}`);
  await pg.close();
});

await step("3e. remote data is embedded", async () => {
  const pg = await browser.newPage();
  const posts: string[] = [];
  pg.on("request", (r) => { if (r.method() === "POST") posts.push(new URL(r.url()).pathname); });
  const res = await pg.goto(base + "/", { waitUntil: "networkidle" });
  const html = (await res?.text()) ?? "";
  await pg.waitForSelector(".row");
  check("3e.1 the list and its answer are in the server HTML", html.includes('class="row-title"') && html.includes('data-yuka-answer="r:issues'), String(html.length));
  check("3e.2 no issues request at load", !posts.some((p) => p.endsWith("/issues")), posts.join(","));
  await pg.locator('.nav-link[href="/my"]').click();
  await pg.waitForURL("**/my");
  await pg.waitForSelector(".row");
  check("3e.3 no issues request after a client navigation", !posts.some((p) => p.endsWith("/issues")), posts.join(","));
  await pg.close();
});

await step("4. status change", async () => {
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  const id = "YUK-4";
  const before = statusSlug(await statusOf(id));
  const target = before === "done" ? "todo" : "done";
  const label = target === "done" ? "Done" : "Todo";
  await page.route("**/_yuka/action/**", async (route) => {
    await new Promise((r) => setTimeout(r, 800));
    await route.continue();
  });
  actionPosts.length = 0;
  await page.locator(`.row[data-id="${id}"] button[aria-label="Change status"]`).click();
  await page.locator(".menu-item", { hasText: new RegExp(`^\\s*${label}\\s*$`) }).click();
  const start = Date.now();
  await page.waitForFunction(
    ([i, t]) => document.querySelector(`.row[data-id="${i}"] button[aria-label="Change status"] svg`)?.getAttribute("class")?.includes("status-" + t),
    [id, target],
    { timeout: 700 },
  );
  const quick = Date.now() - start;
  check("4a row updates at once (before response)", actionPosts.length === 0 && quick < 700, `after ${quick}ms, responses so far=${actionPosts.length}`);
  await page.waitForTimeout(1200);
  await page.unroute("**/_yuka/action/**");
  check(
    "4b POST /_yuka/action/... returned 200",
    actionPosts.length === 1 && actionPosts[0].status === 200,
    JSON.stringify(actionPosts),
  );
  check("4c row keeps new status after response", statusSlug(await statusOf(id)) === target);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  check("4d status persists after reload", statusSlug(await statusOf(id)) === target, `${before} -> ${statusSlug(await statusOf(id))}`);
});

await step("5. failure path", async () => {
  const id = "YUK-5";
  const before = statusSlug(await statusOf(id));
  const target = before === "done" ? "todo" : "done";
  const label = target === "done" ? "Done" : "Todo";
  expectedFailures = 500;
  await page.route("**/_yuka/action/**", async (route) => {
    await new Promise((r) => setTimeout(r, 500));
    await route.fulfill({ status: 500, contentType: "application/json", body: '{"error":"action failed"}' });
  });
  const rowTopBefore = (await page.locator(`.row[data-id="${id}"]`).boundingBox())?.y ?? -1;
  await page.locator(`.row[data-id="${id}"] button[aria-label="Change status"]`).click();
  await page.locator(".menu-item", { hasText: new RegExp(`^\\s*${label}\\s*$`) }).click();
  await page.waitForTimeout(100);
  const optimistic = statusSlug(await statusOf(id));
  await page.waitForTimeout(1200);
  const after = statusSlug(await statusOf(id));
  await page.unroute("**/_yuka/action/**");
  check("5a optimistic change shown first", optimistic === target, `${before} -> ${optimistic}`);
  check("5b row rolls back", after === before, `after=${after}`);
  const toast = await page.locator(".toast").textContent().catch(() => null);
  check("5c error toast shows", !!toast && /Could not update/.test(toast), String(toast));
  const rowTopWithToast = (await page.locator(`.row[data-id="${id}"]`).boundingBox())?.y ?? -2;
  check("5f toast does not move the list", rowTopWithToast === rowTopBefore, `before=${rowTopBefore} with toast=${rowTopWithToast}`);
  await page.screenshot({ path: join(shots, "toast.png") });
  await page.locator(".toast button").click();
  check("5d toast can be dismissed", (await page.locator(".toast").count()) === 0);
  expectedFailures = 0;
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  check("5e server status unchanged", statusSlug(await statusOf(id)) === before);
});

await step("6. new issue dialog", async () => {
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("c");
  await page.waitForSelector(".dialog", { timeout: 2000 });
  check("6a c opens dialog", (await page.locator(".dialog h2").textContent()) === "New issue");
  await page.screenshot({ path: join(shots, "dialog.png") });
  await page.keyboard.press("Escape");
  await page.waitForTimeout(100);
  check("6b Escape closes dialog", (await page.locator(".dialog").count()) === 0);
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("c");
  await page.waitForSelector(".dialog");
  consoleErrors.length = 0;
  await page.locator(".dialog .button.primary").click();
  await page.waitForSelector(".dialog .error", { timeout: 3000 });
  check("6c0 empty title shows 'Title is required'", (await page.locator(".dialog .error").textContent()) === "Title is required");
  check("6c0b dialog stays open", (await page.locator(".dialog").count()) === 1);
  const rejected = consoleErrors.splice(0);
  check("6c0c empty title is a typed error: no console error", rejected.length === 0, rejected.join(" | "));
  const errText = async () => (await page.locator(".dialog .error").textContent()) ?? "";
  await page.fill(".dialog-title", "x".repeat(81));
  await page.locator(".dialog .button.primary").click();
  await page.waitForFunction(() => /too long/.test(document.querySelector(".dialog .error")?.textContent ?? ""), null, { timeout: 3000 });
  check("6c0d long title shows 'Title is too long'", (await errText()) === "Title is too long (at most 80 characters)", await errText());
  await page.fill(".dialog-title", "Write the release notes");
  await page.locator(".dialog .button.primary").click();
  await page.waitForFunction(() => /already exists/.test(document.querySelector(".dialog .error")?.textContent ?? ""), null, { timeout: 3000 });
  check("6c0e duplicate title shows the existing id", (await errText()) === "An issue with this title already exists: YUK-25", await errText());
  check("6c0f typed errors cause no console error", consoleErrors.length === 0, consoleErrors.join(" | "));
  const headerBefore = Number((await page.locator(".page-header .group-count").first().textContent()) ?? "NaN");
  const title = `E2E issue ${run}`;
  await page.fill(".dialog-title", title);
  await page.fill(".dialog-description", "Created by the browser check.");
  const before = await page.locator(".row").count();
  await page.locator(".dialog .button.primary").click();
  await page.waitForSelector(".dialog", { state: "detached", timeout: 3000 });
  await page.waitForTimeout(200);
  const row = page.locator(".row", { hasText: title });
  check("6c issue appears without reload", (await row.count()) === 1 && (await page.locator(".row").count()) === before + 1);
  const headerAfter = Number((await page.locator(".page-header .group-count").first().textContent()) ?? "NaN");
  check("6c2 header count follows the list", headerAfter === headerBefore + 1 && headerAfter === before + 1, `${headerBefore} -> ${headerAfter}, rows ${before + 1}`);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  check("6d issue present after reload", (await page.locator(".row", { hasText: title }).count()) === 1);
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("j");
  check("6e keyboard works after dialog closed", (await page.locator(".row.selected").count()) === 1);
});

const issuePath = "/issue/YUK-1";
await step("6f. new issue form with JavaScript off", async () => {
  const ctx = await browser.newContext({ javaScriptEnabled: false });
  const pg = await ctx.newPage();
  const statuses: number[] = [];
  pg.on("response", (r) => { if (r.request().method() === "POST") statuses.push(r.status()); });
  await pg.goto(base + "/new", { waitUntil: "load" });
  await pg.fill('input[name="title"]', "");
  await pg.fill('textarea[name="description"]', "kept by the server");
  await pg.locator('button[type="submit"]').click();
  await pg.waitForLoadState("load");
  check("6f.1 empty title: 422 page with the error", statuses.includes(422) && (await pg.locator(".error").first().textContent()) === "Title is required", JSON.stringify(statuses));
  check("6f.2 the sent description is kept", (await pg.inputValue('textarea[name="description"]')) === "kept by the server");
  check("6f.3 the address stays /new", new URL(pg.url()).pathname === "/new", pg.url());
  const title = `No-JS issue ${run}`;
  await pg.fill('input[name="title"]', title);
  await pg.locator('button[type="submit"]').click();
  await pg.waitForURL("**/issue/YUK-*");
  check("6f.4 created: 303 to the issue page", statuses.includes(303) && (await pg.locator(".issue-title").textContent()) === title, `${statuses} ${pg.url()}`);
  await ctx.close();
});

await step("7a. streaming", async () => {
  const early = await browser.newPage();
  const earlyErrors: string[] = [];
  early.on("console", (m) => m.type() === "error" && earlyErrors.push(m.text()));
  const t0 = Date.now();
  await early.goto(base + issuePath, { waitUntil: "commit" });
  await early.waitForSelector(".skeleton", { timeout: 3000 });
  const firstPaint = await early.evaluate(() => ({
    skeleton: document.querySelectorAll(".skeleton").length,
    comments: document.querySelectorAll(".comment").length,
    related: document.querySelectorAll(".related-list li").length,
    title: document.querySelector(".issue-title")?.textContent ?? "",
  }));
  const tSkeleton = Date.now() - t0;
  check(
    "7.1 skeleton visible before comments and related arrive",
    firstPaint.skeleton >= 1 && firstPaint.comments === 0 && firstPaint.related === 0 && firstPaint.title !== "",
    `${JSON.stringify(firstPaint)} after ${tSkeleton}ms`,
  );
  await early.waitForSelector(".comment", { timeout: 5000 });
  const tComments = Date.now() - t0;
  const relatedAtComments = await early.locator(".related-list li").count();
  await early.waitForSelector(".related-list li", { timeout: 5000 });
  const tRelated = Date.now() - t0;
  check("7.2 comments arrive before related issues", relatedAtComments === 0 && tRelated > tComments, `comments ${tComments}ms, related ${tRelated}ms`);
  await early.waitForLoadState("networkidle");
  await early.waitForTimeout(300);
  const done = await early.evaluate(() => ({
    skeleton: document.querySelectorAll(".skeleton").length,
    comments: document.querySelectorAll(".comments .comment").length,
    related: document.querySelectorAll(".related-list li").length,
    templates: document.querySelectorAll("template[data-yuka-fill]").length,
    fillScripts: [...document.scripts].filter((s) => s.textContent?.includes("__yukaFill(")  && !s.textContent.includes("window.__yukaFill=")).length,
    islands: document.querySelectorAll("yuka-island").length,
    started: [...document.querySelectorAll("yuka-island")].filter((i) => (i as any).__yuka_started).length,
  }));
  check("7.3 comments list and 4 related issues present", done.comments === 3 && done.related === 4 && done.skeleton === 0, JSON.stringify(done));
  check("7.4 fill templates and scripts are gone", done.templates === 0 && done.fillScripts === 0, JSON.stringify(done));
  check("7.5 every island on the page has been processed", done.islands > 0 && done.started === done.islands, `${done.started}/${done.islands}`);
  check("7.6 no console errors while streaming", earlyErrors.length === 0, earlyErrors.join(" | "));
  await early.close();
});

await step("7b. start strategies", async () => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 260 } });
  await ctx.addInitScript(installProbes);
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  p.on("pageerror", (e) => errors.push(String(e)));
  const chunks: { name: string; t: number }[] = [];
  p.on("request", (r) => {
    const m = chunkRe.exec(new URL(r.url()).pathname);
    if (m) chunks.push({ name: m[1], t: Date.now() });
  });
  const names = () => chunks.map((c) => c.name).join(",");
  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForSelector(".related-list li");
  await p.waitForTimeout(800);
  const state = () =>
    p.evaluate(() => {
      const handler = (sel: string, ev: string) => {
        const el = document.querySelector(sel) as any;
        return !!el && !!el["__yuka_" + ev];
      };
      const related = document.querySelector(".related") as Element;
      const box = related.getBoundingClientRect();
      return {
        counter: handler(".counter-button", "click"),
        props: handler(".props select", "change"),
        io: ((window as any).__ioFired as { cls: string; t: number }[]).filter((x) => /related/.test(x.cls)),
        relatedTop: Math.round(box.top),
        vh: window.innerHeight,
      };
    });
  const before = await state();

  check("7b.2 Issue_props not started before interaction", !before.props);
  check("7b.3 Related not started while below the fold", before.relatedTop > before.vh && before.io.length === 0, `top=${before.relatedTop} vh=${before.vh} fired=${before.io.length}`);
  check("7b.2b before interaction: no issue_props or related chunk requested", !names().includes("issue_props") && !names().includes("related"), names());
  await p.locator(".props .property").first().hover();
  await p.waitForTimeout(200);
  check("7b.2c issue_props chunk requested after hover, related not yet", names().includes("issue_props") && !names().includes("related"), names());
  const hovered = await state();
  check("7b.4 Issue_props started after hover", hovered.props, JSON.stringify(hovered));
  check("7b.5 Related still not started after hover", hovered.io.length === 0);
  const tScroll = Date.now();
  await p.locator(".related").scrollIntoViewIfNeeded();
  await p.waitForTimeout(300);
  const scrolled = await state();
  check("7b.6 Related started when scrolled into view", scrolled.io.length >= 1, `fired=${JSON.stringify(scrolled.io)} ${Date.now() - tScroll}ms after scroll`);
  check("7b.6b related chunk requested after scroll", names().includes("related"), names());
  const slot = await p.evaluate(() => ({
    related: (document.querySelector(".related") as any)?.__tag === "server",
    items: [...document.querySelectorAll(".related-list li")].filter((e) => (e as any).__tag === "server").length,
    total: document.querySelectorAll(".related-list li").length,
    props: (document.querySelector(".props") as any)?.__tag === "server",
  }));
  check("7b.7 slot nodes inside Issue_props are the server nodes", slot.related && slot.props && slot.total === 4 && slot.items === 4, JSON.stringify(slot));
  const counterText = async () => ((await p.locator(".counter-button").textContent()) ?? "").trim();
  const countBefore = await counterText();
  await p.locator(".counter-button").click();
  await p.waitForTimeout(100);
  const countAfter = await counterText();
  check(
    "7b.1 Counter (idle) started without interaction: click changes the count",
    before.counter && countBefore !== countAfter,
    `handler=${before.counter} "${countBefore}" -> "${countAfter}"`,
  );
  check("7b.8 no errors", errors.length === 0, errors.join(" | "));
  await ctx.close();
});

await step("7c. Issue_props status change", async () => {
  const p = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  await p.addInitScript(installProbes);
  const pg = await p.newPage();
  const errors: string[] = [];
  pg.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  pg.on("pageerror", (e) => errors.push(String(e)));
  const posts: number[] = [];
  pg.on("response", (r) => r.request().method() === "POST" && r.url().includes("/_yuka/action/") && posts.push(r.status()));
  await pg.goto(base + "/issue/YUK-6", { waitUntil: "networkidle" });
  await pg.waitForSelector(".related-list li");
  const icon = () => pg.locator(".props .property").first().locator("svg").first().getAttribute("class");
  const select = pg.locator('.props select[aria-label="Status"]');
  const beforeStatus = statusSlug(await icon());
  const preValue = await select.inputValue();
  const preHandler = await pg.evaluate(() => !!(document.querySelector(".props select") as any)?.__yuka_change);
  check("7c.0 status select shows the saved status before hydration", !preHandler && preValue === beforeStatus, `select=${preValue} icon=${beforeStatus} hydrated=${preHandler}`);
  const relatedBefore = await pg.locator(".related-list li").count();
  const target = beforeStatus === "done" ? "todo" : "done";
  await pg.route("**/_yuka/action/**", async (route) => {
    await new Promise((r) => setTimeout(r, 800));
    await route.continue();
  });
  await pg.locator(".props .property").first().hover();
  await select.selectOption({ value: target });
  try {
    await pg.waitForFunction(
      (t) => document.querySelector(".props .property svg")?.getAttribute("class")?.includes("status-" + t),
      target,
      { timeout: 700 },
    );
  } catch {
    const dbg = await pg.evaluate(() => ({
      icon: document.querySelector(".props .property svg")?.getAttribute("class"),
      handler: !!(document.querySelector(".props select") as any)?.__yuka_change,
      value: (document.querySelector('.props select[aria-label="Status"]') as HTMLSelectElement | null)?.value,
    }));
    check("7c.1 status icon updates at once", false, `target=${target} state=${JSON.stringify(dbg)} errors=${errors.join(" | ")}`);
    await p.close();
    return;
  }
  check("7c.1 status icon updates at once", posts.length === 0, `${beforeStatus} -> ${target}, responses so far=${posts.length}`);
  await pg.waitForTimeout(1200);
  await pg.unroute("**/_yuka/action/**");
  check("7c.2 action returned 200", posts.length === 1 && posts[0] === 200, JSON.stringify(posts));
  const slot = await pg.evaluate(() => ({
    items: document.querySelectorAll(".related-list li").length,
    tagged: [...document.querySelectorAll(".related-list li")].filter((e) => (e as any).__tag === "server").length,
    related: (document.querySelector(".related") as any)?.__tag === "server",
    links: [...document.querySelectorAll(".related-list a")].every((a) => (a as HTMLAnchorElement).getAttribute("href")?.startsWith("/issue/")),
  }));
  check("7c.3 Related island intact after Issue_props re-render", relatedBefore > 0 && slot.items === relatedBefore && slot.tagged === relatedBefore && slot.related && slot.links, JSON.stringify(slot));
  await pg.reload({ waitUntil: "networkidle" });
  await pg.waitForSelector(".related-list li");
  check("7c.4 status persists after reload", statusSlug(await icon()) === target && (await select.inputValue()) === target, `${beforeStatus} -> ${statusSlug(await icon())}`);
  check("7c.5 no errors", errors.length === 0, errors.join(" | "));
  await p.close();
});

await step("7f. early start", async () => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  await ctx.addInitScript(() => {
    const w = window as any;
    w.__fills = [];
    let fill: ((id: string) => void) | undefined;
    Object.defineProperty(window, "__yukaFill", {
      configurable: true,
      get: () => fill,
      set: (f: (id: string) => void) => {
        fill = (id: string) => {
          f(id);
          w.__fills.push(Math.round(performance.now()));
        };
      },
    });
    const poll = setInterval(() => {
      const b = document.querySelector(".new-issue-button") as any;
      if (b && b.__yuka_click) {
        w.__newIssueStarted = Math.round(performance.now());
        clearInterval(poll);
      }
    }, 5);
  });
  const p = await ctx.newPage();
  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForTimeout(300);
  const r = await p.evaluate(() => ({
    started: (window as any).__newIssueStarted as number | undefined,
    fills: (window as any).__fills as number[],
  }));
  const last = Math.max(...r.fills, 0);
  check(
    "7f eager island starts before the last fill chunk arrives",
    r.fills.length >= 2 && r.started !== undefined && r.started + 100 < last,
    `New_issue started at ${r.started}ms, fills at ${r.fills.join(",")}ms`,
  );
  await ctx.close();
});

await step("7g. generated island registry", async () => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 260 } });
  await ctx.addInitScript(installProbes);
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  p.on("pageerror", (e) => errors.push(String(e)));
  const islandModuleRe = /\/(counter|new_issue|issue_list|comments|issue_props|related)(-[^/]*)?\.js$/;
  const seen: string[] = [];
  p.on("request", (r) => {
    const m = islandModuleRe.exec(new URL(r.url()).pathname);
    if (m) seen.push(m[1]);
  });
  const lazyNames = () => ["comments", "issue_props", "related"].filter((n) => seen.includes(n)).join(",");
  const has = (sel: string, ev: string) =>
    p.evaluate(([s, e]) => !!(document.querySelector(s) as any)?.["__yuka_" + e], [sel, ev]);

  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForSelector(".related-list li");
  await p.waitForTimeout(500);

  check("7g.1 eager New_issue hydrated", await has(".new-issue-button", "click"));
  check("7g.2 eager Counter (Idle) hydrated", await has(".counter-button", "click"));
  check("7g.5 lazy Comments (Load) hydrated", await has(".comment-input", "input"));
  check("7g.7 lazy Issue_props not started before interaction", !(await has(".props select", "change")));
  check("7g.8 only the comments chunk is requested before interaction", lazyNames() === "comments", lazyNames());

  check("7g.9 non-lazy Counter and New_issue modules requested at load", seen.includes("counter") && seen.includes("new_issue"), seen.join(","));
  check("7g.9b Issue_list module not requested on a page without it", !seen.includes("issue_list"), seen.join(","));

  await p.locator(".props .property").first().hover();
  await p.waitForTimeout(300);
  check("7g.10 Issue_props live after hover", await has(".props select", "change"));
  check("7g.11 issue_props chunk requested after hover, related not yet", lazyNames() === "comments,issue_props", lazyNames());
  check(
    "7g.12 Related not started below the fold",
    (await p.evaluate(() => ((window as any).__ioFired as { cls: string }[]).filter((x) => /related/.test(x.cls)).length)) === 0,
  );
  await p.locator(".related").scrollIntoViewIfNeeded();
  await p.waitForTimeout(400);
  check("7g.13 related chunk requested after scroll", lazyNames() === "comments,issue_props,related", lazyNames());
  const c0 = ((await p.locator(".counter-button").textContent()) ?? "").trim();
  await p.locator(".counter-button").click();
  await p.waitForTimeout(100);
  check("7g.3 Counter is live: click changes the count", ((await p.locator(".counter-button").textContent()) ?? "").trim() !== c0);
  await p.locator("body").click({ position: { x: 5, y: 5 } });
  await p.keyboard.press("c");
  await p.waitForSelector(".dialog", { timeout: 2000 });
  check("7g.4 New_issue is live: c opens the dialog", (await p.locator(".dialog h2").textContent()) === "New issue");
  await p.keyboard.press("Escape");
  await p.locator(".comment-input").fill("probe");
  check("7g.6 Comments is live: send enabled after typing", !(await p.locator(".comment-box button.primary").isDisabled()));

  const requested = await p.evaluate(() =>
    performance.getEntriesByType("resource").map((e) => new URL(e.name).pathname).filter((u) => /\.js$/.test(u)),
  );
  for (const n of ["comments", "issue_props", "related"]) {
    const hits = requested.filter((u) => new RegExp(`/${n}(-[^/]*)?\\.js$`).test(u));
    check(`7g.14 ${n} has its own ${bundleMode ? "chunk" : "module"}, requested once`, hits.length === 1, hits.join(","));
  }
  if (bundleMode) {
    const chunkFiles = requested.filter((u) => /\/(comments|issue_props|related)-[^/]*\.js$/.test(u));
    check("7g.15 bundle: three distinct lazy chunks, not main.js", new Set(chunkFiles).size === 3 && !chunkFiles.some((u) => u.endsWith("/main.js")), chunkFiles.join(","));
  }
  check("7g.16 no 'no entry for island' or other errors", errors.length === 0, errors.join(" | "));
  await ctx.close();
});

await step("7h. client navigation with Yuka.mount ()", async () => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  p.on("pageerror", (e) => errors.push(String(e)));
  const docs: string[] = [];
  const commentsReqs: string[] = [];
  p.on("request", (r) => {
    const path = new URL(r.url()).pathname;
    if (r.resourceType() === "document") docs.push(path);
    if (/\/comments(-[^/]*)?\.js$/.test(path)) commentsReqs.push(path);
  });
  await p.goto(base + "/", { waitUntil: "networkidle" });
  await p.waitForSelector(".row");
  await p.evaluate(() => ((window as any).__nav = "alive"));
  check("7h.1 comments chunk not requested on /", commentsReqs.length === 0, commentsReqs.join(","));
  await p.locator('.row[data-id="YUK-3"] .row-title').click();
  await p.waitForURL("**/issue/YUK-3");
  await p.waitForSelector(".comment-input");
  await p.waitForTimeout(500);
  check("7h.2 link click is not a document load", docs.length === 1 && docs[0] === "/" && (await p.evaluate(() => (window as any).__nav)) === "alive", docs.join(","));
  check("7h.3 lazy island loaded by the navigated page", commentsReqs.length === 1, commentsReqs.join(","));
  check("7h.4 Comments live after navigation", await p.evaluate(() => !!(document.querySelector(".comment-input") as any)?.__yuka_input));
  await p.goBack();
  await p.waitForSelector(".row");
  await p.waitForTimeout(300);
  const total = await p.locator(".row").count();
  await p.fill(".filter", "keyboard");
  await p.waitForTimeout(100);
  check("7h.5 Issue_list live after navigating back", (await p.locator(".row").count()) < total);
  check("7h.6 no errors", errors.length === 0, errors.join(" | "));
  await ctx.close();
});

await step("7i. modulepreload", async () => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  p.on("pageerror", (e) => errors.push(String(e)));
  const reqs: string[] = [];
  p.on("request", (r) => reqs.push(new URL(r.url()).pathname));
  const nameOf = (u: string) => /\/([a-z_]+)(-[^/]*)?\.js$/.exec(u)?.[1] ?? u;
  const count = (n: string) => reqs.filter((u) => nameOf(u) === n).length;
  const preloads = () =>
    p.evaluate(() =>
      [...document.querySelectorAll('link[rel="modulepreload"]')].map((l) => ({
        raw: l.getAttribute("href") ?? "",
        path: new URL((l as HTMLLinkElement).href).pathname,
      })),
    );
  const lazyModules = ["comments", "issue_props", "related"];

  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForSelector(".related-list li");
  await p.waitForTimeout(500);
  const pre = await preloads();
  const preNames = pre.map((l) => nameOf(l.path)).sort();
  check("7i.1 issue page: one modulepreload per non-lazy island, none for lazy uses", JSON.stringify(preNames) === JSON.stringify(["counter", "new_issue"]), JSON.stringify(pre));
  check("7i.2 no duplicate modulepreload hrefs", new Set(pre.map((l) => l.path)).size === pre.length);
  if (!bundleMode) check("7i.3 dev hrefs keep the /../ form and resolve to the served module URL", pre.every((l) => l.raw.includes("/../") && reqs.includes(l.path)), JSON.stringify(pre.map((l) => [l.raw, reqs.includes(l.path)])));
  else check("7i.3 bundle hrefs name the hashed chunk and are requested", pre.every((l) => /\/_yuka\/bundle\/[a-z_]+-[A-Z0-9]+\.js$/.test(l.path) && reqs.includes(l.path)), JSON.stringify(pre));
  for (const l of pre) check(`7i.4 ${nameOf(l.path)} is requested once (preload and import share the request)`, reqs.filter((u) => u === l.path).length === 1, String(reqs.filter((u) => u === l.path).length));
  check("7i.5 Issue_list is never requested on the issue page", count("issue_list") === 0, String(count("issue_list")));
  check("7i.6 lazy modules requested at most once each", lazyModules.every((n) => count(n) <= 1), lazyModules.map((n) => `${n}=${count(n)}`).join(","));

  const q = await ctx.newPage();
  const qReqs: { name: string; t: number }[] = [];
  q.on("request", (r) => {
    const n = nameOf(new URL(r.url()).pathname);
    if (lazyModules.includes(n)) qReqs.push({ name: n, t: Date.now() });
  });
  await q.setViewportSize({ width: 1280, height: 260 });
  await q.goto(base + "/issue/YUK-2", { waitUntil: "commit" });
  await q.waitForSelector(".related-list li", { timeout: 8000 });
  const at = (n: string) => qReqs.filter((r) => r.name === n).length;
  await q.waitForTimeout(500);
  check("7i.7 Comments (Lazy Idle) requested after idle, others not yet", at("comments") === 1 && at("issue_props") === 0 && at("related") === 0, qReqs.map((r) => r.name).join(","));
  await q.locator(".props .property").first().hover();
  await q.waitForTimeout(300);
  check("7i.8 Issue_props (Lazy Interaction) requested only after hover", at("issue_props") === 1 && at("related") === 0, qReqs.map((r) => r.name).join(","));
  await q.locator(".related").scrollIntoViewIfNeeded();
  await q.waitForTimeout(400);
  check("7i.9 Related (Lazy Visible) requested only after scroll", at("related") === 1, qReqs.map((r) => r.name).join(","));
  await q.close();

  const r = await ctx.newPage();
  const rReqs: string[] = [];
  r.on("request", (x) => rReqs.push(nameOf(new URL(x.url()).pathname)));
  await r.goto(base + "/issue/YUK-3", { waitUntil: "networkidle" });
  await r.waitForSelector(".related-list li");
  await r.evaluate(() => ((window as any).__nav = "alive"));
  check("7i.10 Issue_list not loaded before navigation", !rReqs.includes("issue_list"));
  await r.locator('a[href="/"]').first().click();
  await r.waitForSelector(".row");
  await r.waitForTimeout(500);
  check("7i.11 navigation was client-side", (await r.evaluate(() => (window as any).__nav)) === "alive");
  check("7i.12 new non-lazy island module requested once after navigation", rReqs.filter((n) => n === "issue_list").length === 1, String(rReqs.filter((n) => n === "issue_list").length));
  const total = await r.locator(".row").count();
  await r.fill(".filter", "keyboard");
  await r.waitForTimeout(100);
  check("7i.13 Issue_list hydrates after navigation", (await r.locator(".row").count()) < total, `${total} -> ${await r.locator(".row").count()}`);
  check("7i.14 no errors", errors.length === 0, errors.join(" | "));
  await ctx.close();
});

await step("7d. script loading", async () => {
  const pg = await browser.newPage();
  await pg.goto(base + "/", { waitUntil: "networkidle" });
  const info = await pg.evaluate(() => ({
    importmaps: document.querySelectorAll('script[type="importmap"]').length,
    srcs: [...document.querySelectorAll("script[src]")].map((s) => s.getAttribute("src")),
  }));
  const ok = bundleMode ? info.importmaps === 0 && info.srcs.length === 1 : info.importmaps === 1 && info.srcs.length >= 1;
  check(`7d ${bundleMode ? "bundle mode: one script, no import map" : "module mode: import map present"}`, ok, JSON.stringify(info));
  await pg.close();
});

await step("7. comment", async () => {
  await page.goto(base + issuePath, { waitUntil: "networkidle" });
  await page.waitForSelector(".comment-input");
  await page.screenshot({ path: join(shots, "issue.png"), fullPage: true });
  const body = `Browser comment ${run}`;
  const before = await page.locator(".comment").count();
  await page.route("**/_yuka/action/**", async (route) => {
    await new Promise((r) => setTimeout(r, 800));
    await route.continue();
  });
  await page.fill(".comment-input", body);
  await page.getByRole("button", { name: "Comment" }).click();
  await page.waitForTimeout(150);
  const immediate = await page.locator(".comment", { hasText: body }).count();
  check("7e.1 comment appears at once", immediate === 1 && (await page.locator(".comment").count()) === before + 1);
  check("7e.2 draft cleared", (await page.inputValue(".comment-input")) === "");
  await page.waitForTimeout(1200);
  await page.unroute("**/_yuka/action/**");
  check("7e.3 still one copy after response", (await page.locator(".comment", { hasText: body }).count()) === 1);
  await page.reload({ waitUntil: "networkidle" });
  await page.waitForSelector(".comment-input");
  check("7e.4 comment present after reload", (await page.locator(".comment", { hasText: body }).count()) === 1);
});

await step("8. 404", async () => {
  expectedFailures = 404;
  const res = await page.goto(base + "/issue/NOPE", { waitUntil: "networkidle" });
  expectedFailures = 0;
  check("8a status 404", res?.status() === 404, String(res?.status()));
  check("8b not found page", (await page.locator(".not-found h1").textContent()) === "Issue not found");
});

await step("9. screenshots", async () => {
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  await page.screenshot({ path: join(shots, "index.png"), fullPage: true });
  await page.goto(base + "/my", { waitUntil: "networkidle" });
  await page.screenshot({ path: join(shots, "my.png") });
  expectedFailures = 404;
  await page.goto(base + "/issue/NOPE", { waitUntil: "networkidle" });
  expectedFailures = 0;
  await page.screenshot({ path: join(shots, "not-found.png") });
  check("9 screenshots written to e2e/screenshots", true);
});

check("10 no page errors in whole run", pageErrors.length === 0, pageErrors.join(" | "));
const lateConsole = consoleErrors.filter((e) => !/status of (500|404)/.test(e));
check("11 no unexpected console errors in whole run", lateConsole.length === 0, lateConsole.join(" | "));
check("11b no hydration mismatch in whole run", mismatches.length === 0, mismatches.join(" | "));
check("12 no unexpected failed requests in whole run", failedRequests.length === 0, failedRequests.join(" | "));

await browser.close();
console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
