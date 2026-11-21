(** What a shape draws, in its local space, for the page and for the SVG
    export. *)

type paint = Ink of Shape.color | Tint of Shape.color | No_paint

type part =
  | Path of { d : string; fill : paint; stroke : paint; width : float }
  | Text of { lines : (string * float) list; x : float; size : float; color : Shape.color }
      (** Each line with the y of its baseline; [x] is where lines start. *)

val transform : Shape.t -> string
(** The SVG [transform] that places local space in world space. *)

val parts : Shape.metrics -> Shape.t -> part list

val outline : Shape.t -> string
(** Path data of the shape's edge in local space, for the hover and
    selection outline. *)

val baseline : Shape.metrics -> font:float -> int -> float
(** The y of the baseline of line [n] (from 0) of a text. *)
