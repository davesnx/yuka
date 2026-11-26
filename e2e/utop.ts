import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = process.argv[2] ?? "http://127.0.0.1:8125/utop";
const shots = process.env.UTOP_SCREENSHOTS ?? "";

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
    if (m.type() === "error" && !m.text().startsWith("Failed to load resource")) problems.push("console: " + m.text());
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
const phrases = (p: Page) => p.locator(".phrase:not(.live)").count();
const lastAnswer = (p: Page) => p.locator(".phrase:not(.live) .answer").last().innerText();
const type = async (p: Page, text: string) => {
  await p.locator("#utop-input").fill(text);
  await p.keyboard.press("Enter");
};

const P = await open("dark");

await step("the first session renders on the server", async () => {
  await P.goto(app + "/");
  await started(P);
  check("five phrases of lists.ml", (await phrases(P)) === 5, String(await phrases(P)));
  check("banner", (await P.locator(".banner").innerText()).includes("Welcome to utop version"));
  check("the type is highlighted", (await P.locator(".phrase .tk.type").first().innerText()) === "int list");
  check("box drawing survives hydration", !(await P.locator(".terminal").innerText()).includes("\u00e2"));
  check("Lilex loads", await P.evaluate(() => document.fonts.check("13px Lilex")));
  if (shots) await P.screenshot({ path: shots + "/utop-dark.png" });
});

await step("arithmetic and let", async () => {
  await type(P, "let x = 6 * 7;;");
  check("val x", (await lastAnswer(P)) === "val x : int = 42", await lastAnswer(P));
  await type(P, "x / (2 - 2);;");
  check("Division_by_zero", (await lastAnswer(P)) === "Exception: Division_by_zero.", await lastAnswer(P));
  await type(P, "y + 1;;");
  check("unbound", (await lastAnswer(P)).includes("Error: Unbound value y"), await lastAnswer(P));
  check("counter", (await P.locator(".phrase.live .bar-count").first().innerText()) === "8");
});

await step("a phrase on two lines", async () => {
  await type(P, "1 +");
  check("continues", (await P.locator(".phrase.live .prompt-line").count()) === 2);
  await type(P, "2;;");
  check("answers", (await lastAnswer(P)) === "- : int = 3", await lastAnswer(P));
});

await step("history and completion", async () => {
  await P.locator("#utop-input").fill("");
  await P.keyboard.press("ArrowUp");
  check("ArrowUp gives the last phrase", (await P.locator("#utop-input").inputValue()) === "1 + 2;;");
  await P.locator("#utop-input").fill("List.fo");
  check("completions", (await P.locator(".completion .word").allInnerTexts()).join(",") === "fold_left,fold_right");
  await P.keyboard.press("Tab");
  check("Tab completes", (await P.locator("#utop-input").inputValue()) === "List.fold_left");
  await P.keyboard.press("Control+l");
  check("Ctrl+L clears", (await phrases(P)) === 0);
});

await step("another session", async () => {
  await P.locator('.panel a[href*="variants.ml"]').click();
  await P.waitForURL(/variants\.ml/);
  await started(P);
  check("four phrases of variants.ml", (await phrases(P)) === 4, String(await phrases(P)));
  check("warning", (await P.locator(".tk.warning").count()) === 1);
  check("selected file", (await P.locator(".panel .row.selected").innerText()) === "variants.ml");
});

await step("#quit and start again", async () => {
  await type(P, "#quit;;");
  check("exited", await P.locator(".exited").isVisible());
  await P.locator(".exited button").click();
  check("prompt again", await P.locator("#utop-input").isVisible());
});

await step("light theme", async () => {
  const L = await open("light");
  await L.goto(app + "/?file=modules.ml");
  await started(L);
  const background = await L.locator(".center").evaluate((e) => getComputedStyle(e).backgroundColor);
  check("One Light terminal", background === "rgb(250, 250, 250)", background);
  if (shots) await L.screenshot({ path: shots + "/utop-light.png" });
});

check("no page or console error", problems.length === 0, problems.join(" | "));
await browser.close();
console.log(failures === 0 ? "utop: all checks passed" : `utop: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
