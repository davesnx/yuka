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

type t = unit

let attach _ _ = None
let detach () = ()
let viewport _ = (1280., 800.)

let metrics () =
  { Shape.width = (fun ~font text -> font *. 0.55 *. float_of_int (String.length text)); ascent = 0.9; descent = 0.25 }

let load _ = None
let save _ _ = ()
let download ~name:_ ~mime:_ _ = ()
let start_text _ _ = ()
