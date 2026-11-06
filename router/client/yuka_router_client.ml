type node
type controller

let win : unit -> node = [%mel.raw "function () { return window }"]
let doc : unit -> node = [%mel.raw "function () { return document }"]

let assign : string -> unit =
  [%mel.raw "function (url) { window.location.assign(url) }"]

let current_url : unit -> string =
  [%mel.raw
    "function () { const l = window.location; return l.pathname + l.search }"]

let scroll_y : unit -> float =
  [%mel.raw "function () { return window.scrollY || 0 }"]

let scroll_to : float -> unit =
  [%mel.raw "function (y) { window.scrollTo(0, y) }"]

let scroll_to_hash : string -> unit =
  [%mel.raw
    {|function (hash) {
  const el = hash.length > 1 ? document.getElementById(decodeURIComponent(hash.slice(1))) : null;
  if (el) el.scrollIntoView(); else window.scrollTo(0, 0);
}|}]

let fresh_key : unit -> string =
  [%mel.raw
    "function () { globalThis.__yukaKeys = (globalThis.__yukaKeys || 0) + 1; return Date.now() + '-' + globalThis.__yukaKeys }"]

let state_key : unit -> string =
  [%mel.raw
    "function () { const s = window.history.state; return s && typeof s.yukaKey === 'string' ? s.yukaKey : '' }"]

let replace_key : string -> unit =
  [%mel.raw
    "function (k) { window.history.replaceState({ yukaKey: k }, '', window.location.href) }"]

let push_key : string -> string -> unit =
  [%mel.raw
    "function (k, url) { window.history.pushState({ yukaKey: k }, '', url) }"]

let manual_scroll : unit -> unit =
  [%mel.raw
    "function () { try { window.history.scrollRestoration = 'manual' } catch (e) {} }"]

let new_controller : unit -> controller =
  [%mel.raw "function () { return new AbortController() }"]

let abort : controller -> unit = [%mel.raw "function (c) { c.abort() }"]

let listen : node -> string -> (node -> unit) -> unit =
  [%mel.raw "function (target, name, f) { target.addEventListener(name, f) }"]

let prevent_default : node -> unit =
  [%mel.raw "function (e) { e.preventDefault() }"]

let click_href : node -> string =
  [%mel.raw
    {|function (e) {
  if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return "";
  const t = e.target;
  const a = t && t.closest ? t.closest("a[href]") : null;
  if (!a) return "";
  const target = a.getAttribute("target");
  if ((target && target !== "_self") || a.hasAttribute("download") || a.hasAttribute("data-yuka-reload")) return "";
  const l = window.location;
  if (a.origin !== l.origin) return "";
  if (a.hash && a.pathname === l.pathname && a.search === l.search) return "";
  return a.href;
}|}]

let fetch_page : string -> controller -> (string -> string -> unit) -> (unit -> unit) -> unit =
  [%mel.raw
    {|function (url, controller, ok, fail) {
  const signal = controller.signal;
  let request;
  try {
    request = fetch(url, { headers: { "Yuka-Navigate": "1" }, credentials: "same-origin", signal: signal });
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
        ok(target.pathname + target.search + hash, x.text);
      },
      function () { if (!signal.aborted) fail(); });
}|}]

let swap : string -> unit =
  [%mel.raw
    {|function (text) {
  const parsed = new document.defaultView.DOMParser().parseFromString(text, "text/html");
  document.title = parsed.title;
  document.body.innerHTML = parsed.body.innerHTML;
}|}]

let started = ref false
let pending : controller option ref = ref None
let scrolls : (string, float) Hashtbl.t = Hashtbl.create 16
let current_key = ref ""
let loaded = ref ""

let start_islands : (unit -> unit) ref = ref (fun () -> ())

let cancel_pending () =
  match !pending with
  | Some c ->
      pending := None;
      abort c
  | None -> ()

let save_scroll () = Hashtbl.replace scrolls !current_key (scroll_y ())

let hash_of url =
  match String.index_opt url '#' with
  | Some i -> String.sub url i (String.length url - i)
  | None -> ""

let load ~push ~restore url =
  if not !started then assign url
  else begin
      cancel_pending ();
      let controller = new_controller () in
      pending := Some controller;
      fetch_page url controller
        (fun final text ->
          pending := None;
          Yuka_client.stop ();
          swap text;
          if push then begin
            let key = fresh_key () in
            push_key key final;
            current_key := key
          end;
          loaded := current_url ();
          (match restore with
          | Some y -> scroll_to y
          | None -> scroll_to_hash (hash_of final));
          !start_islands ())
        (fun () ->
          pending := None;
          assign url)
  end

let navigate url =
  save_scroll ();
  load ~push:true ~restore:None url

let on_click e =
  match click_href e with
  | "" -> ()
  | href ->
      prevent_default e;
      navigate href

let on_popstate _ =
  save_scroll ();
  current_key := state_key ();
  let restore =
    Some (Option.value (Hashtbl.find_opt scrolls !current_key) ~default:0.)
  in
  if current_url () = !loaded then begin
    cancel_pending ();
    match restore with Some y -> scroll_to y | None -> ()
  end
  else load ~push:false ~restore (current_url ())

let start ?lazy_entries entries =
  cancel_pending ();
  started := true;
  manual_scroll ();
  current_key := state_key ();
  if !current_key = "" then begin
    current_key := fresh_key ();
    replace_key !current_key
  end;
  loaded := current_url ();
  listen (doc ()) "click" on_click;
  listen (win ()) "popstate" on_popstate;
  (start_islands :=
     fun () ->
       Yuka_client.start ?lazy_entries entries;
       Yuka.Internal.platform :=
         { !Yuka.Internal.platform with navigate });
  !start_islands ()
