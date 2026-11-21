(** The outline of a pen stroke: a closed polygon around the input points
    whose width follows the pressure, or the speed when the device gives
    no pressure, with tapered ends. *)

type point = { x : float; y : float; pressure : float }
(** [pressure] is in [0, 1]. *)

type options = {
  size : float;  (** Width of the stroke at pressure 0.5. *)
  thinning : float;  (** How much the pressure changes the width, in [0, 1]. *)
  smoothing : float;  (** How far apart outline points are, as a part of [size]. *)
  streamline : float;  (** How much the input is smoothed, in [0, 1]. *)
  simulate : bool;  (** Width from the speed, not from [pressure]. *)
  taper_start : float;  (** Length of the taper at the start; 0 is a round cap. *)
  taper_end : float;  (** Length of the taper at the end; 0 is a round cap. *)
}

val options : size:float -> simulate:bool -> complete:bool -> options
(** The options of the pen: both ends taper when [complete]; while the
    stroke is drawn, its end is round, so it follows the pointer. *)

val outline : options -> point array -> Vec.t array
(** The outline polygon. One point, or a stroke shorter than a quarter of
    [size], gives a dot. The end of the outline is at the last input
    point, so a stroke in progress has no lag. *)

val path_of_outline : Vec.t array -> string
(** SVG path data of a closed smooth curve through the midpoints of the
    polygon's sides, with the polygon's points as control points; [""]
    for fewer than four points. *)

val path : options -> point array -> string
