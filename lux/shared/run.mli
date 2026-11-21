(** A run of the light: the {!Spread}, its step clock and the camera that
    follows it. Pure: the WebGL and the DOM pages draw it. The camera is in
    card units: a card is one unit wide, and at zoom 1 a view of [width] x
    [height] CSS pixels shows about 200 cards. *)

type t

val create : size:int -> seed:int -> width:float -> height:float -> t
(** A grid of [size] x [size] cards, seeds in the view at zoom 1, the camera
    on them. *)

val spread : t -> Spread.t

val restart : t -> seed:int -> unit
(** New seeds; the camera moves to them with the spring. *)

val resize : t -> width:float -> height:float -> unit
(** The view in CSS pixels. A size of 0 is ignored. The cards keep their
    size on screen. *)

val tick : t -> float -> bool
(** One frame at this time in milliseconds: one step every 120 ms, the
    spring when following, the frame rate. [true] when a step lit cards:
    read them with {!Spread.fresh}. *)

val center_x : t -> float
val center_y : t -> float

val scale : t -> float
(** CSS pixels per card. *)

val zoom : t -> float
val width : t -> float
val height : t -> float

val seconds : t -> float
(** Seconds from the first frame to the last. *)

val glow_level : t -> float
(** The level of the newest cards, plus the steps since they lit. *)

val follow : t -> unit
val following : t -> bool

val readout : t -> string
(** Frames per second, zoom and lit cards. *)

val wheel : t -> x:float -> y:float -> delta:float -> unit
(** Zoom around the point [x, y] (CSS pixels in the view) by a wheel delta
    in pixels. *)

val press : t -> id:int -> x:float -> y:float -> bool
(** A pointer goes down; [false] when two are down already. *)

val move : t -> id:int -> x:float -> y:float -> unit
(** One pointer pans; two pinch. *)

val release : t -> id:int -> unit
