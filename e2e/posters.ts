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
const pathKey = (d: string, fill: string, width: string) => `${d}/${fill}/${width}`;
const grid = (p: Page) =>
  p
    .locator(".poster-art path")
    .evaluateAll((ps) => ps.map((x) => `${x.getAttribute("d")}/${x.getAttribute("fill") ?? ""}/${x.getAttribute("stroke-width") ?? ""}`).join("|"));
const attr = (tag: string, name: string) => tag.match(new RegExp(` ${name}="([^"]*)"`))?.[1] ?? "";
const paths = (text: string) => {
  const start = text.indexOf('class="poster-art"');
  const part = text.slice(start, text.indexOf("</g>", start));
  return [...part.matchAll(/<path [^>]*>/g)].map((m) => pathKey(attr(m[0], "d"), attr(m[0], "fill"), attr(m[0], "stroke-width"))).join("|");
};
const served = async (search: string) => paths(await (await fetch(app + search)).text());
const svgOf = async (query: string) => {
  const r = await fetch(app + "/poster.svg" + query);
  return { type: r.headers.get("content-type") ?? "", cache: r.headers.get("cache-control") ?? "", text: await r.text() };
};
const search = (p: Page, key: string) => new URL(p.url()).searchParams.get(key);
const count = (p: Page) => p.locator(".poster-art path").count();
const mark = (p: Page) => p.locator(".poster-art path").evaluateAll((ps) => ps.forEach((x, i) => ((x as any).__mark = i)));
const kept = (p: Page) =>
  p.locator(".poster-art path").evaluateAll((ps) => [ps.filter((x) => (x as any).__mark !== undefined).length, ps.length]);
const box = async (p: Page, selector: string) => (await p.locator(selector).boundingBox()) ?? { x: -1, y: -1, width: 0, height: 0 };

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
  check("p1.1 the preview has one path per line", (await count(P)) === 22, String(await count(P)));
  check("p1.2 the island keeps the server poster", first === (await served("")));
  check("p1.3 the default URL has no settings", new URL(P.url()).search === "", P.url());
  check("p1.4 the SVG link has no settings", (await P.getByRole("link", { name: "Download SVG" }).getAttribute("href"))?.endsWith("/posters/poster.svg") ?? false);
  check("p1.5 there is no seed input", (await P.locator("#seed").count()) === 0);
  check("p1.6 only the sliders of Lines show", (await P.locator("#waves").count()) === 1 && (await P.locator("#gap, #puffs, #bolts").count()) === 0);
  if (shots) await P.screenshot({ path: `${shots}/posters-lines.png` });
});

await step("p2. each kind draws its shapes, shows its sliders and matches the server", async () => {
  for (const [name, slider, others] of [
    ["Blocks", "#squareness", "#waves, #puffs, #bolts"],
    ["Clouds", "#puffs", "#waves, #gap, #bolts"],
    ["Lightning", "#jaggedness", "#waves, #gap, #puffs"],
    ["Lines", "#amplitude", "#gap, #puffs, #bolts"],
  ] as const) {
    const before = await grid(P);
    await P.getByRole("button", { name, exact: true }).click();
    const kind = name.toLowerCase();
    await P.waitForURL((url) => (kind === "lines" ? !url.searchParams.has("kind") : url.searchParams.get("kind") === kind));
    const drawn = await grid(P);
    check(`p2 ${name}: the preview changes`, drawn !== before && (await count(P)) > 0, String(await count(P)));
    check(`p2 ${name}: the browser draws what the server draws`, drawn === (await served(new URL(P.url()).search)));
    check(`p2 ${name}: the button is pressed`, (await P.getByRole("button", { name, exact: true }).getAttribute("aria-pressed")) === "true");
    check(`p2 ${name}: its sliders show, the others do not`, (await P.locator(slider).count()) === 1 && (await P.locator(others).count()) === 0);
    if (shots) await P.screenshot({ path: `${shots}/posters-${kind}.png` });
  }
  check("p2 back on Lines, the poster of the start", (await grid(P)) === first);
});

let shuffled = "";
await step("p3. Shuffle picks another seed and writes it in the URL", async () => {
  await P.getByRole("button", { name: "Blocks", exact: true }).click();
  await P.waitForURL((url) => url.searchParams.get("kind") === "blocks");
  const before = await grid(P);
  await P.getByRole("button", { name: "Shuffle" }).click();
  await P.waitForURL((url) => url.searchParams.has("seed"));
  shuffled = await grid(P);
  check("p3.1 the preview changes", shuffled !== before, search(P, "seed") ?? "");
  check("p3.2 it matches the server for that seed", shuffled === (await served(new URL(P.url()).search)));
});

let blocks = "";
await step("p4. a slider of the kind and the padding", async () => {
  await P.locator("#gap").fill("30");
  await P.waitForURL((url) => url.searchParams.get("gap") === "30");
  const gapped = await grid(P);
  check("p4.1 the gap changes the preview", gapped !== shuffled);
  check("p4.2 it matches the server", gapped === (await served(new URL(P.url()).search)));
  check("p4.3 the value shows next to the label", ((await P.locator(".field", { has: P.locator("#gap") }).textContent()) ?? "").includes("30"));
  await mark(P);
  await P.locator("#filled").fill("80");
  await P.waitForURL((url) => url.searchParams.get("filled") === "80");
  const [same, total] = await kept(P);
  check("p4.4 a filled share change renders only the blocks that changed", same > 0 && same < total, `${same} of ${total} nodes kept`);
  await P.locator("#padding").fill("20");
  await P.waitForURL((url) => url.searchParams.get("padding") === "20");
  blocks = await grid(P);
  check("p4.5 the padding moves the art", blocks !== gapped);
  check("p4.6 it matches the server", blocks === (await served(new URL(P.url()).search)));
  const xs = await P.locator(".poster-art path").evaluateAll((ps) => ps.map((x) => Number((x.getAttribute("d") ?? "").slice(1).split(" ")[0])));
  check("p4.7 the art starts at the padding", Math.min(...xs) >= 20 && Math.min(...xs) <= 23, String(Math.min(...xs)));
});

await step("p5. the light preset changes attributes only", async () => {
  await mark(P);
  await P.getByRole("button", { name: "Light", exact: true }).click();
  await P.waitForURL((url) => url.searchParams.get("bg") === "f4f4f4");
  const [same, total] = await kept(P);
  check("p5.1 every shape node stays", same === total && total > 0, `${same} of ${total}`);
  check("p5.2 the card is light", (await P.locator(".poster rect").first().getAttribute("fill")) === "#f4f4f4");
  check("p5.3 the shapes are dark", (await P.locator(".poster-art").getAttribute("fill")) === "#333333");
  check("p5.4 the colour input follows", (await P.locator("#background").inputValue()) === "#f4f4f4");
  check("p5.5 the preset is pressed", (await P.getByRole("button", { name: "Light", exact: true }).getAttribute("aria-pressed")) === "true");
});

await step("p6. the text column is left of the poster", async () => {
  const text = await box(P, ".text-panel");
  const poster = await box(P, ".preview");
  const settings = await box(P, ".settings-panel");
  check("p6.1 text, poster, settings from left to right", text.x + text.width <= poster.x && poster.x + poster.width <= settings.x, `${text.x} ${poster.x} ${settings.x}`);
  check("p6.2 the title field is in the text column", (await P.locator(".text-panel #title").count()) === 1);
  await mark(P);
  await P.locator("#title").fill("Hello");
  await P.waitForURL((url) => url.searchParams.get("title") === "Hello");
  check("p6.3 the title is in upper case", (await P.locator(".poster text").first().textContent()) === "HELLO");
  const [same, total] = await kept(P);
  check("p6.4 a text change keeps the shapes", same === total, `${same} of ${total}`);
  await P.setViewportSize({ width: 600, height: 900 });
  const narrowText = await box(P, ".text-panel");
  const narrowPoster = await box(P, ".preview");
  check("p6.5 on a narrow screen the text goes under the poster", narrowText.y >= narrowPoster.y + narrowPoster.height, `${narrowText.y} ${narrowPoster.y + narrowPoster.height}`);
  await P.setViewportSize({ width: 1280, height: 900 });
});

await step("p7. a reload shows the same poster", async () => {
  await P.reload({ waitUntil: "networkidle" });
  await started(P);
  check("p7.1 same shapes", (await grid(P)) === blocks);
  check("p7.2 same colours", (await P.locator(".poster rect").first().getAttribute("fill")) === "#f4f4f4");
  check("p7.3 same controls", (await P.locator("#gap").inputValue()) === "30" && (await P.locator("#padding").inputValue()) === "20");
  check("p7.4 the kind stays pressed", (await P.getByRole("button", { name: "Blocks", exact: true }).getAttribute("aria-pressed")) === "true");
  if (shots) await P.screenshot({ path: `${shots}/posters-light.png` });
});

await step("p8. Download SVG is a link to the poster.svg route; PNG draws it on a canvas", async () => {
  const link = P.getByRole("link", { name: "Download SVG" });
  const href = (await link.getAttribute("href")) ?? "";
  const query = href.slice(href.indexOf("?"));
  check("p8.1 the link is /posters/poster.svg with the settings", href.startsWith("/posters/poster.svg?") || href.startsWith("/poster.svg?"), href);
  check("p8.2 it has the settings of the page", query === new URL(P.url()).search, `${query} vs ${new URL(P.url()).search}`);
  const answer = await svgOf(query);
  check("p8.3 the route answers an SVG with a public cache", answer.type.startsWith("image/svg+xml") && answer.cache.startsWith("public"), `${answer.type}; ${answer.cache}`);
  check("p8.4 the SVG has the shapes of the preview", paths(answer.text) === blocks && answer.text.includes(">HELLO</text>"));
  const seed = search(P, "seed");
  const [svg] = await Promise.all([P.waitForEvent("download"), link.click()]);
  const text = readFileSync(await svg.path(), "utf8");
  check("p8.5 the download is that SVG", text === answer.text && svg.suggestedFilename() === `poster-${seed}.svg`, svg.suggestedFilename());
  const [png] = await Promise.all([P.waitForEvent("download"), P.getByRole("button", { name: "Download PNG" }).click()]);
  const bytes = readFileSync(await png.path());
  const magic = bytes.subarray(1, 4).toString("ascii");
  check("p8.6 the PNG is twice the poster size", magic === "PNG" && bytes.readUInt32BE(16) === 2000 && bytes.readUInt32BE(20) === 2828, `${magic} ${bytes.readUInt32BE(16)}x${bytes.readUInt32BE(20)}`);
});

await step("p9. the gallery", async () => {
  const G = await ctx.newPage();
  G.on("pageerror", (e) => problems.push(String(e)));
  await G.goto(app + "/gallery", { waitUntil: "networkidle" });
  check("p9.1 eight posters", (await G.locator(".gallery-item .poster").count()) === 8);
  check("p9.2 no JavaScript file", (await G.locator('script[type="module"]').count()) === 0);
  if (shots) await G.screenshot({ path: `${shots}/posters-gallery.png`, fullPage: true });
  const card = G.locator(".gallery-item").nth(3);
  const drawn = paths(await card.locator(".poster").evaluate((e) => e.outerHTML));
  await card.locator("a").first().click();
  await G.waitForURL((url) => url.pathname.endsWith("/posters") || url.pathname === "/");
  await started(G);
  check("p9.3 a preset opens in the playground with its settings", (await G.locator("#blocks").inputValue()) === "40" && search(G, "seed") === "1234", G.url());
  check("p9.4 the playground draws the same poster", (await grid(G)) === drawn);
  await G.close();
});

await step("p10. 60 lines with 10 waves", async () => {
  await P.goto(app + "?lines=60&waves=10", { waitUntil: "networkidle" });
  await started(P);
  const nodes = await count(P);
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
  for (const [id, low, high] of [["#amplitude", 60, 80], ["#padding", 40, 60]] as const) {
    const [updates, frames] = await measure(id, low, high);
    console.log(`INFO  60 lines ${id}: ${nodes} paths; update median ${updates[5].toFixed(1)} ms (max ${updates[9].toFixed(1)}), to next frame median ${frames[5].toFixed(1)} ms (max ${frames[9].toFixed(1)})`);
  }
  check("p10.1 one path per line", nodes === 60, String(nodes));
});

check("p11 no console errors, page errors or hydration mismatches", problems.length === 0, problems.join(" | "));

await browser.close();
console.log(failures === 0 ? "\nPOSTERS ALL PASS" : `\n${failures} FAILED (posters)`);
process.exit(failures === 0 ? 0 : 1);
