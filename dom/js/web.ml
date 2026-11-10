type node
type event
type 'a promise = 'a Js.Promise.t

let in_browser = true

let window () : node = [%mel.raw "window"]
external owner_document : node -> node = "ownerDocument" [@@mel.get]
external create_element : node -> string -> node = "createElement" [@@mel.send]
external create_element_ns : node -> string -> string -> node = "createElementNS" [@@mel.send]
external create_text : node -> string -> node = "createTextNode" [@@mel.send]
external create_comment : node -> string -> node = "createComment" [@@mel.send]
external node_type : node -> int = "nodeType" [@@mel.get]
external local_name : node -> string = "localName" [@@mel.get]
external data : node -> string = "data" [@@mel.get]
external set_data : node -> string -> unit = "data" [@@mel.set]
external first_child : node -> node option = "firstChild"
[@@mel.get] [@@mel.return nullable]
external next_sibling : node -> node option = "nextSibling"
[@@mel.get] [@@mel.return nullable]
external parent_node : node -> node option = "parentNode"
[@@mel.get] [@@mel.return nullable]
external append_child : node -> node -> unit = "appendChild" [@@mel.send]
external insert_before : node -> node -> node -> unit = "insertBefore" [@@mel.send]
external remove : node -> unit = "remove" [@@mel.send]
external clear : node -> string -> unit = "textContent" [@@mel.set]
external set_attribute : node -> string -> string -> unit = "setAttribute" [@@mel.send]
external remove_attribute : node -> string -> unit = "removeAttribute" [@@mel.send]
external set_string : node -> string -> string -> unit = "" [@@mel.set_index]
external set_bool : node -> string -> bool -> unit = "" [@@mel.set_index]
external set_prop : node -> string -> 'a -> unit = "" [@@mel.set_index]
external get_prop : node -> string -> 'a option = "" [@@mel.get_index] [@@mel.return nullable]
external add_listener : node -> string -> (event -> unit) -> unit = "addEventListener" [@@mel.send]
external remove_listener : node -> string -> (event -> unit) -> unit = "removeEventListener" [@@mel.send]
external target : event -> node = "target" [@@mel.get]
external value : node -> string = "value" [@@mel.get]
external checked : node -> bool = "checked" [@@mel.get]
external key : event -> string = "key" [@@mel.get]
external meta_key : event -> bool = "metaKey" [@@mel.get]
external ctrl_key : event -> bool = "ctrlKey" [@@mel.get]
external prevent_default : event -> unit = "preventDefault" [@@mel.send]

let document () : node = [%mel.raw "document"]

external query_all : node -> string -> node array = "querySelectorAll" [@@mel.send]
external get_attribute : node -> string -> string option = "getAttribute"
[@@mel.send] [@@mel.return nullable]
external text_content : node -> string = "textContent" [@@mel.get]
external console_error : string -> unit = "error" [@@mel.scope "console"]

let exn_to_string : exn -> string =
  [%mel.raw
    {|function (e) {
      var args = [];
      for (var i = 1; ("_" + i) in e; i++) args.push(String(e["_" + i]));
      return args.length ? e.MEL_EXN_ID + "(" + args.join(", ") + ")" : e.MEL_EXN_ID;
    }|}]

external encode_uri : string -> string = "encodeURIComponent"
external decode_uri : string -> string = "decodeURIComponent"

let contains : node -> node -> bool = [%mel.raw "function (a, b) { return a.contains(b) }"]

let set_title : string -> unit = [%mel.raw "function (t) { document.title = t }"]

let fetch_post :
    string ->
    string ->
    (int -> string -> unit) ->
    (bool -> string -> unit) ->
    unit ->
    unit =
  [%mel.raw
    {|function (url, body, ok, fail) {
  const control = new AbortController();
  let status = 0;
  const message = function (e) { return String((e && e.message) || e); };
  let request;
  try {
    request = fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: body, signal: control.signal });
  } catch (e) {
    fail(false, message(e));
    return function () {};
  }
  request
    .then(function (r) { status = r.status; return r.text(); })
    .then(function (t) { ok(status, t); }, function (e) { fail(control.signal.aborted, message(e)); });
  return function () { control.abort(); };
}|}]

let watch_added : (node array -> bool) -> unit -> unit =
  [%mel.raw
    {|function (check) {
  const view = document.defaultView;
  const observer = new view.MutationObserver(function (records) {
    const added = [];
    for (const r of records) {
      for (const n of r.addedNodes) if (n.nodeType === 1) added.push(n);
      const t = r.target;
      if (r.type === "characterData") {
        const p = t.parentElement;
        if (p && p.localName === "script") added.push(p);
      } else if (t.localName === "script" && r.addedNodes.length) added.push(t);
    }
    if (added.length && check(added)) observer.disconnect();
  });
  observer.observe(document, { childList: true, subtree: true, characterData: true });
  return function () { observer.disconnect(); };
}|}]

external shift_key : event -> bool = "shiftKey" [@@mel.get]
external alt_key : event -> bool = "altKey" [@@mel.get]
external stop_propagation : event -> unit = "stopPropagation" [@@mel.send]
external set_flag : event -> string -> bool -> unit = "" [@@mel.set_index]
external get_flag : event -> string -> bool option = "" [@@mel.get_index] [@@mel.return nullable]

let navigate : string -> unit =
  [%mel.raw "function (url) { window.location.assign(url) }"]

let focus : string -> unit =
  [%mel.raw
    "function (id) { const el = document.getElementById(id); if (el) el.focus() }"]

let scroll_into_view : string -> unit =
  [%mel.raw
    "function (id) { const el = document.getElementById(id); if (el) el.scrollIntoView() }"]

external first_element_child : node -> node option = "firstElementChild"
[@@mel.get] [@@mel.return nullable]

let has_intersection_observer : node -> bool =
  [%mel.raw "function (el) { return typeof el.ownerDocument.defaultView.IntersectionObserver === 'function' }"]

let set_timeout : int -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (ms, f) {
  const id = setTimeout(function () { f() }, ms);
  return function () { clearTimeout(id); };
}|}]

let on_idle : (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (f) {
  const w = document.defaultView;
  if (typeof w.requestIdleCallback === "function") {
    const id = w.requestIdleCallback(function () { f() });
    return function () { if (typeof w.cancelIdleCallback === "function") w.cancelIdleCallback(id); };
  }
  const id = w.setTimeout(function () { f() }, 200);
  return function () { w.clearTimeout(id); };
}|}]

let on_visible : node -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (el, f) {
  const O = el.ownerDocument.defaultView.IntersectionObserver;
  const observer = new O(function (entries) {
    for (const e of entries) if (e.isIntersecting) { observer.disconnect(); f(); return; }
  });
  observer.observe(el);
  return function () { observer.disconnect(); };
}|}]

let promise_map : ('a -> 'b) -> 'a promise -> 'b promise =
  [%mel.raw "function (f, p) { return p.then(function (v) { return f(v) }) }"]

let promise_then : ('a -> unit) -> (string -> unit) -> 'a promise -> unit =
  [%mel.raw
    {|function (ok, fail, p) {
  p.then(function (v) { ok(v) }).catch(function (e) { fail(String((e && e.message) || e)) });
}|}]

let ready_state : unit -> string = [%mel.raw "function () { return document.readyState }"]

let on_dom_ready : (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (f) {
  const handler = function () { f() };
  document.addEventListener("DOMContentLoaded", handler);
  return function () { document.removeEventListener("DOMContentLoaded", handler); };
}|}]

external set_inner_html : node -> string -> unit = "innerHTML" [@@mel.set]
external content : node -> node = "content" [@@mel.get]
external import_node : node -> node -> bool -> node = "importNode" [@@mel.send]

let child_at : node -> int -> node =
  [%mel.raw "function (n, i) { return n.childNodes[i] }"]

external previous_sibling : node -> node option = "previousSibling"
[@@mel.get] [@@mel.return nullable]
external last_child : node -> node option = "lastChild"
[@@mel.get] [@@mel.return nullable]
external clone_node : node -> bool -> node = "cloneNode" [@@mel.send]

let walk : node -> int array -> node array =
  [%mel.raw
    {|function (root, w) {
  const out = [root];
  for (let i = 0; i < w.length; i += 2) {
    let n = out[w[i] >> 1];
    if ((w[i] & 1) === 0) n = n.firstChild;
    for (let k = w[i + 1]; k > 0; k--) n = n.nextSibling;
    out.push(n);
  }
  return out;
}|}]

let delete_between : node -> node -> node -> unit =
  [%mel.raw
    {|function (parent, start, stop) {
  const r = parent.ownerDocument.createRange();
  r.setStartAfter(start);
  r.setEndBefore(stop);
  r.deleteContents();
}|}]

let record_events : node -> (unit -> unit) * (unit -> unit) =
  [%mel.raw
    {|function (island) {
  const types = ["click", "input", "change", "submit", "keydown"];
  let queue = [];
  const listener = function (ev) {
    const owner = ev.target.closest ? ev.target.closest("yuka-island") : island;
    if (owner !== island) return;
    const t = ev.target;
    const field = (ev.type === "input" || ev.type === "change") && t && "value" in t;
    queue.push({ type: ev.type, target: t, ev: ev, field: field, value: field ? t.value : undefined, checked: field ? t.checked : undefined });
  };
  types.forEach(function (t) { island.addEventListener(t, listener, true); });
  const stop = function () { types.forEach(function (t) { island.removeEventListener(t, listener, true); }); };
  const drop = function () { stop(); queue = []; };
  const replay = function () {
    stop();
    const items = queue;
    queue = [];
    const w = island.ownerDocument.defaultView;
    items.forEach(function (item) {
      const type = item.type, target = item.target, ev = item.ev;
      if (!island.contains(target)) return;
      if (item.field) {
        target.value = item.value;
        if (item.checked !== undefined) target.checked = item.checked;
      }
      let copy;
      if (type === "click")
        copy = new w.MouseEvent(type, { bubbles: true, cancelable: true, clientX: ev.clientX, clientY: ev.clientY, button: ev.button, shiftKey: ev.shiftKey, ctrlKey: ev.ctrlKey, altKey: ev.altKey, metaKey: ev.metaKey });
      else if (type === "keydown")
        copy = new w.KeyboardEvent(type, { bubbles: true, cancelable: true, key: ev.key, code: ev.code, repeat: ev.repeat, shiftKey: ev.shiftKey, ctrlKey: ev.ctrlKey, altKey: ev.altKey, metaKey: ev.metaKey });
      else if (type === "input" && w.InputEvent)
        copy = new w.InputEvent(type, { bubbles: true, cancelable: true, data: ev.data, inputType: ev.inputType });
      else copy = new w.Event(type, { bubbles: true, cancelable: true });
      const toggles = type === "click" && (target.type === "checkbox" || target.type === "radio");
      const before = toggles ? target.checked : undefined;
      target.dispatchEvent(copy);
      if (toggles) target.checked = before;
    });
  };
  return [drop, replay];
}|}]

type controller

let location_assign : string -> unit =
  [%mel.raw
    "function (url) { window.location.assign(url) }"]

let current_url : unit -> string =
  [%mel.raw
    "function () { const l = window.location; return l.pathname + l.search }"]

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

let fresh_key : unit -> string =
  [%mel.raw
    "function () { globalThis.__yukaKeys = (globalThis.__yukaKeys || 0) + 1; return Date.now() + '-' + globalThis.__yukaKeys }"]

let history_key : unit -> string =
  [%mel.raw
    "function () { const s = window.history.state; return s && typeof s.yukaKey === 'string' ? s.yukaKey : '' }"]

let history_replace_key : string -> unit =
  [%mel.raw
    "function (k) { window.history.replaceState({ yukaKey: k }, '', window.location.href) }"]

let history_push_key : string -> string -> unit =
  [%mel.raw
    "function (k, url) { window.history.pushState({ yukaKey: k }, '', url) }"]

let manual_scroll : unit -> unit =
  [%mel.raw
    "function () { try { window.history.scrollRestoration = 'manual' } catch (e) {} }"]

let new_controller : unit -> controller =
  [%mel.raw
    "function () { return new AbortController() }"]

let abort : controller -> unit =
  [%mel.raw
    "function (c) { c.abort() }"]

let plain_click : event -> bool =
  [%mel.raw
    "function (e) { return !(e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) }"]

let link_href : bool -> node -> string =
  [%mel.raw
    {|function (prefetch, t) {
  const a = t && t.closest ? t.closest("a[href]") : null;
  if (!a) return "";
  const target = a.getAttribute("target");
  if ((target && target !== "_self") || a.hasAttribute("download") || a.hasAttribute("data-yuka-reload")) return "";
  if (prefetch && a.getAttribute("data-yuka-prefetch") === "off") return "";
  const l = window.location;
  if (a.origin !== l.origin) return "";
  if (a.hash && a.pathname === l.pathname && a.search === l.search) return "";
  return a.href;
}|}]

let fetch_page :
    string -> string -> bool -> controller -> (string -> int -> (string -> string option) -> string -> unit) -> (unit -> unit) -> unit =
  [%mel.raw
    {|function (url, keys, prefetch, controller, ok, fail) {
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

type 'a table

external table : unit -> 'a table = "Map" [@@mel.new]
external table_get : 'a table -> string -> 'a option = "get"
[@@mel.send] [@@mel.return undefined_to_opt]
external table_set : 'a table -> string -> 'a -> unit = "set" [@@mel.send]
external table_has : 'a table -> string -> bool = "has" [@@mel.send]
external table_delete : 'a table -> string -> unit = "delete" [@@mel.send]
external table_size : 'a table -> int = "size" [@@mel.get]
external table_clear : 'a table -> unit = "clear" [@@mel.send]

let table_values : 'a table -> 'a array =
  [%mel.raw "function (t) { return Array.from(t.values()) }"]

let shortest_float : float -> string =
  [%mel.raw
    {|function (f) {
  if (f === 0) return "0";
  for (let p = 15; ; p++) {
    let e = f.toExponential(p - 1);
    if (p < 17 && Number(e) !== f) continue;
    if (p === 17) {
      const x = f.toExponential(99), i = x.indexOf("e"), sign = f < 0 ? "-" : "";
      const all = x.slice(sign.length, i).replace(".", "");
      if (/^50*$/.test(all.slice(17)) && all.charCodeAt(16) % 2 === 0)
        e = sign + all[0] + "." + all.slice(1, 17) + x.slice(i);
    }
    const at = e.indexOf("e"), x = Number(e.slice(at + 1)), neg = f < 0;
    const d = e.slice(neg ? 1 : 0, at).replace(".", "");
    let s;
    if (x < -4 || x >= p) {
      const m = d.replace(/0+$/, ""), a = Math.abs(x);
      s = m[0] + (m.length > 1 ? "." + m.slice(1) : "") + "e" + (x < 0 ? "-" : "+") + (a < 10 ? "0" : "") + a;
    } else if (x >= 0) {
      const frac = d.slice(x + 1).replace(/0+$/, "");
      s = d.slice(0, x + 1) + (frac ? "." + frac : "");
    } else s = "0." + ("0".repeat(-x - 1) + d).replace(/0+$/, "");
    return neg ? "-" + s : s;
  }
}|}]

external parse_float : string -> float = "Number"

let parse_int : string -> int option =
  [%mel.raw "function (t) { const n = Number(t); return (n | 0) === n ? n | 0 : undefined }"]
