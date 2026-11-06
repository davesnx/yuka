val mount : (unit -> 'a) -> 'a * (unit -> unit)
(** [mount f] runs [f] in a new owner. Effects and memos created during [f]
    belong to it. The returned function disposes all of them: it stops the
    effects and runs their cleanups. *)

module State : sig
  type 'a t

  val make : ?equal:('a -> 'a -> bool) -> 'a -> 'a t
  (** [equal] decides whether a write is a change. Default: structural
      equality, or physical equality when structural equality raises
      [Invalid_argument] (a functional value). *)

  val get : 'a t -> 'a
  (** Reads the value. Inside an effect or a memo, the read is tracked. *)

  val peek : 'a t -> 'a
  (** Reads the value without tracking. *)

  val set : 'a t -> 'a -> unit
  (** Raises [Invalid_argument "Yuka: State.set on a memo"] on a memo. *)

  val update : 'a t -> ('a -> 'a) -> unit
  (** Like [set]. *)

  val memo : ?equal:('a -> 'a -> bool) -> (unit -> 'a) -> 'a t
  (** A derived value. It recomputes when a State it read changes. A
      recompute is a change only if [equal] says the new value differs.
      Default: the same equality as {!make}. *)
end

module Effect : sig
  val run : ?cleanup:('r -> unit) -> (unit -> 'r) -> unit
  (** Runs the body now, and again when a State it read with [State.get]
      changes. Before each re-run and when its owner is disposed, [cleanup]
      receives the result of the previous run, and effects created inside the
      previous run are disposed. An exception in one effect does not stop
      other effects; the first one is raised again after all pending effects
      ran. If effects and memos keep changing States they read for more than
      100 update rounds, the pending work is dropped and [Failure] is
      raised. *)

  val on_change :
    ?equal:('a -> 'a -> bool) -> 'a State.t -> (prev:'a -> next:'a -> unit) -> unit
  (** Calls the function when the value changes, with the previous and the
      next value. Not called on the first run. Default [equal]: as in
      {!State.make}. *)
end

type slot
(** Server content passed to a client component. The server prints it; the
    client keeps its DOM nodes and can place them, never re-render them. *)

type loading = [ `Load | `Idle | `Visible | `Interaction ]
(** When the browser starts an island: at start (default), when idle, when
    visible, or at the first interaction. *)

module Json : sig
  type t =
    [ `Null
    | `Bool of bool
    | `Int of int
    | `Float of float
    | `String of string
    | `List of t list
    | `Assoc of (string * t) list ]

  val to_string : t -> string
  (** Compact JSON. Strings are escaped per RFC 8259, non-ASCII stays UTF-8,
      and ['<'] is written as [\u003c] so the text is safe inside a script
      element. Non-finite floats are written as [null]. *)

  val of_string : string -> (t, string) result
  (** A number without ['.'], ['e'] or ['E'] that fits an [int] is [`Int]. *)
end

module Async : sig
  type 'a t
  type 'a status = Pending | Done of 'a | Failed of string

  val make : unit -> 'a t * ('a -> unit) * (string -> unit)
  (** A pending value and its resolve and fail functions. It settles once;
      later calls are ignored. *)

  val resolved : 'a -> 'a t
  val failed : string -> 'a t
  val status : 'a t -> 'a status

  val on_settled : 'a t -> ('a status -> unit) -> unit
  (** Callbacks run in registration order; now, if already settled. *)

  val on_result : 'a t -> (('a, string) result -> unit) -> unit
  (** Like [on_settled], without the [Pending] case. *)

  val map : ('a -> 'b) -> 'a t -> 'b t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val watch : 'a t -> 'a status State.t
  (** A State that follows the status. *)
end

module Codec : sig
  type 'a t = { encode : 'a -> Json.t; decode : Json.t -> ('a, string) result }

  val int : int t
  val float : float t
  (** Decoding accepts [`Int] too. *)

  val string : string t
  val bool : bool t
  val unit : unit t
  val list : 'a t -> 'a list t
  val array : 'a t -> 'a array t
  val option : 'a t -> 'a option t
  (** [None] is [`Null]. *)

  val slot : slot t
  (** Encodes as [null]; decodes to an empty slot. *)

  val result : 'a t -> 'e t -> ('a, 'e) result t
  (** [Ok v] is [{"ok": v}] and [Error e] is [{"error": e}]. *)

  val async : 'a t -> 'a Async.t t
  (** On the server, a settled value is written inline:
      [{"$async":"aN","ok":v}] or [{"$async":"aN","error":m}]. In a streaming
      render, a pending value is written as [{"$async":"aN"}] and the stream
      writes its value later. Outside a streaming render, a pending value is
      written as [{"$async":"aN","error":"pending at render"}]. Decoding a
      bare reference asks [Internal.async_source]. *)

  val encode : 'a t -> 'a -> Json.t
  val decode : 'a t -> Json.t -> ('a, string) result
end

type server
type client


type +'kind element
(** What a JSX expression makes. A server element has no handlers and no
    holes. A client element can have both. *)

type +'kind attribute

module Event : sig
  type t

  val target_value : t -> string
  val target_checked : t -> bool
  val key : t -> string
  val meta_key : t -> bool
  val ctrl_key : t -> bool
  val prevent_default : t -> unit
  val stop_propagation : t -> unit
  val target_tag : t -> string
  (** The lowercase tag name of the event target. *)

  val shift_key : t -> bool
  val alt_key : t -> bool
end

val text : string -> 'kind element
val int : int -> 'kind element
val float : float -> 'kind element
(** Printed as JSON prints a float: [1.0], [2.5]. *)

val list : 'kind element list -> 'kind element
(** The same as [fragment]. *)

val empty : 'kind element
val fragment : 'kind element list -> 'kind element

val lower : string -> 'kind attribute list -> 'kind element list -> 'kind element
(** [lower tag attributes children]: an HTML element. The ppx makes it from
    [<tag ...>]. *)

val attr : string -> string -> 'kind attribute

val hole : (unit -> client element) -> client element
(** A part that changes after the first render. The function runs once; it
    runs again when a State it read changes, and its output replaces the old
    output. *)

val hole_attr : string -> (unit -> string option) -> client attribute
(** An attribute whose value changes. [None] removes the attribute. On the
    client, [value], [checked] and [selected] are set as properties. *)

val slot : slot -> client element
(** Puts a slot where the content goes. *)

val template : string -> 'kind element -> 'kind element
(** [template id e] is [e], marked as a tree of fixed shape. The ppx inserts
    it; [id] is unique per call site. The server prints [e] as usual. *)

module Slot : sig
  val make : server element -> slot
end

val await :
  ?failed:(string -> 'k element) ->
  'a Async.t ->
  loading:'k element ->
  ('a -> 'k element) ->
  'k element
(** Shows [loading] until the value is settled, then the rendered value, or
    [failed message] (default: nothing). On the client it is a hole over
    [Async.watch]. On the server it is printed as a hole; see DESIGN.md. *)

val on : string -> (Event.t -> unit) -> client attribute
(** [on "click" handler]. *)

val each :
  ?equal:('a -> 'a -> bool) ->
  key:('a -> string) ->
  (unit -> 'a list) ->
  ('a -> client element) ->
  client element
(** A keyed list. The list function is tracked as a hole. An item whose key
    stays keeps its DOM nodes; it renders again when [equal] says its value
    changed. Default [equal]: structural equality. *)

module Client : sig
  type entry

  val island :
    ?loading:loading ->
    name:string ->
    props:Json.t ->
    (unit -> client element) ->
    server element
  (** A client component placed in a server tree. The server prints its
      HTML and its props. *)

  val entry :
    name:string ->
    (Json.t -> (unit -> client element, string) result) ->
    entry
  (** What the browser knows about an island: it decodes the props and gives
      the function that builds the component. *)
end

module Action : sig
  type ('i, 'o) t

  val declare :
    name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o) t

  val name : ('i, 'o) t -> string

  val call : ('i, 'o) t -> 'i -> 'o Async.t
  (** Encodes the input, sends it with [Internal.call_action], decodes the
      output. A decode error is [Failed]. *)
end

module Browser : sig
  val on_window : string -> (Event.t -> unit) -> unit
  (** Listens on [window] until the current owner is disposed. Browser only:
      call it inside [Effect.run]. *)

  val navigate : string -> unit
  (** Loads the URL. *)

  val focus : string -> unit
  (** Focuses the element with this id. *)

  val scroll_into_view : string -> unit
  (** Scrolls the element with this id into view. *)
end

module Internal : sig
  type node =
    | Text of string
    | Element of { tag : string; attrs : attr list; children : node list }
    | Fragment of node list
    | Hole of (unit -> node)
    | Island of {
        name : string;
        props : Json.t;
        render : unit -> node;
        loading : loading;
      }
    | Await : {
        async : 'a Async.t;
        loading : node;
        failed : string -> node;
        render : 'a -> node;
      }
        -> node
    | Slot of slot
    | Template of { id : string; node : node }
    | Each : {
        items : unit -> 'a list;
        key : 'a -> string;
        equal : 'a -> 'a -> bool;
        render : 'a -> node;
      }
        -> node

  and attr =
    | Static of string * string
    | Dynamic of string * (unit -> string option)
    | Handler of string * (Event.t -> unit)

  val node : 'kind element -> node
  val element : node -> 'kind element

  val owned : (unit -> 'a) -> 'a * (unit -> unit)
  (** Runs the function in a new owner that belongs to the current owner.
      The returned function disposes it. *)

  type pending =
    | Pending_await of {
        id : string;
        subscribe : (unit -> unit) -> unit;
        fill : unit -> string;
        fill_failed : string -> string;
      }
    | Pending_async of { id : string; async : Json.t Async.t }

  val fill_script : string
  (** The inline script that streaming writes in the head. It defines
      [window.__yukaFill(id)]. *)

  type session
  (** One server render. Counts ids and collects pending parts. *)

  val skeleton_html : node -> string
  (** The fixed shape of a tree: elements, static attributes and texts as
      [to_html] prints them. Each [Hole], [Await], [Each] and [Island]
      is [<!--[--><!--]-->] and each [Slot] is [<!--[$--><!--]-->]. Dynamic
      attributes and handlers are left out. Static [value] on [select] and
      [textarea] follows the rules of [to_html]. *)

  val session : streaming:bool -> session

  val print : session -> (unit -> node) -> string
  (** Builds and prints with [server_rendering] true. In a streaming
      session, a pending [Await] is printed as [<!--[sN-->] loading
      [<!--]-->] and recorded as [Pending_await]; [fill] prints the settled
      content later with the same session, and [fill_failed message] prints
      the [failed] element instead (for a timeout). *)

  val take_pending : session -> pending list
  (** The parts recorded since the last call, in order. *)

  val async_source : (string -> Json.t Async.t) ref
  (** Where [Codec.async] decoding finds the value of a bare reference. The
      browser runtime installs it. Default: a failed [Async]. *)

  val render_html : (unit -> node) -> string
  (** Like [to_html], but also builds the tree with [server_rendering] true,
      so effects in component bodies do nothing. *)

  val to_html : node -> string
  (** Prints the tree as HTML with the hydration markers of DESIGN.md. Holes
      and lists run once. [server_rendering] is true during the call. *)

  val entry_name : Client.entry -> string
  val entry_decode : Client.entry -> Json.t -> (unit -> node, string) result

  val action_codecs : ('i, 'o) Action.t -> 'i Codec.t * 'o Codec.t

  val slot_content : slot -> node option
  (** The server element of the slot, if it has one. *)

  val slot_dom : slot -> Obj.t list ref
  (** The DOM nodes the client captured for the slot. Empty at first. *)

  val owner_size : unit -> int
  (** The number of live disposers of the current owner (0 outside an
      owner). For tests. *)

  val untracked : (unit -> 'a) -> 'a
  (** Runs the function without tracking State reads. *)

  val call_action : (string -> Json.t -> Json.t Async.t) ref
  (** The transport of [Action.call]. Default: a failed [Async]. *)

  val server_rendering : bool ref
  (** When true, [Effect.run] does nothing. *)

  type platform = {
    target_value : Event.t -> string;
    target_checked : Event.t -> bool;
    key : Event.t -> string;
    meta_key : Event.t -> bool;
    ctrl_key : Event.t -> bool;
    prevent_default : Event.t -> unit;
    on_window : string -> (Event.t -> unit) -> unit -> unit;
    stop_propagation : Event.t -> unit;
    target_tag : Event.t -> string;
    shift_key : Event.t -> bool;
    alt_key : Event.t -> bool;
    navigate : string -> unit;
    focus : string -> unit;
    scroll_into_view : string -> unit;
  }

  val platform : platform ref
  (** The browser runtime installs its functions here. The default raises
      [Failure]. *)
end
