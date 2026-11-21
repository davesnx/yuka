import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const url = process.argv[2] ?? "http://127.0.0.1:8130/demo/sketch";
const throttle = Number(process.env.CPU_THROTTLE ?? "1");

const colors = ["black", "grey", "red", "orange", "yellow", "green", "blue", "violet"];
const shapes: unknown[] = [];
let id = 1;
for (let row = 0; row < 20; row++) {
  for (let col = 0; col < 25; col++) {
    const x = 20 + col * 50;
    const y = 20 + row * 38;
    const base = { id, x, y, r: 0, color: colors[id % 8], size: "m", fill: id % 3 === 0 ? "semi" : "none" };
    const pick = id % 10;
    if (pick < 4) {
      const points: number[] = [];
      for (let i = 0; i < 60; i++) points.push(i * 0.6, 12 + Math.sin(i / 5) * 10, 0.5);
      shapes.push({ ...base, w: 35.4, h: 20, kind: "draw", simulate: true, points });
    } else if (pick < 6) shapes.push({ ...base, w: 36, h: 26, kind: "rect" });
    else if (pick < 8) shapes.push({ ...base, w: 36, h: 26, kind: "ellipse" });
    else if (pick < 9) shapes.push({ ...base, w: 36, h: 24, kind: "arrow", ends: [0, 24, 36, 0] });
    else shapes.push({ ...base, w: 36, h: 20, kind: "text", text: "note", scale: 0.6 });
    id++;
  }
}

const browser = await chromium.launch({ headless: true });
const page: Page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const errors: string[] = [];
page.on("pageerror", (e) => errors.push(String(e)));
await page.goto(url);
await page.evaluate((json) => localStorage.setItem("sketch.board.v1", json), JSON.stringify({ board: { next: id, shapes }, camera: { x: 0, y: 0, zoom: 1 } }));
await page.reload();
await page.waitForFunction(() => document.querySelectorAll("[data-shape]").length === 500);
if (throttle > 1) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: throttle });
}

const startFrames = () =>
  page.evaluate(() => {
    const w = window as any;
    w.__frames = [];
    w.__last = performance.now();
    w.__on = true;
    const tick = (t: number) => {
      if (!w.__on) return;
      w.__frames.push(t - w.__last);
      w.__last = t;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame((t) => {
      w.__last = t;
      requestAnimationFrame(tick);
    });
  });
const stopFrames = (): Promise<number[]> =>
  page.evaluate(() => {
    const w = window as any;
    w.__on = false;
    return w.__frames as number[];
  });
const stats = (name: string, frames: number[]) => {
  const sorted = [...frames].sort((a, b) => a - b);
  const q = (p: number) => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  const over = frames.filter((f) => f > 20).length;
  if (process.env.SHOW_LONG) console.log("  long frames at", frames.map((f, i) => [i, Math.round(f)]).filter(([, f]) => f > 20).map(([i, f]) => `#${i}:${f}ms`).join(" "));
  console.log(`${name}: ${frames.length} frames, p50 ${q(0.5).toFixed(1)} ms, p95 ${q(0.95).toFixed(1)} ms, max ${sorted[sorted.length - 1].toFixed(1)} ms, frames over 20 ms: ${over}`);
};
const raf = () => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => r(null))));

await page.keyboard.press("d");
await page.mouse.move(200, 300);
await startFrames();
await page.mouse.down();
for (let i = 0; i < 240; i++) {
  const t = i / 240;
  await page.mouse.move(200 + t * 800, 300 + Math.sin(t * Math.PI * 6) * 150);
  await raf();
}
await page.mouse.up();
stats("freehand draw over 500 shapes", await stopFrames());

await page.keyboard.press("v");
await page.mouse.move(15, 15);
await page.mouse.down();
await page.mouse.move(15 + 50 * 10 - 25, 15 + 38 * 5 - 15, { steps: 5 });
await page.mouse.up();
const selected = await page.evaluate(() => Number(document.querySelector(".select-box")?.getAttribute("data-boxes") ?? 0));
console.log(`selected ${selected} shapes`);
await page.mouse.move(45, 35);
await startFrames();
await page.mouse.down();
for (let i = 0; i < 240; i++) {
  await page.mouse.move(45 + i * 2.5, 35 + i * 1.5);
  await raf();
}
await page.mouse.up();
stats(`drag of ${selected} selected shapes`, await stopFrames());

await page.mouse.move(640, 400);
await startFrames();
for (let i = 0; i < 120; i++) {
  await page.mouse.wheel(4, 3);
  await raf();
}
stats("pan of 500 shapes", await stopFrames());

console.log(errors.length ? "errors: " + errors.join(" | ") : "no page errors");
await browser.close();
