val on : bool
val mismatch : Web.node -> string -> Web.node option -> unit
val untracked_get : string option -> unit
val name : 'a -> string -> unit
val name_of : 'a -> string option
val error : string -> Obj.t -> unit
val guard : (unit -> Obj.t[@u]) -> (Obj.t -> unit[@u]) -> Obj.t
val set_trace : bool -> unit
val tracing : unit -> bool
val cause : 'a -> string -> unit
val take_cause : 'a -> string option
val trace : string -> unit
