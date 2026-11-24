import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = process.argv[2] ?? "http://127.0.0.1:8125/async-feed";
const shots = process.env.ASYNC_FEED_SCREENSHOTS ?? "";

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
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, timezoneId: "UTC", colorScheme: "light" });
await ctx.addCookies([{ name: "async-feed-zone", value: "Asia%2FTokyo", url: new URL(app).origin }]);
const problems: string[] = [];
const started = (p: Page) =>
  p.waitForFunction(() => {
    const islands = [...document.querySelectorAll("yuka-island")];
    return islands.length > 0 && islands.every((i) => (i as any).__yuka_started);
  });
const open = async (path = "") => {
  const p = await ctx.newPage();
  p.on("console", (m) => {
    if (m.type() === "error" || m.text().includes("hydration mismatch")) problems.push(m.text());
  });
  p.on("pageerror", (e) => problems.push(String(e)));
  p.on("requestfailed", (r) => {
    if (r.failure()?.errorText !== "net::ERR_ABORTED") problems.push(`failed ${r.url()} ${r.failure()?.errorText}`);
  });
  await p.goto(app + path, { waitUntil: "networkidle" });
  await started(p);
  return p;
};
const settled = (p: Page) => p.waitForFunction(() => !document.documentElement.hasAttribute("data-yuka-nav"));
const cardTime = async (p: Page, id: string) => {
  const t = p.locator(`.card[data-id="${id}"] .card-side time`).first();
  return {
    date: ((await t.locator(".card-date").textContent()) ?? "").trim(),
    clock: ((await t.locator(".card-clock").textContent()) ?? "").trim(),
    title: (await t.getAttribute("title")) ?? "",
  };
};

let A: Page;
await step("a1. the feed loads chronologically (newest at bottom) with logos, avatars, no descriptions", async () => {
  A = await open();
  check("a1.1 one page of cards", (await A.locator(".feed:not(.feed-live) .card").count()) === 50);
  check("a1.2 oldest of page at top, newest at bottom",
    (await A.locator(".feed:not(.feed-live) .card").first().getAttribute("data-id")) === "4951" &&
    (await A.locator(".feed:not(.feed-live) .card").last().getAttribute("data-id")) === "5000");
  check("a1.2b no Notifications header or event count", (await A.locator(".feed-head, .feed-count").count()) === 0);
  check("a1.2c descriptions hidden on main feed", (await A.locator(".card .card-text").count()) === 0);
  check("a1.2d avatars rendered on cards and sidebar", (await A.locator(".user-avatar").count()) > 50);
  const layout = await A.locator('.card[data-id="5000"]').evaluate((el) => {
    const link = el.querySelector(".card-link")!.getBoundingClientRect();
    const side = el.querySelector(".card-side")!.getBoundingClientRect();
    const src = el.querySelector(".card-author")!.getBoundingClientRect();
    const tag = el.querySelector(".card-tags .tag")!.getBoundingClientRect();
    return {
      linkWidth: Math.round(link.width),
      linkHeight: Math.round(link.height),
      sideOutside: side.left > link.right - 1,
      sameRow: Math.abs(src.top - tag.top) < 8,
    };
  });
  check("a1.2e card has tags on meta row, compact height, and timestamp outside", layout.sideOutside && layout.sameRow && layout.linkHeight < 75, JSON.stringify(layout));
  const t = await cardTime(A, "5000");
  check("a1.3 the time is stacked in Asia/Tokyo", t.date === "20 Nov" && t.clock === "18:01:40", `${t.date} ${t.clock}`);
  const time = A.locator('.card[data-id="5000"] time');
  check("a1.4 the datetime attribute is the UTC instant", (await time.getAttribute("datetime")) === "2026-11-20T09:01:40Z");
  check("a1.5 the title has the full timestamp", t.title.includes("(Asia/Tokyo)"), t.title);
  const days = await A.locator(".feed:not(.feed-live) .feed-day time").evaluateAll((ts) => ts.map((t) => `${t.getAttribute("datetime")} ${t.textContent}`));
  check("a1.6 the first page has a divider per day, in the zone", days.length === 4 && days[3] === "2026-11-20 Friday, November 20", days.join(" | "));
});

await step("a2. Simulate events streams cards one by one to the bottom of every open page", async () => {
  const B = await open();
  const arrivals = A.evaluate(
    () =>
      new Promise<number[]>((resolve) => {
        const list = document.querySelector(".feed-live")!;
        const start = performance.now();
        const counts: number[] = [];
        const times: number[] = [];
        new MutationObserver(() => {
          const n = list.querySelectorAll(".card").length;
          if (n !== counts[counts.length - 1]) {
            counts.push(n);
            times.push(Math.round(performance.now() - start));
          }
          if (n >= 4) resolve([...counts, -1, ...times]);
        }).observe(list, { childList: true, subtree: true });
      }),
  );
  await A.getByRole("button", { name: "Simulate events" }).click();
  const result = await Promise.race([arrivals, new Promise<number[]>((r) => setTimeout(() => r([]), 10000))]);
  const split = result.indexOf(-1);
  const counts = result.slice(0, split);
  const times = result.slice(split + 1);
  check("a2.1 the cards arrive one at a time", counts.join(",") === "1,2,3,4", counts.join(","));
  const gaps = times.slice(1).map((t, i) => t - times[i]);
  check("a2.2 with a delay between each", gaps.length === 3 && gaps.every((g) => g > 300), times.join(" "));
  const last = await A.locator(".card").last().getAttribute("data-id");
  check("a2.3 the newest card is at the bottom", last === "5004", last ?? "");
  check("a2.4 a new card has the enter class", (await A.locator(".feed-live .card").last().getAttribute("class"))?.includes("card-new") ?? false);
  const zoned = await cardTime(A, "5004");
  check("a2.5 a new card shows its time in the zone", zoned.title.includes("(Asia/Tokyo)") && /^\d{1,2}:\d{2}:\d{2}$/.test(zoned.clock), `${zoned.date} ${zoned.clock} ${zoned.title}`);
  const other = await B.waitForFunction(() => document.querySelectorAll(".feed-live .card").length === 4, null, { timeout: 5000 }).then(() => true, () => false);
  check("a2.6 the other page gets the same events", other);
  await A.getByRole("button", { name: "Simulate events" }).waitFor({ timeout: 5000 });
  check("a2.7 the button is enabled again", await A.getByRole("button", { name: "Simulate events" }).isEnabled());
  await B.close();
  for (let i = 1; i < 10; i++) {
    await A.getByRole("button", { name: "Simulate events" }).click();
    await A.getByRole("button", { name: "Simulate events" }).waitFor({ timeout: 10000 });
  }
  const live = await A.locator(".feed-live .card").count();
  check("a2.8 after 10 clicks all 40 live cards stay", live === 40, String(live));
  const ids = await A.locator(".feed-live .card").evaluateAll((cards) => cards.map((c) => Number(c.getAttribute("data-id"))));
  check("a2.9 the live cards are chronological (5001..5040)", ids[0] === 5001 && ids[39] === 5040, `${ids[0]} ${ids[39]}`);
  const zone = await cardTime(A, "5040");
  check("a2.10 a live card shows its time in the zone", zone.title.includes("(Asia/Tokyo)") && /^\d{1,2}:\d{2}:\d{2}$/.test(zone.clock), `${zone.date} ${zone.clock} ${zone.title}`);
});

await step("a8. an older page opens no live socket", async () => {
  const O = await ctx.newPage();
  const sockets: string[] = [];
  O.on("websocket", (w) => sockets.push(w.url()));
  await O.goto(app + "/?before=1795165300", { waitUntil: "networkidle" });
  await started(O);
  await O.waitForTimeout(500);
  check("a8.1 no live feed on an older page", (await O.locator(".feed-live").count()) === 0);
  check("a8.2 no WebSocket", sockets.length === 0, sockets.join(" "));
  check("a8.3 Back to latest link is shown", (await O.getByRole("link", { name: "Back to latest" }).count()) === 1);
  await O.close();
});

await step("a3. sidebar filters: project/team dropdowns and direct assignee list", async () => {
  await A.goto(app, { waitUntil: "networkidle" });
  await started(A);
  const sidebarBox = await A.locator(".sidebar").boundingBox();
  const mainBox = await A.locator(".main").boundingBox();
  check("a3.0 filters are on the left side", !!sidebarBox && !!mainBox && sidebarBox.x < mainBox.x);
  check("a3.0b assignee is a direct list, not a dropdown", (await A.locator(".assignee-list .assignee-item").count()) === 8 && (await A.locator("#assignee-button").count()) === 0);

  await A.locator("#project-button").focus();
  await A.keyboard.press("ArrowDown");
  await A.locator("#project-input").waitFor();
  check("a3.1 ArrowDown opens the list and focuses the search", await A.evaluate(() => document.activeElement?.id === "project-input"));
  await A.keyboard.type("bill");
  const options = await A.locator("#project-list [role=option]").allTextContents();
  check("a3.2 typing filters the options", options.length === 1 && options[0].trim() === "Billing", options.join("|"));
  await A.keyboard.press("Backspace");
  await A.keyboard.press("Backspace");
  await A.keyboard.press("Backspace");
  await A.keyboard.press("Backspace");
  const rows = await A.evaluate(
    () =>
      new Promise<number>((resolve) => {
        const changed = new Set<Element>();
        const observer = new MutationObserver((records) => records.forEach((r) => changed.add(r.target as Element)));
        observer.observe(document.querySelector("#project-list")!, { attributes: true, subtree: true, attributeFilter: ["class"] });
        document.querySelector("#project-input")!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
        setTimeout(() => {
          observer.disconnect();
          resolve(changed.size);
        }, 100);
      }),
  );
  check("a3.2b an arrow key updates two rows", rows === 2, String(rows));
  const active = await A.locator("#project-input").getAttribute("aria-activedescendant");
  check("a3.2c the active row is the second option", active === "project-item-1" && (await A.locator("#project-item-1").getAttribute("class")) === "option active", active ?? "");
  await A.keyboard.type("bill");
  await A.keyboard.press("Enter");
  await A.waitForURL((url) => url.searchParams.getAll("project").join() === "Billing");
  await A.waitForFunction(() => document.querySelector('#project-list [role=option][aria-selected="true"]') !== null);
  check("a3.3 Enter picks the option and the list stays open", await A.locator("#project-list").isVisible());
  const tags = await A.locator(".feed .card").evaluateAll((cards) => cards.every((c) => c.textContent!.includes("Billing")));
  check("a3.4 the server renders the filtered feed", tags && (await A.locator(".feed .card").count()) > 0);
  await A.keyboard.press("Escape");
  check("a3.5 Escape closes and focuses the button", (await A.locator("#project-list").count()) === 0 && (await A.evaluate(() => document.activeElement?.id === "project-button")));
  check("a3.6 the button shows the choice", ((await A.locator("#project-button").textContent()) ?? "").includes("Billing"));
  await A.keyboard.press("ArrowDown");
  await A.locator("#project-input").waitFor();
  await A.keyboard.press("End");
  check("a3.7 End reaches Clear selection", ((await A.locator("#project-list .option.active").textContent()) ?? "").includes("Clear selection"));
  await A.keyboard.press("Enter");
  await A.waitForURL((url) => !url.searchParams.has("project"));
  await A.waitForFunction(() => document.querySelector('.feed .card[data-id="5040"]') !== null);
  check("a3.8 Clear removes the filter", (await A.locator(".feed:not(.feed-live) .card").last().getAttribute("data-id")) === "5040");

  await A.locator(".assignee-item", { hasText: "Ana Ruiz" }).click();
  await A.waitForURL((url) => url.searchParams.getAll("assignee").join() === "Ana Ruiz");
  await settled(A);
  // Ana Ruiz is the assignee of every event n with n mod 8 = 2 (server/data.ml).
  const assigneeTags = await A.locator(".feed .card").evaluateAll((cards) => cards.every((c) => Number(c.getAttribute("data-id")) % 8 === 2));
  check("a3.9 clicking an assignee filters directly", assigneeTags && (await A.locator(".feed .card").count()) > 0);
  await A.locator(".filters-clear").click();
  await A.waitForURL((url) => !url.searchParams.has("assignee"));
  await settled(A);
});

await step("a4. timezone and date live directly in the header", async () => {
  await A.locator("#header-zone").selectOption("America/New_York");
  const t = await cardTime(A, "5000");
  check("a4.1 every date follows the new zone", t.date === "20 Nov" && t.clock === "4:01:40" && t.title.includes("(America/New_York)"), `${t.date} ${t.clock} ${t.title}`);
  await A.locator("#header-date").fill("2026-11-01T12:00");
  await A.getByRole("button", { name: "Go" }).click();
  await A.waitForURL((url) => url.searchParams.has("before"));
  await settled(A);
  const before = Number(new URL(A.url()).searchParams.get("before"));
  check("a4.2 the date is read in the zone", before === Date.UTC(2026, 10, 1, 17, 1) / 1000, String(before));
  const last = Date.parse((await A.locator(".feed .card time").last().getAttribute("datetime")) ?? "") / 1000;
  check("a4.3 the feed ends right before that date", last < before && before - last < 5700, `${last} ${before}`);
  await A.reload({ waitUntil: "networkidle" });
  check("a4.4 the zone is kept after a reload", ((await A.locator(".feed .card time").last().getAttribute("title")) ?? "").includes("(America/New_York)"));
});

await step("a5. the theme toggle", async () => {
  await A.goto(app, { waitUntil: "networkidle" });
  await started(A);
  if (shots) await A.screenshot({ path: `${shots}/async-feed-light.png` });
  const background = () => A.evaluate(() => getComputedStyle(document.body).backgroundColor);
  const toggle = A.locator("#theme");
  check("a5.1 the theme follows the system first", (await toggle.getAttribute("data-theme")) === "system" && (await background()) === "rgb(241, 241, 242)", await background());
  await toggle.click();
  check("a5.2 a click turns it dark", (await toggle.getAttribute("aria-pressed")) === "true" && (await background()) === "rgb(8, 8, 10)", await background());
  const html = await (await ctx.request.get(app)).text();
  check("a5.3 the first HTML after a reload is dark, with no script", html.includes('data-theme="dark" aria-pressed="true"') && !html.includes("localStorage"));
  await A.reload({ waitUntil: "networkidle" });
  await started(A);
  check("a5.4 the choice is kept after a reload", (await background()) === "rgb(8, 8, 10)" && (await toggle.getAttribute("aria-pressed")) === "true");
  if (shots) await A.screenshot({ path: `${shots}/async-feed-dark.png` });
  await toggle.click();
  check("a5.5 a second click turns it light", (await toggle.getAttribute("aria-pressed")) === "false" && (await background()) === "rgb(241, 241, 242)");
  const dark = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: "dark" });
  const D = await dark.newPage();
  await D.goto(app, { waitUntil: "networkidle" });
  check("a5.6 with no cookie a dark system gets the dark theme", (await D.evaluate(() => getComputedStyle(document.body).backgroundColor)) === "rgb(8, 8, 10)");
  await dark.close();
});

await step("a7. full-card click opens rich 80% split-view panel with embeds and graphs", async () => {
  const P = await open();
  const base = new URL(app).pathname;
  const card = P.locator('.card[data-id="4999"] .card-link');
  check("a7.1 cards have no comment count", (await P.locator(".comment-count").count()) === 0);
  const sheet = P.locator(".sheet-panel");
  await card.click();
  await P.waitForURL((url) => url.pathname === `${base}/item/4999`);
  await sheet.waitFor();
  await started(P);
  await settled(P);
  check("a7.2 clicking the card opens the panel at the item URL", (await P.getByRole("dialog", { name: /New post in r\/acme/ }).count()) === 1, P.url());
  const sheetBox = await sheet.boundingBox();
  check("a7.2b the panel is ~80% of the screen width", !!sheetBox && sheetBox.width >= 960 && sheetBox.width <= 1100, String(sheetBox?.width));
  const mainBox = await sheet.locator(".sheet-main").boundingBox();
  const metaBox = await sheet.locator(".sheet-meta").boundingBox();
  check("a7.2c metadata is rendered in a split view alongside main content", !!mainBox && !!metaBox && metaBox.x > mainBox.x);
  check("a7.3 the feed stays under the panel", (await P.locator(".feed:not(.feed-live) .card").count()) === 50);
  const moved = await sheet.evaluate((e) => getComputedStyle(e).animationName);
  check("a7.4 the panel slides in", moved === "sheet-in", moved);
  const link = sheet.locator(".source-link");
  check(
    "a7.5 the source link opens a new tab",
    (await link.getAttribute("target")) === "_blank" && (await link.getAttribute("rel")) === "noopener" && ((await link.getAttribute("href")) ?? "").startsWith("https://www.reddit.com/r/acme/"),
    (await link.getAttribute("href")) ?? "",
  );
  check("a7.6 the details have source fields", (await sheet.locator("dt", { hasText: "Subreddit" }).count()) === 1);
  const redditFrame = sheet.frameLocator("iframe.embed-reddit");
  check("a7.6b Reddit iframe renders the OG preview card", (await redditFrame.locator(".og-card").count()) === 1);
  const zoned = (await sheet.locator(".detail-time").textContent()) ?? "";
  check("a7.7 the time is in the chosen zone", zoned.endsWith("EST"), zoned);
  check("a7.8 no comments section or form in panel", (await sheet.locator(".comments, .comment-form").count()) === 0);
  if (shots) {
    await P.waitForTimeout(700);
    await P.evaluate(() => (document.getElementById("theme") as HTMLElement).click());
    await P.screenshot({ path: `${shots}/async-feed-panel-dark.png` });
    await P.evaluate(() => (document.getElementById("theme") as HTMLElement).click());
    await P.screenshot({ path: `${shots}/async-feed-panel-light.png` });
  }

  await P.goBack();
  await P.waitForURL((url) => url.pathname === base || url.pathname === `${base}/`);
  await sheet.waitFor({ state: "detached" });
  check("a7.13 Back closes the panel", (await P.locator(".sheet").count()) === 0);

  await card.click();
  await sheet.waitFor();
  await started(P);
  await settled(P);
  await P.keyboard.press("Escape");
  await sheet.waitFor({ state: "detached" });
  check("a7.15 Escape closes the panel", !P.url().includes("/item/"), P.url());

  await card.click();
  await sheet.waitFor();
  await started(P);
  await settled(P);
  await P.mouse.click(40, 450);
  await sheet.waitFor({ state: "detached" });
  check("a7.16 a click on the backdrop closes the panel", !P.url().includes("/item/"), P.url());
  await P.close();

  const NR = await open("/item/5000");
  check("a7.16b New Relic item renders uptime graph and error chart",
    (await NR.locator(".sheet-panel .uptime-bars .uptime-bar").count()) === 48 &&
    (await NR.locator(".sheet-panel .chart-svg").count()) === 1);
  if (shots) await NR.screenshot({ path: `${shots}/async-feed-newrelic.png` });
  await NR.close();

  const FG = await open("/item/4");
  const figmaFrame = FG.frameLocator("iframe.embed-figma");
  check("a7.16c Figma item renders embedded canvas iframe", (await figmaFrame.locator(".figma-artboard").count()) === 1);
  if (shots) await FG.screenshot({ path: `${shots}/async-feed-figma.png` });
  await FG.close();

  const D = await open("/item/4999");
  check("a7.17 a direct load shows the panel over the feed", (await D.locator(".sheet-panel").count()) === 1 && (await D.locator(".feed:not(.feed-live) .card").count()) === 50);
  await D.getByRole("button", { name: "Close" }).click();
  await D.waitForURL((url) => !url.pathname.includes("/item/"));
  await D.locator(".sheet").waitFor({ state: "detached" });
  check("a7.19 Close after a direct load shows the feed", (await D.locator(".feed:not(.feed-live) .card").count()) === 50);
  await D.close();
});

check("a6 no console errors, page errors, hydration mismatches or failed requests", problems.length === 0, problems.join(" | "));

await step("a9. opening the panel hides the scrollbar without moving the feed", async () => {
  // Headless Chromium hides scrollbars; without them nothing would move.
  const visible = await chromium.launch({ headless: true, ignoreDefaultArgs: ["--hide-scrollbars"] });
  for (const width of [1280, 600]) {
    const S = await (await visible.newContext({ viewport: { width, height: 800 }, timezoneId: "UTC" })).newPage();
    await S.goto(app, { waitUntil: "networkidle" });
    // The steps before added live events, so take a card the page has.
    const id = await S.locator(".feed:not(.feed-live) .card").nth(10).getAttribute("data-id");
    await S.locator(`.card[data-id="${id}"]`).scrollIntoViewIfNeeded();
    const measure = () => S.evaluate((id) => {
      const main = document.querySelector(".main")!;
      const title = document.querySelector(`.card[data-id="${id}"] .card-title`)!.getBoundingClientRect();
      const gap = main.offsetWidth - main.clientWidth + innerWidth - document.documentElement.clientWidth;
      return { left: title.left, width: title.width, gap };
    }, id);
    const before = await measure();
    await S.locator(`.card[data-id="${id}"] .card-link`).click();
    await S.locator(".sheet-panel").waitFor();
    const open = await measure();
    check(`a9.1 at ${width}px the scrollbar goes and the feed stays`, before.gap > 0 && open.gap === 0 && open.left === before.left && open.width === before.width, JSON.stringify({ before, open }));
    await S.keyboard.press("Escape");
    await S.locator(".sheet").waitFor({ state: "detached" });
    const closed = await measure();
    const inline = await S.evaluate(() => [document.querySelector(".main")!, document.body, document.documentElement].map((e) => e.getAttribute("style") ?? "").join(""));
    check(`a9.2 at ${width}px closing gives the scrollbar back`, closed.gap === before.gap && closed.width === before.width && inline === "", JSON.stringify({ closed, inline }));
    await S.close();
  }
  await visible.close();
});

await browser.close();
console.log(failures === 0 ? "\nASYNC FEED ALL PASS" : `\n${failures} FAILED (async feed)`);
process.exit(failures === 0 ? 0 : 1);
