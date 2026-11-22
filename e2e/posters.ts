import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";
import { readFileSync } from "node:fs";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const app = process.argv[2] ?? "http://127.0.0.1:8125/posters";
const shots = process.env.POSTERS_SCREENSHOTS ?? "";

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
const started = (p: Page) =>
  p.waitForFunction(() => {
    const islands = [...document.querySelectorAll("yuka-island")];
    return islands.length > 0 && islands.every((i) => (i as any).__yuka_started);
  });
const grid = (p: Page) => p.locator(".poster-grid").getAttribute("d");
const served = async (path: string) => {
  const html = await (await fetch(app + path)).text();
  return /class="poster-grid"[^>]* d="([^"]*)"/.exec(html)?.[1] ?? "";
};
const search = (p: Page, key: string) => new URL(p.url()).searchParams.get(key);

const P: Page = await ctx.newPage();
P.on("console", (m) => {
  if (m.type() === "error" || m.text().includes("hydration mismatch")) problems.push(m.text());
});
P.on("pageerror", (e) => problems.push(String(e)));

let first = "";
await step("p1. the playground loads with the server poster", async () => {
  await P.goto(app, { waitUntil: "networkidle" });
  await started(P);
  first = (await grid(P)) ?? "";
  check("p1.1 the preview has a grid", first.length > 100);
  check("p1.2 the island keeps the server poster", first === (await served("")));
  check("p1.3 the default URL has no settings", new URL(P.url()).search === "", P.url());
  if (shots) await P.screenshot({ path: `${shots}/posters-dark.png` });
});

let seeded = "";
await step("p2. a new seed redraws the poster and writes the URL", async () => {
  await P.locator("#seed").fill("42");
  await P.waitForURL((url) => url.searchParams.get("seed") === "42");
  seeded = (await grid(P)) ?? "";
  check("p2.1 the preview changes", seeded !== first && seeded.length > 100);
  check("p2.2 the browser draws what the server draws for that seed", seeded === (await served("?seed=42")));
  await P.getByRole("button", { name: "Shuffle" }).click();
  await P.waitForURL((url) => url.searchParams.get("seed") !== "42");
  const shuffled = (await grid(P)) ?? "";
  check("p2.3 Shuffle picks another seed", shuffled !== seeded && (await P.locator("#seed").inputValue()) === search(P, "seed"), search(P, "seed") ?? "");
  await P.locator("#seed").fill("42");
  await P.waitForURL((url) => url.searchParams.get("seed") === "42");
});

let columns = "";
await step("p3. the columns slider", async () => {
  await P.locator("#columns").fill("9");
  await P.waitForURL((url) => url.searchParams.get("columns") === "9");
  columns = (await grid(P)) ?? "";
  check("p3.1 the preview changes", columns !== seeded);
  check("p3.2 it matches the server", columns === (await served("?seed=42&columns=9")));
  check("p3.3 the value shows next to the label", ((await P.locator(".field", { has: P.locator("#columns") }).textContent()) ?? "").includes("9"));
});

await step("p4. the light preset", async () => {
  await P.getByRole("button", { name: "Light" }).click();
  await P.waitForURL((url) => url.searchParams.get("bg") === "f4f4f4");
  check("p4.1 the card is light", (await P.locator(".poster rect").first().getAttribute("fill")) === "#f4f4f4");
  check("p4.2 the shapes are dark", (await P.locator(".poster-grid").getAttribute("fill")) === "#333333");
  check("p4.3 the colour input follows", (await P.locator("#background").inputValue()) === "#f4f4f4");
  check("p4.4 the preset is pressed", (await P.getByRole("button", { name: "Light" }).getAttribute("aria-pressed")) === "true");
  await P.locator("#title").fill("Hello");
  await P.waitForURL((url) => url.searchParams.get("title") === "Hello");
  check("p4.5 the title is in upper case", (await P.locator(".poster text").first().textContent()) === "HELLO");
});

await step("p5. a reload shows the same poster", async () => {
  await P.reload({ waitUntil: "networkidle" });
  await started(P);
  check("p5.1 same grid", (await grid(P)) === columns);
  check("p5.2 same colours", (await P.locator(".poster rect").first().getAttribute("fill")) === "#f4f4f4");
  check("p5.3 same controls", (await P.locator("#seed").inputValue()) === "42" && (await P.locator("#columns").inputValue()) === "9");
  if (shots) await P.screenshot({ path: `${shots}/posters-light.png` });
});

await step("p6. Download SVG and PNG", async () => {
  const [svg] = await Promise.all([P.waitForEvent("download"), P.getByRole("button", { name: "Download SVG" }).click()]);
  const text = readFileSync(await svg.path(), "utf8");
  check("p6.1 the file is an SVG", text.startsWith("<svg xmlns=\"http://www.w3.org/2000/svg\"") && text.endsWith("</svg>"), svg.suggestedFilename());
  check("p6.2 it has the poster of the preview", text.includes(`d="${columns}"`) && text.includes(">HELLO</text>"));
  check("p6.3 its name has the seed", svg.suggestedFilename() === "poster-42.svg");
  const [png] = await Promise.all([P.waitForEvent("download"), P.getByRole("button", { name: "Download PNG" }).click()]);
  const bytes = readFileSync(await png.path());
  const magic = bytes.subarray(1, 4).toString("ascii");
  check("p6.4 the PNG is twice the poster size", magic === "PNG" && bytes.readUInt32BE(16) === 2000 && bytes.readUInt32BE(20) === 2828, `${magic} ${bytes.readUInt32BE(16)}x${bytes.readUInt32BE(20)}`);
});

check("p7 no console errors, page errors or hydration mismatches", problems.length === 0, problems.join(" | "));

await browser.close();
console.log(failures === 0 ? "\nPOSTERS ALL PASS" : `\n${failures} FAILED (posters)`);
process.exit(failures === 0 ? 0 : 1);
