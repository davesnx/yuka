type handlers = {
  down : Editor.pointer -> unit;
  move : Editor.pointer list -> unit;
  up : Editor.pointer -> unit;
  cancel : int -> unit;
  wheel : at:Vec.t -> dx:float -> dy:float -> ctrl:bool -> unit;
  double_click : Vec.t -> unit;
  resize : width:float -> height:float -> unit;
  blur : unit -> unit;
}

type element
type event
type remover

let find : string -> element Js.Nullable.t = [%mel.raw {|function (id) { return document.getElementById(id) }|}]

let listen : element -> string -> (event -> unit) -> remover =
  [%mel.raw
    {|function (element, name, handler) {
  var f = function (e) { handler(e) };
  element.addEventListener(name, f, { passive: false });
  return function () { element.removeEventListener(name, f) };
}|}]

let listen_window : string -> (event -> unit) -> remover =
  [%mel.raw
    {|function (name, handler) {
  var f = function (e) { handler(e) };
  window.addEventListener(name, f);
  return function () { window.removeEventListener(name, f) };
}|}]

let unlisten : remover -> unit = [%mel.raw {|function (remove) { remove() }|}]

let capture : element -> event -> unit =
  [%mel.raw {|function (element, e) { try { element.setPointerCapture(e.pointerId) } catch (error) {} }|}]

let coalesced : event -> event array =
  [%mel.raw
    {|function (e) {
  var list = typeof e.getCoalescedEvents === "function" ? e.getCoalescedEvents() : null;
  return list && list.length ? list : [e];
}|}]

let left : element -> float = [%mel.raw {|function (element) { return element.getBoundingClientRect().left }|}]
let top : element -> float = [%mel.raw {|function (element) { return element.getBoundingClientRect().top }|}]
let width_of : element -> float = [%mel.raw {|function (element) { return element.getBoundingClientRect().width }|}]
let height_of : element -> float = [%mel.raw {|function (element) { return element.getBoundingClientRect().height }|}]

external client_x : event -> float = "clientX" [@@mel.get]
external client_y : event -> float = "clientY" [@@mel.get]
external pointer_id : event -> int = "pointerId" [@@mel.get]
external pointer_type : event -> string = "pointerType" [@@mel.get]
external pressure : event -> float = "pressure" [@@mel.get]
external button : event -> int = "button" [@@mel.get]
external shift_key : event -> bool = "shiftKey" [@@mel.get]
external alt_key : event -> bool = "altKey" [@@mel.get]
external ctrl_key : event -> bool = "ctrlKey" [@@mel.get]
external meta_key : event -> bool = "metaKey" [@@mel.get]
external delta_x : event -> float = "deltaX" [@@mel.get]
external delta_y : event -> float = "deltaY" [@@mel.get]
external delta_mode : event -> int = "deltaMode" [@@mel.get]
external prevent_default : event -> unit = "preventDefault" [@@mel.send]

type t = remover list

let pointer element ~button:b e : Editor.pointer =
  {
    id = pointer_id e;
    screen = Vec.make (client_x e -. left element) (client_y e -. top element);
    device = (match pointer_type e with "pen" -> Pen | "touch" -> Touch | _ -> Mouse);
    pressure = pressure e;
    button = b;
    shift = shift_key e;
    alt = alt_key e;
    ctrl = ctrl_key e || meta_key e;
  }

let attach id (h : handlers) =
  match Js.Nullable.toOption (find id) with
  | None -> None
  | Some element ->
      let down e =
        prevent_default e;
        let p = pointer element ~button:(button e) e in
        capture element e;
        h.down p
      in
      let move e =
        let main = pointer element ~button:0 e in
        h.move (Array.to_list (Array.map (fun c -> { (pointer element ~button:0 c) with id = main.id }) (coalesced e)))
      in
      let up e = h.up (pointer element ~button:(button e) e) in
      let cancel e = h.cancel (pointer_id e) in
      let wheel e =
        prevent_default e;
        let unit = match delta_mode e with 1 -> 16. | 2 -> height_of element | _ -> 1. in
        let dx = delta_x e *. unit and dy = delta_y e *. unit in
        let dx, dy = if shift_key e && dx = 0. && not (ctrl_key e) then (dy, 0.) else (dx, dy) in
        h.wheel
          ~at:(Vec.make (client_x e -. left element) (client_y e -. top element))
          ~dx ~dy
          ~ctrl:(ctrl_key e || meta_key e)
      in
      let double e = h.double_click (Vec.make (client_x e -. left element) (client_y e -. top element)) in
      let resize _ = h.resize ~width:(width_of element) ~height:(height_of element) in
      Some
        [
          listen element "pointerdown" down;
          listen element "pointermove" move;
          listen element "pointerup" up;
          listen element "pointercancel" cancel;
          listen element "wheel" wheel;
          listen element "dblclick" double;
          listen element "contextmenu" prevent_default;
          listen_window "resize" resize;
          listen_window "blur" (fun _ -> h.blur ());
        ]

let detach removers = List.iter unlisten removers

let viewport id =
  match Js.Nullable.toOption (find id) with
  | Some element -> (width_of element, height_of element)
  | None -> (0., 0.)

let measure : string -> float -> string -> float =
  [%mel.raw
    {|function (family, size, text) {
  var c = window.__sketchMeasure || (window.__sketchMeasure = document.createElement("canvas").getContext("2d"));
  c.font = size + "px " + family;
  return c.measureText(text).width;
}|}]

let font_box : string -> float array =
  [%mel.raw
    {|function (family) {
  var c = window.__sketchMeasure || (window.__sketchMeasure = document.createElement("canvas").getContext("2d"));
  c.font = "100px " + family;
  var m = c.measureText("Hg");
  var a = m.fontBoundingBoxAscent, d = m.fontBoundingBoxDescent;
  if (!(a > 0)) { a = 92; d = 24; }
  return [a / 100, d / 100];
}|}]

let metrics () =
  let family = Export.font_family in
  let box = font_box family in
  { Shape.width = (fun ~font text -> measure family font text); ascent = box.(0); descent = box.(1) }

let load : string -> string Js.Nullable.t =
  [%mel.raw {|function (key) { try { return window.localStorage.getItem(key) } catch (error) { return null } }|}]

let load key = Js.Nullable.toOption (load key)

let save : string -> (unit -> string) -> unit =
  [%mel.raw
    {|function (key, value) {
  var timers = window.__sketchSave || (window.__sketchSave = {});
  clearTimeout(timers[key]);
  timers[key] = setTimeout(function () {
    try { window.localStorage.setItem(key, value()) } catch (error) {}
  }, 300);
}|}]

let download_raw : string -> string -> string -> unit =
  [%mel.raw
    {|function (name, mime, content) {
  var url = URL.createObjectURL(new Blob([content], { type: mime }));
  var a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(function () { URL.revokeObjectURL(url) }, 1000);
}|}]

let download ~name ~mime content = download_raw name mime content

let start_text : string -> string -> unit =
  [%mel.raw
    {|function (id, text) {
  var el = document.getElementById(id);
  if (!el) return;
  el.value = text;
  el.focus({ preventScroll: true });
  el.setSelectionRange(text.length, text.length);
}|}]
