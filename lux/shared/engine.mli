(** The WebGL2 view of a {!Spread}: browser only. On native, {!start} gives
    [Error]. *)

type t

val start : canvas_id:string -> (t, string) result
(** Draws on the canvas with this id. [Error] when the canvas or WebGL2 is
    missing, or a shader does not compile. *)

val frame : t -> float -> unit
(** One frame at this time in milliseconds: steps the light every 120 ms,
    moves the camera and draws. *)

val follow : t -> unit
(** The camera fits the lit cards again. *)

val restart : t -> unit
(** New seeds, the camera at zoom 1. *)

val following : t -> bool

val readout : t -> string
(** Frames per second, zoom and lit cards. *)

val stop : t -> unit
(** Removes the listeners and frees the GPU memory. *)
