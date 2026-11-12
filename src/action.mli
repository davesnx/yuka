type (_, _, _) form =
  | Mutation : (_, _, [ `Mutation ]) form
  | Query : (_, _, [ `Query ]) form
  | Form : ('i, 'f) Form_core.t * 'x Codec.t -> ('i, ('x, ('f option * string) list) result, [ `Form ]) form

type ('i, 'o, 'kind) t

val mutation : name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Mutation ]) t
val query : name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Query ]) t

val with_form :
  name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Form ]) form -> ('i, 'o, [ `Form ]) t

val name : (_, _, _) t -> string
val input : ('i, _, _) t -> 'i Codec.t
val output : (_, 'o, _) t -> 'o Codec.t
val form : ('i, 'o, 'kind) t -> ('i, 'o, 'kind) form
val send : string -> Json.t -> (Json.t, Status.error) result Async.t
val call : ('i, 'o, _) t -> 'i -> ('o, Status.error) result Async.t
