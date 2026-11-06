module Dom : sig
  type element
end

val render : Dom.element -> (unit -> 'k Yuka.element) -> unit -> unit
(** [render container f] clears [container], builds the DOM of [f ()] and
    returns a function that stops all effects and handlers of this tree. The
    DOM stays in place. *)

val hydrate : Dom.element -> (unit -> 'k Yuka.element) -> unit -> unit
(** [hydrate container f] adopts the server DOM in [container] (written with
    the markers of DESIGN.md), attaches handlers and starts holes. Where the
    DOM does not match, it creates the missing nodes. Returns a function that
    stops all effects and handlers. *)

type lazy_entry

val lazy_entry :
  name:string -> (unit -> Yuka.Client.entry Js.Promise.t) -> lazy_entry
(** [lazy_entry ~name load]: an island whose code is loaded on demand.
    [load] is called, at most once, when the start strategy of an island
    named [name] fires, for example with a dynamic import of the module that
    defines the entry. If it fails, the island keeps its server HTML and the
    error is logged. *)

val start :
  ?lazy_entries:lazy_entry list -> Yuka.Client.entry list -> unit
(** [start entries] installs the browser runtime and the action transport,
    then hydrates every [yuka-island] element of the document with the entry
    of the same name. Each island is its own root. Props come from the
    [script] element with the same [data-yuka-props] id. An island that
    cannot start is logged with [console.error] and keeps its server HTML.
    An island that was started is not started again.

    The action transport sends [POST /_yuka/action/<name>] with the input as
    a JSON body. The response is [{"ok": value}] or [{"error": message}]. *)

val stop : unit -> unit
(** Stops every island that [start] started: effects, handlers and document
    listeners are removed, start strategies that did not fire yet are
    cancelled, and action requests in flight are aborted (their [Async]
    fails with ["cancelled"]). The DOM stays. [start] works again afterwards,
    for example on a new body. *)
