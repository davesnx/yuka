type node
type event = Yuka.Event.t

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

let insert parent n = function
  | None -> append_child parent n
  | Some before -> insert_before parent n before

let document () : node = [%mel.raw "document"]

external query_all : node -> string -> node array = "querySelectorAll" [@@mel.send]
external get_attribute : node -> string -> string option = "getAttribute"
[@@mel.send] [@@mel.return nullable]
external text_content : node -> string = "textContent" [@@mel.get]
external console_error : string -> unit = "error" [@@mel.scope "console"]
external encode_uri : string -> string = "encodeURIComponent"

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

let watch_document : (unit -> bool) -> unit -> unit =
  [%mel.raw
    {|function (check) {
  const view = document.defaultView;
  const observer = new view.MutationObserver(function () { if (check()) observer.disconnect(); });
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

let error_message : Js.Promise.error -> string =
  [%mel.raw "function (e) { return String((e && e.message) || e) }"]

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

let record_events : node -> (unit -> unit) * (unit -> unit) =
  [%mel.raw
    {|function (island) {
  const types = ["click", "input", "change", "submit", "keydown"];
  let queue = [];
  const listener = function (ev) {
    const owner = ev.target.closest ? ev.target.closest("yuka-island") : island;
    if (owner === island) queue.push({ type: ev.type, target: ev.target, ev: ev });
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
