open Web

let set_title : string -> unit = [%mel.raw "function (t) { document.title = t }"]

type controller

let scroll_y : unit -> float =
  [%mel.raw
    "function () { return window.scrollY || 0 }"]

let scroll_to : float -> unit =
  [%mel.raw
    "function (y) { window.scrollTo(0, y) }"]

let scroll_to_hash : string -> unit =
  [%mel.raw
    {|function (hash) {
  let id = hash.slice(1);
  try { id = decodeURIComponent(id) } catch (e) {}
  const el = id ? document.getElementById(id) : null;
  if (el) el.scrollIntoView(); else window.scrollTo(0, 0);
}|}]

let history_push_key : string -> string -> unit =
  [%mel.raw
    "function (k, url) { window.history.pushState({ yukaKey: k }, '', url) }"]

let new_controller : unit -> controller =
  [%mel.raw
    "function () { return new AbortController() }"]

let abort : controller -> unit =
  [%mel.raw
    "function (c) { c.abort() }"]

let fetch_page :
    string * string * string * bool * controller -> (string -> int -> (string -> string option) -> string -> unit) -> (unit -> unit) -> unit =
  [%mel.raw
    {|function (a, ok, fail) {
  const url = a[0], keys = a[1], prefetch = a[2], low = a[3], controller = a[4];
  const signal = controller.signal;
  const init = { headers: { "Yuka-Navigate": keys }, credentials: "same-origin", signal: signal };
  if (prefetch) { init.headers["Yuka-Prefetch"] = prefetch; init.cache = "no-store"; }
  if (low) init.priority = "low";
  let request;
  try {
    request = fetch(url, init);
  } catch (e) {
    fail();
    return;
  }
  request
    .then(function (r) {
      return r.text().then(function (text) { return { r: r, text: text }; });
    })
    .then(
      function (x) {
        if (signal.aborted) return;
        const base = window.location.href;
        const target = new URL(typeof x.r.url === "string" && x.r.url ? x.r.url : url, base);
        if (target.origin !== window.location.origin) { fail(); return; }
        const hash = target.hash || new URL(url, base).hash;
        ok(target.pathname + target.search + hash, x.r.status, function (name) { const v = x.r.headers && x.r.headers.get ? x.r.headers.get(name) : null; return v === null ? undefined : v; }, x.text);
      },
      function () { if (!signal.aborted) fail(); });
}|}]

let hash_of : string -> string =
  [%mel.raw "function (u) { const i = u.indexOf('#'); return i < 0 ? '' : u.slice(i) }"]

let no_hash : string -> string = [%mel.raw "function (u) { return u.split('#')[0] }"]
let path_of : string -> string = [%mel.raw "function (u) { return u.split('#')[0].split('?')[0] }"]

let keys : unit -> string =
  [%mel.raw
    {|function () {
  const k = Array.from(document.querySelectorAll("yuka-outlet"), function (o) { return o.getAttribute("data-k") }).filter(function (k) { return k !== null });
  return k.length ? k.join(" ") : "-";
}|}]

let is_html : string -> bool = [%mel.raw "function (t) { return t.toLowerCase().startsWith('text/html') }"]
let event_type : event -> string = [%mel.raw "function (e) { return e.type }"]

let absolute : string -> string =
  [%mel.raw "function (u) { const x = new URL(u, window.location.href); x.hash = ''; return x.href }"]

let max_age : string -> int =
  [%mel.raw
    {|function (v) { const m = /(?:^|,)\s*max-age=(\d+)/.exec(v); return /(?:^|,)\s*no-(?:store|cache)\s*(?:,|$)/.test(v) || !m ? 0 : +m[1] }|}]

let key_before : string -> string -> bool =
  [%mel.raw
    {|function (a, b) { const x = a.split("-"), y = b.split("-"); return +x[0] < +y[0] || (+x[0] === +y[0] && +x[1] < +y[1]) }|}]

let now : unit -> float = [%mel.raw "function () { return Date.now() }"]

let after : int -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    "function (ms, f) { const id = setTimeout(function () { f() }, ms); return function () { clearTimeout(id) } }"]

let save_data : unit -> bool =
  [%mel.raw
    "function () { const c = window.navigator.connection; return !!(c && c.saveData) }"]

let observe : node array -> (node -> bool -> (unit -> unit) -> unit) -> unit -> unit =
  [%mel.raw
    {|function (els, f) {
  const O = window.IntersectionObserver;
  if (typeof O !== "function") return function () {};
  const observer = new O(function (entries) {
    for (const e of entries) f(e.target, e.isIntersecting, function () { observer.unobserve(e.target); });
  }, { rootMargin: "200px" });
  for (const el of els) observer.observe(el);
  return function () { observer.disconnect(); };
}|}]

let trajectory : (node -> string) -> (string -> unit) -> unit -> unit =
  [%mel.raw
    {|function (href, go) {
  const d = document, w = window, O = w.IntersectionObserver;
  if (typeof O !== "function") return function () {};
  let last = -Infinity, k = 0, px, py, vx = 0, vy = 0, was = "", links = [], at = -Infinity, o = null;
  const reset = function () { links = []; at = -Infinity; };
  const shown = { opacityProperty: true, visibilityProperty: true };
  const refresh = function () {
    if (o) o.disconnect();
    o = null;
    const els = d.querySelectorAll("a[href]"), found = [];
    let left = els.length;
    at = Date.now();
    if (!left) { links = found; return; }
    const mine = (o = new O(function (entries) {
      for (const e of entries) {
        const t = e.target, h = e.isIntersecting && !(t.checkVisibility && !t.checkVisibility(shown)) ? href(t) : "";
        if (h) found.push({ el: t, h: h, r: e.boundingClientRect });
      }
      if ((left -= entries.length) > 0) return;
      mine.disconnect();
      o = null;
      links = found;
    }));
    els.forEach(function (a) { mine.observe(a); });
  };
  const move = function (e) {
    const t = e.timeStamp, gap = t - last;
    if (e.pointerType !== "mouse" || gap < 50) return;
    last = t;
    const x = e.clientX, y = e.clientY, now = Date.now();
    if ((!o || now - at > 1000) && (now - at > 300 || links.some(function (l) { return !l.el.isConnected; }))) refresh();
    if (gap > 200) { px = x; py = y; vx = vy = 0; k = 0; was = ""; return; }
    const a = ++k > 2 ? 0.6 : 0.3;
    vx = a * vx + ((1 - a) * (x - px)) / gap;
    vy = a * vy + ((1 - a) * (y - py)) / gap;
    px = x;
    py = y;
    const s = Math.hypot(vx, vy);
    let best = "", low = 500;
    if (s >= 0.12)
      for (const l of links) {
        const r = l.r, cx = r.left + r.width / 2 - x, cy = r.top + r.height / 2 - y;
        const along = (cx * vx + cy * vy) / s, perp = Math.abs(cx * vy - cy * vx) / s, dist = Math.hypot(cx, cy);
        if (along < 0 || perp > (Math.max(r.width, r.height) / 2 + 30) * Math.max(0.2, 1 - dist / 1000) + 20) continue;
        if (along + perp * 5 < low) { low = along + perp * 5; best = l.h; }
      }
    if (best && best === was) go(best);
    was = best;
  };
  d.addEventListener("pointermove", move, { passive: true });
  w.addEventListener("scroll", reset, { capture: true, passive: true });
  return function () {
    if (o) o.disconnect();
    o = null;
    d.removeEventListener("pointermove", move);
    w.removeEventListener("scroll", reset, { capture: true });
  };
}|}]

let warm : string -> string -> unit =
  [%mel.raw
    {|function (final, text) {
  const d = document, seen = d.__yukaWarm || (d.__yukaWarm = new Set()), base = new URL(window.location.origin + final);
  d.querySelectorAll("link[href]").forEach(function (l) { seen.add(l.href); });
  for (const m of text.matchAll(/<link rel="(?:modulepreload" href="([^"]*)">|stylesheet" href="([^"]*)" data-yuka-css>)/g)) {
    let href;
    try { href = new URL((m[1] === undefined ? m[2] : m[1]).replace(/&lt;/g, "<").replace(/&quot;/g, '"').replace(/&amp;/g, "&"), base).href; } catch (e) { continue; }
    if (seen.has(href)) continue;
    seen.add(href);
    const l = d.createElement("link");
    l.rel = m[1] === undefined ? "prefetch" : "modulepreload";
    l.href = href;
    d.head.appendChild(l);
  }
}|}]

let transition : string -> (unit -> unit) -> unit =
  [%mel.raw
    {|function (dir, f) {
  const d = document;
  if (typeof d.startViewTransition !== "function") { f(); return; }
  const h = d.documentElement;
  const id = (globalThis.__yukaTransition = (globalThis.__yukaTransition || 0) + 1);
  h.setAttribute("data-yuka-nav", dir);
  const done = function () { if (globalThis.__yukaTransition === id) h.removeAttribute("data-yuka-nav"); };
  const t = d.startViewTransition(function () {
    try { f(); } catch (e) { d.defaultView.setTimeout(function () { throw e; }); }
  });
  t.ready.then(null, function () {});
  t.finished.then(done, done);
}|}]

let swap_page : string -> unit =
  [%mel.raw
    {|function (text) {
  const parsed = new document.defaultView.DOMParser().parseFromString(text, "text/html");
  document.title = parsed.title;
  document.body.innerHTML = parsed.body.innerHTML;
}|}]

let adopt_stylesheets : unit -> unit =
  [%mel.raw
    {|function () {
  if (!document.body) return;
  var head = document.head, seen = new Set();
  head.querySelectorAll("link[data-yuka-css]").forEach(function (l) { seen.add(l.getAttribute("href")); });
  document.body.querySelectorAll("link[data-yuka-css]").forEach(function (l) {
    var href = l.getAttribute("href");
    if (seen.has(href)) l.remove();
    else { seen.add(href); head.appendChild(l); }
  });
  document.__yukaSheets = seen;
}|}]
