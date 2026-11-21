type 'a status = Pending | Done of 'a | Failed of string
type 'a t

val make : unit -> 'a t * ('a -> unit) * (string -> unit)
(** A pending value and its resolve and fail functions. It settles once;
    later calls are ignored. *)

val return : 'a -> 'a t
(** A value that is already [Done]. *)

val failed : string -> 'a t
(** A value that is already [Failed] with this message. *)

val status : 'a t -> 'a status

val on_settled : 'a t -> ('a status -> unit) -> unit
(** Callbacks run in registration order; now, if already settled. *)

val on_result : 'a t -> (('a, string) result -> unit) -> unit
(** Like [on_settled], without the [Pending] case. *)

val map : ('a -> 'b) -> 'a t -> 'b t
(** Applies the function to the value when it is [Done]. A failure stays a
    failure with the same message. An exception that the function raises
    gives [Failed] with the exception as text. *)

val bind : 'a t -> ('a -> 'b t) -> 'b t
(** Like [map], with a function that gives an [Async]. *)

val watch : 'a t -> 'a status State.read
(** A State that follows the status. *)

(**/**)

val guard : ('a -> 'b t) -> 'a -> 'b t
