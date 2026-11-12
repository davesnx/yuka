type ('k, 's) t

val declare : name:string -> key:'k Codec.t -> state:'s Codec.t -> ('k, 's) t
val name : (_, _) t -> string
val key : ('k, _) t -> 'k Codec.t
val state : (_, 's) t -> 's Codec.t
val wire_key : ('k, _) t -> 'k -> string
