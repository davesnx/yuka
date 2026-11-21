val color_hex : Shape.color -> string
(** The ink of a color on the light page. *)

val tint_hex : Shape.color -> string
(** The pale fill of a color on the light page. *)

val font_family : string

val svg : Shape.metrics -> Board.t -> string option
(** A standalone SVG document of the board on a light page, sized to its
    shapes with a margin; [None] for an empty board. *)
