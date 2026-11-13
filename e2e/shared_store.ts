import type { Page } from "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.js";

const playwrightPath =
  process.env.PLAYWRIGHT_CORE ??
  "/home/me/workplace/davesnx/sancho.dev/node_modules/playwright-core/index.mjs";
const { chromium } = await import(playwrightPath);

const [first, second] = process.argv.slice(2).map((url) => url.replace(/\/$/, ""));
if (!first || !second) {
  console.log("usage: node e2e/shared_store.ts FIRST_URL SECOND_URL");
  process.exit(2);
}

let failures = 0;
const check = (name: string, ok: boolean, evidence = "") => {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${evidence ? "  [" + evidence + "]" : ""}`);
};

const action = async (base: string, name: string, input: unknown) => {
  const response = await fetch(`${base}/_yuka/action/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: base },
    body: JSON.stringify(input),
  });
  return { status: response.status, text: await response.text() };
};

const text = `Shared note ${Date.now().toString(36)}`;
const browser = await chromium.launch({ headless: true });
const open = async (base: string) => {
  const p: Page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await p.addInitScript(() => {
    const W = window.WebSocket;
    (window as any).__sockets = [];
    (window as any).WebSocket = class extends W {
      constructor(url: string | URL, protocols?: string | string[]) {
        super(url, protocols);
        (window as any).__sockets.push(this);
      }
    };
  });
  await p.goto(base + "/canvas", { waitUntil: "networkidle" });
  await p.waitForFunction(() => {
    const s = (window as any).__sockets as WebSocket[];
    return s.length > 0 && s[s.length - 1].readyState === 1;
  }, null, { timeout: 5000 });
  return p;
};
const shows = (p: Page, id: string, style?: string) =>
  p
    .waitForFunction(
      ([i, s]) => {
        const item = document.querySelector(`[data-canvas] [data-id="${i}"]`);
        return !!item && (s === "" || (item.getAttribute("style") ?? "").includes(s as string));
      },
      [id, style ?? ""] as const,
      { timeout: 3000 },
    )
    .then(() => true, () => false);

let noteId = "";
try {
  const A = await open(first);
  const B = await open(second);

  const added = await action(first, "add_note", { workspace: "Yuka", text });
  const board = added.status === 200 ? (JSON.parse(added.text).ok as { id: string; content: [string, unknown] }[]) : [];
  noteId = board.find((item) => item.content[0] === "Note" && item.content[1] === text)?.id ?? "";
  check("s.1 a note is added through the first server", added.status === 200 && noteId !== "", `${added.status} ${noteId || added.text.slice(0, 200)}`);

  check("s.2 a page on the second server gets the new note over Live", await shows(B, noteId), noteId);

  const pages = await Promise.all(
    Array.from({ length: 20 }, (_, index) => fetch(`${index % 2 ? second : first}/canvas`).then((r) => r.text())),
  );
  const missing = pages.filter((html) => !html.includes(text)).length;
  check("s.3 every /canvas answer of both servers has the note", missing === 0, `${missing} of ${pages.length} without it`);

  const moved = await action(second, "move_item", { workspace: "Yuka", id: noteId, x: 40, y: 60 });
  check("s.4 the note is moved through the second server with no error", moved.status === 200, `${moved.status} ${moved.text.slice(0, 200)}`);

  check("s.5 the page on the second server shows the move", await shows(B, noteId, "translate(40px,60px)"));
  check("s.6 the page on the first server gets the move over Live", await shows(A, noteId, "translate(40px,60px)"));
} catch (e) {
  check("s. no exception", false, String((e as Error).message).split("\n")[0]);
} finally {
  if (noteId !== "") {
    const removed = await action(first, "remove_note", { workspace: "Yuka", note_id: noteId });
    check("s.7 the note is removed through the first server", removed.status === 200, `${removed.status} ${removed.text.slice(0, 200)}`);
  }
  await browser.close();
}

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
