type entry = Island.entry = {
  name : string;
  decode : Json.t -> (unit -> Types.node, string) result;
}

val island :
  ?loading:Types.loading ->
  name:string ->
  props:Json.t ->
  (unit -> Types.node) ->
  Types.node

val entry : name:string -> (Json.t -> (unit -> Types.node, string) result) -> entry

type container = Web.node
type 'a promise = 'a Web.promise

val promise_map : ('a -> 'b) -> 'a promise -> 'b promise

type lazy_entry

val lazy_entry : name:string -> (unit -> entry promise) -> lazy_entry

type registry = { entries : entry list; lazy_registry : lazy_entry list }

val registry : ?lazy_entries:lazy_entry list -> entry list -> registry
val render : container -> (unit -> Types.node) -> unit -> unit
val hydrate : container -> (unit -> Types.node) -> unit -> unit
val start : ?lazy_entries:lazy_entry list -> entry list -> unit
val stop : unit -> unit
