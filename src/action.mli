type ('i, 'o) form =
  | Form : ('i, 'f) Form_core.t * 'x Codec.t -> ('i, ('x, ('f option * string) list) result) form

type ('i, 'o, 'kind) t

val declare : name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Mutation ]) t
val query : name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Query ]) t

val with_form :
  name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o) form -> ('i, 'o, [ `Mutation ]) t

val name : (_, _, _) t -> string
val input : ('i, _, _) t -> 'i Codec.t
val output : (_, 'o, _) t -> 'o Codec.t
val form : ('i, 'o, _) t -> ('i, 'o) form option
val send : string -> Json.t -> Json.t Async.t
val call : ('i, 'o, _) t -> 'i -> 'o Async.t
