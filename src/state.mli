type ('a, 'access) signal
type 'a t = ('a, [ `Write ]) signal
type 'a read = ('a, [ `Read ]) signal

val on_change : ?equal:('a -> 'a -> bool) -> ('a, _) signal -> (prev:'a -> next:'a -> unit) -> unit
val make : ?equal:('a -> 'a -> bool) -> 'a -> 'a t
val get : ('a, _) signal -> 'a
val peek : ('a, _) signal -> 'a
val set : 'a t -> 'a -> unit
val update : 'a t -> ('a -> 'a) -> unit
val memo : ?equal:('a -> 'a -> bool) -> (unit -> 'a) -> 'a read
val deferred : ?equal:('a -> 'a -> bool) -> ('a, _) signal -> 'a read
external read_only : 'a t -> 'a read = "%identity"
val untrack : (unit -> 'a) -> 'a
external signal : ('a, _) signal -> 'a Signal.t = "%identity"
external of_signal : 'a Signal.t -> ('a, _) signal = "%identity"
