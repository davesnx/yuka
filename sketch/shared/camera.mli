(** The view: a screen point is [world * zoom + offset]. *)

type t = { x : float; y : float; zoom : float }

val initial : t
val min_zoom : float
val max_zoom : float
val to_screen : t -> Vec.t -> Vec.t
val to_world : t -> Vec.t -> Vec.t

val pan : t -> Vec.t -> t
(** Moves the view by a screen distance. *)

val zoom_at : t -> Vec.t -> float -> t
(** Sets the zoom, clamped to [\[min_zoom, max_zoom\]], and keeps the world
    point under the screen point in place. *)

val zoom_in : t -> Vec.t -> t
(** The next zoom step ([0.1, 0.25, 0.5, 1, 2, 4, 8]) around the screen
    point. *)

val zoom_out : t -> Vec.t -> t

val fit : Geom.Box.t -> width:float -> height:float -> t
(** Shows the box in the middle of a screen of this size, with a margin,
    at a zoom of at most 1. *)

val to_json_text : t -> string
val of_json : Yuka.Json.t -> t option
