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
await ctx.addInitScript(() => {
  if (!localStorage.getItem("async-feed-zone")) localStorage.setItem("async-feed-zone", "Asia/Tokyo");
});
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
const timeOf = (p: Page, id: string) => p.locator(`.card[data-id="${id}"] time`).first().textContent();

let A: Page;
await step("a1. the feed loads with dates in the chosen zone", async () => {
  A = await open();
  check("a1.1 one page of cards", (await A.locator(".feed .card").count()) === 50);
  check("a1.2 newest first", (await A.locator(".feed .card").first().getAttribute("data-id")) === "5000");
  const text = await timeOf(A, "5000");
  check("a1.3 the time is in Asia/Tokyo", text === "Nov 20, 2026, 18:01:40 GMT+9", text ?? "");
  const time = A.locator('.card[data-id="5000"] time');
  check("a1.4 the datetime attribute is the UTC instant", (await time.getAttribute("datetime")) === "2026-11-20T09:01:40Z");
  check("a1.5 the title has the full timestamp", ((await time.getAttribute("title")) ?? "").includes("(Asia/Tokyo)"), (await time.getAttribute("title")) ?? "");
});

await step("a2. Simulate events streams cards one by one to every open page", async () => {
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
  const first = await A.locator(".card").first().getAttribute("data-id");
  check("a2.3 the newest card is at the top", first === "5004", first ?? "");
  check("a2.4 a new card has the enter class", (await A.locator(".feed-live .card").first().getAttribute("class"))?.includes("card-new") ?? false);
  const zoned = await timeOf(A, "5004");
  check("a2.5 a new card shows its time in the zone", (zoned ?? "").endsWith("GMT+9"), zoned ?? "");
  const other = await B.waitForFunction(() => document.querySelectorAll(".feed-live .card").length === 4, null, { timeout: 5000 }).then(() => true, () => false);
  check("a2.6 the other page gets the same events", other);
  await A.getByRole("button", { name: "Simulate events" }).waitFor({ timeout: 5000 });
  check("a2.7 the button is enabled again", await A.getByRole("button", { name: "Simulate events" }).isEnabled());
  await B.close();
});

await step("a3. the project filter works with the keyboard", async () => {
  await A.goto(app, { waitUntil: "networkidle" });
  await started(A);
  await A.locator("#project-button").focus();
  await A.keyboard.press("ArrowDown");
  await A.locator("#project-input").waitFor();
  check("a3.1 ArrowDown opens the list and focuses the search", await A.evaluate(() => document.activeElement?.id === "project-input"));
  await A.keyboard.type("bill");
  const options = await A.locator("#project-list [role=option]").allTextContents();
  check("a3.2 typing filters the options", options.length === 1 && options[0].trim() === "Billing", options.join("|"));
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
  await A.waitForFunction(() => document.querySelector(".feed-count")?.textContent?.includes("of 5004 events"));
  check("a3.8 Clear removes the filter", (await A.locator(".feed .card").first().getAttribute("data-id")) === "5004");
});

await step("a4. the settings change the time zone and jump to a date", async () => {
  await A.getByRole("button", { name: "Settings" }).click();
  await A.locator("#settings-zone").selectOption("America/New_York");
  const text = await timeOf(A, "5000");
  check("a4.1 every date follows the new zone", text === "Nov 20, 2026, 04:01:40 EST", text ?? "");
  await A.locator("#settings-date").fill("2026-11-01T12:00");
  await A.getByRole("button", { name: "Go" }).click();
  await A.waitForURL((url) => url.searchParams.has("before"));
  await A.waitForFunction(() => document.querySelector(".feed-count")?.textContent?.includes("before"));
  const before = Number(new URL(A.url()).searchParams.get("before"));
  check("a4.2 the date is read in the zone", before === Date.UTC(2026, 10, 1, 17, 1) / 1000, String(before));
  const first = Number(await A.locator(".feed .card time").first().getAttribute("data-ts"));
  check("a4.3 the feed starts at that date", first < before && before - first < 1200, `${first} ${before}`);
  await A.reload({ waitUntil: "networkidle" });
  check("a4.4 the zone is kept after a reload", ((await A.locator(".feed .card time").first().textContent()) ?? "").endsWith("EST"));
});

await step("a5. the theme toggle", async () => {
  await A.goto(app, { waitUntil: "networkidle" });
  await started(A);
  if (shots) await A.screenshot({ path: `${shots}/async-feed-light.png` });
  const theme = () => A.evaluate(() => document.documentElement.getAttribute("data-theme"));
  check("a5.1 the theme follows the system first", (await theme()) === "light");
  await A.getByRole("button", { name: "Toggle light and dark theme" }).click();
  check("a5.2 a click turns it dark", (await theme()) === "dark");
  await A.reload({ waitUntil: "networkidle" });
  check("a5.3 the choice is kept before the first paint", (await theme()) === "dark");
  if (shots) {
    await started(A);
    await A.screenshot({ path: `${shots}/async-feed-dark.png` });
  }
});

check("a6 no console errors, page errors, hydration mismatches or failed requests", problems.length === 0, problems.join(" | "));

await browser.close();
console.log(failures === 0 ? "\nASYNC FEED ALL PASS" : `\n${failures} FAILED (async feed)`);
process.exit(failures === 0 ? 0 : 1);
