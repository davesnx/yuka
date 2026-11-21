open Web

let set_title : string -> unit = [%mel.raw "function (t) { document.title = t }"]
let title : unit -> string = [%mel.raw "function () { return document.title }"]
let active : unit -> node = [%mel.raw "function () { return document.activeElement || document.body }"]
let refocus : node -> unit = [%mel.raw "function (n) { n.focus({ preventScroll: true }) }"]

let route_script : unit -> (node * node) option =
  [%mel.raw
    {|function () { const s = document.querySelector('script[data-yuka-context="route"]'); return s && s.parentNode ? [s, s.parentNode] : undefined }|}]

let put_back : node * node -> unit = [%mel.raw "function (r) { r[0].__yuka_seen = false; r[1].appendChild(r[0]) }"]

let layer : unit -> node =
  [%mel.raw
    {|function () {
  const d = document;
  return d.querySelector("yuka-overlay") || d.body.appendChild(d.createElement("yuka-overlay"));
}|}]

type controller

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

let new_controller : unit -> controller =
  [%mel.raw
    "function () { return new AbortController() }"]

let abort : controller -> unit =
  [%mel.raw
    "function (c) { c.abort() }"]

let fetch_page :
    string * string * string * bool * controller * bool ->
    (string -> int -> (string -> string option) -> string -> bool -> unit) ->
    (string -> string -> unit) ->
    (bool -> unit) ->
    (unit -> unit) ->
    unit =
  [%mel.raw
    {|function (a, ok, part, ended, fail) {
  const url = a[0], keys = a[1], prefetch = a[2], low = a[3], controller = a[4];
  const signal = controller.signal;
  const init = { headers: { "Yuka-Navigate": keys }, credentials: "same-origin", signal: signal };
  if (a[5]) init.headers["Yuka-Overlay"] = "1";
  if (prefetch) { init.headers["Yuka-Prefetch"] = prefetch; init.cache = "no-store"; }
  if (low) init.priority = "low";
  let request, shown = false;
  const broke = function () { if (shown) ended(false); else if (!signal.aborted) fail(); };
  try {
    request = fetch(url, init);
  } catch (e) {
    fail();
    return;
  }
  request
    .then(function (r) {
      const base = window.location.href;
      const target = new URL(typeof r.url === "string" && r.url ? r.url : url, base);
      const header = function (name) { const v = r.headers && r.headers.get ? r.headers.get(name) : null; return v === null ? undefined : v; };
      const show = function (text, streamed) {
        if (signal.aborted) return false;
        if (target.origin !== window.location.origin) { fail(); return false; }
        shown = true;
        ok(target.pathname + target.search + (target.hash || new URL(url, base).hash), r.status, header, text, streamed);
        return true;
      };
      if (!header("yuka-stream") || !r.body) return r.text().then(function (text) { show(text, false); });
      const reader = r.body.getReader(), decoder = new TextDecoder();
      let buffer = "", complete = false;
      const step = function (x) {
        buffer += decoder.decode(x.value, { stream: !x.done });
        let i;
        while ((i = buffer.indexOf("\n")) >= 0) {
          const v = JSON.parse(buffer.slice(0, i));
          buffer = buffer.slice(i + 1);
          if (!shown) { if (!show(v, true)) { reader.cancel().catch(function () {}); return; } }
          else if (v.length) part(v[0], v[1]);
          else complete = true;
        }
        if (!x.done) return reader.read().then(step);
        if (shown) ended(complete); else fail();
      };
      return reader.read().then(step);
    })
    .then(null, broke);
}|}]

let put : node -> string -> string -> node =
  [%mel.raw
    {|function (root, id, html) {
  const d = document, t = d.createElement("template"), g = d.createDocumentFragment();
  root = root.body || root;
  t.innerHTML = html;
  if (!id) { root.appendChild(t.content); return g; }
  const w = d.createTreeWalker(root, 128);
  let c, n, k = 1;
  while ((c = w.nextNode()) && c.data !== "[" + id);
  if (!c) return g;
  while ((n = c.nextSibling) && !(n.nodeType === 8 && (n.data[0] === "[" ? !++k : n.data === "]" && !--k))) g.appendChild(n);
  c.parentNode.insertBefore(t.content, n);
  c.data = "[";
  return g;
}|}]

let hold : node -> int -> bool -> unit =
  [%mel.raw
    {|function (root, owner, release) {
  const d = document;
  const pending = function (i) {
    const w = d.createTreeWalker(i, 128);
    let c;
    while ((c = w.nextNode())) if (c.data[0] === "[" && c.data.length > 2) return true;
    return false;
  };
  for (const i of (root.body || root).querySelectorAll("yuka-island"))
    if (i.__yukaHeld === owner) { if (release || !pending(i)) i.__yuka_started = i.__yukaHeld = undefined; }
    else if (!release && !i.__yuka_started && pending(i)) { i.__yukaHeld = owner; i.__yuka_started = true; }
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

let hidden_or_slow : unit -> bool =
  [%mel.raw
    "function () { const c = window.navigator.connection, t = c && c.effectiveType; return document.hidden || t === '2g' || t === 'slow-2g' }"]

let on_visible : (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (f) {
  const d = document, h = function () { if (!d.hidden) f(); };
  d.addEventListener("visibilitychange", h);
  return function () { d.removeEventListener("visibilitychange", h); };
}|}]

let on_input : (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (f) {
  const w = window, names = ["wheel", "touchstart", "keydown", "pointerdown"], o = { capture: true, passive: true };
  const off = function () { names.forEach(function (n) { w.removeEventListener(n, h, o); }); };
  const h = function () { off(); f(); };
  names.forEach(function (n) { w.addEventListener(n, h, o); });
  return off;
}|}]

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

let live : unit -> unit =
  [%mel.raw
    {|function () {
  const d = document;
  let r = d.__yukaLive;
  if (!r) {
    r = d.__yukaLive = d.createElement("div");
    r.id = "yuka-announcer";
    r.setAttribute("aria-live", "assertive");
    r.setAttribute("aria-atomic", "true");
    r.style.cssText = "position:absolute;top:0;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap";
  }
  if (!r.isConnected && d.body) d.body.appendChild(r);
}|}]

let settle : node -> string -> unit =
  [%mel.raw
    {|function (root, hash) {
  const d = document, h = (root = root.body || root).querySelector("h1"), a = d.activeElement;
  if (d.__yukaLive) d.__yukaLive.textContent = d.title || (h ? h.textContent.trim() : "");
  if (a && a !== d.body && (a.matches("input,textarea,select,[contenteditable]") || (a !== root && root.contains(a)))) return;
  const f = function (t) {
    if (!t) return false;
    const add = t !== d.body && t.tabIndex < 0 && !t.hasAttribute("tabindex");
    if (add) t.setAttribute("tabindex", "-1");
    t.focus({ preventScroll: true });
    if (d.activeElement === t) return true;
    if (add) t.removeAttribute("tabindex");
    return false;
  };
  let id = hash.slice(1);
  try { id = decodeURIComponent(id) } catch (e) {}
  if (f(root.querySelector("[autofocus]")) || f(id && d.getElementById(id)) || f(h) || f(root)) return;
  for (const t of root.querySelectorAll("*")) if (f(t)) return;
}|}]
