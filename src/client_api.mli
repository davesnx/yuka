type entry = Island.entry
(** Made by [entry]. The island modules expose it as [register], for
    generated code only. *)

type registry = Types.registry

type lazy_entry = Client.lazy_entry

val island :
  ?loading:Types.loading ->
  name:string ->
  props:Json.t ->
  (unit -> Types.client Kind.element) ->
  Types.server Kind.element
(** A client component placed in a server tree. The server prints its
    HTML and its props. *)

val registry : ?lazy_entries:lazy_entry list -> entry list -> registry
(** The islands of an app. For generated code: [yuka.ppx] and
    [yuka-islands] build it. Pass it to [Yuka.render]. *)

val entry :
  name:string ->
  (Json.t -> (unit -> Types.client Kind.element, string) result) ->
  entry
(** What the browser knows about an island: it decodes the props and gives
    the function that builds the component. *)

type container = Web.node
(** A DOM element that holds a rendered tree. In a Melange entry, get one
    with an [external ... = "%identity"] binding of your own. *)

type 'a promise = 'a Web.promise
(** A JavaScript promise, as made by a dynamic [import]. *)

val promise_map : ('a -> 'b) -> 'a promise -> 'b promise
(** [then] of a JavaScript promise. For the code of [yuka-islands]. *)

val lazy_entry : name:string -> (unit -> entry promise) -> lazy_entry
(** [lazy_entry ~name load]: an island whose code is loaded on demand.
    [load] is called, at most once, when the start strategy of an island
    named [name] fires, for example with a dynamic import of the module
    that defines the entry. If it fails, the island keeps its server HTML
    and the error is logged. *)

val hydrate : container -> (unit -> 'k Kind.element) -> unit -> unit
(** [hydrate container f] adopts the server DOM in [container] (written
    with the markers of DESIGN.md), attaches handlers and starts holes.
    Where the DOM does not match, it creates the missing nodes. Unless the bundler
    defines [__YUKA_DEV__] as [false], each mismatch (a missing node,
    another tag, another text, an extra node) logs one [console.warn] with
    the island name, the expected and the found node, and a short path. Returns a function
    that stops all effects and handlers. Browser only. *)
