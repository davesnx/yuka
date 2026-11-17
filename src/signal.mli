type scope

val scope : scope

type 'a thunk = unit -> 'a

external scoped : (scope -> 'a) -> 'a thunk = "%identity"

type 'a t = {
  mutable value : 'a;
  mutable old : 'a;
  equal : ('a -> 'a -> bool) option;
  node : Scheduler.node;
}

val same : 'a -> 'a -> bool
val differs : ('a -> 'a -> bool) option -> 'a -> 'a -> bool
val make : ?equal:('a -> 'a -> bool) -> 'a -> 'a t
val quiet_set : 'a t -> 'a -> unit
val peek : 'a t -> 'a
val get : scope -> 'a t -> 'a
val set : 'a t -> 'a -> unit
val update : 'a t -> ('a -> 'a) -> unit
val computed : ?equal:('a -> 'a -> bool) -> (scope -> 'a) -> 'a t
val dispose_computed : 'a t -> unit
