type t = Web.event

val target_value : t -> string

val target_checked : t -> bool

val key : t -> string

val meta_key : t -> bool

val ctrl_key : t -> bool

val prevent_default : t -> unit

val stop_propagation : t -> unit
(** Stops the event: no other Yuka handler of an outer element receives
    it, and it does not propagate in the DOM. *)

val target_tag : t -> string
(** The lowercase tag name of the event target. *)

val shift_key : t -> bool

val alt_key : t -> bool

val client_x : t -> float
(** The horizontal position of the pointer, in CSS pixels from the left
    edge of the viewport ([clientX]). For a mouse or pointer event only. *)

val client_y : t -> float
(** The vertical position of the pointer, in CSS pixels from the top edge
    of the viewport ([clientY]). For a mouse or pointer event only. *)

val detail : 'a Codec.t -> t -> ('a, string) result
(** Reads the [detail] of a [CustomEvent] with [codec]. The value goes
    through [JSON.stringify], so a [Date] becomes a string and a function
    is not kept. An event without [detail], or a [detail] that
    [JSON.stringify] cannot write, gives [Error]. The server build gives
    [Error] for each event. *)
