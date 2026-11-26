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
const clock = (p: Page) => p.locator(".clock").innerText();
const rows = (p: Page) => p.locator('.proc[role="row"][data-pid]');
const column = async (p: Page, index: number) =>
  (await rows(p).locator(`.cell:nth-child(${index})`).allInnerTexts()).map((t) => t.trim());
const sortedDown = (values: number[]) => values.every((v, i) => i === 0 || values[i - 1] >= v);
const dialog = (p: Page) => p.locator('[role="dialog"]');

const P = await open("dark");

await step("the first screen", async () => {
  await P.goto(app + "/");
  const server = await P.locator(".box.mem").innerText();
  await started(P);
  check("the island keeps the server screen", (await P.locator(".box.mem").innerText()) === server);
  check("the clock of the laptop", (await clock(P)) === "18:42:07", await clock(P));
  check("at least 28 processes", (await rows(P).count()) >= 28, String(await rows(P).count()));
  check("sorted by %CPU", sortedDown((await column(P, 8)).map(Number)));
  check("four boxes", (await P.locator("section.box").count()) === 4);
  check("a full CPU graph", (await P.locator(".box.cpu .graph-line").count()) === 13);
  check("8 cores", (await P.locator(".core").count()) === 8);
  const height = await P.locator(".window").evaluate((e) => e.getBoundingClientRect().height);
  check("the window fills the screen", height === 980, String(height));
  check("Lilex loads", await P.evaluate(() => document.fonts.check("13px Lilex")));
  if (shots) await P.screenshot({ path: shots + "/top-dark.png" });
});

await step("a new screen each second", async () => {
  const before = await clock(P);
  await P.waitForFunction((b) => document.querySelector(".clock")?.textContent !== b, before, { timeout: 3000 });
  check("the clock moves", (await clock(P)) !== before, `${before} -> ${await clock(P)}`);
});

await step("sort", async () => {
  await P.keyboard.press("Space");
  check("Space pauses", (await P.locator(".rate").innerText()).includes("paused"));
  await P.keyboard.press("M");
  check("M sorts by memory", (await P.locator(".sortable.on").innerText()).trim() === "MemB");
  check("the sort on the border", (await P.locator(".sort-tag").innerText()).trim() === "mem");
  await P.locator('.sortable[title^="Sort by Pid"]').click();
  check("a click on Pid sorts by PID", sortedDown((await column(P, 1)).map(Number)));
  await P.locator('.sortable[title^="Sort by Pid"]').click();
  const pids = (await column(P, 1)).map(Number);
  check("a second click reverses", pids[0] === 1, String(pids[0]));
  await P.locator(".key", { hasText: "reverse" }).click();
  await P.keyboard.press("Space");
  check("Space after a click on a key goes to top", !(await P.locator(".rate").innerText()).includes("paused"));
  await P.keyboard.press("Space");
  await P.locator(".key", { hasText: "reverse" }).click();
  await P.keyboard.press("P");
});

await step("filter", async () => {
  await P.keyboard.press("f");
  check("f focuses the filter", await P.evaluate(() => document.activeElement?.id === "proc-filter"));
  await P.keyboard.type("fire");
  await P.waitForFunction(() => document.querySelectorAll('.proc[data-pid]').length < 5);
  const value = await P.locator("#proc-filter").inputValue();
  const commands = await column(P, 3);
  check("only firefox", commands.length === 1 && commands[0] === "firefox", commands.join(",") + " for " + value);
  check("the count", (await P.locator(".box-foot .dim").innerText()).startsWith("1/"));
  await P.keyboard.press("Escape");
  check("Escape clears", (await rows(P).count()) >= 28);
  await P.locator("#proc-filter").blur();
});

await step("the detail of a process", async () => {
  await P.keyboard.press("Space");
  check("Space goes on", !(await P.locator(".rate").innerText()).includes("paused"));
  await P.locator('.proc[data-pid="1"]').click();
  check("a click opens the detail", await dialog(P).isVisible());
  check("its title", (await P.locator("#proc-title").innerText()) === "systemd");
  check("the close button has the focus", await P.evaluate(() => document.activeElement?.id === "proc-close"));
  check("the row is selected", (await P.locator(".proc.selected").getAttribute("data-pid")) === "1");
  await P.keyboard.press("k");
  check("root's process stays", (await P.locator('.proc[data-pid="1"]').count()) === 1);
  check("not permitted", (await dialog(P).innerText()).includes("Operation not permitted"));
  const frame = await dialog(P).elementHandle();
  await P.waitForFunction((b) => document.querySelector(".clock")?.textContent !== b, await clock(P), {
    timeout: 3000,
  });
  check("the detail stays across screens", await frame!.evaluate((e) => e.isConnected));
  check("the focus stays on the close button", await P.evaluate(() => document.activeElement?.id === "proc-close"));
  await P.keyboard.press("Escape");
  check("Escape closes", (await dialog(P).count()) === 0);
  await P.locator('.proc[data-pid="1"]').click();
  await P.locator(".scrim").click({ position: { x: 5, y: 5 } });
  check("a click outside closes", (await dialog(P).count()) === 0);
});

await step("kill", async () => {
  const firefox = P.locator(".proc", { hasText: "firefox" });
  const pid = await firefox.getAttribute("data-pid");
  await firefox.click();
  check("the command", (await P.locator(".cmdline").innerText()) === "firefox");
  await dialog(P).getByRole("button", { name: "Kill" }).click();
  check("the detail closes", (await dialog(P).count()) === 0);
  check("firefox is gone", (await P.locator(`.proc[data-pid="${pid}"]`).count()) === 0);
  check("the message", (await P.locator(".box-foot .message").innerText()).includes("SIGKILL to pid " + pid));
  await P.keyboard.press("ArrowDown");
  check("ArrowDown selects", (await P.locator(".proc.selected").count()) === 1);
  await P.keyboard.press("Enter");
  check("Enter opens the detail", await dialog(P).isVisible());
  await P.keyboard.press("Escape");
});

await step("another host", async () => {
  await P.locator('.panel a[href*="build-01"]').click();
  await P.waitForURL(/build-01/);
  await started(P);
  check("the clock of build-01", (await clock(P)) === "03:14:51", await clock(P));
  check("selected host", (await P.locator(".panel .row.selected .label").innerText()) === "build-01");
  check("32 cores", (await P.locator(".core").count()) === 32);
});

await step("quit and start again", async () => {
  await P.keyboard.press("q");
  check("exited", await P.locator(".exited").isVisible());
  await P.locator(".exited button").click();
  check("the boxes again", await P.locator(".box.cpu").isVisible());
});

await step("light theme", async () => {
  const L = await open("light");
  await L.goto(app + "/?host=db-1");
  await started(L);
  const background = await L.locator(".center").evaluate((e) => getComputedStyle(e).backgroundColor);
  check("One Light terminal", background === "rgb(250, 250, 250)", background);
  await L.locator(".proc", { hasText: "checkpointer" }).click();
  check("the detail in the light theme", await dialog(L).isVisible());
  await L.waitForTimeout(300);
  if (shots) await L.screenshot({ path: shots + "/top-light.png" });
});

check("no page or console error", problems.length === 0, problems.join(" | "));
await browser.close();
console.log(failures === 0 ? "top: all checks passed" : `top: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
