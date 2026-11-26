import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";
import { readFileSync } from "node:fs";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = process.argv[2] ?? "http://127.0.0.1:8125/genart";

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
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
const problems: string[] = [];
const P: Page = await ctx.newPage();
P.on("console", (m) => {
  if (m.type() === "error" || m.text().includes("hydration mismatch")) problems.push(m.text());
});
P.on("pageerror", (e) => problems.push(String(e)));

const started = (p: Page) =>
  p.waitForFunction(() => {
    const islands = [...document.querySelectorAll("yuka-island")];
    return islands.length > 0 && islands.every((i) => (i as any).__yuka_started);
  });
const keyOf = (tag: string) =>
  ["x1", "y1", "x2", "y2", "stroke", "opacity"].map((n) => tag.match(new RegExp(` ${n}="([^"]*)"`))?.[1] ?? "").join(",");
const drawn = (p: Page) =>
  p
    .locator("#sketch line")
    .evaluateAll((ls) =>
      ls.map((l) => ["x1", "y1", "x2", "y2", "stroke", "opacity"].map((n) => l.getAttribute(n) ?? "").join(",")).join("|"),
    );
const served = async (search: string) =>
  [...(await (await fetch(app + search)).text()).matchAll(/<line [^>]*>/g)].map((m) => keyOf(m[0])).join("|");
const count = (p: Page) => p.locator("#sketch line").count();
const search = (p: Page) => new URL(p.url()).search;
const mark = (p: Page) => p.locator("#sketch line").evaluateAll((ls) => ls.forEach((l, i) => ((l as any).__mark = i)));
const kept = (p: Page) =>
  p.locator("#sketch line").evaluateAll((ls) => ls.filter((l) => (l as any).__mark !== undefined).length);
const setRange = (p: Page, id: string, value: number) =>
  p.locator(id).evaluate((input, value) => {
    (input as HTMLInputElement).value = String(value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  }, value);

await step("g1. the island keeps the lines of the server", async () => {
  await P.goto(app, { waitUntil: "networkidle" });
  await started(P);
  check("g1.1 400 lines", (await count(P)) === 400, String(await count(P)));
  check("g1.2 the browser shows the server lines", (await drawn(P)) === (await served("")));
  check("g1.3 the default URL has no settings", search(P) === "", P.url());
});

await step("g2. the grid slider draws the lines again in the browser", async () => {
  await setRange(P, "#grid", 21);
  check("g2.1 441 lines", (await count(P)) === 441, String(await count(P)));
  check("g2.2 the URL has the grid", search(P) === "?grid=21", search(P));
  check("g2.3 the browser draws what the server draws", (await drawn(P)) === (await served("?grid=21")));
});

await step("g3. the width sets one attribute", async () => {
  await mark(P);
  await setRange(P, "#stroke", 24);
  const width = await P.locator("#sketch g").getAttribute("stroke-width");
  check("g3.1 the width", width === "24", String(width));
  check("g3.2 every line keeps its node", (await kept(P)) === 441, String(await kept(P)));
});

await step("g4. a palette", async () => {
  await P.getByRole("button", { name: "Glacier" }).click();
  const colors = new Set(await P.locator("#sketch line").evaluateAll((ls) => ls.map((l) => l.getAttribute("stroke"))));
  check("g4.1 five colours or fewer", colors.size <= 5, [...colors].join(" "));
  check("g4.2 pressed", (await P.getByRole("button", { name: "Glacier" }).getAttribute("aria-pressed")) === "true");
  check("g4.3 the URL", search(P) === "?grid=21&stroke=24&palette=5", search(P));
});

await step("g5. shuffle and reload", async () => {
  const before = await drawn(P);
  await P.getByRole("button", { name: "Shuffle" }).click();
  check("g5.1 other lines", (await drawn(P)) !== before);
  const seed = new URL(P.url()).searchParams.get("seed");
  check("g5.2 the seed is in the URL", seed !== null && seed !== "4", String(seed));
  const shown = await drawn(P);
  await P.reload({ waitUntil: "networkidle" });
  await started(P);
  check("g5.3 a reload shows the same lines", (await drawn(P)) === shown);
});

await step("g6. the drift draws some lines again", async () => {
  await mark(P);
  const before = await drawn(P);
  await P.getByRole("button", { name: "Drift" }).click();
  await P.waitForTimeout(600);
  await P.getByRole("button", { name: "Stop drift" }).click();
  const after = await drawn(P);
  const a = before.split("|"), b = after.split("|");
  const changed = a.filter((x, i) => x !== b[i]).length;
  check("g6.1 some lines changed", changed > 0 && changed < a.length / 2, `${changed} of ${a.length}`);
  const stayed = await kept(P);
  check("g6.2 the other lines keep their nodes", stayed >= a.length - 2 * changed && stayed < a.length, `${stayed} of ${a.length}`);
  await P.waitForTimeout(300);
  check("g6.3 the drift stops", (await drawn(P)) === after);
});

await step("g7. download PNG", async () => {
  const [download] = await Promise.all([P.waitForEvent("download"), P.getByRole("button", { name: "Download PNG" }).click()]);
  const file = readFileSync(await download.path());
  check("g7.1 a PNG", file.subarray(1, 4).toString() === "PNG", download.suggestedFilename());
  check("g7.2 2048 px", file.readUInt32BE(16) === 2048 && file.readUInt32BE(20) === 2048);
});

check("g8 no console errors, page errors or hydration mismatches", problems.length === 0, problems.join(" | "));

await browser.close();
console.log(failures === 0 ? "\nGENART ALL PASS" : `\n${failures} FAILED (genart)`);
process.exit(failures === 0 ? 0 : 1);
