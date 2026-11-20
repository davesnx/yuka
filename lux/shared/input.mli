(** Wheel, drag and pinch on a page element move the camera of a {!Run};
    the size of the window. Browser only: on native, {!attach} gives [None],
    the sizes are 0 and {!set_transform} does nothing. *)

type t

val attach : string -> Run.t -> t option
(** Listens on the element with this id; [None] when there is none. *)

val detach : t -> unit
val width : unit -> float
val height : unit -> float
val random_seed : unit -> int

val set_transform : string -> float -> float -> float -> unit
(** [set_transform id x y scale] sets [transform: translate(x, y)
    scale(scale)] on the element with this id, when there is one. *)
