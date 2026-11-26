import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = process.argv[2] ?? "http://127.0.0.1:8125/quest";
const shots = process.env.QUEST_SCREENSHOTS ?? "";

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

// The right answer of each riddle, and "Continue" at the start of each act after the first.
const way = [
  "A mountain", "Footsteps", "A river", "A map", "Silence", "Continue",
  "A fish", "Wind", "The letter M", "A coffin", "Fire", "Continue",
  "An egg", "A bottle", "Time", "A towel", "A needle", "Continue",
  "None more", "A ton", "Light", "Nine", "A coin", "Continue",
  "A cold", "Teeth", "A comb", "Your age", "Darkness",
];

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const problems: string[] = [];
const P: Page = await ctx.newPage();
P.on("pageerror", (e) => problems.push(String(e)));
P.on("console", (m) => {
  if (m.type() === "error") problems.push(m.text());
});
const started = (p: Page) =>
  p.waitForFunction(() => {
    const islands = [...document.querySelectorAll("yuka-island")];
    return islands.length > 0 && islands.every((i) => (i as any).__yuka_started);
  });
const exitsShown = (p: Page) => p.waitForSelector(".scene .exits", { timeout: 10000 });
const take = async (p: Page, label: string) => {
  await exitsShown(p);
  await p.locator("a.exit", { hasText: label }).first().click();
};

await step("q1 the opening streams its exits after its lines", async () => {
  const started = performance.now();
  const reader = (await fetch(app)).body!.getReader();
  const decoder = new TextDecoder();
  let html = "";
  let first = -1;
  let exits = -1;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    html += decoder.decode(value, { stream: true });
    if (first < 0) first = performance.now() - started;
    if (exits < 0 && html.includes('class="exits"')) exits = performance.now() - started;
  }
  check("q1.1 the exits come 0.5 s or more after the first bytes", exits - first >= 500, `${Math.round(first)} ms, ${Math.round(exits)} ms`);
  await P.goto(app);
  await exitsShown(P);
  check("q1.2 the title", (await P.title()) === "Ashfall");
  check("q1.3 one exit", (await P.locator("a.exit").count()) === 1);
  check("q1.4 the page does not scroll", await P.evaluate(() => document.documentElement.scrollHeight <= innerHeight));
  if (shots) await P.screenshot({ path: `${shots}/quest-opening.png` });
});

await step("q2 a client navigation keeps the layout", async () => {
  await started(P);
  await P.evaluate(() => ((document.querySelector(".hud") as any).__mark = 1));
  await take(P, "Enter the world");
  await P.waitForSelector(".scene.act");
  check("q2.1 the HUD stays", await P.evaluate(() => (document.querySelector(".hud") as any).__mark === 1));
  check("q2.2 the URL is an opaque id", /\/scene\/[0-9a-f]{12}$/.test(P.url()), P.url());
});

await step("q3 a key follows an exit", async () => {
  await exitsShown(P);
  await started(P);
  await P.keyboard.press("1");
  await P.waitForSelector(".scene.riddle");
  await exitsShown(P);
  check("q3.1 the first riddle", (await P.locator(".sub").textContent()) === "Riddle 1 of 5");
  check("q3.2 three answers", (await P.locator("a.exit").count()) === 3);
  if (shots) await P.screenshot({ path: `${shots}/quest-riddle.png` });
});

let riddle = "";
await step("q4 a wrong answer is a death, with a way back", async () => {
  await exitsShown(P);
  riddle = P.url();
  await take(P, "A shadow");
  await P.waitForSelector(".scene.death");
  check("q4.1 the heading", (await P.locator("h1").textContent()) === "You have died");
  check("q4.2 the life globe is empty", (await P.locator(".globe.life.empty").count()) === 1);
  if (shots) await P.screenshot({ path: `${shots}/quest-death.png` });
  await P.goBack();
  await P.waitForSelector(".scene.riddle");
  check("q4.3 Back is the riddle", P.url() === riddle, P.url());
  await P.goForward();
  await P.waitForSelector(".scene.death");
  await take(P, "Rise again");
  await P.waitForSelector(".scene.riddle");
  check("q4.4 Rise again is the riddle", P.url() === riddle, P.url());
});

await step("q5 the right answers lead to the duel", async () => {
  for (const label of way) await take(P, label);
  await P.waitForSelector(".scene.duel .board");
  check("q5.1 nine cells", (await P.locator(".board .cell").count()) === 9);
  check("q5.2 every pip lit", (await P.locator(".pip.lit").count()) === 25);
  if (shots) await P.screenshot({ path: `${shots}/quest-duel.png` });
});

await step("q6 a fork beats the Ash King", async () => {
  await started(P);
  for (const cell of ["1", "9", "7", "4"]) {
    await P.waitForSelector(".scene.duel, .scene.ending");
    if (await P.locator(".scene.ending").count()) break;
    await started(P);
    await P.keyboard.press(cell);
    await P.waitForFunction((n) => !document.querySelector(`.cell.open kbd`) || ![...document.querySelectorAll(".cell.open kbd")].some((k) => k.textContent === n), cell);
  }
  await P.waitForSelector(".scene.ending.victory");
  check("q6.1 victory", (await P.locator("h1").textContent()) === "Victory");
  check("q6.2 the winning line", (await P.locator(".cell.win").count()) === 3);
  await exitsShown(P);
  if (shots) await P.screenshot({ path: `${shots}/quest-victory.png` });
});

await step("q7 a reload shows the same scene", async () => {
  const url = P.url();
  await P.reload();
  await P.waitForSelector(".scene.ending.victory");
  check("q7.1 the same URL", P.url() === url);
});

check("q8 no console error", problems.length === 0, problems.join(" | "));

await step("q9 an unknown scene is a 404", async () => {
  const response = await P.goto(app + "/scene/000000000000");
  check("q9.1 404", response?.status() === 404, String(response?.status()));
});
await browser.close();
console.log(failures === 0 ? "\nQUEST ALL PASS" : `\n${failures} FAILED (quest)`);
process.exit(failures === 0 ? 0 : 1);
