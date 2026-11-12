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
  const el = hash.length > 1 ? document.getElementById(decodeURIComponent(hash.slice(1))) : null;
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
    string * string * bool * controller -> (string -> int -> (string -> string option) -> string -> unit) -> (unit -> unit) -> unit =
  [%mel.raw
    {|function (a, ok, fail) {
  const url = a[0], keys = a[1], prefetch = a[2], controller = a[3];
  const signal = controller.signal;
  const init = { headers: { "Yuka-Navigate": keys }, credentials: "same-origin", signal: signal };
  if (prefetch) { init.headers["Yuka-Prefetch"] = "1"; init.cache = "no-store"; }
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

let observe : node array -> (node -> unit) -> unit -> unit =
  [%mel.raw
    {|function (els, f) {
  const O = window.IntersectionObserver;
  if (typeof O !== "function") return function () {};
  const observer = new O(function (entries) {
    for (const e of entries) if (e.isIntersecting) { observer.unobserve(e.target); f(e.target); }
  });
  for (const el of els) observer.observe(el);
  return function () { observer.disconnect(); };
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
