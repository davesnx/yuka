val owner : (unit -> 'a) -> 'a * (unit -> unit)
(** [owner f] runs [f] in a new owner. Effects and memos created during [f]
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

type trigger = [ `Idle | `Visible | `Interaction ]
(** An event that starts an island: the browser is idle, the island is
    visible, or the first interaction with it. *)

type loading = [ `Load | trigger | `Lazy of trigger ]
(** When the browser downloads and starts an island.
    - [`Load] (default): download and start when the page opens.
    - A trigger: download when the page opens, start at the trigger.
    - [`Lazy t]: download and start at the trigger [t]. Events before the
      start are recorded and replayed. The server prints no preload link for
      it.

    The early download of a non-lazy island happens through the
    [<link rel="modulepreload">] that the server prints when the app gives
    [?preload] to [Server.respond] (see [Server.preload_urls]). Without it,
    the island downloads when it starts. *)

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
  (** A number without ['.'], ['e'] or ['E'] that fits an [int] is [`Int].
      Arrays and objects nested more than 512 levels are an error. *)
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
(** Printed as JSON prints a float: [1.0], [2.5]. Not-a-number and the
    infinities are printed as [NaN], [Infinity] and [-Infinity]. *)

val format : ('a, unit, string, 'kind element) format4 -> 'a
(** [format "%d of %d" done total]: a text element made with [Printf]. *)

val list : 'kind element list -> 'kind element
(** The same as [fragment]. *)

val array : 'kind element array -> 'kind element

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

module Await : sig
  val make :
    async:'a Async.t ->
    loading:'k element ->
    ?failed:(string -> 'k element) ->
    children:('a -> 'k element) ->
    unit ->
    'k element
  (** Shows [loading] until the value is settled, then [children] applied to
      the value, or [failed message] (default: nothing). On the client it is
      a hole over [Async.watch]. On the server it is printed as a hole; see
      DESIGN.md. *)
end

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
  (** Made by [entry]. The island modules expose it as [register], for
      generated code only. *)

  type registry

  type lazy_entry

  val island :
    ?loading:loading ->
    name:string ->
    props:Json.t ->
    (unit -> client element) ->
    server element
  (** A client component placed in a server tree. The server prints its
      HTML and its props. *)

  val registry : ?lazy_entries:lazy_entry list -> entry list -> registry
  (** The islands of an app. For generated code: [yuka.ppx] and
      [yuka-islands] build it. Pass it to [Yuka.mount]. *)

  val entry :
    name:string ->
    (Json.t -> (unit -> client element, string) result) ->
    entry
  (** What the browser knows about an island: it decodes the props and gives
      the function that builds the component. *)

  type container
  (** A DOM element that holds a rendered tree. In a Melange entry, get one
      with an [external ... = "%identity"] binding of your own. *)

  type 'a promise
  (** A JavaScript promise, as made by a dynamic [import]. *)

  val promise_map : ('a -> 'b) -> 'a promise -> 'b promise

  val lazy_entry : name:string -> (unit -> entry promise) -> lazy_entry
  (** [lazy_entry ~name load]: an island whose code is loaded on demand.
      [load] is called, at most once, when the start strategy of an island
      named [name] fires, for example with a dynamic import of the module
      that defines the entry. If it fails, the island keeps its server HTML
      and the error is logged. *)

  val render : container -> (unit -> 'k element) -> unit -> unit
  (** [render container f] clears [container], builds the DOM of [f ()] and
      returns a function that stops all effects and handlers of this tree.
      The DOM stays in place. Browser only. *)

  val hydrate : container -> (unit -> 'k element) -> unit -> unit
  (** [hydrate container f] adopts the server DOM in [container] (written
      with the markers of DESIGN.md), attaches handlers and starts holes.
      Where the DOM does not match, it creates the missing nodes. Returns a
      function that stops all effects and handlers. Browser only. *)

  val start : ?lazy_entries:lazy_entry list -> entry list -> unit
  (** [start entries] installs the browser runtime and the action transport,
      then hydrates every [yuka-island] element of the document with the
      entry of the same name, following each island's start strategy. Props
      come from the [script] element with the same [data-yuka-props] id. It
      also watches the document, so islands that arrive later (streaming,
      fills) start when their props script is complete. An island that
      cannot start is logged with [console.error] and keeps its server HTML.
      An island is not started twice.

      The action transport sends [POST /_yuka/action/<name>] with the input
      as a JSON body. The response is [{"ok": value}] or
      [{"error": message}]. *)

  val stop : unit -> unit
  (** Stops every island that [start] started: effects, handlers and
      document listeners are removed, start strategies that did not fire yet
      are cancelled, and action requests in flight are aborted (their
      [Async] fails with ["cancelled"]). The DOM stays. [start] works again
      afterwards, for example on a new body. *)
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
        inside_island : bool;
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

  val session : streaming:bool -> islands_only:bool -> session
  (** With [islands_only], [print] writes hydration markers only inside an
      island. A pending streamed [Await] outside an island still writes
      [<!--[sN-->] and [<!--]-->], which the fill needs. *)

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

module Router : sig
  type ('a, 'r) t
  (** A path. ['a] is the type of the function that takes the parameters of the
      path, and ['r] is what that function returns. *)

  val root : ('r, 'r) t
  (** The path [/]. *)

  val s : string -> ('r, 'r) t
  (** A fixed segment. Raises [Invalid_argument] if the text is empty or holds
      a [/]. *)

  val string : (string -> 'r, 'r) t
  (** A segment taken as a string parameter. *)

  val int : (int -> 'r, 'r) t
  (** A segment taken as an int parameter. It matches an optional [-] and
      digits only. *)

  val ( / ) : ('a, 'b) t -> ('b, 'c) t -> ('a, 'c) t
  (** Joins two paths. [s "issue" / string] has type
      [(string -> 'r, 'r) t]. *)

  val href : ?query:(string * string) list -> ('a, string) t -> 'a
  (** [href path] is a function that takes the parameters and returns the URL.
      Parameters and query are percent-encoded. The URL starts with [/] and
      has no trailing slash, except [/] itself. *)

  val parse : ('a, 'r) t -> 'a -> string -> 'r option
  (** [parse path f target] matches a request target (path, with an optional
      query and fragment, which are ignored) against [path]. A trailing slash
      is ignored. Segments are percent-decoded. On a match it returns [f]
      applied to the parameters. *)

  val query : string -> (string * string) list
  (** The decoded query pairs of a request target ([+] is a space). *)

  type 'r case
  (** A path with the function that handles it. *)

  val case : ('a, 'r) t -> 'a -> 'r case

  val dispatch : 'r case list -> string -> 'r option
  (** The result of the first case that matches the target. *)

  val navigate : string -> unit
  (** [navigate url] loads [url] with the header [Yuka-Navigate: 1], stops
      the islands, replaces the content of [<body>] and [document.title] with
      those of the response, starts the islands again, pushes a history entry
      (after the page loaded) and scrolls to the fragment or to the top. A
      navigation started while another one loads aborts the first. If the
      request fails, the response is not 2xx or not [text/html], or it was
      redirected to another origin, it does [location.assign url]. Before [Yuka.mount], it does
      [location.assign url]. Browser only. *)
end

val mount : ?islands:Client.registry -> ?navigation:bool -> unit -> unit
(** [mount ()] is the whole client start. [yuka.ppx] rewrites it into
    [mount ~islands:Yuka_islands.registry ()]. It starts the islands. When
    [navigation] is true (default) it also takes over navigation:

    - A left click on an [<a href>] goes through [Router.navigate] unless:
      the event is already prevented, a modifier key is down, the link has a
      [target] other than [_self], a [download] attribute or a
      [data-yuka-reload] attribute, the URL is on another origin, or the URL
      differs from the current one only by its fragment.
    - [popstate] loads the entry's URL without pushing history.

    With [~navigation:false] only the islands start and links load full
    pages. Calling [mount] again is safe: the listeners are not added twice.
    Raises [Failure], naming [yuka.ppx], without [~islands] (the ppx did not
    run) or outside the browser. *)

module Server : sig
  val log_error : (string -> unit) ref
  (** Where [handle_action] reports an action that failed (the client only
      sees a generic message). Default: [prerr_endline]. *)

  val to_string : (unit -> server element) -> string
  (** The tree as HTML. Hydration markers are written only inside an island,
      because the browser hydrates nothing else. The function builds the tree
      with effects off, so component bodies do not run effects. *)

  val page :
    ?head:string ->
    ?early:bool ->
    ?import_map:(string * string) list ->
    ?title:string ->
    ?styles:string list ->
    ?scripts:string list ->
    (unit -> server element) ->
    string
  (** A full HTML document. [styles] are stylesheet URLs, [scripts] are
      module script URLs. [head] is raw HTML added inside the head.
      [import_map] is written as an import map script before any other
      script. With [early], module scripts get the [async] attribute, so
      they run while the stream continues. *)

  val import_map : url:string -> string list -> (string * string) list
  (** [import_map ~url packages] maps ["pkg/"] to ["url/node_modules/pkg/"]
      for each package name (scoped ones as [@scope/name]), in the given
      order, for the [import_map] option of [page]. The app lists the
      packages; this function does not read the file system. *)

  val fill_script : string
  (** [Internal.fill_script]. *)

  val stream :
    ?head:string ->
    ?early:bool ->
    ?import_map:(string * string) list ->
    ?timeout:float ->
    ?title:string ->
    ?styles:string list ->
    ?scripts:string list ->
    ?preload:(string -> string option) ->
    sleep:(float -> unit Async.t) ->
    write:(string -> unit Async.t) ->
    (unit -> server element) ->
    unit Async.t
  (** Writes the document head and the shell at once. For each pending
      [await] and each pending [Codec.async] value, it writes a chunk when
      the value settles, in settle order, including parts that appear in
      streamed content. It ends when all have settled, or after [timeout]
      seconds (default 10, measured with [sleep]): then each pending await
      is filled with its [failed] element for the message [timeout], each
      pending async value gets [{error: timeout}], and the stream ends.
      Writes are sequenced: a chunk is written after the previous write
      finished. The result fails if a write fails. *)

  val render_settled :
    ?timeout:float ->
    ?preload:(string -> string option) ->
    sleep:(float -> unit Async.t) ->
    (unit -> server element) ->
    string Async.t
  (** Waits until every pending value settled (or [timeout]) and returns
      the HTML as [to_string] would print it had the values been settled at
      print time, followed by the scripts of the async props. *)

  val respond :
    ?navigating:bool ->
    ?head:string ->
    ?early:bool ->
    ?import_map:(string * string) list ->
    ?timeout:float ->
    ?title:string ->
    ?styles:string list ->
    ?scripts:string list ->
    ?preload:(string -> string option) ->
    sleep:(float -> unit Async.t) ->
    write:(string -> unit Async.t) ->
    (unit -> server element) ->
    unit Async.t
  (** [stream], or, when [navigating] (the request had [Yuka-Navigate: 1]),
      the whole page settled in one [write]: a full document without the
      fill script, whose body is [render_settled]. The app sets the status
      and the header [Vary: Yuka-Navigate]. *)

  val preload_urls :
    manifest:string ->
    base:string ->
    ?metafile:string ->
    unit ->
    string ->
    string option
  (** [preload_urls ~manifest ~base ()] makes the [preload] function of
      [stream], [render_settled] and [respond]. [manifest] is the JSON text
      [{"<island name>": "<path>"}] that [yuka-islands --manifest] prints;
      each path is relative to the emit directory, and a leading [./] is
      removed. Without [metafile] the URL is [base ^ path]. With [metafile],
      the esbuild metafile JSON text, the URL is [base ^ file] where [file]
      is the key in its [outputs] whose [entryPoint] equals the path (a
      leading [./] removed on both). There is no looser match: esbuild must
      run from the directory the manifest paths are relative to. Output keys
      keep their directory (for example [dist/lazy_one-3F2A.js]), so choose
      [base] for that. An island with no path, or no matching output, has no
      URL. Raises [Invalid_argument] when
      the manifest or the metafile is not the expected JSON.

      The server prints [<link rel="modulepreload" href="URL">] before the
      first [<yuka-island>] of each island name whose [loading] is not
      [`Lazy _], once per response. *)

  module Action : sig
    val implement : ('i, 'o) Action.t -> ('i -> 'o Async.t) -> unit
    (** Registers the implementation of a declared action, and makes
        [Action.call] run it directly on the server. Raises
        [Invalid_argument] if the name is already implemented. *)

    val reject : string -> 'a
    (** Raised inside an implementation to refuse the input:
        [handle_action] answers 400 [{"error": message}] and [Action.call]
        on the server fails with the message. Any other exception or failed
        [Async] is a 500 with a generic message. *)

    val rejected : string -> 'a Async.t
    (** Like [reject], for use after a wait (in an [Async] chain). *)
  end

  val handle_action :
    name:string ->
    content_type:string option ->
    origin:string option ->
    host:string option ->
    body:string ->
    (int * string) Async.t
  (** Runs the action [name] for a request [POST /_yuka/action/:name] and
      returns the status and the JSON body. [body] is the JSON input. The
      answer is [{"ok": output}] (200) or [{"error": message}] with 403
      (origin differs from host), 404 (unknown action), 415 (content type
      is not application/json), 413 (body over 1 MiB), 400 (bad JSON, bad
      input, or [reject]) or 500 (the implementation failed; the message is
      generic and the failure goes to [log_error]). Checks run in this
      order. *)
end
