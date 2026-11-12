type 'a status = Pending | Done of 'a | Failed of string
type 'a t

val make : unit -> 'a t * ('a -> unit) * (string -> unit)
val return : 'a -> 'a t
val failed : string -> 'a t
val status : 'a t -> 'a status
val on_settled : 'a t -> ('a status -> unit) -> unit
val on_result : 'a t -> (('a, string) result -> unit) -> unit
val bind : 'a t -> ('a -> 'b t) -> 'b t
val map : ('a -> 'b) -> 'a t -> 'b t
val watch : 'a t -> 'a status State.t
val guard : ('a -> 'b t) -> 'a -> 'b t
