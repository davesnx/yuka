import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";
import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const url = process.argv[2] ?? "http://127.0.0.1:8130/demo/sketch";
const shots = process.argv[3] ?? "e2e/screenshots/sketch";
mkdirSync(shots, { recursive: true });

let failures = 0;
const check = (name: string, ok: boolean, evidence = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${evidence ? "  [" + evidence + "]" : ""}`);
};

type Shape = {
  id: number; x: number; y: number; w: number; h: number; r: number;
  color: string; size: string; fill: string; kind: string;
  ends?: number[]; text?: string; scale?: number; points?: number[];
};
type Saved = { board: { shapes: Shape[] }; camera: { x: number; y: number; zoom: number } };

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, acceptDownloads: true });
const page: Page = await context.newPage();
const errors: string[] = [];
page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
page.on("pageerror", (e) => errors.push(String(e)));

const saved = async (): Promise<Saved> => {
  await page.waitForTimeout(380);
  return page.evaluate(() => JSON.parse(localStorage.getItem("sketch.board.v1") ?? "null"));
};
const shapes = async () => (await saved()).board.shapes;
const shot = (name: string) => page.screenshot({ path: join(shots, name + ".png") });
const key = (k: string) => page.keyboard.press(k);
const drag = async (from: [number, number], to: [number, number], steps = 12, button: "left" | "middle" = "left") => {
  await page.mouse.move(from[0], from[1]);
  await page.mouse.down({ button });
  await page.mouse.move(to[0], to[1], { steps });
  await page.mouse.up({ button });
};
const withKey = async (k: string, f: () => Promise<void>) => {
  await page.keyboard.down(k);
  await f();
  await page.keyboard.up(k);
};
const reset = async () => {
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForSelector(".sketch");
  await page.waitForFunction(() => document.querySelector(".hint") !== null);
};
const camera = () => page.evaluate(() => document.querySelector('[data-layer="world"]')!.getAttribute("transform")!);
const handle = (name: string) =>
  page.evaluate((n) => {
    const el = document.querySelector(`[data-handle="${n}"]`);
    if (!el) return null;
    const b = el.getBoundingClientRect();
    return [b.x + b.width / 2, b.y + b.height / 2] as [number, number];
  }, name);
const resizeHandles = () =>
  page.evaluate(() => ["n", "s", "e", "w", "ne", "nw", "se", "sw"].filter((n) => document.querySelector(`[data-handle="${n}"]`)).length);
const boxes = () => page.evaluate(() => Number(document.querySelector(".select-box")?.getAttribute("data-boxes") ?? 0));
const count = (selector: string) => page.evaluate((s) => document.querySelectorAll(s).length, selector);
const near = (a: number, b: number, eps = 0.6) => Math.abs(a - b) <= eps;
const onStep = (deg: number, step = 15, eps = 0.01) => {
  const r = ((deg % step) + step) % step;
  return r <= eps || step - r <= eps;
};

await page.goto(url);
await reset();

{
  await key("r");
  await drag([560, 330], [720, 450]);
  await key("Escape");
  await withKey("Space", () => drag([300, 300], [380, 340]));
  const afterSpace = await camera();
  check("canvas: space+drag pans", afterSpace.startsWith("translate(80 40)"), afterSpace);
  await drag([300, 300], [260, 300], 6, "middle");
  check("canvas: middle drag pans", (await camera()).startsWith("translate(40 40)"), await camera());
  await page.mouse.move(640, 400);
  await page.mouse.wheel(30, 60);
  await page.waitForTimeout(50);
  check("canvas: wheel pans", (await camera()).startsWith("translate(10 -20)"), await camera());
  const before = await page.evaluate(() => {
    const r = document.querySelector('[data-shape]')!.getBoundingClientRect();
    return [r.x, r.y];
  });
  const anchor = [before[0] + 20, before[1] + 20];
  await page.mouse.move(anchor[0], anchor[1]);
  await page.keyboard.down("Control");
  for (let i = 0; i < 6; i++) await page.mouse.wheel(0, -20);
  await page.keyboard.up("Control");
  await page.waitForTimeout(50);
  const after = await page.evaluate(() => {
    const r = document.querySelector('[data-shape]')!.getBoundingClientRect();
    return [r.x, r.y];
  });
  const s = await saved();
  const z = s.camera.zoom;
  check("canvas: ctrl+wheel zooms in", z > 1.5, `zoom ${z.toFixed(3)}`);
  const expected = [anchor[0] - (anchor[0] - before[0]) * z, anchor[1] - (anchor[1] - before[1]) * z];
  check("canvas: zoom keeps the point under the cursor", near(after[0], expected[0], 1) && near(after[1], expected[1], 1), `${after} vs ${expected}`);
  const patternAt = (await page.getAttribute("#sketch-dots", "width"))!;
  check("canvas: dot grid scales with zoom", near(Number(patternAt), 24 * z, 0.02), `pattern ${patternAt}, zoom ${z}`);
  await shot("01-canvas-zoomed");
  await key("Shift+0");
  check("canvas: shift+0 is 100%", (await page.textContent(".zoom")) === "100%", (await page.textContent(".zoom"))!);
  await key("=");
  check("canvas: + zooms a step", (await page.textContent(".zoom")) === "200%", (await page.textContent(".zoom"))!);
  await key("-");
  await key("-");
  check("canvas: - zooms a step", (await page.textContent(".zoom")) === "50%", (await page.textContent(".zoom"))!);
  await key("Shift+1");
  const fit = await saved();
  check("canvas: shift+1 fits the board", fit.camera.zoom === 1 && near(fit.camera.x, 640 - 640, 1), JSON.stringify(fit.camera));
  await page.click('[data-action="zoom-out"]');
  await page.click('[data-action="zoom-out"]');
  const zoomedOut = (await saved()).camera.zoom;
  const patternOut = Number(await page.getAttribute("#sketch-dots", "width"));
  check("canvas: grid stays readable zoomed out", patternOut >= 14, `zoom ${zoomedOut} pattern ${patternOut}`);
  await page.click('[data-action="zoom-fit"]');
  await shot("01-canvas");
}

{
  await reset();
  await key("d");
  await page.mouse.move(300, 420);
  await page.mouse.down();
  let liveSeen = false;
  for (let i = 1; i <= 90; i++) {
    const t = i / 90;
    await page.mouse.move(300 + t * 620, 420 + Math.sin(t * Math.PI * 3) * 110 * (1 - t * 0.4));
    if (i === 45) liveSeen = (await count('[data-live="true"]')) === 1;
  }
  await page.mouse.up();
  check("pen: the stroke shows while drawing", liveSeen);
  check("pen: no live stroke after release", (await count('[data-live="true"]')) === 0);
  for (let i = 0; i <= 40; i++) {
    const t = i / 40;
    await page.mouse.move(300 + t * 200, 600 - t * 60, { steps: 1 });
    if (i === 0) await page.mouse.down();
  }
  for (let i = 0; i <= 12; i++) await page.mouse.move(500 + i * 30, 540 + i * 4, { steps: 1 });
  await page.mouse.up();
  const s = await shapes();
  check("pen: two strokes", s.length === 2 && s.every((x) => x.kind === "draw"), `${s.length}`);
  const d = await page.getAttribute('[data-shape] path', "d");
  check("pen: smooth closed outline path", !!d && d.startsWith("M") && d.includes("T") && d.endsWith("Z"), (d ?? "").slice(0, 40));
  await shot("02-pen");
  await key("v");
  await page.mouse.move(600, 380);
  await page.keyboard.down("Control");
  for (let i = 0; i < 12; i++) await page.mouse.wheel(0, -20);
  await page.keyboard.up("Control");
  await shot("02-pen-zoomed");
}

{
  await reset();
  await key("r");
  await drag([200, 200], [360, 300]);
  await key("r");
  await withKey("Shift", () => drag([420, 200], [560, 260]));
  await key("o");
  await withKey("Alt", () => drag([760, 260], [840, 300]));
  await key("o");
  await withKey("Shift", () => drag([300, 420], [420, 470]));
  await page.click('[data-fill="semi"]');
  await key("r");
  await page.mouse.click(700, 500);
  await page.mouse.click(1000, 650);
  const s = await shapes();
  const [r1, sq, el, circle, clicked] = s;
  check("rect: drag", s.length === 5 && r1.kind === "rect" && r1.w === 160 && r1.h === 100, JSON.stringify(r1));
  check("rect: shift makes a square", sq.w === sq.h && sq.w === 140, `${sq.w}x${sq.h}`);
  check("ellipse: alt draws from the centre", el.kind === "ellipse" && el.x === 680 && el.y === 220 && el.w === 160 && el.h === 80, JSON.stringify(el));
  check("ellipse: shift makes a circle", circle.kind === "ellipse" && circle.w === circle.h, `${circle.w}x${circle.h}`);
  check("rect: a click makes a 100x100", clicked.w === 100 && clicked.h === 100 && clicked.fill === "semi", JSON.stringify(clicked));
  await shot("03-rect-ellipse");
}

{
  await reset();
  await key("a");
  await drag([200, 200], [520, 260]);
  await key("a");
  await withKey("Shift", () => drag([200, 360], [520, 380]));
  await key("l");
  await withKey("Shift", () => drag([640, 420], [800, 260]));
  await key("a");
  await drag([700, 600], [1000, 520]);
  await page.mouse.click(1100, 700);
  const s = await shapes();
  const snapped = s[1].ends!;
  const angle = (e: number[]) => (Math.atan2(e[3] - e[1], e[2] - e[0]) * 180) / Math.PI;
  check("arrow: two paths (shaft and head)", (await count('[data-shape="' + s[0].id + '"] path')) === 2);
  check("arrow: shift snaps to 15 degrees", onStep(angle(snapped)), `${angle(snapped)}`);
  check("line: shift snaps to 45 degrees", near(Math.abs(angle(s[2].ends!)), 45, 0.01), `${angle(s[2].ends!)}`);
  check("line: no head", (await count('[data-shape="' + s[2].id + '"] path')) === 1);
  await page.mouse.click(360, 230);
  check("arrow: selected arrow shows end handles", (await count('[data-handle="start"]')) === 1 && (await count('[data-handle="end"]')) === 1);
  const end = (await handle("end"))!;
  await withKey("Shift", () => drag(end, [end[0] + 20, end[1] + 140]));
  const moved = (await shapes())[0].ends!;
  check("arrow: dragging an end with shift snaps", onStep(angle(moved)) && !near(angle(moved), angle(s[0].ends!), 1), `${angle(s[0].ends!)} -> ${angle(moved)}`);
  await shot("04-arrow-line");
}

{
  await reset();
  await key("t");
  await page.mouse.click(300, 300);
  await page.waitForFunction(() => document.activeElement?.id === "sketch-text");
  await page.keyboard.type("Hello sketch");
  const w1 = await page.evaluate(() => (document.getElementById("sketch-text") as HTMLElement).getBoundingClientRect().width);
  await page.keyboard.press("Enter");
  await page.keyboard.type("second line, longer");
  const w2 = await page.evaluate(() => (document.getElementById("sketch-text") as HTMLElement).getBoundingClientRect().width);
  check("text: the box grows while typing", w2 > w1, `${w1} -> ${w2}`);
  await shot("05-text-editing");
  await key("Escape");
  let s = await shapes();
  check("text: kept with two lines", s.length === 1 && s[0].text === "Hello sketch\nsecond line, longer", JSON.stringify(s[0]?.text));
  check("text: rendered as two tspans", (await count('[data-shape] tspan')) === 2);
  const box = await page.evaluate(() => document.querySelector('[data-shape] text')!.getBoundingClientRect().toJSON());
  check("text: rendered where it was typed", near(box.x, 298, 6) && box.y > 270 && box.y < 300, JSON.stringify(box));
  await page.mouse.dblclick(box.x + 20, box.y + 10);
  await page.waitForFunction(() => document.activeElement?.id === "sketch-text");
  await page.keyboard.type("!");
  await key("Escape");
  s = await shapes();
  check("text: double click edits", s[0].text === "Hello sketch\nsecond line, longer!", JSON.stringify(s[0].text));
  await key("t");
  await page.mouse.click(600, 500);
  await page.waitForFunction(() => document.activeElement?.id === "sketch-text");
  await key("Escape");
  s = await shapes();
  check("text: an empty text is removed", s.length === 1, `${s.length}`);
  await page.mouse.dblclick(700, 600);
  await page.waitForFunction(() => document.activeElement?.id === "sketch-text");
  await page.keyboard.type("Made by double click");
  await page.mouse.click(1000, 300);
  s = await shapes();
  check("text: double click on the canvas makes a text; a click outside ends it", s.length === 2 && s[1].text === "Made by double click", `${s.length}`);
  await page.mouse.click(box.x + 20, box.y + 10);
  check("text: a selected text has 8 resize handles", (await resizeHandles()) === 8);
  const te = (await handle("e"))!;
  await drag(te, [te[0] + 60, te[1]]);
  s = await shapes();
  check("text: the side handle scales the text evenly", (s[0].scale ?? 1) > 1.1, `${s[0].scale}`);
  await key("Control+z");
  await shot("05-text");
}

{
  await reset();
  await key("r");
  await drag([200, 200], [340, 300]);
  await key("o");
  await drag([420, 200], [560, 300]);
  await key("d");
  await drag([640, 240], [800, 260], 20);
  await key("v");
  await page.mouse.click(1000, 650);
  await page.mouse.move(270, 200);
  await page.waitForTimeout(30);
  check("selection: hover outline", (await count(".outline.hover")) === 1);
  await page.mouse.click(270, 200);
  check("selection: click selects one, with 8 resize handles", (await count(".frame")) === 1 && (await resizeHandles()) === 8 && (await boxes()) === 0);
  await page.keyboard.down("Shift");
  await page.mouse.click(420, 250);
  await page.keyboard.up("Shift");
  check("selection: shift+click adds (outlines per shape)", (await boxes()) === 2);
  await page.mouse.click(1000, 650);
  check("selection: click on empty clears", (await count(".frame")) === 0);
  await page.mouse.move(380, 150);
  await page.mouse.down();
  await page.mouse.move(700, 350, { steps: 10 });
  const marquee = await count(".marquee");
  await shot("06-marquee");
  await page.mouse.up();
  check("selection: marquee box shows", marquee === 1);
  check("selection: marquee selects what it touches", (await boxes()) === 2);
  await key("Escape");
  check("selection: escape clears", (await count(".frame")) === 0);
  await key("Control+a");
  check("selection: ctrl+a selects all", (await boxes()) === 3);
  await shot("06-selection");
  await key("Escape");
}

{
  await reset();
  await key("r");
  await drag([400, 300], [600, 400]);
  let s = await shapes();
  const id = s[0].id;
  await drag([500, 350], [560, 380]);
  s = await shapes();
  check("move: drag moves", s[0].x === 460 && s[0].y === 330, `${s[0].x},${s[0].y}`);
  await key("ArrowRight");
  await key("Shift+ArrowDown");
  s = await shapes();
  check("move: arrow keys nudge (shift = 10)", s[0].x === 461 && s[0].y === 340, `${s[0].x},${s[0].y}`);
  const se = (await handle("se"))!;
  await drag(se, [se[0] + 100, se[1] + 50]);
  s = await shapes();
  check("resize: corner handle", near(s[0].w, 300) && near(s[0].h, 150), `${s[0].w}x${s[0].h}`);
  const se2 = (await handle("se"))!;
  await withKey("Shift", () => drag(se2, [se2[0] + 150, se2[1] + 10]));
  s = await shapes();
  check("resize: shift keeps the ratio", near(s[0].w / s[0].h, 2, 0.01), `${s[0].w}x${s[0].h}`);
  await key("Control+z");
  s = await shapes();
  const left = s[0].x;
  const width = s[0].w;
  const e = (await handle("e"))!;
  await drag(e, [e[0] - width - 120, e[1]]);
  s = await shapes();
  check("resize: the right edge handle dragged past the left edge flips", near(s[0].x, left - 120, 1) && near(s[0].w, 120, 1), `${s[0].x} ${s[0].w}`);
  await key("Control+z");
  s = await shapes();
  const top = s[0].y;
  const n = (await handle("n"))!;
  await drag(n, [n[0], n[1] - 40]);
  s = await shapes();
  check("resize: the top edge handle moves only the top", near(s[0].y, top - 40, 1) && near(s[0].w, width, 0.5), `${s[0].y} ${s[0].w}`);
  await key("Control+z");
  s = await shapes();
  const c = s[0].x + s[0].w / 2;
  const e2 = (await handle("e"))!;
  await withKey("Alt", () => drag(e2, [e2[0] + 50, e2[1]]));
  s = await shapes();
  const cx = s[0].x + s[0].w / 2;
  check("resize: alt resizes from the centre", near(cx, c, 1) && near(s[0].w, width + 100, 1), `${cx} ${s[0].w}`);
  await key("Control+z");
  const rot = (await handle("rotate"))!;
  await withKey("Shift", () => drag(rot, [rot[0] + 160, rot[1] + 40], 16));
  s = await shapes();
  const deg = (s[0].r * 180) / Math.PI;
  check("rotate: shift snaps to 15 degrees", deg > 1 && onStep(deg), `${deg}`);
  const corners = await page.evaluate(() => {
    const poly = document.querySelector(".frame")!.getAttribute("points")!.split(" ").map((p) => p.split(",").map(Number));
    const hs = ["nw", "ne", "se", "sw"].map((n) => {
      const r = document.querySelector(`[data-handle="${n}"]`)!;
      return [Number(r.getAttribute("x")) + 4, Number(r.getAttribute("y")) + 4];
    });
    return { poly, hs };
  });
  const onCorners = corners.hs.every((h, i) => near(h[0], corners.poly[i][0], 0.02) && near(h[1], corners.poly[i][1], 0.02));
  check("rotate: handles sit on the turned corners", onCorners, JSON.stringify(corners));
  const box = await page.evaluate((i) => document.querySelector(`[data-shape="${i}"]`)!.getBoundingClientRect().toJSON(), id);
  const frameBox = await page.evaluate(() => document.querySelector(".frame")!.getBoundingClientRect().toJSON());
  check("rotate: the frame is just outside the turned shape", frameBox.x < box.x && box.x - frameBox.x < 10 && frameBox.width > box.width && frameBox.width - box.width < 20, `${box.x},${box.width} vs ${frameBox.x},${frameBox.width}`);
  check("rotate: a turned shape keeps its 8 resize handles", (await resizeHandles()) === 8);
  await shot("07-rotated");
  const turnedW = s[0].w;
  const turnedH = s[0].h;
  const east = (await handle("e"))!;
  await drag(east, [east[0] + Math.cos(s[0].r) * 60, east[1] + Math.sin(s[0].r) * 60]);
  s = await shapes();
  check("resize: the edge handle of a turned shape stretches it along its own axis", near(s[0].w, turnedW + 60, 1) && near(s[0].h, turnedH, 0.5) && near((s[0].r * 180) / Math.PI, deg, 0.01), `${s[0].w}x${s[0].h} vs ${turnedW + 60}x${turnedH}`);
  const south = (await handle("s"))!;
  await drag(south, [south[0] - Math.sin(s[0].r) * 30, south[1] + Math.cos(s[0].r) * 30]);
  s = await shapes();
  check("resize: the bottom edge handle of a turned shape changes only its height", near(s[0].h, turnedH + 30, 1) && near(s[0].w, turnedW + 60, 1), `${s[0].w}x${s[0].h}`);
  await shot("07-rotated-resized");
  await key("Control+z");
  await key("Control+z");
  await key("Control+z");
  await key("o");
  await drag([300, 550], [400, 650]);
  await key("Control+a");
  const multiSe = (await handle("se"))!;
  const nw = (await handle("nw"))!;
  await drag(multiSe, [multiSe[0] + (multiSe[0] - nw[0]) * 0.5, multiSe[1] + (multiSe[1] - nw[1]) * 0.5]);
  s = await shapes();
  check("transform: a multi-selection resizes together", s.length === 2 && near(s[1].w, 150, 1.5), JSON.stringify(s.map((x) => [x.w, x.h])));
  await shot("07-multi");
}

{
  await reset();
  await key("r");
  await drag([300, 300], [480, 420]);
  await page.click('[data-color="red"]');
  await page.click('[data-size="l"]');
  await page.click('[data-fill="semi"]');
  let s = await shapes();
  check("style: applies to the selection", s[0].color === "red" && s[0].size === "l" && s[0].fill === "semi", JSON.stringify(s[0]));
  const fill = await page.getAttribute(`[data-shape="${s[0].id}"] path`, "fill");
  check("style: semi fill is the tint of the color", fill === "var(--tint-red)", fill ?? "");
  await key("Escape");
  await key("o");
  await drag([600, 300], [760, 420]);
  await page.click('[data-color="blue"]');
  await page.click('[data-fill="solid"]');
  await key("Escape");
  await key("d");
  await drag([300, 560], [700, 600], 24);
  await key("a");
  await drag([800, 560], [1000, 480]);
  s = await shapes();
  check("style: the next shape takes the last style", s[1].color === "blue" && s[2].color === "blue" && s[2].size === "l" && s[3].color === "blue", JSON.stringify(s.map((x) => x.color)));
  await page.mouse.click(1100, 700);
  await shot("08-style");
  await page.click('[data-color="green"]');
  await page.click('[data-size="s"]');
  await key("t");
  await page.mouse.click(300, 680);
  await page.keyboard.type("green small text");
  await key("Escape");
  s = await shapes();
  check("style: text takes color and size", s[4].color === "green" && s[4].size === "s", JSON.stringify(s[4]));
  await shot("08-style-text");
}

{
  await reset();
  await key("r");
  await drag([300, 300], [400, 400]);
  await drag([350, 350], [450, 380], 20);
  let s = await shapes();
  check("undo: drag moved", s[0].x === 400, `${s[0].x}`);
  await key("Control+z");
  s = await shapes();
  check("undo: a whole drag is one step", s[0].x === 300, `${s[0].x}`);
  await key("Control+Shift+z");
  s = await shapes();
  check("redo: ctrl+shift+z", s[0].x === 400, `${s[0].x}`);
  await key("Control+z");
  await key("Control+y");
  s = await shapes();
  check("redo: ctrl+y", s[0].x === 400, `${s[0].x}`);
  await key("Control+z");
  await key("Control+z");
  s = await shapes();
  check("undo: back to the empty board", s.length === 0, `${s.length}`);
  check("undo: the undo button is off at the start", await page.isDisabled('[data-action="undo"]'));
  await page.click('[data-action="redo"]');
  await page.click('[data-action="redo"]');
  s = await shapes();
  check("redo: the buttons replay both steps", s.length === 1 && s[0].x === 400, JSON.stringify(s[0]));
  await shot("09-undo");
}

{
  await reset();
  await key("r");
  await drag([200, 200], [300, 300]);
  await key("o");
  await drag([260, 240], [380, 340]);
  await key("Escape");
  let s = await shapes();
  const [a] = s;
  await page.mouse.click(200, 250);
  await key("Control+d");
  s = await shapes();
  check("edit: ctrl+d duplicates", s.length === 3 && s[2].x === a.x + 16, JSON.stringify(s.map((x) => x.x)));
  await key("Delete");
  s = await shapes();
  check("edit: delete", s.length === 2);
  await page.mouse.click(200, 250);
  await key("Control+c");
  await page.mouse.move(800, 500);
  await key("Control+v");
  s = await shapes();
  const pasted = s[2];
  check("edit: ctrl+v pastes at the cursor", s.length === 3 && near(pasted.x + pasted.w / 2, 800, 1) && near(pasted.y + pasted.h / 2, 500, 1), JSON.stringify(pasted));
  await page.mouse.click(200, 250);
  await key("]");
  s = await shapes();
  check("edit: ] brings to front", s[2].id === a.id, JSON.stringify(s.map((x) => x.id)));
  await page.click('[data-action="back"]');
  s = await shapes();
  check("edit: send to back", s[0].id === a.id, JSON.stringify(s.map((x) => x.id)));
  const download = page.waitForEvent("download");
  await page.click('[data-action="export"]');
  const file = await download;
  const path = await file.path();
  const svg = readFileSync(path, "utf8");
  check("edit: export SVG", file.suggestedFilename() === "sketch.svg" && svg.startsWith("<svg xmlns=\"http://www.w3.org/2000/svg\"") && (svg.match(/<g transform=/g) ?? []).length === 3, svg.slice(0, 80));
  await page.setContent(`<body style="margin:0;background:#888">${svg}</body>`);
  await shot("10-export");
  await page.goBack().catch(() => {});
  await page.goto(url);
  await page.waitForSelector('[data-shape]');
  await key("e");
  await page.mouse.move(180, 280);
  await page.mouse.down();
  await page.mouse.move(400, 280, { steps: 10 });
  const marked = await page.evaluate(() => [...document.querySelectorAll('[data-shape]')].filter((g) => g.getAttribute("opacity") === "0.25").length);
  await shot("10-eraser");
  await page.mouse.up();
  s = await shapes();
  check("edit: the eraser marks then removes what it touches", marked === 2 && s.length === 1 && s[0].id === pasted.id, `marked ${marked}, left ${s.map((x) => x.id)}`);
  await key("Control+z");
  s = await shapes();
  check("edit: one undo brings erased shapes back", s.length === 3);
  await shot("10-edit");
}

{
  const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, colorScheme: "dark" });
  const p: Page = await phone.newPage();
  p.on("pageerror", (e) => errors.push(String(e)));
  await p.goto(url);
  await p.evaluate(() => localStorage.clear());
  await p.reload();
  await p.waitForSelector(".hint");
  const cdp = await phone.newCDPSession(p);
  const touch = (type: string, points: [number, number][]) =>
    cdp.send("Input.dispatchTouchEvent", { type, touchPoints: points.map(([x, y], i) => ({ x, y, id: i + 1 })) });
  await p.tap('[data-tool="pen"]');
  await touch("touchStart", [[60, 300]]);
  for (let i = 1; i <= 30; i++) await touch("touchMove", [[60 + i * 9, 300 + Math.sin(i / 4) * 60]]);
  await touch("touchEnd", []);
  await p.tap('[data-tool="rectangle"]');
  await touch("touchStart", [[80, 450]]);
  for (let i = 1; i <= 10; i++) await touch("touchMove", [[80 + i * 20, 450 + i * 12]]);
  await touch("touchEnd", []);
  await p.waitForTimeout(400);
  const stored = await p.evaluate(() => JSON.parse(localStorage.getItem("sketch.board.v1")!).board.shapes.map((x: { kind: string }) => x.kind));
  check("touch: one finger draws with the pen and the rectangle tool", JSON.stringify(stored) === '["draw","rect"]', JSON.stringify(stored));
  await touch("touchStart", [[150, 400], [250, 400]]);
  for (let i = 1; i <= 10; i++) await touch("touchMove", [[150 - i * 5, 400], [250 + i * 5, 400]]);
  await touch("touchEnd", []);
  await p.waitForTimeout(400);
  const zoom = await p.textContent(".zoom");
  check("touch: two fingers pinch to zoom", zoom === "200%", zoom ?? "");
  const kinds = await p.evaluate(() => JSON.parse(localStorage.getItem("sketch.board.v1")!).board.shapes.length);
  check("touch: a pinch draws nothing", kinds === 2, `${kinds}`);
  const visible = (sel: string) => p.evaluate((q) => { const el = document.querySelector(q) as HTMLElement; return !!el && getComputedStyle(el).display !== "none"; }, sel);
  check("phone: the style panel starts closed", !(await visible(".panel")) && (await visible(".style-toggle")));
  const rects = await p.evaluate(() => [".toolbar", ".dock", ".style-toggle"].map((q) => document.querySelector(q)!.getBoundingClientRect().toJSON()));
  const overlap = (a: DOMRect, b: DOMRect) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
  const inside = rects.every((r: DOMRect) => r.left >= 0 && r.right <= 390);
  check("phone: toolbar, zoom bar and style button do not overlap and fit", !overlap(rects[0], rects[1]) && !overlap(rects[0], rects[2]) && !overlap(rects[1], rects[2]) && inside, JSON.stringify(rects.map((r: DOMRect) => [r.left, r.top, r.right, r.bottom])));
  await p.screenshot({ path: join(shots, "11-phone-dark.png") });
  await p.tap('[data-action="style"]');
  check("phone: the style button opens the panel", await visible(".panel"));
  await p.tap('[data-color="red"]');
  await p.screenshot({ path: join(shots, "11-phone-panel.png") });
  await touch("touchStart", [[200, 250]]);
  await touch("touchEnd", []);
  check("phone: a touch on the board closes the panel", !(await visible(".panel")));
  const bg = await p.evaluate(() => getComputedStyle(document.body).backgroundColor);
  check("dark: the page follows the system theme", bg === "rgb(23, 24, 26)", bg);
  await phone.close();
}

check("no console errors", errors.length === 0, errors.slice(0, 3).join(" | "));
await browser.close();
console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
