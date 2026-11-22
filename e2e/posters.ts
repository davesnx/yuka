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
const grid = (p: Page) => p.locator(".poster-grid path").evaluateAll((ps) => ps.map((x) => x.getAttribute("d")).join("|"));
const paths = (text: string) => {
  const start = text.indexOf('class="poster-grid"');
  const part = text.slice(start, text.indexOf("</g>", start));
  return [...part.matchAll(/<path d="([^"]*)"/g)].map((m) => m[1]).join("|");
};
const served = async (path: string) => paths(await (await fetch(app + path)).text());
const svgOf = async (query: string) => {
  const r = await fetch(app + "/poster.svg" + query);
  return { type: r.headers.get("content-type") ?? "", cache: r.headers.get("cache-control") ?? "", text: await r.text() };
};
const search = (p: Page, key: string) => new URL(p.url()).searchParams.get(key);
const mark = (p: Page) => p.locator(".poster-grid path").evaluateAll((ps) => ps.forEach((x, i) => ((x as any).__mark = i)));
const kept = (p: Page) =>
  p.locator(".poster-grid path").evaluateAll((ps) => [ps.filter((x) => (x as any).__mark !== undefined).length, ps.length]);

const P: Page = await ctx.newPage();
P.on("console", (m) => {
  if (m.type() === "error" || m.text().includes("hydration mismatch")) problems.push(m.text());
});
P.on("pageerror", (e) => problems.push(String(e)));

let first = "";
await step("p1. the playground loads with the server poster", async () => {
  await P.goto(app, { waitUntil: "networkidle" });
  await started(P);
  first = await grid(P);
  check("p1.1 the preview has one path per drawn cell", (await P.locator(".poster-grid path").count()) > 100, String(await P.locator(".poster-grid path").count()));
  check("p1.2 the island keeps the server poster", first === (await served("")));
  check("p1.3 the default URL has no settings", new URL(P.url()).search === "", P.url());
  check("p1.4 the SVG link has no settings", (await P.getByRole("link", { name: "Download SVG" }).getAttribute("href"))?.endsWith("/posters/poster.svg") ?? false);
  if (shots) await P.screenshot({ path: `${shots}/posters-dark.png` });
});

let seeded = "";
await step("p2. a new seed redraws the poster and writes the URL", async () => {
  await P.locator("#seed").fill("42");
  await P.waitForURL((url) => url.searchParams.get("seed") === "42");
  seeded = await grid(P);
  check("p2.1 the preview changes", seeded !== first && seeded.length > 100);
  check("p2.2 the browser draws what the server draws for that seed", seeded === (await served("?seed=42")));
  await P.getByRole("button", { name: "Shuffle" }).click();
  await P.waitForURL((url) => url.searchParams.get("seed") !== "42");
  const shuffled = await grid(P);
  check("p2.3 Shuffle picks another seed", shuffled !== seeded && (await P.locator("#seed").inputValue()) === search(P, "seed"), search(P, "seed") ?? "");
  await P.locator("#seed").fill("42");
  await P.waitForURL((url) => url.searchParams.get("seed") === "42");
});

let columns = "";
await step("p3. the columns slider and the shape mix", async () => {
  await P.locator("#columns").fill("9");
  await P.waitForURL((url) => url.searchParams.get("columns") === "9");
  columns = await grid(P);
  check("p3.1 the preview changes", columns !== seeded);
  check("p3.2 it matches the server", columns === (await served("?seed=42&columns=9")));
  check("p3.3 the value shows next to the label", ((await P.locator(".field", { has: P.locator("#columns") }).textContent()) ?? "").includes("9"));
  await mark(P);
  await P.locator("#bar").fill("10");
  await P.waitForURL((url) => url.searchParams.get("bar") === "10");
  const [same, total] = await kept(P);
  check("p3.4 a mix change renders only the cells whose shape changed", same > 0 && same < total, `${same} of ${total} nodes kept`);
  await P.locator("#bar").fill("6");
  await P.waitForURL((url) => !url.searchParams.has("bar"));
  columns = await grid(P);
});

await step("p4. the light preset changes attributes only", async () => {
  await mark(P);
  await P.getByRole("button", { name: "Light" }).click();
  await P.waitForURL((url) => url.searchParams.get("bg") === "f4f4f4");
  const [same, total] = await kept(P);
  check("p4.1 every cell node stays", same === total && total > 0, `${same} of ${total}`);
  check("p4.2 the card is light", (await P.locator(".poster rect").first().getAttribute("fill")) === "#f4f4f4");
  check("p4.3 the shapes are dark", (await P.locator(".poster-grid").getAttribute("fill")) === "#333333");
  check("p4.4 the colour input follows", (await P.locator("#background").inputValue()) === "#f4f4f4");
  check("p4.5 the preset is pressed", (await P.getByRole("button", { name: "Light" }).getAttribute("aria-pressed")) === "true");
  await P.locator("#title").fill("Hello");
  await P.waitForURL((url) => url.searchParams.get("title") === "Hello");
  check("p4.6 the title is in upper case", (await P.locator(".poster text").first().textContent()) === "HELLO");
  check("p4.7 a text change keeps the cells", (await kept(P))[0] === total);
});

await step("p5. a reload shows the same poster", async () => {
  await P.reload({ waitUntil: "networkidle" });
  await started(P);
  check("p5.1 same grid", (await grid(P)) === columns);
  check("p5.2 same colours", (await P.locator(".poster rect").first().getAttribute("fill")) === "#f4f4f4");
  check("p5.3 same controls", (await P.locator("#seed").inputValue()) === "42" && (await P.locator("#columns").inputValue()) === "9");
  if (shots) await P.screenshot({ path: `${shots}/posters-light.png` });
});

await step("p6. Download SVG is a link to the poster.svg route; PNG draws it on a canvas", async () => {
  const link = P.getByRole("link", { name: "Download SVG" });
  const href = (await link.getAttribute("href")) ?? "";
  const query = href.slice(href.indexOf("?"));
  check("p6.1 the link is /posters/poster.svg with the settings", href.startsWith("/posters/poster.svg?") || href.startsWith("/poster.svg?"), href);
  check("p6.2 it has the settings of the page", query === new URL(P.url()).search, `${query} vs ${new URL(P.url()).search}`);
  const answer = await svgOf(query);
  check("p6.3 the route answers an SVG with a public cache", answer.type.startsWith("image/svg+xml") && answer.cache.startsWith("public"), `${answer.type}; ${answer.cache}`);
  check("p6.4 the SVG has the cells of the preview", paths(answer.text) === columns && answer.text.includes(">HELLO</text>"));
  const [svg] = await Promise.all([P.waitForEvent("download"), link.click()]);
  const text = readFileSync(await svg.path(), "utf8");
  check("p6.5 the download is that SVG", text === answer.text && svg.suggestedFilename() === "poster-42.svg", svg.suggestedFilename());
  const [png] = await Promise.all([P.waitForEvent("download"), P.getByRole("button", { name: "Download PNG" }).click()]);
  const bytes = readFileSync(await png.path());
  const magic = bytes.subarray(1, 4).toString("ascii");
  check("p6.6 the PNG is twice the poster size", magic === "PNG" && bytes.readUInt32BE(16) === 2000 && bytes.readUInt32BE(20) === 2828, `${magic} ${bytes.readUInt32BE(16)}x${bytes.readUInt32BE(20)}`);
});

await step("p7. the gallery", async () => {
  const G = await ctx.newPage();
  G.on("pageerror", (e) => problems.push(String(e)));
  await G.goto(app + "/gallery", { waitUntil: "networkidle" });
  check("p7.1 eight posters", (await G.locator(".gallery-item .poster").count()) === 8);
  check("p7.2 no JavaScript file", (await G.locator('script[type="module"]').count()) === 0);
  if (shots) await G.screenshot({ path: `${shots}/posters-gallery.png`, fullPage: true });
  const card = G.locator(".gallery-item").nth(3);
  const drawn = paths(await card.locator(".poster").evaluate((e) => e.outerHTML));
  await card.locator("a").first().click();
  await G.waitForURL((url) => url.pathname.endsWith("/posters") || url.pathname === "/");
  await started(G);
  check("p7.3 a preset opens in the playground with its settings", (await G.locator("#columns").inputValue()) === "8" && search(G, "seed") === "314", G.url());
  check("p7.4 the playground draws the same poster", (await grid(G)) === drawn);
  await G.close();
});

await step("p8. 24 x 30 cells", async () => {
  await P.goto(app + "?columns=24&rows=30", { waitUntil: "networkidle" });
  await started(P);
  const nodes = await P.locator(".poster-grid path").count();
  const all = await P.evaluate(() => document.querySelectorAll(".poster *").length);
  const measure = (id: string, low: number, high: number) =>
    P.evaluate(
      async ([id, low, high]) => {
        const input = document.querySelector(id as string) as HTMLInputElement;
        const out: number[][] = [[], []];
        for (let i = 0; i < 10; i++) {
          const start = performance.now();
          input.value = String(i % 2 ? low : high);
          input.dispatchEvent(new Event("input", { bubbles: true }));
          out[0].push(performance.now() - start);
          await new Promise((r) => requestAnimationFrame(() => setTimeout(r)));
          out[1].push(performance.now() - start);
        }
        return out.map((xs) => xs.sort((a, b) => a - b));
      },
      [id, low, high],
    );
  for (const [id, low, high] of [["#half", 60, 80], ["#columns", 23, 24]] as const) {
    const [updates, frames] = await measure(id, low, high);
    console.log(`INFO  24x30 ${id}: ${nodes} cell paths, ${all} nodes in the poster; update median ${updates[5].toFixed(1)} ms (max ${updates[9].toFixed(1)}), to next frame median ${frames[5].toFixed(1)} ms (max ${frames[9].toFixed(1)})`);
  }
  check("p8.1 the grid has at most 720 cell paths", nodes > 600 && nodes <= 720, String(nodes));
});

check("p9 no console errors, page errors or hydration mismatches", problems.length === 0, problems.join(" | "));

await browser.close();
console.log(failures === 0 ? "\nPOSTERS ALL PASS" : `\n${failures} FAILED (posters)`);
process.exit(failures === 0 ? 0 : 1);
