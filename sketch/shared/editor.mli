(** The whiteboard as a pure state machine: pointer, wheel and key input in
    screen space go in; the board, selection, camera and what the page
    shows come out. *)

type tool = Select | Hand | Draw | Rect | Ellipse | Arrow | Line | Text | Eraser

val tools : tool list
val tool_name : tool -> string
val tool_key : tool -> string
(** The shortcut letter. *)

type device = Mouse | Pen | Touch

type pointer = {
  id : int;
  screen : Vec.t;
  device : device;
  pressure : float;
  button : int;  (** 0 main, 1 middle, 2 secondary. *)
  shift : bool;
  alt : bool;
  ctrl : bool;  (** Control or Meta. *)
}

type key = { key : string; shift : bool; alt : bool; ctrl : bool }

type handle = N | S | E | W | NE | NW | SE | SW | Rotate | Start | End

type cursor =
  | Default
  | Cross
  | Grab
  | Grabbing
  | Move
  | Resize of float  (** Direction of the resize on screen, in radians. *)
  | Rotate_cursor
  | Text_cursor

type t

val create : metrics:Shape.metrics -> width:float -> height:float -> t
val load : t -> Board.t -> Camera.t -> t
(** A new board and view; no undo step. *)

val resize_viewport : t -> width:float -> height:float -> t

(** {1 Input} *)

val pointer_down : t -> pointer -> t
val pointer_move : t -> pointer list -> t
(** The samples of one move, oldest first (coalesced events). *)

val pointer_up : t -> pointer -> t
val pointer_cancel : t -> int -> t
val double_click : t -> Vec.t -> t
val wheel : t -> at:Vec.t -> dx:float -> dy:float -> ctrl:bool -> t

val key_down : t -> key -> t * bool
(** The new state, and whether the key was used (the page then prevents
    the browser's action). *)

val key_up : t -> key -> t
val blur : t -> t
(** The window lost focus: the space key is no longer held and a gesture
    stops. *)

(** {1 Commands} *)

val set_tool : t -> tool -> t
val set_color : t -> Shape.color -> t
val set_size : t -> Shape.size -> t
val set_fill : t -> Shape.fill -> t
val undo : t -> t
val redo : t -> t
val delete : t -> t
val duplicate : t -> t
val copy : t -> t
val cut : t -> t
val paste : t -> t
val to_front : t -> t
val to_back : t -> t
val select_all : t -> t
val zoom_in : t -> t
val zoom_out : t -> t
val zoom_to_fit : t -> t
val zoom_reset : t -> t
val set_text : t -> string -> t
(** The text of the text being edited. *)

val stop_editing : t -> t
(** Ends the text edit; an empty text is removed. *)

(** {1 Output} *)

val board : t -> Board.t
val selection : t -> int list
val camera : t -> Camera.t
val tool : t -> tool
val style : t -> Shape.style
(** The style of the selection, or the style of the next shape. *)

val hover : t -> int option
val editing : t -> int option
val erasing : t -> int list

val drawing : t -> (string * Shape.style) option
(** Path data, in world space, of the stroke being drawn. *)

val marquee : t -> Geom.Box.t option
(** The selection box being dragged, in world space. *)

val selection_frame : t -> Geom.Frame.t option
(** The box around the selection, in world space, outside the strokes by
    a gap of a few screen pixels; the handles sit on it. *)

val selection_boxes : t -> Geom.Frame.t list
(** With two or more shapes selected, or one line or arrow, a box around
    each of them, outside its stroke; along the line for a line or
    arrow. *)

val handles : t -> (handle * Vec.t) list
(** The handles of the selection, in screen space; none while a shape is
    moved, resized or turned. The handles in the middle of two sides show
    only when those sides are at least {!edge_handle_room} pixels long. *)

val edge_handle_room : float

val transforming : t -> bool
(** A move, resize or turn is in progress. *)

val busy : t -> bool
(** A gesture or a text edit is in progress. *)

val cursor : t -> cursor
val can_undo : t -> bool
val can_redo : t -> bool
val metrics : t -> Shape.metrics
