(** Shapes of the board. A shape has a box [x, y, w, h] in world space,
    turned by [rotation] radians around its center. Lines and arrows keep
    [rotation = 0] and store their two ends. Points of a shape's kind are
    local: relative to [(x, y)]. *)

type color = Black | Grey | Red | Orange | Yellow | Green | Blue | Violet
type size = S | M | L
type fill = Hollow | Semi | Solid
type style = { color : color; size : size; fill : fill }

val colors : color list
val color_name : color -> string
val size_name : size -> string
val fill_name : fill -> string
val default_style : style

type metrics = { width : font:float -> string -> float; ascent : float; descent : float }
(** Text measures of the host: the width of one line at a font size, and
    the ascent and descent of the font for a font size of 1. *)

type kind =
  | Rect
  | Ellipse
  | Draw of { points : Freehand.point array; simulate : bool; path : string }
      (** [path] is the outline of [points], kept so a move does not
          compute it again. *)
  | Line of { start : Vec.t; end_ : Vec.t; arrow : bool }
  | Text of { text : string; scale : float }

type t = private {
  id : int;
  x : float;
  y : float;
  w : float;
  h : float;
  rotation : float;
  style : style;
  kind : kind;
}

val rect : id:int -> style:style -> Geom.Box.t -> t
val ellipse : id:int -> style:style -> Geom.Box.t -> t

val draw : id:int -> style:style -> simulate:bool -> Freehand.point list -> t option
(** A pen stroke from world points; [None] for no point. *)

val line : id:int -> style:style -> arrow:bool -> Vec.t -> Vec.t -> t
(** A line or arrow from its two ends in world space. *)

val text : metrics -> id:int -> style:style -> scale:float -> Vec.t -> string -> t
(** A text whose top-left corner is the point, sized to its lines. *)

val with_id : t -> int -> t
val stroke_width : style -> float
val pen_size : size -> float
val font_size : t -> float
(** For a text: the font size; for other shapes, 0. *)

val line_height : float
(** Line height as a part of the font size. *)

val text_padding : float
(** Room left and right of a text, as a part of the font size. *)

val is_line : t -> bool
val is_text : t -> bool
val center : t -> Vec.t
val frame : t -> Geom.Frame.t

val ends : t -> (Vec.t * Vec.t) option
(** World ends of a line or arrow. *)

val bounds : t -> Geom.Box.t
(** World box of the geometry, without the stroke width. *)

val half_stroke : t -> float
(** Half the width of the drawn stroke; 0 for a text. *)

val arrowhead_length : t -> float
(** Length of the two strokes of the arrowhead, which open at 30 degrees
    from the line; 0 for a shape that is not an arrow. *)

val visual_bounds : t -> Geom.Box.t
(** [bounds] with room for the stroke and the arrowhead. *)

type hit = Miss | Edge | Inside
(** [Edge]: on the stroke, on a filled area or on a text. [Inside]: in the
    empty middle of a hollow rectangle or ellipse. *)

val hit : t -> tolerance:float -> Vec.t -> hit
val touches_box : t -> Geom.Box.t -> bool
(** Whether a part of the geometry is in the box. *)

val touches_segment : t -> tolerance:float -> Vec.t -> Vec.t -> bool
(** Whether a segment passes within [tolerance] of the geometry. *)

val translate : t -> Vec.t -> t
val rotate_about : t -> center:Vec.t -> float -> t

val resize : t -> rotation:float -> map:(Vec.t -> Vec.t) -> sx:float -> sy:float -> t
(** Applies a scale of [sx, sy] along the axes of a frame turned by
    [rotation]; [map] is that transform on world points. A negative scale
    flips. A shape turned against the frame by an angle that is not a
    multiple of 90 degrees needs [|sx| = |sy|]. A text keeps its glyphs
    unmirrored and scales by the mean of [|sx|] and [|sy|]. *)

val set_ends : t -> Vec.t -> Vec.t -> t
(** New world ends of a line or arrow; other shapes stay. *)

val set_style : metrics -> t -> style -> t
val set_text : metrics -> t -> string -> t
val text_of : t -> string option

val write_json : Buffer.t -> t -> unit
(** Writes the shape as JSON text, with numbers rounded as they are
    drawn, which {!of_json} reads back. *)

val of_json : metrics -> Yuka.Json.t -> (t, string) result
