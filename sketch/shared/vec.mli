type t = { x : float; y : float }

val make : float -> float -> t
val zero : t
val add : t -> t -> t
val sub : t -> t -> t
val scale : t -> float -> t
val neg : t -> t
val dot : t -> t -> float
val cross : t -> t -> float
val length : t -> float
val dist : t -> t -> float
val dist2 : t -> t -> float
val lerp : t -> t -> float -> t
val mid : t -> t -> t

val normalize : t -> t
(** The unit vector of the same direction; [zero] for [zero]. *)

val perp : t -> t
(** The vector turned a quarter turn: [(y, -x)]. *)

val rotate : t -> float -> t
(** Turns by an angle in radians. With y down, as on screen, a positive
    angle turns clockwise, as SVG [rotate] does. *)

val rotate_about : center:t -> t -> float -> t
val angle : t -> float
(** [atan2 y x]. *)

val equal : t -> t -> bool
