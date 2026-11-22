type entry = Island.entry = {
  name : string;
  decode : Json.t -> (unit -> Types.node, string) result;
}

val island :
  ?start:Types.start ->
  name:string ->
  props:Json.t ->
  (unit -> Types.client Kind.element) ->
  Types.server Kind.element

val entry : name:string -> (Json.t -> (unit -> Types.client Kind.element, string) result) -> entry

type container = Web.node

val container : string -> container option
type 'a promise = 'a Web.promise

val promise_map : ('a -> 'b) -> 'a promise -> 'b promise

type lazy_entry

val lazy_entry : name:string -> (unit -> entry promise) -> lazy_entry

val acting : Base.owner option ref
val own_call : 'a Async.t -> (unit -> unit) -> unit
val query : string -> Json.t -> ((Json.t, Status.error) result -> unit) -> unit -> unit

val render : container -> (unit -> 'k Kind.element) -> unit -> unit
val hydrate : container -> (unit -> 'k Kind.element) -> unit -> unit
val render_root : container * (unit -> 'k Kind.element) -> unit
val stop_roots : unit -> unit
val start : ?lazy_entries:lazy_entry list -> entry list -> unit
val stop : unit -> unit
val stop_within : Web.node -> unit
val has_handler : Web.node -> string -> (Web.event -> unit) -> bool
val on_error : (string -> unit) ref

val use_element : unit -> unit
val use_await : unit -> unit
val use_slot : unit -> unit
val use_catch : unit -> unit
val at : Obj.t -> Obj.t option
val mount_at : Obj.t -> bool ref -> Types.node -> unit
val hole_start_at : Obj.t -> Web.node
val comment_at : Obj.t -> string -> Web.node
val drop_rest_at : Obj.t -> unit
val skip_region : Obj.t -> unit
val off_page_at : Obj.t -> Web.node -> Obj.t
val use_actions : unit -> unit

val use_url_check : unit -> unit
