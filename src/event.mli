type t = Web.event

val target_value : t -> string
(** The [value] property of the event target. *)

val target_checked : t -> bool
(** The [checked] property of the event target. *)

val key : t -> string
(** The [key] of a keyboard event. *)

val meta_key : t -> bool
(** Whether the Meta key was down. *)

val ctrl_key : t -> bool
(** Whether the Control key was down. *)

val prevent_default : t -> unit
(** Calls [preventDefault] on the event. *)

val stop_propagation : t -> unit
(** Stops the event: no other Yuka handler of an outer element receives
    it, and it does not propagate in the DOM. *)

val target_tag : t -> string
(** The lowercase tag name of the event target. *)

val shift_key : t -> bool
(** Whether the Shift key was down. *)

val alt_key : t -> bool
(** Whether the Alt key was down. *)

val client_x : t -> float
(** The horizontal position of the pointer, in CSS pixels from the left
    edge of the viewport ([clientX]). For a mouse or pointer event only. *)

val client_y : t -> float
(** The vertical position of the pointer, in CSS pixels from the top edge
    of the viewport ([clientY]). For a mouse or pointer event only. *)
