(** The browser side of the board: pointer, wheel and resize events of the
    canvas, text measures, storage and file download. On native, {!attach}
    gives [None], storage is empty and the measures are estimates. *)

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

type t

val attach : string -> handlers -> t option
(** Listens on the element with this id and on the window; [None] when
    there is no such element. Points are relative to the element. *)

val detach : t -> unit
val viewport : string -> float * float
(** The size of the element with this id. *)

val metrics : unit -> Shape.metrics
val load : string -> string option
val save : string -> (unit -> string) -> unit
(** Writes the value of the function a moment after the last call for
    this key, so a burst of changes writes once. *)
val download : name:string -> mime:string -> string -> unit

val start_text : string -> string -> unit
(** [start_text id text] puts [text] in the text field with this id,
    focuses it and puts the caret at the end. *)
