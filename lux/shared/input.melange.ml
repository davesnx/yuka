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

let unlisten : remover -> unit = [%mel.raw {|function (remove) { remove() }|}]

let capture : element -> event -> unit =
  [%mel.raw {|function (element, e) { try { element.setPointerCapture(e.pointerId) } catch (error) {} }|}]

let width : unit -> float = [%mel.raw {|function () { return window.innerWidth }|}]
let height : unit -> float = [%mel.raw {|function () { return window.innerHeight }|}]
let random_seed : unit -> int = [%mel.raw {|function () { return Math.floor(Math.random() * 1073741823) }|}]

let set_transform : string -> float -> float -> float -> unit =
  [%mel.raw
    {|function (id, x, y, s) {
  var element = document.getElementById(id);
  if (element) element.style.transform = "translate(" + x + "px," + y + "px) scale(" + s + ")";
}|}]

external client_x : event -> float = "clientX" [@@mel.get]
external client_y : event -> float = "clientY" [@@mel.get]
external delta_y : event -> float = "deltaY" [@@mel.get]
external delta_mode : event -> int = "deltaMode" [@@mel.get]
external pointer_id : event -> int = "pointerId" [@@mel.get]
external prevent_default : event -> unit = "preventDefault" [@@mel.send]

type t = remover list

let attach id run =
  match Js.Nullable.toOption (find id) with
  | None -> None
  | Some element ->
      let wheel event =
        prevent_default event;
        let unit = match delta_mode event with 1 -> 16. | 2 -> Run.height run | _ -> 1. in
        Run.wheel run ~x:(client_x event) ~y:(client_y event) ~delta:(delta_y event *. unit)
      in
      let down event =
        if Run.press run ~id:(pointer_id event) ~x:(client_x event) ~y:(client_y event) then capture element event
      in
      let move event = Run.move run ~id:(pointer_id event) ~x:(client_x event) ~y:(client_y event) in
      let up event = Run.release run ~id:(pointer_id event) in
      Some
        [
          listen element "wheel" wheel;
          listen element "pointerdown" down;
          listen element "pointermove" move;
          listen element "pointerup" up;
          listen element "pointercancel" up;
        ]

let detach removers = List.iter unlisten removers
