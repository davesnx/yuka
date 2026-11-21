module Box : sig
  type t = { x : float; y : float; w : float; h : float }
  (** Axis-aligned: top-left corner and size, both sizes >= 0. *)

  val of_corners : Vec.t -> Vec.t -> t
  (** The box with these two opposite corners, in any order. *)

  val of_points : Vec.t list -> t option
  val union : t -> t -> t
  val expand : t -> float -> t
  val center : t -> Vec.t
  val contains : t -> Vec.t -> bool
  val intersects : t -> t -> bool
end

module Frame : sig
  type t = { origin : Vec.t; w : float; h : float; rotation : float }
  (** A box turned by [rotation] radians around [origin], its top-left
      corner. Local point [(0, 0)] is [origin], [(w, h)] the opposite
      corner. *)

  val of_box : Box.t -> t
  val to_world : t -> Vec.t -> Vec.t
  val to_local : t -> Vec.t -> Vec.t
  val center : t -> Vec.t

  val corners : t -> Vec.t array
  (** Top-left, top-right, bottom-right, bottom-left, in world space. *)

  val around : rotation:float -> Vec.t list -> t option
  (** The smallest frame with this rotation that holds the points. *)
end

val dist_to_segment : Vec.t -> Vec.t -> Vec.t -> float
(** [dist_to_segment p a b]. *)

val segments_cross : Vec.t -> Vec.t -> Vec.t -> Vec.t -> bool
(** Whether segment [a b] and segment [c d] share a point. *)

val segment_hits_box : Vec.t -> Vec.t -> Box.t -> bool
(** Whether the segment has a point inside or on the box. *)

val inside_polygon : Vec.t array -> Vec.t -> bool
(** Even-odd test. *)

val normalize_angle : float -> float
(** The same angle in [\[0, 2 pi)]. *)

val snap_angle : step:float -> float -> float
(** The nearest multiple of [step]. *)
