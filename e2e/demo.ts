import type { Page, Response } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { request } from "node:http";
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, openSync } from "node:fs";

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
const allRequests: { url: string; t: number; navigate: boolean; keys?: string; prefetch: boolean }[] = [];
page.on("request", (r) =>
  allRequests.push({ url: r.url(), t: Date.now(), navigate: r.headers()["yuka-navigate"] !== undefined, keys: r.headers()["yuka-navigate"], prefetch: r.headers()["yuka-prefetch"] === "1" }),
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
      if (e.matches(".row, .filter, .list, .toolbar, .new-issue-button, .comment-input, .comment, .props, .props select, [class^=related_], [class^=related-list_] li"))
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
  const opened = allRequests.length;
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  await page.locator(".filter").hover();
  await page.locator(".filter").focus();
  await page.waitForTimeout(200);
  await page.locator(".filter").blur();
  await page.evaluate(() => ((window as any).__marker = "alive"));
  const marker = () => page.evaluate(() => (window as any).__marker as string | undefined);
  const titleBefore = await page.title();
  await page.evaluate(() => window.scrollTo(0, 250));
  const y = await page.evaluate(() => Math.round(window.scrollY));
  const mark = allRequests.length;
  const routerCode = (r: { url: string }) => /\/navigation(-[^/]*)?\.js$/.test(new URL(r.url).pathname);
  const loadedAtStart = allRequests.slice(opened, mark).filter(routerCode).length;
  await page.locator('.row[data-id="YUK-8"] .row-title').click();
  await page.waitForURL("**/issue/YUK-8");
  await page.waitForSelector(".comment-input");
  const navReq = allRequests.slice(mark).filter((r) => r.url.endsWith("/issue/YUK-8"));
  check("3b.0 the navigation code loads on first use, not at start nor on pointer or focus off links", loadedAtStart === 0 && allRequests.slice(mark).filter(routerCode).length === 1, `at start=${loadedAtStart} after=${allRequests.slice(mark).filter(routerCode).length}`);
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
  const bar = () =>
    page.evaluate(() => {
      const element = document.querySelector("[data-nav-progress]") as any;
      return { state: element?.getAttribute("data-nav-progress"), kept: element?.__kept as boolean | undefined };
    });
  await page.waitForFunction(() => !!(document.querySelector("[data-nav-progress]") as any)?.__yuka_animationstart, null, { timeout: 5000 });
  await page.evaluate(() => ((document.querySelector("[data-nav-progress]") as any).__kept = true));
  check("3c.1 the progress bar (Idle) started without interaction and is idle", (await bar()).state === "idle", JSON.stringify(await bar()));
  const current = () => page.evaluate(() => [...document.querySelectorAll(".nav-link")].map((a) => `${a.getAttribute("href")}=${a.getAttribute("aria-current")}`).join(" "));
  check("3c.2 Issues link is current on /", (await current()) === "/=page /my=null /insights=null /report=null /canvas=null", await current());
  const buttonInView = () =>
    page.evaluate(() => {
      const rect = document.querySelector(".new-issue-button")!.getBoundingClientRect();
      return { top: Math.round(rect.top), bottom: Math.round(rect.bottom), scrollY: Math.round(scrollY), height: innerHeight };
    });
  const atTop = await buttonInView();
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  const atEnd = await buttonInView();
  await page.evaluate(() => window.scrollTo(0, 0));
  check(
    "3c.2b the new issue button stays in the viewport on a long list",
    [atTop, atEnd].every((box) => box.top >= 0 && box.bottom <= box.height) && atEnd.scrollY > 0,
    JSON.stringify({ atTop, atEnd }),
  );
  const outlet = page.waitForResponse((r) => r.url().endsWith("/issue/YUK-3"));
  await page.locator('.row[data-id="YUK-3"] .row-title').click();
  const response = await outlet;
  await page.waitForURL("**/issue/YUK-3");
  await page.waitForSelector(".comment-input");
  check("3c.3 partial response for the shell outlet", response.headers()["yuka-outlet"] === "L0" && !(await response.text()).includes("<!DOCTYPE"), String(response.headers()["yuka-outlet"]));
  await page.waitForSelector("[data-nav-progress=finished]", { timeout: 5000 });
  check("3c.4 the shell progress bar kept its element and its state (finished)", (await bar()).kept === true && (await marker()) === "alive", JSON.stringify(await bar()));
  check("3c.5 title changed", (await page.title()) === "YUK-3", await page.title());
  check("3c.6 no link is current on an issue page", (await current()) === "/=null /my=null /insights=null /report=null /canvas=null", await current());
  await page.locator(".new-issue-button").click();
  await page.waitForSelector(".dialog", { timeout: 2000 });
  check("3c.7 New_issue in the kept sidebar still opens", (await page.locator(".dialog").count()) === 1);
  await page.keyboard.press("Escape");
  await page.locator('.nav-link[href="/my"]').click();
  await page.waitForURL("**/my");
  await page.waitForSelector(".row");
  check("3c.8 aria-current moves to My issues", (await current()) === "/=null /my=page /insights=null /report=null /canvas=null", await current());
  check("3c.9 progress bar still kept", (await bar()).kept === true, JSON.stringify(await bar()));
  const y0 = await page.evaluate(() => Math.round(window.scrollY));
  check("3c.10 a new page starts at the top", y0 === 0, String(y0));
  await page.route("**/my", async (route) => {
    const real = await route.fetch();
    await route.fulfill({ response: real, headers: { ...real.headers(), "yuka-build": "changed" } });
  });
  await page.goBack();
  await page.waitForURL("**/issue/YUK-3");
  await page.waitForSelector(".comment-input");
  check("3c.11 back is partial too (progress bar kept)", (await bar()).kept === true && (await marker()) === "alive", JSON.stringify(await bar()));
  await page.locator('.nav-link[href="/my"]').click();
  await page.waitForURL("**/my");
  await page.waitForSelector(".row");
  await page.unroute("**/my");
  check("3c.12 another Yuka-Build is a full page load", (await marker()) === undefined && (await bar()).kept === undefined, `marker=${await marker()} ${JSON.stringify(await bar())}`);
});

await step("3d. a page with no island loads no script", async () => {
  const pg = await browser.newPage();
  const scripts: string[] = [];
  pg.on("request", (r) => { if (r.resourceType() === "script") scripts.push(r.url()); });
  await pg.goto(base + "/about", { waitUntil: "networkidle" });
  const inline = await pg.evaluate(() => [...document.querySelectorAll("script")].filter((s) => s.type !== "importmap" && !s.textContent!.includes("yuka-demo-theme")).length);
  check("3d.1 /about requests no script and has no inline script but the theme script", scripts.length === 0 && inline === 0, `${scripts.join(",")} inline=${inline}`);
  await pg.close();
});

await step("3i. input made before hydration", async () => {
  const pg = await browser.newPage();
  const errors: string[] = [];
  pg.on("console", (m) => (m.type() === "error" || m.text().includes("hydration mismatch")) && errors.push(m.text()));
  pg.on("pageerror", (e) => errors.push(String(e)));
  const t0 = Date.now();
  await pg.goto(base + "/before-hydration", { waitUntil: "commit" });
  await pg.waitForSelector("#early-note", { timeout: 3000 });
  const early = await pg.textContent("yuka-island p");
  await pg.locator("#early-name").pressSequentially("typed early");
  await pg.locator("#early-agreed").check();
  await pg.locator("#early-size").selectOption("large");
  await pg.locator("#early-note").pressSequentially("a note");
  await pg.locator("#early-name").evaluate((el: HTMLInputElement) => { el.focus(); el.setSelectionRange(2, 5); });
  const typedAt = Date.now() - t0;
  await pg.waitForFunction(() => document.querySelector("yuka-island p")?.textContent?.startsWith("Interactive"), null, { timeout: 8000 });
  const readyAt = Date.now() - t0;
  const got = await pg.evaluate(() => {
    const v = (id: string) => (document.getElementById(id) as HTMLInputElement).value;
    const t = (id: string) => document.getElementById(id)!.textContent;
    const name = document.getElementById("early-name") as HTMLInputElement;
    return {
      values: [v("early-name"), String((document.getElementById("early-agreed") as HTMLInputElement).checked), v("early-size"), v("early-note")].join("|"),
      states: ["early-name-state", "early-agreed-state", "early-size-state", "early-note-state"].map(t).join("|"),
      focus: [document.activeElement === name, name.selectionStart, name.selectionEnd].join(","),
    };
  });
  check("3i.1 the fields were changed before the late script ran", (early ?? "").startsWith("Not interactive") && typedAt < 2500 && readyAt >= 3000, `status=${early} typed by ${typedAt}ms, interactive at ${readyAt}ms`);
  check("3i.2 hydration keeps what the user did", got.values === "typed early|true|large|a note", got.values);
  check("3i.3 each State learned it", got.states === "State: typed early|State: true|State: large|State: a note", got.states);
  check("3i.4 focus and selection did not move", got.focus === "true,2,5", got.focus);
  await pg.locator("#early-name").press("End");
  await pg.locator("#early-name").pressSequentially("!");
  check("3i.5 the input works after hydration", (await pg.textContent("#early-name-state")) === "State: typed early!", (await pg.textContent("#early-name-state")) ?? "");
  check("3i.6 no console error and no hydration mismatch", errors.length === 0, errors.join(" | "));
  await pg.close();
});

await step("3j. themes and the navigation progress bar", async () => {
  const themeAtBody = `
    new MutationObserver((records, observer) => {
      if (document.body) {
        window.__themeAtBody = document.documentElement.getAttribute("data-theme");
        window.__codeAtBody = document.documentElement.getAttribute("data-code-theme");
        observer.disconnect();
      }
    }).observe(document, { childList: true, subtree: true });
  `;
  for (const scheme of ["dark", "light"] as const) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, colorScheme: scheme });
    const p = await ctx.newPage();
    await p.goto(base + "/", { waitUntil: "networkidle" });
    check(`3j.1 no choice: prefers-color-scheme ${scheme} gives the ${scheme} theme and the Auto code style`, (await p.getAttribute("html", "data-theme")) === scheme && (await p.getAttribute("html", "data-code-theme")) === null);
    await ctx.close();
  }
  const html = await (await fetch(base + "/")).text();
  const at = (needle: string) => html.indexOf(needle);
  const script = html.slice(html.lastIndexOf("<script", at("yuka-demo-theme")), html.indexOf("</script>", at("yuka-demo-theme")));
  check(
    "3j.2 one script in the head, before the stylesheet and the body, restores the theme and the code style",
    at("yuka-demo-theme") > 0 && at("yuka-demo-theme") < at('rel="stylesheet"') && at("yuka-demo-theme") < at("<body") && script.includes("yuka-demo-code-theme") && script.length < 600 && !html.includes("data-code-style"),
    `${script.length} ${script}`,
  );
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, colorScheme: "dark" });
  await ctx.addInitScript(themeAtBody);
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("pageerror", (e) => errors.push(String(e)));
  await p.goto(base + "/", { waitUntil: "networkidle" });
  await p.click("#theme-button");
  await p.waitForSelector("[role=menu]");
  check("3j.3 the menu opens with the current theme checked and focused", (await p.getAttribute("#theme-dark", "aria-checked")) === "true" && (await p.evaluate(() => document.activeElement?.id)) === "theme-dark");
  await p.click("#theme-gray");
  check("3j.4 a click on Gray applies and stores it", (await p.getAttribute("html", "data-theme")) === "gray" && (await p.evaluate(() => localStorage.getItem("yuka-demo-theme"))) === "gray" && (await p.locator("[role=menu]").count()) === 0);
  check("3j.5 the colours follow the theme", (await p.evaluate(() => getComputedStyle(document.body).backgroundColor)) === "rgb(43, 44, 48)", await p.evaluate(() => getComputedStyle(document.body).backgroundColor));
  await p.focus("#theme-button");
  await p.keyboard.press("Enter");
  await p.waitForSelector("[role=menu]");
  await p.keyboard.press("ArrowDown");
  check("3j.6 ArrowDown moves the focus", (await p.evaluate(() => document.activeElement?.id)) === "theme-pale");
  await p.keyboard.press("Enter");
  check("3j.7 Enter chooses, the menu closes and the button has the focus", (await p.getAttribute("html", "data-theme")) === "pale" && (await p.locator("[role=menu]").count()) === 0 && (await p.evaluate(() => document.activeElement?.id)) === "theme-button");
  await p.keyboard.press("Enter");
  await p.waitForSelector("[role=menu]");
  await p.keyboard.press("Escape");
  check("3j.8 Escape closes without a change", (await p.locator("[role=menu]").count()) === 0 && (await p.getAttribute("html", "data-theme")) === "pale");
  await p.evaluate(() => ((window as any).__alive = true));
  await p.locator('.row[data-id="YUK-1"] .row-title').click();
  await p.waitForSelector("[data-nav-progress=loading]", { timeout: 2000 });
  await p.waitForTimeout(300);
  const bar = await p.evaluate(() => {
    const element = document.querySelector("[data-nav-progress]")!;
    const box = element.getBoundingClientRect();
    return { width: box.width, top: box.top, state: element.getAttribute("data-nav-progress"), path: location.pathname };
  });
  check("3j.9 a slow navigation shows the progress bar at the top while the old page is shown", bar.width > 0 && bar.top === 0 && bar.state === "loading" && bar.path === "/", JSON.stringify(bar));
  await p.waitForURL("**/issue/YUK-1");
  await p.waitForSelector("[data-nav-progress=finished]", { timeout: 5000 });
  await p.waitForTimeout(700);
  check("3j.10 the bar goes away when the page is shown", (await p.evaluate(() => getComputedStyle(document.querySelector("[data-nav-progress]")!).opacity)) === "0");
  check("3j.11 the theme stays after a client navigation", (await p.evaluate(() => (window as any).__alive)) === true && (await p.getAttribute("html", "data-theme")) === "pale");
  await p.goBack();
  await p.waitForSelector(".row");
  await p.waitForFunction(() => document.querySelector("[data-nav-progress]")?.getAttribute("data-nav-progress") !== "loading", null, { timeout: 5000 });
  check("3j.12 back: the bar is not left loading", true);
  await p.reload({ waitUntil: "networkidle" });
  check("3j.13 the theme stays after a reload, set before the body is parsed", (await p.getAttribute("html", "data-theme")) === "pale" && (await p.evaluate(() => (window as any).__themeAtBody)) === "pale", String(await p.evaluate(() => (window as any).__themeAtBody)));
  await p.click("#theme-button");
  await p.click("#code-nord");
  for (const path of ["/about", "/before-hydration"]) {
    await p.goto(base + path, { waitUntil: "networkidle" });
    check(
      `3j.14 ${path} follows the theme and the code style`,
      (await p.evaluate(() => (window as any).__themeAtBody)) === "pale" && (await p.evaluate(() => (window as any).__codeAtBody)) === "nord" &&
        (await p.evaluate(() => getComputedStyle(document.body).backgroundColor)) === "rgb(247, 245, 251)",
    );
  }
  check("3j.15 no page errors", errors.length === 0, errors.join(" | "));
  await ctx.close();
  const small = await browser.newContext({ viewport: { width: 390, height: 560 } });
  const s = await small.newPage();
  await s.goto(base + "/issue/YUK-2", { waitUntil: "networkidle" });
  await s.click("#theme-button");
  await s.waitForSelector("[role=menu]");
  await s.keyboard.press("End");
  await s.waitForFunction(() => document.activeElement?.id === "code-light");
  const box = await s.evaluate(() => {
    const menu = document.querySelector("[role=menu]")!.getBoundingClientRect();
    const last = document.activeElement!.getBoundingClientRect();
    return { left: menu.left, right: menu.right, top: menu.top, bottom: menu.bottom, lastTop: last.top, lastBottom: last.bottom, width: innerWidth, height: innerHeight };
  });
  check(
    "3j.16 at 390 px the menu stays in the viewport and scrolls to its last item",
    box.left >= 0 && box.right <= box.width && box.bottom <= box.height && box.lastTop >= box.top && box.lastBottom <= box.bottom,
    JSON.stringify(box),
  );
  await small.close();
});

await step("3e. live data is embedded", async () => {
  const pg = await browser.newPage();
  const posts: string[] = [];
  pg.on("request", (r) => { if (r.method() === "POST") posts.push(new URL(r.url()).pathname); });
  const res = await pg.goto(base + "/", { waitUntil: "networkidle" });
  const html = (await res?.text()) ?? "";
  await pg.waitForSelector(".row");
  check("3e.1 the list, its live answer and the token are in the server HTML", html.includes('class="row-title"') && html.includes('data-yuka-answer="l:issues') && html.includes('data-yuka-answer="l:csrf"'), String(html.length));
  check("3e.2 no labels request at load, the chips are in the server HTML", html.includes('data-yuka-answer="r:labels') && html.includes('class="chip"') && !posts.some((p) => p.endsWith("/labels")), posts.join(","));
  const all = await pg.locator(".row").count();
  await pg.locator(".chip", { hasText: /^client / }).click();
  const only = await pg.locator(".row").count();
  const labelled = await pg.locator(".row").evaluateAll((rows) => rows.every((r) => !!r.querySelector(".label-client")));
  check("3e.4 a label chip filters the list", only > 0 && only < all && labelled, `${all} -> ${only}`);
  await pg.locator(".chip.on").click();
  await pg.locator('.nav-link[href="/my"]').click();
  await pg.waitForURL("**/my");
  await pg.waitForSelector(".row");
  check("3e.3 no labels request after a client navigation", !posts.some((p) => p.endsWith("/labels")), posts.join(","));
  await pg.close();
});

await step("3f. prefetch and the navigation cache", async () => {
  await page.goto(base + "/", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  const requestsTo = (from: number, path: string) => allRequests.slice(from).filter((r) => new URL(r.url).pathname === path);
  const link = (id: string) => page.locator(`.row[data-id="${id}"] .row-title`);
  let from = allRequests.length;
  await link("YUK-5").hover();
  await page.waitForTimeout(300);
  const pre = requestsTo(from, "/issue/YUK-5");
  check("3f.1 hover sends one prefetch", pre.length === 1 && pre[0].prefetch && pre[0].navigate, JSON.stringify(pre));
  await page.evaluate(() => {
    const w = window as any;
    w.__vt = [];
    const real = (document as any).startViewTransition?.bind(document);
    (document as any).startViewTransition = (f: () => void) => {
      w.__vt.push(document.documentElement.getAttribute("data-yuka-nav"));
      return real ? real(f) : (f(), { ready: Promise.resolve(), finished: Promise.resolve() });
    };
  });
  await link("YUK-5").click();
  await page.waitForURL("**/issue/YUK-5");
  await page.waitForSelector(".comment-input");
  const vt = await page.evaluate(() => (window as any).__vt);
  check("3f.2a the navigation runs in a view transition (demo enables them)", JSON.stringify(vt) === '["push"]', JSON.stringify(vt));
  const removed = await page
    .waitForFunction(() => document.documentElement.getAttribute("data-yuka-nav") === null, null, { timeout: 3000 })
    .then(() => true, () => false);
  check("3f.2b data-yuka-nav is removed after the transition", removed);
  check("3f.2 the click uses the prefetch", requestsTo(from, "/issue/YUK-5").length === 1, String(requestsTo(from, "/issue/YUK-5").length));
  await page.goBack();
  await page.waitForSelector(".row");
  await page.mouse.move(1, 1);
  from = allRequests.length;
  await link("YUK-5").click();
  await page.waitForURL("**/issue/YUK-5");
  await page.waitForSelector(".comment-input");
  const again = requestsTo(from, "/issue/YUK-5");
  check("3f.3 a no-store page is fetched again", again.length === 1, JSON.stringify(again));
  await page.goBack();
  await page.waitForSelector(".row");
  await page.mouse.move(1, 1);
  from = allRequests.length;
  await link("YUK-6").hover();
  await page.waitForTimeout(300);
  check("3f.4 prefetched before the action", requestsTo(from, "/issue/YUK-6").length === 1);
  const posts = actionPosts.length;
  const failedBefore = failedRequests.length;
  const before = statusSlug(await statusOf("YUK-6"));
  const label = before === "done" ? "Todo" : "Done";
  await page.locator('.row[data-id="YUK-6"] button[aria-label="Change status"]').click();
  await page.locator(".menu-item", { hasText: new RegExp(`^\\s*${label}\\s*$`) }).click();
  const deadline = Date.now() + 5000;
  while (actionPosts.length === posts && Date.now() < deadline) await page.waitForTimeout(50);
  await page.waitForTimeout(100);
  await link("YUK-6").click();
  await page.waitForURL("**/issue/YUK-6");
  await page.waitForSelector(".comment-input");
  const dropped = (f: string) => f === `GET ${base}/issue/YUK-6 net::ERR_ABORTED`;
  const aborted = failedRequests.slice(failedBefore).filter(dropped).length;
  failedRequests.splice(failedBefore, failedRequests.length - failedBefore, ...failedRequests.slice(failedBefore).filter((f) => !dropped(f)));
  check("3f.6 emptying the cache aborts at most the one prefetch in flight", aborted <= 1, String(aborted));
  check("3f.5 a successful action clears the cache (the click fetches again)", actionPosts.slice(posts).filter((p) => p.url.endsWith("/update_issue")).length === 1 && requestsTo(from, "/issue/YUK-6").length === 2, `posts=${actionPosts.length - posts} ${JSON.stringify(requestsTo(from, "/issue/YUK-6"))}`);
  await page.goto(base + "/", { waitUntil: "networkidle" });
});


const recordSockets = () => {
  if (!navigator.onLine) Object.defineProperty(Navigator.prototype, "onLine", { configurable: true, get: () => true });
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
  }, null, { timeout: 5000 });
const livePage = async (path: string, at = base) => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  await ctx.addInitScript(recordSockets);
  const routes: { close: (o?: { code?: number; reason?: string }) => Promise<void> }[] = [];
  await ctx.routeWebSocket(/\/_yuka\/live$/, (ws) => {
    ws.connectToServer();
    routes.push(ws);
  });
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  p.on("pageerror", (e) => errors.push(String(e)));
  await p.goto(at + path, { waitUntil: "networkidle" });
  await p.waitForSelector(".row");
  await liveOpen(p);
  return { ctx, p, errors, routes };
};
const statusIn = async (p: Page, id: string) =>
  statusSlug(await p.locator(`.row[data-id="${id}"] button[aria-label="Change status"] svg`).first().getAttribute("class"));
const pickStatus = async (p: Page, id: string, label: string) => {
  await p.locator(`.row[data-id="${id}"] button[aria-label="Change status"]`).click();
  await p.locator(".menu-item", { hasText: new RegExp(`^\\s*${label}\\s*$`) }).click();
};
const handshake = (origin: string) =>
  new Promise<number>((resolve, reject) => {
    const u = new URL(base);
    const req = request({
      host: u.hostname,
      port: u.port,
      path: "/_yuka/live",
      headers: {
        Connection: "Upgrade",
        Upgrade: "websocket",
        "Sec-WebSocket-Version": "13",
        "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
        Origin: origin,
      },
    });
    req.on("response", (r) => {
      r.resume();
      resolve(r.statusCode ?? 0);
    });
    req.on("upgrade", (_r, socket) => {
      socket.destroy();
      resolve(101);
    });
    req.on("error", reject);
    req.end();
  });

const second = process.env.YUKA_E2E_SECOND;
if (second)
  await step("3h. live data across two server nodes", async () => {
    const A = await livePage("/");
    const B = await livePage("/", second);
    const id = (await B.p.locator(".row").first().getAttribute("data-id")) ?? "";
    const before = await statusIn(B.p, id);
    const target = before === "done" ? "todo" : "done";
    await pickStatus(A.p, id, target === "done" ? "Done" : "Todo");
    const seen = await B.p
      .waitForFunction(
        ([i, t]) => document.querySelector(`.row[data-id="${i}"] button[aria-label="Change status"] svg`)?.getAttribute("class")?.includes("status-" + t),
        [id, target],
        { timeout: 2000 },
      )
      .then(() => true, () => false);
    check("3h.1 a change in a page on node 1 shows in a page on node 2", seen, `${id} ${before} -> ${target} on ${second}`);
    const back = target === "done" ? "todo" : "done";
    await pickStatus(B.p, id, back === "done" ? "Done" : "Todo");
    const shown: string[] = [];
    for (let i = 0; i < 15; i++) {
      shown.push(await statusIn(B.p, id));
      await B.p.waitForTimeout(100);
    }
    const inA = await A.p
      .waitForFunction(
        ([i, t]) => document.querySelector(`.row[data-id="${i}"] button[aria-label="Change status"] svg`)?.getAttribute("class")?.includes("status-" + t),
        [id, back],
        { timeout: 2000 },
      )
      .then(() => true, () => false);
    check("3h.2 a change made on node 2 never flickers back there and reaches node 1", shown.every((s) => s === back) && inA, `node 2 showed ${shown.join(",")}, node 1 got it: ${inA}`);
    const unexpected = [...A.errors, ...B.errors];
    check("3h.3 no console errors in the two-node pages", unexpected.length === 0, unexpected.join(" | "));
    await A.ctx.close();
    await B.ctx.close();
  });

await step("3g. live data", async () => {
  const A = await livePage("/");
  const B = await livePage("/my");
  const id = (await B.p.locator(".row").first().getAttribute("data-id")) ?? "";
  const before = await statusIn(B.p, id);
  const target = before === "done" ? "todo" : "done";
  const label = target === "done" ? "Done" : "Todo";
  const t0 = Date.now();
  await pickStatus(A.p, id, label);
  const seen = await B.p
    .waitForFunction(
      ([i, t]) => document.querySelector(`.row[data-id="${i}"] button[aria-label="Change status"] svg`)?.getAttribute("class")?.includes("status-" + t),
      [id, target],
      { timeout: 1000 },
    )
    .then(() => Date.now() - t0, () => -1);
  check("3g.1 a status change in page A (/) shows in page B (/my) within 1 s", seen >= 0, `${id} ${before} -> ${target} after ${seen} ms`);

  await B.p.goto(base + "/", { waitUntil: "networkidle" });
  await B.p.waitForSelector(".row");
  await liveOpen(B.p);
  const title = `Live issue ${run}`;
  await A.p.locator("body").click({ position: { x: 5, y: 5 } });
  await A.p.keyboard.press("c");
  await A.p.waitForSelector(".dialog");
  await A.p.fill(".dialog-title", title);
  await A.p.locator(".dialog .button.primary").click();
  const created = await B.p.locator(".row", { hasText: title }).waitFor({ timeout: 2000 }).then(() => true, () => false);
  check("3g.2 an issue created in page A shows in page B", created);
  await A.p.waitForURL(/\/issue\/YUK-\d+$/);
  await A.p.goBack();
  await A.p.waitForSelector(`.row:has-text("${title}")`);

  await B.routes[B.routes.length - 1].close({ code: 4001, reason: "dropped by the test" });
  const offline = await B.p.waitForSelector(".offline", { timeout: 1000 }).then(() => true, () => false);
  const back = await B.p.waitForSelector(".offline", { state: "detached", timeout: 5000 }).then(() => true, () => false);
  check("3g.3 a closed socket shows Offline, then the page reconnects", offline && back, `offline=${offline} back=${back}`);
  await liveOpen(B.p);

  const before2 = await statusIn(B.p, id);
  const target2 = before2 === "done" ? "todo" : "done";
  await A.p.route("**/_yuka/action/**", async (route) => {
    await new Promise((r) => setTimeout(r, 300));
    await route.fulfill({ status: 500, contentType: "application/json", body: '{"error":"action failed"}' });
  });
  await pickStatus(A.p, id, target2 === "done" ? "Done" : "Todo");
  const shownInA = await statusIn(A.p, id);
  let seenInB = false;
  for (let i = 0; i < 12; i++) {
    if ((await statusIn(B.p, id)) === target2) seenInB = true;
    await B.p.waitForTimeout(100);
  }
  await A.p.unroute("**/_yuka/action/**");
  check("3g.4 a forced 500 rolls back in page A and page B never shows the change", shownInA === target2 && (await statusIn(A.p, id)) === before2 && !seenInB, `A ${before2} -> ${shownInA} -> ${await statusIn(A.p, id)}, B saw it: ${seenInB}`);

  const foreign = await handshake("http://evil.example");
  const same = await handshake(base);
  check("3g.5 a WebSocket handshake from another origin gets 403", foreign === 403 && same === 101, `foreign=${foreign} same=${same}`);
  const unexpected = [...A.errors, ...B.errors].filter((e) => !/status of 500/.test(e));
  check("3g.6 no unexpected console errors in the live pages", unexpected.length === 0, unexpected.join(" | "));
  await A.ctx.close();
  await B.ctx.close();
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
    await route.continue().catch(() => {});
  });
  actionPosts.length = 0;
  const labelsAgain = page
    .waitForResponse((r) => r.url().endsWith("/_yuka/action/labels") && r.status() === 200, { timeout: 5000 })
    .then(() => true, () => false);
  await page.locator(`.row[data-id="${id}"] button[aria-label="Change status"]`).click();
  await page.locator(".menu-item", { hasText: new RegExp(`^\\s*${label}\\s*$`) }).click();
  await page.mouse.move(0, 0);
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
  const updates = actionPosts.filter((p) => p.url.endsWith("/update_issue"));
  check(
    "4b POST /_yuka/action/update_issue returned 200",
    updates.length === 1 && updates[0].status === 200,
    JSON.stringify(actionPosts),
  );
  check("4e the label counts are fetched again after a status change", await labelsAgain);
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
  const listUrl = page.url();
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
  check("6c0g typed errors do not navigate", page.url() === listUrl, `${listUrl} -> ${page.url()}`);
  const headerBefore = Number((await page.locator(".page-header .group-count").first().textContent()) ?? "NaN");
  const title = `E2E issue ${run}`;
  await page.fill(".dialog-title", title);
  await page.fill(".dialog-description", "Created by the browser check.");
  const before = await page.locator(".row").count();
  await page.evaluate(() => ((window as any).__created = "alive"));
  await page.locator(".dialog .button.primary").click();
  await page.waitForURL(/\/issue\/YUK-\d+$/, { timeout: 3000 });
  await page.waitForSelector(".issue-title");
  const landed = {
    path: new URL(page.url()).pathname,
    title: await page.locator(".issue-title").textContent(),
    description: (await page.locator(".issue-description").textContent())?.trim(),
    marker: await page.evaluate(() => (window as any).__created),
    dialogs: await page.locator(".dialog").count(),
    focus: await page.evaluate(() => !!document.activeElement?.isConnected && !document.activeElement.closest(".dialog")),
  };
  check("6c issue opens its page with a client navigation", /^\/issue\/YUK-\d+$/.test(landed.path) && landed.title === title && landed.description === "Created by the browser check." && landed.marker === "alive" && landed.dialogs === 0, JSON.stringify(landed));
  check("6c3 focus is on a connected element outside the dialog", landed.focus, JSON.stringify(landed));
  await page.locator("body").click({ position: { x: 5, y: 5 } });
  await page.keyboard.press("c");
  await page.waitForSelector(".dialog", { timeout: 2000 });
  const fresh = {
    title: await page.inputValue(".dialog-title"),
    description: await page.inputValue(".dialog-description"),
    errors: await page.locator(".dialog .error").count(),
    disabled: await page.locator(".dialog .button.primary").isDisabled(),
  };
  check("6c4 c on the new issue opens an empty dialog", fresh.title === "" && fresh.description === "" && fresh.errors === 0 && !fresh.disabled, JSON.stringify(fresh));
  await page.keyboard.press("Escape");
  await page.waitForSelector(".dialog", { state: "detached", timeout: 2000 });
  await page.goBack();
  await page.waitForURL(listUrl);
  await page.waitForSelector(`.row:has-text("${title}")`, { timeout: 3000 });
  const row = page.locator(".row", { hasText: title });
  check("6c5 Back is a client navigation to the list", (await page.evaluate(() => (window as any).__created)) === "alive");
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

await step("6g. workspaces", async () => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto(base + "/w/stress", { waitUntil: "networkidle" });
  await page.waitForSelector(".row");
  const current = () => page.evaluate(() => [...document.querySelectorAll(".workspace-link")].map((a) => `${a.getAttribute("href")}=${a.getAttribute("aria-current")}`).join(" "));
  check("6g.1 the stress list has 2000 rows", (await page.locator(".row").count()) === 2000, String(await page.locator(".row").count()));
  check("6g.2 the stress list has 30 label chips", (await page.locator(".chip").count()) === 30, String(await page.locator(".chip").count()));
  check("6g.3 the switcher marks Stress", (await current()) === "/=false /w/stress=true", await current());
  const github = page.locator('.topbar-link[href="https://github.com/davesnx/yuka"]');
  const x = page.locator('.topbar-link[href="https://x.com/davesnx"]');
  check("6g.4 GitHub and X links open apart with rel=noopener",
    (await github.getAttribute("rel")) === "noopener" && (await github.getAttribute("target")) === "_blank" &&
    (await x.getAttribute("rel")) === "noopener" && (await x.getAttribute("target")) === "_blank" && (await x.textContent()) === "@davesnx");
  const avatar = await page.evaluate(() => (document.querySelector(".profile-avatar") as HTMLImageElement | null)?.naturalWidth ?? 0);
  check("6g.5 the avatar loads from /static", avatar > 0, String(avatar));
  const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check("6g.6 no horizontal overflow at 1280 px", (await overflow()) <= 0, String(await overflow()));
  await page.setViewportSize({ width: 390, height: 800 });
  check("6g.7 no horizontal overflow at 390 px", (await overflow()) <= 0, String(await overflow()));
  const navLines = await page.locator(".nav-link").evaluateAll((links) =>
    links.map((link) => {
      const range = document.createRange();
      range.selectNodeContents(link);
      return new Set([...range.getClientRects()].map((rect) => Math.round(rect.top))).size;
    }),
  );
  check("6g.7b at 390 px each nav link stays on one line", navLines.length === 5 && navLines.every((lines) => lines === 1), navLines.join(","));
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.locator(".filter").fill("speed up");
  const filtered = await page.locator(".row").count();
  check("6g.8 the filter works on 2000 issues", filtered > 0 && filtered < 2000, String(filtered));
  await page.locator(".filter").fill("");
  await page.locator(".page-header").first().click();
  await page.keyboard.press("j");
  await page.keyboard.press("j");
  const selected = await page.locator(".row.selected").getAttribute("data-id");
  await page.keyboard.press("Enter");
  await page.waitForURL(`**/w/stress/issue/${selected}`);
  await page.waitForSelector(".comment-input");
  check("6g.9 j, j, Enter opens a stress issue", /^STR-\d+$/.test(selected ?? ""), String(selected));
  const streamed = { comments: await page.locator(".comment").count(), hidden: await page.locator("[aria-label='Hidden comments'] [aria-live]").textContent() };
  check("6g.10 a stress issue streams its first 3 and last 5 comments and hides 192", streamed.comments === 8 && streamed.hidden === "192 hidden comments", JSON.stringify(streamed));
  check("6g.11 the crumb goes back to the stress list", (await page.locator(".crumb").getAttribute("href")) === "/w/stress");
  await page.locator(".crumb").click();
  await page.waitForURL("**/w/stress");
  await page.waitForSelector(".filter");
  await page.locator(".page-header").first().click();
  await page.keyboard.press("c");
  await page.waitForSelector(".dialog", { timeout: 2000 });
  const title = `Stress issue ${run}`;
  await page.fill(".dialog-title", title);
  await page.evaluate(() => ((window as any).__created = "stress"));
  await page.locator(".dialog .button.primary").click();
  await page.waitForURL(/\/w\/stress\/issue\/STR-\d+$/, { timeout: 30000 });
  await page.waitForSelector(".issue-title");
  const landed = { path: new URL(page.url()).pathname, title: await page.locator(".issue-title").textContent(), marker: await page.evaluate(() => (window as any).__created) };
  check("6g.12a creating in stress opens /w/stress/issue/STR-n with a client navigation", landed.title === title && landed.marker === "stress", JSON.stringify(landed));
  await page.goBack();
  await page.waitForURL("**/w/stress");
  await page.waitForSelector(`.row:has-text("${title}")`, { timeout: 30000 });
  const created = await page.locator(".row", { hasText: title }).getAttribute("data-id");
  check("6g.12b the issue page is the created issue", landed.path === `/w/stress/issue/${created}`, `${landed.path} ${created}`);
  check("6g.12 an issue made in stress gets a stress id", /^STR-\d+$/.test(created ?? "") && (await page.locator(".row").count()) === 2001, `${created} rows=${await page.locator(".row").count()}`);
  await page.evaluate(() => ((window as any).__workspace = "alive"));
  await page.locator('.workspace-link[href="/"]').click();
  await page.waitForURL(base + "/");
  await page.waitForSelector('.workspace-link[href="/"][aria-current="true"]', { timeout: 30000 });
  await page.waitForSelector(".row");
  check("6g.13 switching workspace is a client navigation", (await page.evaluate(() => (window as any).__workspace)) === "alive");
  check("6g.14 the switcher marks Home", (await current()) === "/=true /w/stress=false", await current());
  const yukaIds = await page.locator(".row").evaluateAll((rows) => rows.map((r) => r.getAttribute("data-id") ?? ""));
  check("6g.15 the yuka list has no stress issue", yukaIds.length > 0 && yukaIds.every((id) => id.startsWith("YUK-")) && (await page.locator(".row", { hasText: title }).count()) === 0, String(yukaIds.length));
  await page.locator('.workspace-link[href="/w/stress"]').click();
  await page.waitForURL("**/w/stress");
  await page.waitForSelector('.workspace-link[href="/w/stress"][aria-current="true"]', { timeout: 30000 });
  await page.waitForSelector(".row");
  check("6g.16 the new stress issue is still in stress", (await page.locator(".row", { hasText: title }).count()) === 1);
  const nav = await page.evaluate(() => [...document.querySelectorAll(".nav-link")].map((a) => `${a.getAttribute("href")}=${a.getAttribute("aria-current")}`).join(" "));
  check("6g.17 the sidebar links stay in the workspace", nav === "/w/stress=page /w/stress/my=null /w/stress/insights=null /w/stress/report=null /w/stress/canvas=null", nav);
});

await step("6i. the label menu", async () => {
  const pg = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await pg.goto(base + "/w/stress", { waitUntil: "networkidle" });
  await pg.waitForFunction(() => !!(document.querySelector("#labels-button") as any)?.__yuka_click, null, { timeout: 30000 });
  const sideways = () => pg.evaluate(() => { const chips = document.querySelector(".chips")!; return chips.scrollWidth - chips.clientWidth; });
  const shown = () => pg.evaluate(() => {
    const bottom = document.querySelector(".chips")!.getBoundingClientRect().bottom;
    return [...document.querySelectorAll(".chips .chip")].filter((chip) => chip.getBoundingClientRect().top < bottom).map((chip) => chip.getAttribute("data-label") ?? "");
  });
  const visibleAt1280 = await shown();
  check("6i.1 the stress chip row is one line that does not scroll sideways at 1280 px", (await sideways()) <= 0 && visibleAt1280.length > 0 && visibleAt1280.length < 30, `${await sideways()} ${visibleAt1280.length}`);
  const menuLabels = await pg.locator("#labels-menu [data-label]").count();
  await pg.locator("#labels-button").click();
  await pg.waitForSelector("#labels-menu:popover-open");
  const items = await pg.locator('#labels-menu [role="menuitemcheckbox"]').evaluateAll((nodes) => nodes.map((node) => node.getAttribute("data-label") ?? ""));
  const firstFocused = await pg.evaluate(() => document.activeElement?.getAttribute("data-label"));
  check("6i.2 the dots button opens a menu with every label, the first one focused", menuLabels === 0 && items.length === 30 && firstFocused === items[0], `${items.length} ${firstFocused}`);
  const hidden = items.filter((label) => !visibleAt1280.includes(label)).at(-1) ?? "";
  await pg.keyboard.press("End");
  const lastFocused = await pg.evaluate(() => document.activeElement?.getAttribute("data-label"));
  await pg.keyboard.press("Space");
  await pg.waitForURL(`**/w/stress?label=${hidden}`);
  await pg.waitForSelector(`#labels-menu [data-label="${hidden}"][aria-checked="true"]`);
  const rows = await pg.locator(".row").evaluateAll((nodes, label) => nodes.map((node) => !!node.querySelector(".label-" + label)), hidden);
  check("6i.3 End and Space choose a hidden label: the URL and the rows follow, the menu stays open",
    lastFocused === hidden && rows.length > 0 && rows.length < 2000 && rows.every(Boolean) && (await pg.locator("#labels-menu:popover-open").count()) === 1, `${hidden} ${lastFocused} ${rows.length}`);
  const chosenShown = (await shown()).includes(hidden) && (await pg.locator(`.chips .chip.on[data-label="${hidden}"]`).count()) === 1;
  check("6i.4 the chosen hidden label moves into the visible row", chosenShown, (await shown()).join(","));
  await pg.keyboard.press("Escape");
  await pg.waitForSelector("#labels-menu:popover-open", { state: "detached" });
  check("6i.5 Escape closes the menu and focus goes back to the dots button", (await pg.evaluate(() => document.activeElement?.id)) === "labels-button");
  await pg.locator("#labels-button").click();
  await pg.waitForSelector("#labels-menu:popover-open");
  await pg.locator(".page-header").first().click();
  await pg.waitForSelector("#labels-menu:popover-open", { state: "detached" });
  check("6i.6 a click outside closes the menu", (await pg.locator("#labels-menu:popover-open").count()) === 0);
  await pg.setViewportSize({ width: 390, height: 800 });
  await pg.waitForFunction((label) => {
    const bottom = document.querySelector(".chips")!.getBoundingClientRect().bottom;
    return document.querySelector(`.chips .chip[data-label="${label}"]`)!.getBoundingClientRect().top < bottom;
  }, hidden, { timeout: 5000 }).catch(() => {});
  check("6i.7 at 390 px the row does not scroll sideways and keeps the chosen label", (await sideways()) <= 0 && (await shown()).includes(hidden), `${await sideways()} ${(await shown()).join(",")}`);
  await pg.close();
});

await step("6h. insights", async () => {
  const errors: string[] = [];
  const pg = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  pg.on("console", (m) => { if (m.type() === "error" || m.text().includes("hydration mismatch")) errors.push(m.text()); });
  pg.on("pageerror", (e) => errors.push(String(e)));
  const html = await (await pg.request.get(base + "/insights")).text();
  const served = Number(/<dd data-metric="points">(\d+)<\/dd>/.exec(html)?.[1] ?? "0");
  check("6h.1 the server HTML has the seven charts and a point per issue", (html.match(/data-chart="/g) ?? []).length === 7 && served >= 25 && (html.match(/ r="2"/g) ?? []).length === served, `charts=${(html.match(/data-chart="/g) ?? []).length} points=${(html.match(/<circle /g) ?? []).length} issues=${served}`);
  const placeholders = ["fps", "update", "updates", "worst-frame", "long-frames", "nodes", "dom-nodes"].filter((metric) => !new RegExp(`data-metric="${metric}">-<`).test(html));
  check("6h.1b the server HTML has the panel with a placeholder for each measured metric", placeholders.length === 0 && html.includes('aria-live="off"'), placeholders.join(","));
  await pg.goto(base + "/insights", { waitUntil: "networkidle" });
  await pg.waitForFunction(() => !!(document.querySelector("button.chip") as any)?.__yuka_click, null, { timeout: 5000 });
  const nav = await pg.evaluate(() => [...document.querySelectorAll(".nav-link")].map((a) => `${a.getAttribute("href")}=${a.getAttribute("aria-current")}`).join(" "));
  check("6h.2 the sidebar marks Insights", nav === "/=null /my=null /insights=page /report=null /canvas=null", nav);
  const amounts = () => pg.evaluate(() => [...document.querySelectorAll('[data-chart="status"] g[data-key]')].map((g) => g.querySelector("text")?.textContent).join(","));
  const points = () => pg.locator('[data-chart="scatter"] circle').count();
  const all = await amounts();
  const allPoints = await points();
  await pg.locator("button.chip", { hasText: /^Urgent$/ }).click();
  await pg.waitForFunction((previous) => [...document.querySelectorAll('[data-chart="status"] g[data-key]')].map((g) => g.querySelector("text")?.textContent).join(",") !== previous, all, { timeout: 5000 }).catch(() => undefined);
  const urgent = await amounts();
  check("6h.3 a priority filter changes the status bars", urgent !== all && (await points()) < allPoints, `${all} -> ${urgent}`);
  await pg.locator('[data-chart="status"] g[data-key="done"] rect').click();
  check("6h.4 a click on a bar toggles its filter", (await pg.locator("button.chip", { hasText: /^Done$/ }).getAttribute("aria-pressed")) === "true");
  await pg.locator("button", { hasText: "Clear filters" }).click();
  await pg.waitForFunction((count) => document.querySelectorAll('[data-chart="scatter"] circle').length === count, allPoints, { timeout: 5000 }).catch(() => undefined);
  check("6h.5 clearing the filters restores the bars", (await amounts()) === all && (await points()) === allPoints, `${await amounts()} points=${await points()}`);
  await pg.locator('[data-chart="status"] g[data-key="todo"] rect').hover();
  const tip = await pg.locator('[data-chart="status"] g:last-child text').last().textContent();
  check("6h.6 hover shows a tooltip", /^Todo: \d+ issues?$/.test(tip ?? ""), String(tip));
  await pg.mouse.move(5, 790);
  const other = await browser.newPage();
  await other.goto(base + "/", { waitUntil: "networkidle" });
  await other.waitForFunction(() => !!(document.querySelector(".icon-button") as any)?.__yuka_click, null, { timeout: 5000 });
  const id = (await other.locator(".row").first().getAttribute("data-id")) ?? "";
  const before = await statusIn(other, id);
  const target = before === "done" ? "Todo" : "Done";
  await pickStatus(other, id, target);
  const live = await pg.waitForFunction((previous) => [...document.querySelectorAll('[data-chart="status"] g[data-key]')].map((g) => g.querySelector("text")?.textContent).join(",") !== previous, all, { timeout: 5000 }).then(() => true, () => false);
  check("6h.7 a status change in another page updates the charts", live, `${id} ${before} -> ${target}: ${await amounts()}`);
  await pickStatus(other, id, before === "done" ? "Done" : before === "todo" ? "Todo" : before === "in-progress" ? "In Progress" : before === "backlog" ? "Backlog" : "Canceled");
  await other.close();
  await pg.goto(base + "/w/stress/insights", { waitUntil: "networkidle" });
  await pg.waitForFunction(() => !!(document.querySelector("button.chip") as any)?.__yuka_click, null, { timeout: 30000 });
  const stress = Number(((await pg.locator('[data-metric="points"]').textContent()) ?? "").replace(/,/g, ""));
  check("6h.8 stress has a point per issue", stress >= 2000 && (await points()) === stress, `${await points()} of ${stress}`);
  const dates = pg.locator("[data-filters] button[data-dates]");
  const timeNote = () => pg.locator('section:has([data-chart="time"]) header > span').textContent();
  const datesText = async () => ((await dates.textContent()) ?? "").replace(/^Created/, "");
  const fullRange = await datesText();
  check("6h.12 the date range is a control in the filter band that shows the dates of the time chart", (await dates.count()) === 1 && fullRange === (await timeNote()) && / to /.test(fullRange), `${fullRange} / ${await timeNote()}`);
  const stressAmounts = await amounts();
  const reset = pg.locator("#insights-dates button", { hasText: "Full range" });
  await dates.click();
  await pg.waitForSelector("#insights-dates:popover-open");
  check("6h.13 the range control opens a dialog with the two dates; reset is off at the full range", (await pg.locator("#insights-dates").getAttribute("role")) === "dialog" && (await pg.locator('#insights-dates input[type="range"]').count()) === 2 && (await reset.isDisabled()));
  const from = pg.locator('#insights-dates input[data-bound="From"]');
  await from.focus();
  for (let press = 0; press < 20; press++) await pg.keyboard.press("ArrowRight");
  await pg.waitForFunction((full) => document.querySelector("[data-dates]")?.textContent?.replace(/^Created/, "") !== full, fullRange, { timeout: 5000 }).catch(() => {});
  const narrowed = await datesText();
  check("6h.14 arrow keys on From narrow the range; the control, the slider and the time chart show the same dates", narrowed !== fullRange && narrowed === (await timeNote()) && narrowed.startsWith((await from.getAttribute("aria-valuetext")) ?? "-"), `${narrowed} / ${await timeNote()} / ${await from.getAttribute("aria-valuetext")}`);
  await pg.waitForFunction((count) => document.querySelectorAll('[data-chart="scatter"] circle').length < count, stress, { timeout: 5000 }).catch(() => undefined);
  check("6h.15 the narrower range changes the charts", (await amounts()) !== stressAmounts && (await points()) < stress, `${stressAmounts} -> ${await amounts()} points=${await points()}`);
  await reset.click();
  await pg.waitForFunction((full) => document.querySelector("[data-dates]")?.textContent?.replace(/^Created/, "") === full, fullRange, { timeout: 5000 }).catch(() => {});
  await pg.waitForFunction((count) => document.querySelectorAll('[data-chart="scatter"] circle').length === count, stress, { timeout: 5000 }).catch(() => undefined);
  check("6h.16 Full range restores the dates and the charts", (await datesText()) === fullRange && (await amounts()) === stressAmounts && (await points()) === stress && (await reset.isDisabled()), `${await datesText()} ${await amounts()} points=${await points()}`);
  await pg.keyboard.press("Escape");
  await pg.waitForSelector("#insights-dates:popover-open", { state: "detached" });
  check("6h.17 Escape closes the range dialog", (await pg.locator("#insights-dates:popover-open").count()) === 0);
  const animate = pg.locator(".page-header button[data-animate]");
  const placement = await pg.evaluate(() => {
    const header = document.querySelector(".page-header")!.getBoundingClientRect();
    const button = document.querySelector(".page-header button[data-animate]")!.getBoundingClientRect();
    const others = [...document.querySelectorAll(".page-header > :not([data-animate])")].map((element) => element.getBoundingClientRect().right);
    return { gap: header.right - button.right, left: button.left, others: Math.max(...others), half: header.left + header.width / 2 };
  });
  check("6h.18 Animate is at the right of the Insights header and is not pressed", placement.gap < 40 && placement.left > placement.half && placement.left > placement.others && (await animate.getAttribute("aria-pressed")) === "false", JSON.stringify(placement));
  await pg.locator("button", { hasText: /^100x$/ }).click();
  const maxPoints = 20000;
  const hundredPoints = Math.min(stress * 100, maxPoints);
  const hundred = hundredPoints.toLocaleString("en-US");
  await pg.waitForFunction((text) => document.querySelector('[data-metric="points"]')?.textContent === text, hundred, { timeout: 10000 });
  const cappedNote = (await pg.locator("[data-capped]").textContent()) ?? "";
  check("6h.9 the 100x stress control makes 100 times the points, capped at 20,000 with a note", (await points()) === hundredPoints && cappedNote === "capped at 20,000 points", `${await points()} (${hundred}) ${cappedNote}`);
  const metric = (name: string) => pg.locator(`[data-metric="${name}"]`).textContent();
  await animate.click();
  check("6h.19 Animate is a toggle with aria-pressed", (await animate.getAttribute("aria-pressed")) === "true");
  const measured = await pg.waitForFunction(() => {
    const text = (name: string) => document.querySelector(`[data-metric="${name}"]`)?.textContent ?? "-";
    return Number(text("fps")) > 0 && / ms$/.test(text("update")) && Number(text("updates")) > 0 && / ms$/.test(text("worst-frame"))
      && /^\d+$/.test(text("long-frames")) && Number(text("nodes").replace(/,/g, "")) > 0 && Number(text("dom-nodes").replace(/,/g, "")) > 0
      && (document.querySelector("[data-frames] path")?.getAttribute("d") ?? "").startsWith("M");
  }, null, { timeout: 15000 }).then(() => true, () => false);
  const readings = Object.fromEntries(await Promise.all(["fps", "update", "updates", "worst-frame", "long-frames", "nodes", "dom-nodes", "points"].map(async (name) => [name, await metric(name)])));
  check("6h.10 animate runs and the panel shows a measured value for each metric", measured && readings.points === hundred, JSON.stringify(readings));
  const swept = await pg.waitForFunction((full) => document.querySelector("[data-dates]")?.textContent?.replace(/^Created/, "") !== full, fullRange, { timeout: 5000 }).then(() => true, () => false);
  check("6h.21 Animate sweeps the same range the control shows", swept && (await datesText()) !== fullRange, await datesText());
  await animate.click();
  check("6h.22 a second click stops Animate", (await animate.getAttribute("aria-pressed")) === "false");
  await reset.evaluate((button: HTMLButtonElement) => button.click());
  await pg.waitForFunction((full) => document.querySelector("[data-dates]")?.textContent?.replace(/^Created/, "") === full, fullRange, { timeout: 5000 }).catch(() => {});
  const counted = () => pg.evaluate(() => {
    const shown = (name: string) => Number((document.querySelector(`[data-metric="${name}"]`)?.textContent ?? "").replace(/,/g, ""));
    return { svg: shown("nodes"), svgPage: document.querySelectorAll("[data-chart] *").length, dom: shown("dom-nodes"), domPage: document.querySelectorAll("*").length };
  });
  await pg.waitForFunction(() => Number((document.querySelector('[data-metric="nodes"]')?.textContent ?? "").replace(/,/g, "")) === document.querySelectorAll("[data-chart] *").length, null, { timeout: 5000 }).catch(() => {});
  const nodeCounts = await counted();
  check("6h.20 after a change the node counts are the counts of the page", nodeCounts.svg === nodeCounts.svgPage && nodeCounts.svg > hundredPoints && nodeCounts.dom === nodeCounts.domPage, JSON.stringify(nodeCounts));
  const hud = pg.locator("aside[data-hud]");
  const toggle = hud.locator("button[aria-controls]");
  await pg.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  const pinned = await hud.evaluate((element) => {
    const box = element.getBoundingClientRect();
    return { style: getComputedStyle(element).position, live: element.getAttribute("aria-live"), right: innerWidth - box.right, bottom: innerHeight - box.bottom };
  });
  check("6h.23 the panel stays at the bottom right while scrolling and does not announce each frame", pinned.style === "fixed" && pinned.live === "off" && pinned.right >= 0 && pinned.right < 40 && pinned.bottom >= 0 && pinned.bottom < 40, JSON.stringify(pinned));
  const expandedHeight = (await hud.boundingBox())!.height;
  await toggle.click();
  await pg.waitForSelector("#insights-metrics", { state: "detached" });
  const collapsedHeight = (await hud.boundingBox())!.height;
  check("6h.24 the panel collapses to one line with FPS", (await toggle.getAttribute("aria-expanded")) === "false" && collapsedHeight < 40 && collapsedHeight < expandedHeight && Number(await metric("fps")) > 0, `${expandedHeight} -> ${collapsedHeight} fps=${await metric("fps")}`);
  await toggle.focus();
  await pg.keyboard.press("Enter");
  await pg.waitForSelector("#insights-metrics");
  check("6h.25 Enter on the focused toggle expands the panel again", (await toggle.getAttribute("aria-expanded")) === "true" && (await metric("points")) === hundred, `${await toggle.getAttribute("aria-expanded")} ${await metric("points")}`);
  await pg.locator("button", { hasText: /^1x$/ }).click();
  await pg.waitForFunction((text) => document.querySelector('[data-metric="points"]')?.textContent === text, stress.toLocaleString("en-US"), { timeout: 10000 });
  await pg.setViewportSize({ width: 390, height: 800 });
  await pg.evaluate(() => window.scrollTo(0, 0));
  await dates.click();
  await pg.waitForSelector("#insights-dates:popover-open");
  const narrow = await pg.evaluate(() => {
    const inside = (selector: string) => { const box = document.querySelector(selector)!.getBoundingClientRect(); return box.left >= 0 && box.right <= innerWidth; };
    return { overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth, hud: inside("aside[data-hud]"), dialog: inside("#insights-dates"), animate: inside("button[data-animate]") };
  });
  check("6h.26 at 390 px nothing scrolls sideways and the panel, the range dialog and Animate fit", narrow.overflow <= 0 && narrow.hud && narrow.dialog && narrow.animate, JSON.stringify(narrow));
  await pg.keyboard.press("Escape");
  check("6h.11 no console error and no hydration mismatch", errors.length === 0, errors.join(" | "));
  await pg.close();
});

await step("6i. report and canvas", async () => {
  const errors: string[] = [];
  const open = async (path: string) => {
    const p = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    p.on("console", (m) => { if (m.type() === "error" || m.text().includes("hydration mismatch")) errors.push(m.text()); });
    p.on("pageerror", (e) => errors.push(String(e)));
    await p.addInitScript(recordSockets);
    await p.goto(base + path, { waitUntil: "networkidle" });
    return p;
  };
  const nav = (p: Page) => p.evaluate(() => [...document.querySelectorAll(".nav-link")].map((a) => `${a.getAttribute("href")}=${a.getAttribute("aria-current")}`).join(" "));
  const report = await open("/report");
  const html = await (await report.request.get(base + "/report")).text();
  const charts = (html.match(/data-chart="/g) ?? []).length;
  check("6i.1 /report has the seven charts in the server HTML, with no island or data for them", charts === 7 && !html.includes("data-yuka-answer") && !html.includes("Demo_shared.Insights") && (await report.locator('[data-chart="scatter"] circle').count()) >= 25, `charts=${charts} bytes=${html.length}`);
  check("6i.2 the sidebar marks Report", (await nav(report)) === "/=null /my=null /insights=null /report=page /canvas=null", await nav(report));
  await report.close();
  const A = await open("/canvas");
  const B = await open("/canvas");
  await liveOpen(A);
  await liveOpen(B);
  await A.waitForFunction(() => !!(document.querySelector("[data-canvas] [data-id]") as any)?.__yuka_pointerdown, null, { timeout: 5000 });
  check("6i.3 the sidebar marks Canvas", (await nav(A)) === "/=null /my=null /insights=null /report=null /canvas=page", await nav(A));
  const at = (style: string | null) => (/translate\((-?\d+)px, ?(-?\d+)px\)/.exec(style ?? "") ?? []).slice(1).map(Number);
  const grip = await A.evaluate(() => {
    for (const card of document.querySelectorAll<HTMLElement>("[data-canvas] [data-id]")) {
      const box = card.getBoundingClientRect();
      const x = box.left + 40, y = box.top + 8;
      const hit = document.elementFromPoint(x, y);
      if (x > 0 && y > 0 && x + 80 < innerWidth && y + 60 < innerHeight && hit && hit.localName !== "a" && hit.closest("[data-id]") === card)
        return { id: card.dataset.id ?? "", x, y };
    }
    return null;
  });
  if (!grip) throw new Error("no card to grab in the viewport");
  const card = (p: Page) => p.locator(`[data-canvas] [data-id="${grip.id}"]`);
  const [x0, y0] = at(await card(A).getAttribute("style"));
  const moves: string[] = [];
  A.on("request", (r) => { if (r.url().endsWith("/_yuka/action/move_item")) moves.push(r.url()); });
  const url = A.url();
  await A.mouse.move(grip.x, grip.y);
  await A.mouse.down();
  await A.mouse.move(grip.x + 60, grip.y + 40, { steps: 6 });
  const during = at(await card(A).getAttribute("style"));
  const sentDuring = moves.length;
  await A.mouse.up();
  const want = [Math.min(2200, x0 + 120), Math.min(1528, y0 + 80)];
  const moved = await A.waitForFunction(
    ([sel, x, y]) => (document.querySelector(sel as string)?.getAttribute("style") ?? "").includes(`translate(${x}px,${y}px)`),
    [`[data-canvas] [data-id="${grip.id}"]`, want[0], want[1]] as const,
    { timeout: 2000 },
  ).then(() => true, () => false);
  check("6i.4 a drag moves the card with the pointer and sends one move on release", during.join(",") === want.join(",") && moved && sentDuring === 0 && A.url() === url, `${grip.id} ${x0},${y0} -> during ${during.join(",")}, after ${at(await card(A).getAttribute("style")).join(",")}, want ${want.join(",")}; moves sent during the drag ${sentDuring}`);
  await A.waitForTimeout(300);
  check("6i.5 one move_item call", moves.length === 1, String(moves.length));
  const seen = await B.waitForFunction(
    ([sel, x, y]) => (document.querySelector(sel as string)?.getAttribute("style") ?? "").includes(`translate(${x}px,${y}px)`),
    [`[data-canvas] [data-id="${grip.id}"]`, want[0], want[1]] as const,
    { timeout: 2000 },
  ).then(() => true, () => false);
  check("6i.6 the second page gets the move over Live", seen, `${grip.id} in B: ${await card(B).getAttribute("style")}`);
  await A.locator('[aria-label="Note text"]').fill("e2e note");
  await A.locator("button", { hasText: /^Add note$/ }).click();
  const note = A.locator("[data-canvas] [data-id^='note-']", { hasText: "e2e note" });
  await note.waitFor({ timeout: 5000 });
  await note.locator("button").click();
  await note.waitFor({ state: "detached", timeout: 5000 });
  await A.waitForTimeout(300);
  const noteErrors = await A.locator("[data-canvas] .error").allTextContents();
  check("6i.7 a note is added and removed with no error message", noteErrors.length === 0, noteErrors.join(" | "));
  check("6i.8 no console error and no hydration mismatch on /report and /canvas", errors.length === 0, errors.join(" | "));
  await A.close();
  await B.close();
});

await step("6h. issue list: row link, user popup, filter in the URL", async () => {
  await page.setViewportSize({ width: 1280, height: 800 });
  const started = () => page.waitForFunction(() => [...document.querySelectorAll("yuka-island")].every((i) => (i as any).__yuka_started));
  const openCard = () => page.evaluate(() => document.querySelector("[popover]:popover-open")?.getAttribute("id") ?? "");
  await page.goto(base + "/w/stress", { waitUntil: "networkidle" });
  await started();
  await page.evaluate(() => ((window as any).__list = "alive"));
  const row = page.locator('.row[data-id="STR-2"]');
  const box = (await row.boundingBox())!;
  await row.click({ position: { x: box.width - 20, y: box.height / 2 } });
  await page.waitForURL("**/w/stress/issue/STR-2");
  check("6h.1 a click on the row outside the title opens the issue, client navigation", (await page.evaluate(() => (window as any).__list)) === "alive");
  await page.goBack();
  await page.waitForURL(/\/w\/stress$/);
  await page.waitForSelector('.row[data-id="STR-2"]');
  await started();
  await page.locator('.row[data-id="STR-2"] button[aria-label="Change status"]').click();
  check("6h.2 the status button in a row opens its menu and does not navigate", (await page.locator(".menu").count()) === 1 && page.url().endsWith("/w/stress"), page.url());
  await page.keyboard.press("Escape");
  const unassigned = await page.evaluate(() => [...document.querySelectorAll(".row")].filter((r) => r.querySelector(".avatar.empty")).map((r) => !!r.querySelector("[popovertarget]")));
  check("6h.3 unassigned rows have no user popup", unassigned.length > 0 && unassigned.every((has) => !has), String(unassigned.length));
  const trigger = page.locator('.row[data-id="STR-2"] [popovertarget]');
  check("6h.4 the closed popups are not in the HTML", (await page.locator("[popover]").count()) === 0, String(await page.locator("[popover]").count()));
  await trigger.click();
  await page.waitForSelector("[popover]:popover-open dd");
  const card = page.locator("[popover]:popover-open");
  const text = await card.innerText();
  check("6h.5 the avatar opens a card with the user and numbers, no navigation",
    page.url().endsWith("/w/stress") && /@\w+/.test(text) && /Open\s+\d+/.test(text) && /Done\s+\d+/.test(text) && (await card.getAttribute("role")) === "dialog",
    text.replace(/\s+/g, " "));
  check("6h.6 the trigger names the dialog it opens", (await trigger.getAttribute("aria-haspopup")) === "dialog" && (await trigger.getAttribute("popovertarget")) === (await openCard()));
  await page.keyboard.press("Escape");
  check("6h.7 Escape closes the card", (await openCard()) === "");
  await trigger.click();
  await page.mouse.click(640, 20);
  check("6h.8 a click outside closes the card", (await openCard()) === "" && page.url().endsWith("/w/stress"));
  await trigger.focus();
  await page.keyboard.press("Enter");
  check("6h.9 Enter on the focused avatar opens the card", (await openCard()) === "user-STR-2");
  await page.keyboard.press("Escape");
  const last = page.locator(".row:has([popovertarget])").last();
  await last.scrollIntoViewIfNeeded();
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  await last.locator("[popovertarget]").click();
  await page.waitForSelector("[popover]:popover-open dd");
  const inside = await page.evaluate(() => {
    const r = document.querySelector("[popover]:popover-open")!.getBoundingClientRect();
    return r.top >= 0 && r.left >= 0 && r.bottom <= window.innerHeight && r.right <= window.innerWidth;
  });
  check("6h.10 a card at the bottom right stays in the viewport", inside);
  await page.keyboard.press("Escape");
  const shared = "/w/stress?q=router&label=router";
  const html = await (await page.request.get(base + shared)).text();
  const titles = [...html.matchAll(/class="row-title" href="[^"]*">([^<]*)</g)].map((m) => m[1]);
  check("6h.11 a URL with q and label renders the filtered list on the server",
    titles.length > 0 && titles.length < 2000 && titles.every((t) => /router/i.test(t)) && html.includes('value="router"') && /class="chip on" aria-pressed="true" data-label="router"/.test(html),
    String(titles.length));
  const mine = await (await page.request.get(base + "/my?label=feature")).text();
  const mineRows = [...mine.matchAll(/class="row" data-id="([^"]*)"/g)].length;
  check("6h.12 My issues reads the label from the URL too", mineRows > 0 && /class="chip on" aria-pressed="true" data-label="feature"/.test(mine), String(mineRows));
  await page.goto(base + "/w/stress", { waitUntil: "networkidle" });
  await started();
  const entries = await page.evaluate(() => history.length);
  await page.locator(".filter").fill("router");
  await page.locator('.chip[data-label="router"]').click();
  await page.waitForURL("**" + shared);
  check("6h.13 typing and a chip update the URL without a new history entry", (await page.evaluate(() => history.length)) === entries, page.url());
  await page.locator(".filter").fill("");
  await page.locator('.chip[data-label="bug"]').click();
  await page.waitForURL("**/w/stress?label=router&label=bug");
  const both = await page.locator(".row").evaluateAll((rows) => rows.map((r) => !!(r.querySelector(".label-router") && r.querySelector(".label-bug"))));
  check("6h.14 two chips keep the issues that have both labels", both.length > 0 && both.every(Boolean), `${both.length} rows`);
  await page.locator('.chip[data-label="bug"]').click();
  await page.locator(".filter").fill("router");
  await page.waitForURL("**" + shared);
  await page.reload({ waitUntil: "networkidle" });
  await started();
  const count = await page.locator(".row").count();
  check("6h.15 a reload keeps the filter, the chip and the rows",
    (await page.inputValue(".filter")) === "router" && (await page.locator(".chip.on").count()) === 1 && count === titles.length, `${count} rows`);
  await page.locator(".row .row-title").first().click();
  await page.waitForURL("**/w/stress/issue/**");
  await page.waitForSelector(".issue-title");
  await page.goBack();
  await page.waitForURL("**" + shared);
  await page.waitForSelector(".row");
  check("6h.16 back from an issue shows the filtered list",
    (await page.inputValue(".filter")) === "router" && (await page.locator(".row").count()) === count, String(await page.locator(".row").count()));
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
    related: document.querySelectorAll("[class^=related-list_] li").length,
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
  const relatedAtComments = await early.locator("[class^=related-list_] li").count();
  await early.waitForSelector("[class^=related-list_] li", { timeout: 5000 });
  const tRelated = Date.now() - t0;
  check("7.2 comments arrive before related issues", relatedAtComments === 0 && tRelated > tComments, `comments ${tComments}ms, related ${tRelated}ms`);
  await early.waitForLoadState("networkidle");
  await early.waitForTimeout(300);
  const done = await early.evaluate(() => ({
    skeleton: document.querySelectorAll(".skeleton").length,
    comments: document.querySelectorAll(".comments .comment").length,
    related: document.querySelectorAll("[class^=related-list_] li").length,
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
  await p.waitForSelector("[class^=related-list_] li");
  await p.waitForTimeout(800);
  const state = () =>
    p.evaluate(() => {
      const handler = (sel: string, ev: string) => {
        const el = document.querySelector(sel) as any;
        return !!el && !!el["__yuka_" + ev];
      };
      const related = document.querySelector("[class^=related_]") as Element;
      const box = related.getBoundingClientRect();
      return {
        navProgress: handler("[data-nav-progress]", "animationstart"),
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
  await p.locator("[class^=related_]").scrollIntoViewIfNeeded();
  await p.waitForTimeout(300);
  const scrolled = await state();
  check("7b.6 Related started when scrolled into view", scrolled.io.length >= 1, `fired=${JSON.stringify(scrolled.io)} ${Date.now() - tScroll}ms after scroll`);
  check("7b.6b related chunk requested after scroll", names().includes("related"), names());
  const slot = await p.evaluate(() => ({
    related: (document.querySelector("[class^=related_]") as any)?.__tag === "server",
    items: [...document.querySelectorAll("[class^=related-list_] li")].filter((e) => (e as any).__tag === "server").length,
    total: document.querySelectorAll("[class^=related-list_] li").length,
    props: (document.querySelector(".props") as any)?.__tag === "server",
  }));
  check("7b.7 slot nodes inside Issue_props are the server nodes", slot.related && slot.props && slot.total === 4 && slot.items === 4, JSON.stringify(slot));
  await p.route(base + "/", async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 400));
    await route.continue();
  });
  await p.locator('.nav-link[href="/"]').click();
  const barShown = await p.waitForSelector("[data-nav-progress=loading]", { timeout: 2000 }).then(() => true, () => false);
  await p.waitForURL(base + "/");
  check("7b.1 Nav_progress (idle) started without interaction: a slow navigation shows the bar", before.navProgress && barShown, `handler=${before.navProgress} shown=${barShown}`);
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
  await pg.waitForSelector("[class^=related-list_] li");
  const icon = () => pg.locator(".props .property").first().locator("svg").first().getAttribute("class");
  const select = pg.locator('.props select[aria-label="Status"]');
  const beforeStatus = statusSlug(await icon());
  const preValue = await select.inputValue();
  const preHandler = await pg.evaluate(() => !!(document.querySelector(".props select") as any)?.__yuka_change);
  check("7c.0 status select shows the saved status before hydration", !preHandler && preValue === beforeStatus, `select=${preValue} icon=${beforeStatus} hydrated=${preHandler}`);
  const relatedBefore = await pg.locator("[class^=related-list_] li").count();
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
    items: document.querySelectorAll("[class^=related-list_] li").length,
    tagged: [...document.querySelectorAll("[class^=related-list_] li")].filter((e) => (e as any).__tag === "server").length,
    related: (document.querySelector("[class^=related_]") as any)?.__tag === "server",
    links: [...document.querySelectorAll("[class^=related-list_] a")].every((a) => (a as HTMLAnchorElement).getAttribute("href")?.startsWith("/issue/")),
  }));
  check("7c.3 Related island intact after Issue_props re-render", relatedBefore > 0 && slot.items === relatedBefore && slot.tagged === relatedBefore && slot.related && slot.links, JSON.stringify(slot));
  await pg.reload({ waitUntil: "networkidle" });
  await pg.waitForSelector("[class^=related-list_] li");
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
      const b = document.querySelector("#theme-button") as any;
      if (b && b.__yuka_click) {
        w.__themeMenuStarted = Math.round(performance.now());
        clearInterval(poll);
      }
    }, 5);
  });
  const p = await ctx.newPage();
  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForTimeout(300);
  const r = await p.evaluate(() => ({
    started: (window as any).__themeMenuStarted as number | undefined,
    fills: (window as any).__fills as number[],
  }));
  const last = Math.max(...r.fills, 0);
  check(
    "7f an island that starts at idle starts before the last fill chunk arrives",
    r.fills.length >= 2 && r.started !== undefined && r.started + 100 < last,
    `Theme_menu started at ${r.started}ms, fills at ${r.fills.join(",")}ms`,
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
  const islandModuleRe = /\/(nav_progress|new_issue|issue_list|comments|issue_props|related)(-[^/]*)?\.js$/;
  const seen: string[] = [];
  p.on("request", (r) => {
    const m = islandModuleRe.exec(new URL(r.url()).pathname);
    if (m) seen.push(m[1]);
  });
  const lazyNames = () => ["comments", "issue_props", "related", "new_issue"].filter((n) => seen.includes(n)).join(",");
  const has = (sel: string, ev: string) =>
    p.evaluate(([s, e]) => !!(document.querySelector(s) as any)?.["__yuka_" + e], [sel, ev]);

  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForSelector("[class^=related-list_] li");
  await p.waitForTimeout(500);

  check("7g.1 lazy New_issue not started before interaction", !(await has(".new-issue-button", "click")));
  check("7g.2 eager Nav_progress (Idle) hydrated", await has("[data-nav-progress]", "animationstart"));
  check("7g.5 lazy Comments (Load) hydrated", await has(".comment-input", "input"));
  check("7g.7 lazy Issue_props not started before interaction", !(await has(".props select", "change")));
  check("7g.8 only the comments chunk is requested before interaction", lazyNames() === "comments", lazyNames());

  check("7g.9 non-lazy Nav_progress module requested at load", seen.includes("nav_progress"), seen.join(","));
  check("7g.9b Issue_list module not requested on a page without it", !seen.includes("issue_list"), seen.join(","));

  await p.locator(".props .property").first().hover();
  await p.waitForTimeout(300);
  check("7g.10 Issue_props live after hover", await has(".props select", "change"));
  check("7g.11 issue_props chunk requested after hover, related not yet", lazyNames() === "comments,issue_props", lazyNames());
  check(
    "7g.12 Related not started below the fold",
    (await p.evaluate(() => ((window as any).__ioFired as { cls: string }[]).filter((x) => /related/.test(x.cls)).length)) === 0,
  );
  await p.locator("[class^=related_]").scrollIntoViewIfNeeded();
  await p.waitForTimeout(400);
  check("7g.13 related chunk requested after scroll", lazyNames() === "comments,issue_props,related", lazyNames());
  await p.locator("body").click({ position: { x: 5, y: 5 } });
  await p.keyboard.press("c");
  await p.waitForSelector(".dialog", { timeout: 2000 });
  check("7g.4 c starts New_issue and opens the dialog", (await p.locator(".dialog h2").textContent()) === "New issue" && seen.includes("new_issue"), seen.join(","));
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
  await p.route(base + "/", async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 400));
    await route.continue();
  });
  await p.locator('.nav-link[href="/"]').click();
  const barShown = await p.waitForSelector("[data-nav-progress=loading]", { timeout: 2000 }).then(() => true, () => false);
  await p.waitForURL(base + "/");
  check("7g.3 Nav_progress is live: a slow navigation shows the bar", barShown);
  check("7g.16 no 'no entry for island' or other errors", errors.length === 0, errors.join(" | "));
  await ctx.close();
});

await step("7h. client navigation with Yuka.render ~islands", async () => {
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
  await p.waitForSelector("[class^=related-list_] li");
  await p.waitForTimeout(500);
  const pre = await preloads();
  const preNames = pre.map((l) => nameOf(l.path)).filter((n) => n !== "chunk").sort();
  check("7i.1 issue page: one modulepreload per non-lazy island, none for lazy uses", JSON.stringify(preNames) === JSON.stringify(["nav_progress", "theme_menu"]), JSON.stringify(pre));
  check("7i.2 no duplicate modulepreload hrefs", new Set(pre.map((l) => l.path)).size === pre.length);
  if (!bundleMode) check("7i.3 dev hrefs keep the /../ form and resolve to the served module URL", pre.every((l) => l.raw.includes("/../") && reqs.includes(l.path)), JSON.stringify(pre.map((l) => [l.raw, reqs.includes(l.path)])));
  else check("7i.3 bundle hrefs name the hashed chunk and are requested", pre.every((l) => /\/_yuka\/app\/bundle\/[a-z_]+-[A-Z0-9]+\.js$/.test(l.path) && reqs.includes(l.path)), JSON.stringify(pre));
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
  await q.waitForSelector("[class^=related-list_] li", { timeout: 8000 });
  const at = (n: string) => qReqs.filter((r) => r.name === n).length;
  await q.waitForTimeout(500);
  check("7i.7 Comments (Lazy Idle) requested after idle, others not yet", at("comments") === 1 && at("issue_props") === 0 && at("related") === 0, qReqs.map((r) => r.name).join(","));
  await q.locator(".props .property").first().hover();
  await q.waitForTimeout(300);
  check("7i.8 Issue_props (Lazy Interaction) requested only after hover", at("issue_props") === 1 && at("related") === 0, qReqs.map((r) => r.name).join(","));
  await q.locator("[class^=related_]").scrollIntoViewIfNeeded();
  await q.waitForTimeout(400);
  check("7i.9 Related (Lazy Visible) requested only after scroll", at("related") === 1, qReqs.map((r) => r.name).join(","));
  await q.close();

  const r = await ctx.newPage();
  const rReqs: string[] = [];
  r.on("request", (x) => rReqs.push(nameOf(new URL(x.url()).pathname)));
  await r.goto(base + "/issue/YUK-3", { waitUntil: "networkidle" });
  await r.waitForSelector("[class^=related-list_] li");
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

await step("7j. css per module", async () => {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const p = await ctx.newPage();
  const sheetsIn = (where: string) =>
    p.evaluate((w) => [...document.querySelectorAll(w + " link[data-yuka-css][href*='/related-']")].map((l) => l.getAttribute("href")), where);
  const styled = () =>
    p.evaluate(() => {
      const r = document.querySelector('[class^=related_]');
      const l = document.querySelector('[class^=related-list_]');
      return !!r && !!l && getComputedStyle(r).borderTopWidth === "1px" && getComputedStyle(l).listStyleType === "none";
    });
  await p.goto(base + "/", { waitUntil: "networkidle" });
  await p.waitForSelector(".row");
  check("7j.1 a page that does not use the sheet has no link", (await sheetsIn("")).length === 0, JSON.stringify(await sheetsIn("")));
  await p.locator('.row[data-id="YUK-8"] .row-title').click();
  await p.waitForURL("**/issue/YUK-8");
  await p.waitForSelector('[class^=related-list_] li');
  check("7j.2 after a client navigation the sheet is in the head, once", (await sheetsIn("head")).length === 1 && (await sheetsIn("body")).length === 0, JSON.stringify([await sheetsIn("head"), await sheetsIn("body")]));
  check("7j.3 Related is styled after a client navigation", await styled());
  await p.goBack({ waitUntil: "networkidle" });
  await p.waitForSelector(".row");
  await p.locator('.row[data-id="YUK-1"] .row-title').click();
  await p.waitForURL("**/issue/YUK-1");
  await p.waitForSelector('[class^=related-list_] li');
  check("7j.4 styles survive a second navigation, still one link", (await styled()) && (await sheetsIn("")).length === 1, JSON.stringify(await sheetsIn("")));
  await p.goto(base + "/issue/YUK-1", { waitUntil: "networkidle" });
  await p.waitForSelector('[class^=related-list_] li');
  const order = await p.evaluate(() => {
    const l = document.querySelector("link[data-yuka-css][href*='/related-']");
    const island = document.querySelector('yuka-island[data-name="Demo_shared.Issue_props"]');
    return !!l && !!island && l.compareDocumentPosition(island) === Node.DOCUMENT_POSITION_FOLLOWING && !island.contains(l);
  });
  check("7j.5 full load: one link, before the island that uses it", order && (await sheetsIn("")).length === 1);
  check("7j.6 Related is styled on a full load", await styled());
  const href = (await sheetsIn(""))[0]!;
  const res = await p.request.get(base + href);
  check("7j.7 the sheet is served immutable", res.status() === 200 && (res.headers()["cache-control"] ?? "").includes("immutable"), `${res.status()} ${res.headers()["cache-control"]}`);
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

await step("7l. long comment threads", async () => {
  const issue = "STR-60";
  const url = base + "/w/stress/issue/" + issue;
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const pg = await ctx.newPage();
  const errors: string[] = [];
  pg.on("console", (m) => m.type() === "error" && !m.text().includes("Failed to load resource") && errors.push(m.text()));
  pg.on("pageerror", (e) => errors.push(String(e)));
  const html = await (await pg.request.get(url)).text();
  const sent = {
    html: (html.match(new RegExp(`id="comment-${issue}-c\\d+"`, "g")) ?? []).length,
    props: (html.match(new RegExp(`\\{"id":"${issue}-c\\d+"`, "g")) ?? []).length,
    hidden: html.includes('"hidden":192'),
  };
  check("7l.1 the first response has only the first 3 and the last 5 comments, as HTML and as props", sent.html === 8 && sent.props === 8 && sent.hidden, JSON.stringify(sent));
  const number = (id: string) => Number(id.replace(`comment-${issue}-c`, ""));
  const ids = () => pg.$$eval(".comments .comment", (items) => items.map((item) => item.id));
  const counter = pg.locator("[aria-label='Hidden comments'] [aria-live=polite]");
  const inOrder = (list: string[], expected: number[]) => list.length === expected.length && list.every((id, index) => number(id) === expected[index]);
  const range = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, index) => from + index);
  await pg.goto(url, { waitUntil: "networkidle" });
  await pg.waitForSelector("#load-more-comments");
  const region = await pg.evaluate(() => {
    const element = document.querySelector("[aria-label='Hidden comments']");
    return { role: element?.getAttribute("role"), button: document.querySelector("#load-more-comments")?.tagName, link: element?.querySelector("a")?.getAttribute("href") };
  });
  check("7l.2 the control is a labelled region with a button and a link to the whole thread", region.role === "region" && region.button === "BUTTON" && region.link === `/w/stress/issue/${issue}?comments=all#comment-${issue}-c3`, JSON.stringify(region));
  check("7l.3 collapsed: the first 3 and the last 5 in order, 192 hidden", inOrder(await ids(), [1, 2, 3, 196, 197, 198, 199, 200]) && (await counter.textContent()) === "192 hidden comments", (await ids()).join(","));
  const body = `Long thread comment ${run}`;
  await pg.fill(".comment-input", body);
  await pg.getByRole("button", { name: "Comment" }).click();
  await pg.waitForFunction((text) => document.querySelector(".comments .comment:last-child")?.textContent?.includes(text) && !document.querySelector(".comments .comment:last-child")?.id.includes("tmp-"), body);
  check("7l.4 a new comment goes last and the hidden count stays", (await counter.textContent()) === "192 hidden comments" && (await ids()).length === 9, (await ids()).join(","));
  await pg.evaluate(() => document.querySelectorAll(".comments .comment").forEach((item) => ((item as any).__kept = true)));
  await pg.route("**/_yuka/action/comment_range", async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 500));
    await route.continue();
  });
  await pg.click("#load-more-comments");
  await pg.waitForFunction(() => document.querySelector("#load-more-comments")?.textContent === "Loading...");
  check("7l.5 the button shows a pending state", (await pg.getAttribute("#load-more-comments", "aria-disabled")) === "true");
  await pg.waitForFunction(() => document.querySelector("[aria-label='Hidden comments'] [aria-live]")?.textContent === "142 hidden comments");
  await pg.unroute("**/_yuka/action/comment_range");
  const afterMore = await ids();
  check("7l.6 Load 50 more inserts comments 4 to 53 in order", inOrder(afterMore.slice(0, 58), [...range(1, 53), 196, 197, 198, 199, 200]) && afterMore.length === 59, afterMore.map(number).join(","));
  const kept = await pg.evaluate(() => [...document.querySelectorAll(".comments .comment")].filter((item) => (item as any).__kept).length);
  check("7l.7 the comments already shown keep their DOM nodes", kept === 9, String(kept));
  check("7l.8 focus stays on the Load more button", (await pg.evaluate(() => document.activeElement?.id)) === "load-more-comments");
  await pg.route("**/_yuka/action/comment_range", (route) => route.abort());
  await pg.click("#load-more-comments");
  await pg.waitForSelector("[aria-label='Hidden comments'] [role=alert]");
  await pg.unroute("**/_yuka/action/comment_range");
  check("7l.9 a failed load shows an error and keeps the count", (await counter.textContent()) === "142 hidden comments" && (await ids()).length === 59);
  await pg.getByRole("button", { name: "Retry" }).click();
  await pg.waitForFunction(() => document.querySelector("[aria-label='Hidden comments'] [aria-live]")?.textContent === "92 hidden comments");
  check("7l.10 Retry loads the next 50 and clears the error", (await pg.locator("[role=alert]").count()) === 0 && (await ids()).length === 109);
  await pg.getByRole("link", { name: "Load all" }).click();
  await pg.waitForSelector("[aria-label='Hidden comments']", { state: "detached" });
  const whole = await ids();
  check("7l.11 Load all shows the 200 comments in order, then the new one, with no duplicate", inOrder(whole.slice(0, 200), range(1, 200)) && whole.length === 201 && new Set(whole).size === 201, `${whole.length} ${new Set(whole).size}`);
  check("7l.12 the new comment is still last", (await pg.locator(".comments .comment").last().textContent())?.includes(body) === true);
  check("7l.13 Load all stays on the page and focuses the first loaded comment", pg.url() === url && (await pg.evaluate(() => document.activeElement?.id)) === `comment-${issue}-c104`, `${pg.url()} ${await pg.evaluate(() => document.activeElement?.id)}`);
  check("7l.14 no console error", errors.length === 0, errors.join(" | "));
  await pg.goto(url + "?comments=all", { waitUntil: "networkidle" });
  await pg.waitForSelector(".comment-input");
  const shared = await ids();
  check("7l.15 a shared link with comments=all shows the whole thread", shared.length === 201 && inOrder(shared.slice(0, 200), range(1, 200)) && (await pg.locator("[aria-label='Hidden comments']").count()) === 0, String(shared.length));
  await ctx.close();
  const link = new RegExp(`<a class="[^"]*" href="/w/stress/issue/${issue}[?]comments=all#comment-${issue}-c3"[^>]*>Load all</a>`);
  check("7l.16 the server prints the control as a plain link to the whole thread, with no Load more button", link.test(html) && !html.includes('id="load-more-comments"'));
});

await step("7k. markdown and code style", async () => {
  await page.goto(base + "/issue/YUK-19", { waitUntil: "networkidle" });
  await page.waitForSelector(".comment-input");
  const markdown = await page.evaluate(() => ({
    heading: document.querySelector(".issue-description h4")?.textContent,
    cells: document.querySelectorAll(".issue-description td").length,
    tokens: document.querySelectorAll(".issue-description .code-block span[style]").length,
    commentTokens: document.querySelectorAll(".comment .code-block span[style]").length,
    scripts: document.querySelectorAll(".issue-description script, .comment script").length,
  }));
  check("7k.1 the description is markdown with highlighted code", markdown.heading === "Measurements" && markdown.cells === 6 && markdown.tokens > 0 && markdown.scripts === 0, JSON.stringify(markdown));
  check("7k.2 a stored comment has highlighted code", markdown.commentTokens > 0, String(markdown.commentTokens));
  const pairs: Record<string, number> = { dark: 0, light: 5, gray: 1, pale: 5 };
  const look = () =>
    page.evaluate(() => {
      const block = document.querySelector(".issue-description .code-block") as HTMLElement;
      const token = [...block.querySelectorAll<HTMLElement>("span[style]")].find((span) => [0, 1, 2, 3, 4, 5].every((index) => span.style.getPropertyValue(`--c${index}`)))!;
      const resolve = (color: string) => {
        const probe = document.createElement("span");
        probe.style.color = color;
        document.body.append(probe);
        const value = getComputedStyle(probe).color;
        probe.remove();
        return value;
      };
      return {
        theme: document.documentElement.getAttribute("data-theme"),
        code: document.documentElement.getAttribute("data-code-theme"),
        stored: localStorage.getItem("yuka-demo-code-theme"),
        background: getComputedStyle(block).backgroundColor,
        surface: resolve("var(--bg-sidebar)"),
        token: getComputedStyle(token).color,
        variants: [0, 1, 2, 3, 4, 5].map((index) => resolve(token.style.getPropertyValue(`--c${index}`))),
      };
    });
  const pick = async (id: string) => {
    await page.click("#theme-button");
    await page.waitForSelector("[role=menu]");
    await page.click(`#${id}`);
    await page.waitForSelector("[role=menu]", { state: "detached" });
  };
  await page.click("#theme-button");
  await page.waitForSelector("[role=menu]");
  const menu = await page.evaluate(() => {
    const groups = [...document.querySelectorAll("[role=menu] [role=group]")];
    return {
      groups: groups.map((group) => document.getElementById(group.getAttribute("aria-labelledby")!)?.textContent),
      items: groups.map((group) => group.querySelectorAll("[role=menuitemradio]").length),
      checked: [...document.querySelectorAll("[role=menuitemradio][aria-checked=true]")].map((item) => item.id),
    };
  });
  await page.keyboard.press("Escape");
  check(
    "7k.3 one menu has a Theme and a Code radio group, with the theme and Auto checked",
    JSON.stringify(menu.groups) === '["Theme","Code"]' && JSON.stringify(menu.items) === "[4,7]" && menu.checked.length === 2 && menu.checked[0].startsWith("theme-") && menu.checked[1] === "code-auto",
    JSON.stringify(menu),
  );
  await page.evaluate(() => ((window as any).__codeStyleMarker = "kept"));
  const mark = allRequests.length;
  for (const theme of Object.keys(pairs)) {
    await pick(`theme-${theme}`);
    const state = await look();
    check(
      `7k.4 Auto: the ${theme} theme gives its code style on the theme surface`,
      state.theme === theme && state.code === null && state.token === state.variants[pairs[theme]] && state.background === state.surface,
      JSON.stringify(state),
    );
  }
  await pick("code-nord");
  const nord = await look();
  const requestsAfter = allRequests.slice(mark).filter((r) => !r.url.includes("/_yuka/live"));
  check(
    "7k.5 a code style overrides the pairing, with no request and no reload",
    nord.code === "nord" && nord.stored === "nord" && nord.token === nord.variants[2] && nord.background === "rgb(46, 52, 64)" &&
      requestsAfter.length === 0 && (await page.evaluate(() => (window as any).__codeStyleMarker)) === "kept",
    `${JSON.stringify(nord)} requests=${requestsAfter.map((r) => r.url).join(",")}`,
  );
  await pick("theme-light");
  const kept = await look();
  check("7k.6 the code style stays when the theme changes", kept.theme === "light" && kept.code === "nord" && kept.token === nord.token && kept.background === nord.background, JSON.stringify(kept));
  await page.focus("#theme-button");
  await page.keyboard.press("Enter");
  await page.waitForSelector("[role=menu]");
  const checked = await page.evaluate(() => [...document.querySelectorAll("[role=menuitemradio][aria-checked=true]")].map((item) => item.id).join(","));
  await page.keyboard.press("End");
  const last = await page.evaluate(() => document.activeElement?.id);
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("Enter");
  await page.waitForSelector("[role=menu]", { state: "detached" });
  const keyboard = await look();
  check(
    "7k.7 the menu checks the theme and the code style and works with the keyboard",
    checked === "theme-light,code-nord" && last === "code-light" && keyboard.code === "gruvbox" && keyboard.token === keyboard.variants[4] &&
      (await page.evaluate(() => document.activeElement?.id)) === "theme-button",
    `${checked} ${last} ${JSON.stringify(keyboard)}`,
  );
  await page.reload({ waitUntil: "domcontentloaded" });
  const firstPaint = await look();
  check(
    "7k.8 both choices are kept after a reload, before the scripts run",
    firstPaint.theme === "light" && firstPaint.code === "gruvbox" && firstPaint.token === firstPaint.variants[4] && firstPaint.background === keyboard.background,
    JSON.stringify(firstPaint),
  );
  await page.waitForLoadState("networkidle");
  await page.locator(".crumb").click();
  await page.waitForSelector(".row");
  await page.locator('.row[data-id="YUK-1"] .row-title').click();
  await page.waitForURL("**/issue/YUK-1");
  await page.waitForSelector(".comment-input");
  const navigated = await look();
  check(
    "7k.9 both choices are kept after a client navigation",
    navigated.theme === "light" && navigated.code === "gruvbox" && navigated.token === navigated.variants[4] && navigated.background === keyboard.background,
    JSON.stringify(navigated),
  );
  await pick("code-auto");
  const auto = await look();
  check(
    "7k.10 Auto restores the pairing and forgets the code style",
    auto.code === null && auto.stored === null && auto.token === auto.variants[pairs.light] && auto.background === auto.surface,
    JSON.stringify(auto),
  );
  await page.evaluate(() => localStorage.setItem("yuka-demo-code-theme", "tokyonight"));
  await page.reload({ waitUntil: "domcontentloaded" });
  const former = await look();
  check("7k.11 a code style stored by the former select is honoured", former.code === "tokyonight" && former.token === former.variants[3], JSON.stringify(former));
  await page.waitForLoadState("networkidle");
  await page.goto(base + "/issue/YUK-19", { waitUntil: "networkidle" });
  await page.waitForSelector(".comment-input");
  const body = `**Bold ${run}** and \`code\`\n\n\`\`\`ocaml\nlet answer = 42\n\`\`\``;
  await page.route("**/_yuka/action/**", async (route) => {
    await new Promise((r) => setTimeout(r, 600));
    await route.continue();
  });
  await page.fill(".comment-input", body);
  await page.getByRole("button", { name: "Comment" }).click();
  await page.waitForTimeout(150);
  const pending = await page.locator(".comment", { hasText: `**Bold ${run}**` }).count();
  check("7k.12 the new comment shows its text at once", pending === 1, String(pending));
  await page.waitForSelector(`.comment strong:text("Bold ${run}")`, { timeout: 5000 });
  await page.unroute("**/_yuka/action/**");
  const saved = await page.evaluate((run) => {
    const strong = [...document.querySelectorAll(".comment strong")].find((element) => element.textContent === `Bold ${run}`);
    const comment = strong?.closest(".comment");
    return { code: comment?.querySelector("p code")?.textContent, tokens: comment?.querySelectorAll(".code-block span[style]").length ?? 0 };
  }, run);
  check("7k.13 the saved comment is markdown with highlighted code, with no reload", saved.code === "code" && saved.tokens > 0, JSON.stringify(saved));
  await page.evaluate(() => {
    localStorage.removeItem("yuka-demo-code-theme");
    localStorage.removeItem("yuka-demo-theme");
  });
});

await step("8. 404", async () => {
  expectedFailures = 404;
  const res = await page.goto(base + "/issue/NOPE", { waitUntil: "networkidle" });
  expectedFailures = 0;
  check("8a status 404", res?.status() === 404, String(res?.status()));
  check("8b not found page", (await page.locator(".not-found h1").textContent()) === "Issue not found");
  expectedFailures = 404;
  const unknown = await page.goto(base + "/w/nope", { waitUntil: "networkidle" });
  expectedFailures = 0;
  check("8d unknown workspace is 404", unknown?.status() === 404 && (await page.locator(".not-found h1").textContent()) === "Page not found", String(unknown?.status()));
});


await step("8c. live pages after a server restart", async () => {
  const command = process.env.YUKA_E2E_SERVER;
  const pidfile = process.env.YUKA_E2E_PIDFILE;
  const logfile = process.env.YUKA_E2E_LOG;
  if (!command || !pidfile || !logfile) {
    console.log("SKIP  8c no YUKA_E2E_SERVER (run through e2e/run.sh)");
    return;
  }
  const A = await livePage("/");
  const B = await livePage("/my");
  await A.p.evaluate(() => ((window as any).__marker = "alive"));
  await B.p.evaluate(() => ((window as any).__marker = "alive"));
  process.kill(Number(readFileSync(pidfile, "utf8").trim()));
  const offA = await A.p.waitForSelector(".offline", { timeout: 3000 }).then(() => true, () => false);
  const offB = await B.p.waitForSelector(".offline", { timeout: 3000 }).then(() => true, () => false);
  check("8c.1 both pages show Offline", offA && offB, `A=${offA} B=${offB}`);
  const [exe, ...args] = command.split(" ").filter((x) => x !== "");
  const log = openSync(logfile, "a");
  const server = spawn(exe, args, { detached: true, stdio: ["ignore", log, log] });
  server.unref();
  writeFileSync(pidfile, String(server.pid));
  const backA = await A.p.waitForSelector(".offline", { state: "detached", timeout: 15000 }).then(() => true, () => false);
  const backB = await B.p.waitForSelector(".offline", { state: "detached", timeout: 15000 }).then(() => true, () => false);
  const rows = await A.p.locator(".row").count();
  const markers = [await A.p.evaluate(() => (window as any).__marker), await B.p.evaluate(() => (window as any).__marker)];
  check("8c.2 both pages reconnect and show the current list, with no reload", backA && backB && rows > 0 && markers.every((m) => m === "alive"), `A=${backA} B=${backB} rows=${rows} markers=${markers}`);
  const id = (await B.p.locator(".row").first().getAttribute("data-id")) ?? "";
  const before = await statusIn(B.p, id);
  const target = before === "done" ? "todo" : "done";
  await pickStatus(A.p, id, target === "done" ? "Done" : "Todo");
  const live = await B.p
    .waitForFunction(
      ([i, t]) => document.querySelector(`.row[data-id="${i}"] button[aria-label="Change status"] svg`)?.getAttribute("class")?.includes("status-" + t),
      [id, target],
      { timeout: 3000 },
    )
    .then(() => true, () => false);
  const failed = await B.p.locator(".list-empty.error").count();
  check("8c.4 after the restart a change in page A still shows in page B (the CSRF check passes)", live && failed === 0, `${id} ${before} -> ${target} live=${live} error shown=${failed}`);
  const unexpected = [...A.errors, ...B.errors].filter((e) => !/WebSocket connection to .* failed/.test(e));
  check("8c.3 no console error but the expected socket failures", unexpected.length === 0, unexpected.join(" | "));
  await A.ctx.close();
  await B.ctx.close();
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
