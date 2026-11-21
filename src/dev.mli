val on : bool
val mismatch : Web.node -> string -> Web.node option -> unit
val untracked_get : string option -> unit
val name : 'a -> string -> unit
val name_of : 'a -> string option
val error : string -> Obj.t -> unit
val guard : (unit -> Obj.t[@u]) -> (Obj.t -> unit[@u]) -> Obj.t
