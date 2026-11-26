import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = process.argv[2] ?? "http://127.0.0.1:8125/top";
const shots = process.env.TOP_SCREENSHOTS ?? "";

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
const problems: string[] = [];
const open = async (scheme: "dark" | "light") => {
  const ctx = await browser.newContext({ viewport: { width: 1360, height: 980 }, colorScheme: scheme });
  const p: Page = await ctx.newPage();
  p.on("pageerror", (e) => problems.push("pageerror: " + e.message));
  p.on("console", (m) => {
    if ((m.type() === "error" || m.type() === "warning") && !m.text().startsWith("Failed to load resource"))
      problems.push("console: " + m.text());
  });
  p.on("response", (r) => {
    if (r.status() >= 400) problems.push(`${r.status()} ${r.url()}`);
  });
  return p;
};
const started = (p: Page) =>
  p.waitForFunction(() => {
    const islands = [...document.querySelectorAll("yuka-island")];
    return islands.length > 0 && islands.every((i) => (i as any).__yuka_started);
  });
const clock = (p: Page) => p.locator(".summary .value").first().innerText();
const rows = (p: Page) => p.locator('.proc[role="row"][data-pid]');
const column = async (p: Page, index: number) =>
  (await rows(p).locator(`.cell:nth-child(${index})`).allInnerTexts()).map((t) => t.trim());
const sortedDown = (values: number[]) => values.every((v, i) => i === 0 || values[i - 1] >= v);

const P = await open("dark");

await step("the first screen", async () => {
  await P.goto(app + "/");
  const server = await P.locator(".summary").innerText();
  await started(P);
  check("the island keeps the server screen", (await P.locator(".summary").innerText()) === server);
  check("the clock of the laptop", (await clock(P)) === "18:42:07", await clock(P));
  check("28 processes", (await rows(P).count()) === 28, String(await rows(P).count()));
  check("sorted by %CPU", sortedDown((await column(P, 9)).map(Number)));
  check("graphs", (await P.locator(".meter").count()) === 3, String(await P.locator(".meter").count()));
  check("Lilex loads", await P.evaluate(() => document.fonts.check("13px Lilex")));
  if (shots) await P.screenshot({ path: shots + "/top-dark.png" });
});

await step("a new screen each second", async () => {
  const before = await clock(P);
  await P.waitForFunction((b) => document.querySelector(".summary .value")?.textContent !== b, before, {
    timeout: 3000,
  });
  check("the clock moves", (await clock(P)) !== before, `${before} -> ${await clock(P)}`);
});

await step("sort", async () => {
  await P.keyboard.press("M");
  check("M sorts by memory", (await P.locator(".sortable.on").innerText()).trim() === "%MEM");
  await P.keyboard.press("Space");
  check("Space pauses", (await P.locator(".message").innerText()).includes("Paused"));
  check("sorted by %MEM", sortedDown((await column(P, 10)).map(Number)));
  await P.locator('.sortable[title^="Sort by PID"]').click();
  check("a click on PID sorts by PID", sortedDown((await column(P, 1)).map(Number)));
  await P.locator('.sortable[title^="Sort by PID"]').click();
  const pids = (await column(P, 1)).map(Number);
  check("a second click reverses", pids[0] === 1, String(pids[0]));
  await P.keyboard.press("Space");
});

await step("graphs and cores", async () => {
  await P.keyboard.press("t");
  check("t shows text", (await P.locator(".meter").count()) === 0);
  check("the CPU line", (await P.locator(".summary").innerText()).includes("%Cpu(s):"));
  await P.keyboard.press("1");
  check("1 shows 8 cores", (await P.locator(".cores .line").count()) === 8);
  await P.keyboard.press("1");
  await P.keyboard.press("t");
});

await step("select and kill", async () => {
  await P.keyboard.press("P");
  await P.keyboard.press("Space");
  await P.locator('.proc[data-pid="1"]').click();
  check("a click selects", (await P.locator(".proc.selected").getAttribute("data-pid")) === "1");
  await P.keyboard.press("k");
  check("root's process stays", (await P.locator('.proc[data-pid="1"]').count()) === 1);
  check("not permitted", (await P.locator(".message").innerText()).includes("Operation not permitted"));
  const firefox = P.locator(".proc", { hasText: "firefox" });
  const pid = await firefox.getAttribute("data-pid");
  await firefox.click();
  await P.keyboard.press("k");
  check("firefox is gone", (await P.locator(`.proc[data-pid="${pid}"]`).count()) === 0);
  check("the message", (await P.locator(".message").innerText()).includes("SIGTERM to pid " + pid));
  await P.keyboard.press("ArrowDown");
  check("ArrowDown selects", (await P.locator(".proc.selected").count()) === 1);
  await P.keyboard.press("Space");
});

await step("another host", async () => {
  await P.locator('.panel a[href*="build-01"]').click();
  await P.waitForURL(/build-01/);
  await started(P);
  check("the clock of build-01", (await clock(P)) === "03:14:51", await clock(P));
  check("selected host", (await P.locator(".panel .row.selected .label").innerText()) === "build-01");
  await P.keyboard.press("1");
  check("32 cores", (await P.locator(".cores .line").count()) === 32);
});

await step("quit and start again", async () => {
  await P.keyboard.press("q");
  check("exited", await P.locator(".exited").isVisible());
  await P.locator(".exited button").click();
  check("the screen again", await P.locator(".summary").isVisible());
});

await step("light theme", async () => {
  const L = await open("light");
  await L.goto(app + "/?host=db-1");
  await started(L);
  const background = await L.locator(".center").evaluate((e) => getComputedStyle(e).backgroundColor);
  check("One Light terminal", background === "rgb(250, 250, 250)", background);
  if (shots) await L.screenshot({ path: shots + "/top-light.png" });
});

check("no page or console error", problems.length === 0, problems.join(" | "));
await browser.close();
console.log(failures === 0 ? "top: all checks passed" : `top: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
