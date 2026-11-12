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

val render : container -> (unit -> 'k Kind.element) -> unit -> unit
val hydrate : container -> (unit -> 'k Kind.element) -> unit -> unit
val render_root : container * (unit -> 'k Kind.element) -> unit
val stop_roots : unit -> unit
val start : ?lazy_entries:lazy_entry list -> entry list -> unit
val stop : unit -> unit
val stop_within : Web.node -> unit
val on_error : (string -> unit) ref

val use_element : unit -> unit
val use_await : unit -> unit
val use_slot : unit -> unit
val use_catch : unit -> unit
val use_actions : unit -> unit
val use_async : unit -> unit
(** The node constructors call the first four, so that the client links
    the mount code of a node kind only when the app makes such a node.
    [Action.send] calls [use_actions] and a [Codec.async] reference calls
    [use_async], so that the action transport and the reader of streamed
    async values are linked only when the app uses them. *)

val use_url_check : unit -> unit
(** Links the URL check of the attributes the client sets. {!Yuka.attr},
    {!Yuka.hole_attr} (and their ppx forms) and [use_element] call it.
    Without it, setting a URL attribute raises [Failure]. *)
