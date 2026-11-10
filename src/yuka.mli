val owner : (unit -> 'a) -> 'a * (unit -> unit)
(** [owner f] runs [f] in a new owner. Effects and memos created during [f]
    belong to it. The returned function disposes all of them: it stops the
    effects and runs their cleanups. *)

module State : sig
  type ('a, 'access) signal
  (** A value that tracks its readers. ['access] is [[ `Write ]] for a State
      made with {!make} and [[ `Read ]] for a {!memo}. A function that only
      reads takes [('a, _) signal] and accepts both. *)

  type 'a t = ('a, [ `Write ]) signal
  (** A State that {!set} and {!update} can write. *)

  type 'a read = ('a, [ `Read ]) signal
  (** A read-only State: {!set} and {!update} on it do not compile. *)

  val make : ?equal:('a -> 'a -> bool) -> 'a -> 'a t
  (** [equal] decides whether a write is a change. Default: identity, as
      JavaScript [===]: the same value ([==]), or two ints, chars, bools,
      constant constructors, strings or floats with the same value. A new
      record, tuple, list, array or constructor with arguments is a change
      even when its contents are equal; pass [~equal:( = )] for structural
      equality. The default never raises, also for functional values. In the
      browser, [Some x] is [x] itself, so a new [Some x] that wraps the same
      [x] is not a change there; on native it is. An exception raised by
      [equal] counts as a change. *)

  val get : ('a, _) signal -> 'a
  (** Reads the value. Inside an effect or a memo, the read is tracked. *)

  val peek : ('a, _) signal -> 'a
  (** Reads the value without tracking. *)

  val set : 'a t -> 'a -> unit
  (** Writes the value. *)

  val update : 'a t -> ('a -> 'a) -> unit
  (** Like [set], with a function of the current value. *)

  val memo : ?equal:('a -> 'a -> bool) -> (unit -> 'a) -> 'a read
  (** A derived value. It recomputes when a State it read changes. A
      recompute is a change only if [equal] says the new value differs.
      Default: the same equality as {!make}. *)
end

val batch : (unit -> 'a) -> 'a
(** [batch f] runs [f] and returns its result. Effects that writes in [f]
    make pending run once, after [f] returns, not after each write. Memos
    read inside [f] are up to date. A [batch] inside a [batch] (or inside an
    effect) runs its pending effects when the outermost one ends. When [f]
    raises, the pending effects still run, then the exception of [f] is
    raised again. Event handlers are not batched: each [State.set] in a
    handler updates the DOM before the next line runs. *)

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
    ?equal:('a -> 'a -> bool) -> ('a, _) State.signal -> (prev:'a -> next:'a -> unit) -> unit
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
    [<link rel="modulepreload">] that the server prints from the manifest
    given to [Server.modules] or [Server.bundle]. An island without a
    manifest entry downloads when it starts. *)

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
  val watch : 'a t -> 'a status State.read
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
      [{"$async":"aN","ok":v}] or [{"$async":"aN","error":"failed"}]. In a
      streaming render, a pending value is written as [{"$async":"aN"}] and
      the stream writes its value later, or [{"error":"failed"}] if it fails.
      A failure message goes to [Server.log_error] and never into the page,
      except for a [Server.Action.reject] message, which is sent. Outside a streaming render, a pending value is
      written as [{"$async":"aN","error":"pending at render"}]. Decoding a
      bare reference gives, after [mount], the value that the page writes
      for that id; before [mount] or outside the browser, a failed
      [Async]. *)

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

module Template : sig
  (** A compiled element tree. The ppx makes one [t] per lowercase JSX tree
      (at the top of the module) and one [instance] per evaluation. Part
      numbers count from 0 in the order of [parts]. See "Templates" in
      DESIGN.md. *)

  type t
  type shape
  type attr
  type 'kind part

  val text : string -> shape
  val element : string -> attr list -> shape list -> shape
  val part : int -> shape
  (** The child at this place is part [i], made with [child]. *)

  val fixed : string -> string -> attr
  val part_attr : int -> attr
  (** The attribute at this place is part [i], made with [attribute] or
      [attribute_option]. *)

  val make :
    shape ->
    html:string ->
    walk:int array ->
    kids:int array ->
    attrs:int array ->
    values:(int * string) array ->
    t
  (** [make shape ~html ~walk ~kids ~attrs ~values]: the ppx computes all
      arguments but [shape] from [shape] at build time. [html] is the HTML of
      the shape without its parts; the other arguments are the paths from the
      template root to its parts. The ppx writes this call. *)

  val child : 'kind element -> 'kind part
  val attribute : 'kind attribute -> 'kind part
  val attribute_option : 'kind attribute option -> 'kind part

  val instance : t -> 'kind part array -> 'kind element
  (** The tree of [t] with its parts filled in. It prints and hydrates as the
      same tree made with [lower]. Fresh client creation parses [html] of
      [make] once, clones it and goes to each part with the paths of
      [make]. *)
end

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
    changed. Default [equal]: identity, as in {!State.make}. *)

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
      Where the DOM does not match, it creates the missing nodes. Unless the bundler
      defines [__YUKA_DEV__] as [false], each mismatch (a missing node,
      another tag, another text, an extra node) logs one [console.warn] with
      the island name, the expected and the found node, and a short path. Returns a function
      that stops all effects and handlers. Browser only. *)

end

module Action : sig
  type ('i, 'o) t

  val declare :
    name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o) t

  val name : ('i, 'o) t -> string

  val call : ('i, 'o) t -> 'i -> 'o Async.t
  (** Encodes the input, sends it to the server (in the browser after
      [mount], as [POST /_yuka/action/<name>]; on the server, to the
      implementation), decodes the output. A decode error is [Failed]. *)
end

module Browser : sig
  val on_window : string -> (Event.t -> unit) -> unit
  (** Listens on [window] until the current owner is disposed. Browser only:
      call it inside [Effect.run]. *)

  val navigate : string -> unit
  (** Loads the URL. After [mount] with navigation (the default), it is a
      client navigation, as a click on a link; see {!mount}. Otherwise it
      does [location.assign url]. *)

  val focus : string -> unit
  (** Focuses the element with this id. *)

  val scroll_into_view : string -> unit
  (** Scrolls the element with this id into view. *)
end

(**/**)

module Private : sig
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
    | Template of { template : template; parts : part array }
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

  and template = Template.t
  and part = Child of node | Attribute of attr | No_attribute

  type shape =
    | Fixed_text of string
    | Fixed_element of { tag : string; attrs : fixed_attr list; children : shape list }
    | Part of int

  and fixed_attr = Fixed of string * string | Part_attr of int

  val template_shape : template -> shape

  val template : Template.shape -> template
  (** A template made at run time: its HTML and paths are computed from the
      shape with the code that the ppx runs at build time. For tests and
      hand-written trees. *)

  val recompile : template -> template
  (** [template (template_shape t)]: the template again, with its HTML and
      paths computed at run time. Tests compare it with what the ppx
      emitted. *)

  val template_plan :
    template -> int array * int array * int array * (int * string) array
  (** The [walk], [kids], [attrs] and [values] given to [Template.make]. *)

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

  val template_html : template -> string
  (** The [html] given to [Template.make]: the HTML of a template without
      its parts, elements, fixed attributes and texts as [to_html] prints
      them. A part writes nothing. Two texts with only parts between them get
      [<!---->]. Static [value] on [select] and [textarea] follows the rules
      of [to_html]. *)

  val expand : template -> part array -> node
  (** The tree of a template instance, as [lower] would make it. *)

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

  val has_readers : ('a, _) State.signal -> bool
  (** Whether an effect or a memo reads the State. For tests. *)

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
  (** The streamed document that the request cycle sends, for tests. *)

  val settled :
    ?timeout:float ->
    ?preload:(string -> string option) ->
    sleep:(float -> unit Async.t) ->
    (unit -> server element) ->
    string Async.t
  (** The settled body that the cycle sends for [Yuka-Navigate], for tests. *)

  val import_map : url:string -> string list -> (string * string) list

  val query : string -> (string * string) list
  (** The decoded query pairs of a request target, as the cycle reads them
      ([+] is a space). *)

  val preload_urls :
    manifest:string -> base:string -> ?metafile:string -> unit -> string -> string option

  val handle_action :
    name:string ->
    content_type:string option ->
    origin:string option ->
    host:string option ->
    body:string ->
    (int * string) Async.t
end

(**/**)

module Router : sig
  (** The members that the code generated by [yuka-routes] calls: the
      shared [Routes] module (route type, [href], [find]) is written from
      [Routes.mlx]. See "Routes" in the README. *)

  type meth =
    [ `GET | `HEAD | `POST | `PUT | `PATCH | `DELETE | `OPTIONS | `Other of string ]
  (** A request method. *)

  (** The result of the generated [Routes.find]. *)
  type 'r lookup =
    | Found of 'r  (** A node matches the path and the method. *)
    | Wrong_method of meth list
        (** A node matches the path but not the method. The list holds the
            methods of the path, in file order. [`GET] stands for [`HEAD]
            too. *)
    | Redirect of { permanent : bool; location : string }
        (** A redirect node matches the path. [location] has its params
            substituted and encoded. *)
    | Missing  (** No node matches, or a param does not decode. *)

  (** A custom param or search type, written [:id<M>] in a path. *)
  module type PARAM = sig
    type t

    val of_string : string -> t option
    (** [None] means the path does not match. *)

    val to_string : t -> string
  end

  val encode : string -> string
  (** Percent-encodes one path segment or one query part. Only
      [A-Z a-z 0-9 - . _ ~] stay as they are. *)

  val segment : string -> string
  (** [encode] for one path segment that [href] writes. Raises
      [Invalid_argument] on [""], ["."] and [".."]: the request cycle drops
      empty segments and browsers resolve dot segments (also written
      [%2E]), so no URL can give them back. *)

  val segments : string list -> string
  (** A catch-all for [href]: ["/"] and {!segment} of each element. Raises
      [Invalid_argument] on [[]], since a catch-all matches one segment or
      more, and on an element that {!segment} refuses. *)

  val int_param : string -> int option
  (** Decodes an [int] param in the form [string_of_int] writes: [0], or an
      optional [-] and digits without a leading [0], within the range of
      [int]. So each value has one URL: [01], [-0] and [+1] give [None]. *)

  val search : (string * string) list -> string -> string list
  (** [search query key] is every value of [key] in the decoded query pairs,
      in order. *)
end

val mount : ?islands:Client.registry -> ?navigation:bool -> unit -> unit
(** [mount ()] is the whole client start. [yuka.ppx] rewrites it into
    [mount ~islands:Yuka_islands.registry ()].

    It installs the browser runtime and the action transport, then hydrates
    every [yuka-island] element of the document with the entry of the same
    name, following each island's start strategy. Props come from the
    [script] element with the same [data-yuka-props] id. It also watches the
    document, so islands that arrive later (streaming, fills) start when
    their props script is complete. An island that cannot start is logged
    with [console.error] and keeps its server HTML. An island is not started
    twice. The action transport sends [POST /_yuka/action/<name>] with the
    input as a JSON body. The response is [{"ok": value}] or
    [{"error": message}].

    When [navigation] is true (default) it also takes over navigation:

    - A left click on an [<a href>] is a client navigation unless: the
      event is already prevented, a modifier key is down, the link has a
      [target] other than [_self], a [download] attribute or a
      [data-yuka-reload] attribute, the URL is on another origin, or the URL
      differs from the current one only by its fragment.
    - [popstate] loads the entry's URL without pushing history.
    - {!Browser.navigate} is a client navigation.

    A client navigation loads the URL with the header [Yuka-Navigate: 1],
    stops the islands, replaces the content of [<body>] and [document.title]
    with those of the response, starts the islands again, pushes a history
    entry (after the page loaded) and scrolls to the fragment or to the top.
    A navigation started while another one loads aborts the first. If the
    request fails, the response is not 2xx or not [text/html], or it was
    redirected to another origin, it does [location.assign url].

    With [~navigation:false] only the islands start and links load full
    pages. Calling [mount] again is safe: the listeners are not added twice.
    Raises [Failure], naming [yuka.ppx], without [~islands] (the ppx did not
    run) or outside the browser.

    Only an app that calls [mount] contains the island, action and
    navigation code. *)

val unmount : unit -> unit
(** Stops every island that [mount] started: effects, handlers and document
    listeners are removed, start strategies that did not fire yet are
    cancelled, and action requests in flight are aborted (their [Async]
    fails with ["cancelled"]). It also stops navigation: the [click] and
    [popstate] listeners are removed, a navigation in flight is aborted, and
    {!Browser.navigate} does [location.assign] again. The DOM stays.
    [mount] works again afterwards, for example on a new body. *)

module Server : sig
  val log_error : (string -> unit) ref
  (** Where the server reports what the client must not see: an action
      that failed, a failed render, a failed async value. Default:
      [prerr_endline]. *)

  val to_string : (unit -> server element) -> string
  (** The tree as HTML. Hydration markers are written only inside an island,
      because the browser hydrates nothing else. The function builds the tree
      with effects off, so component bodies do not run effects. *)

  val document :
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

  val fill_script : string
  (** The inline script that the request cycle writes in the head when the
      shell has a pending [await]. It defines [window.__yukaFill(id)], which
      replaces the loading content between the markers of [id] with the
      streamed chunk. *)

  module Action : sig
    val implement : ('i, 'o) Action.t -> ('i -> 'o Async.t) -> unit
    (** Registers the implementation of a declared action, and makes
        [Action.call] run it directly on the server. Raises
        [Invalid_argument] if the name is already implemented. *)

    val reject : string -> 'a
    (** Raised inside an implementation to refuse the input:
        the action call answers 400 [{"error": message}] and [Action.call]
        on the server fails with the message. Any other exception or failed
        [Async] is a 500 with a generic message. *)

    val rejected : string -> 'a Async.t
    (** Like [reject], for use after a wait (in an [Async] chain). *)
  end

  (** {2 Request cycle}

      The types and functions that the code generated by [yuka-routes
      --server] calls, and the request cycle that answers a request with
      them. The cycle has no server dependency: a server implements
      {!ADAPTER}. See "Request cycle" in DESIGN.md. *)

  (** Why a guard or a loader stops a request. *)
  type stop =
    | Not_found  (** The not-found page of the route, status 404. *)
    | Redirect of { status : int; location : string }
        (** A response with this status (303, 307 or 308) and [location],
            and no body. *)
    | Fail of string
        (** The error page, status 500. The message goes to [log_error],
            never to the page. *)

  type page
  (** What a page function returns: a title, extra head HTML and the body. *)

  val page : ?title:string -> ?head:string -> (unit -> server element) -> page
  (** [page ~title body]. The cycle calls [body] only when it renders: never
      for [HEAD]. [head] is raw HTML added to the document head. *)

  type layer = { key : string; wrap : server element -> server element }
  (** A layout on the path of a route. [key] names its outlet; [wrap] puts
      the layout around its children. *)

  type plan = { layers : layer list; page : page }
  (** What a page route renders. [layers] are outermost first. *)

  (** The [cache-control] value of a route rule. *)
  type cache =
    | No_store  (** [no-store] *)
    | Private of { max_age : int }  (** [private, max-age=N] *)
    | Public of { max_age : int; s_max_age : int option }
        (** [public, max-age=N], and [, s-maxage=M] when given *)
    | Immutable  (** [public, max-age=31536000, immutable] *)

  type rules
  (** The merged route rules of one node. *)

  val rules :
    headers:(string * string) list list -> ?cache:cache -> prerender:bool -> unit -> rules
  (** [headers] holds one list per node from the root down. Later lists are
      added after earlier ones; for one header name (case-insensitive), the
      last value wins. *)

  type body =
    | String of string
    | Stream of ((string -> unit Async.t) -> unit Async.t)
        (** The adapter calls the function with its write function and ends
            the response when the result settles. *)

  type response = { status : int; headers : (string * string) list; body : body }

  val text : ?status:int -> ?headers:(string * string) list -> string -> response Async.t
  (** A [text/plain; charset=utf-8] response. Default status: 200. A
      [content-type] in [headers] replaces the default one. *)

  val html : ?status:int -> ?headers:(string * string) list -> string -> response Async.t
  (** Like {!text}, with [text/html; charset=utf-8]. *)

  val json : ?status:int -> ?headers:(string * string) list -> Json.t -> response Async.t
  (** Like {!text}, with [application/json]. *)

  val see_other : string -> response Async.t
  (** 303 to the location, no body. *)

  type fallback = { layers : layer list; not_found : string -> page; error : int -> page }
  (** The pages for a 404 ([not_found] gets the request path) and a 500
      ([error] gets the status), inside [layers]. *)

  val default_not_found : string -> page
  (** An [<h1>Not Found</h1>] page, for a [Routes.mlx] without [not_found]. *)

  val default_error : int -> page
  (** An [<h1>Internal Server Error</h1>] page, for a [Routes.mlx] without
      [error]. *)

  (** What a matched route runs. *)
  type target =
    | Page of {
        rules : rules;
        guards : (unit -> (unit, stop) result Async.t) list;  (** Parent first. *)
        load : unit -> (plan, stop) result Async.t;
        fallback : fallback;
      }
    | Handler of {
        rules : rules;
        same_origin : bool;  (** True for an [Action]: 403 for a foreign [Origin]. *)
        guards : (unit -> (unit, stop) result Async.t) list;
        run : unit -> response Async.t;
      }

  val loaded :
    ('a, stop) result Async.t -> ('a -> ('b, stop) result Async.t) -> ('b, stop) result Async.t
  (** Chains a loader result. An [Error], a failed [Async] or an exception
      of the function gives an [Error]; the last two give [Fail]. *)

  type 'req app
  (** The routes of an app. ['req] is the request type of the adapter: the
      generated code passes the request to each loader, guard and handler. *)

  val app :
    build:string ->
    headers:(string * string) list ->
    prerender:string list ->
    find:(Router.meth -> string list -> (string * string) list -> 'r Router.lookup) ->
    resolve:('req -> 'r -> target) ->
    missing:fallback ->
    'req app
  (** [build] is a digest of the route tree. [headers] are the rule headers
      of the root, sent with every 404 and 500 page. [prerender] lists the
      paths of the nodes with no param whose rules say [prerender]: where
      {!prerender_seeds} starts. [missing] gives the page when no route
      matches. *)

  val build_id : 'req app -> string

  type assets
  (** Where the client JavaScript is. The cycle serves it under [/_yuka/]. *)

  val modules :
    dir:string -> entry:string -> manifest:string -> packages:string list -> assets
  (** The Melange module tree. [dir] is the emit directory, [entry] the path
      of the entry module in it (served as [/_yuka/<entry>]), [manifest] the
      JSON text that [yuka-islands --manifest] prints (paths relative to the
      directory of [entry]), and [packages] the npm packages under
      [dir/node_modules] for the import map. Files get
      [cache-control: no-cache]. *)

  val bundle :
    dir:string -> entry:string -> manifest:string -> metafile:string -> assets
  (** An esbuild bundle. [dir] is the directory esbuild ran in, so that the
      [outputs] keys of the [metafile] JSON text are paths in it; [entry] is
      the path of the entry output. Outputs other than [entry] get
      [Immutable]; other files get [no-cache]. Raises [Invalid_argument]
      when [manifest] or [metafile] is not valid JSON of that shape. *)

  type config

  val config :
    ?assets:assets ->
    ?public:(string * string) list ->
    ?prerendered:string ->
    ?styles:string list ->
    ?head:string ->
    ?timeout:float ->
    unit ->
    config
  (** [public] maps URL prefixes to directories ([("/static", "static")]).
      A prefix with no segment (["/"]) raises [Invalid_argument]: files
      under a prefix are never routed, so it would hide every route.
      [prerendered] is the directory that a prerender wrote: a [GET] or
      [HEAD] of a page whose rules say [prerender], without a query and
      without [Yuka-Navigate], is answered with its file there when the file
      exists ({!prerender_file}), after the guards and instead of the
      loaders. [styles] are stylesheet URLs and [head] raw HTML for the head
      of every page. [timeout] (default 10 seconds) bounds a streamed
      render. *)

  val served_dirs : config -> (string * string) list
  (** The URL prefixes and directories that the cycle serves files from:
      [("/_yuka", dir)] of [assets], then each [public] prefix. A
      prerender copies them. *)

  type request = {
    meth : Router.meth;
    target : string;  (** Path and query, as sent. *)
    header : string -> string option;  (** Case-insensitive. *)
    body : unit -> string Async.t;
  }
  (** What the cycle reads from a request. *)

  type outcome =
    | Respond of response
    | File of { root : string; path : string; headers : (string * string) list }
        (** Send the file [root/path] with [headers], or 404 with
            [cache-control: no-store] when it does not exist. [path] has no
            empty, [.] or [..] segment. *)

  val handle :
    config ->
    'req app ->
    sleep:(float -> unit Async.t) ->
    exists:(root:string -> path:string -> bool) ->
    'req ->
    request ->
    outcome Async.t
  (** Answers one request. [exists] tells whether a file is there
      ({!ADAPTER.exists}). Steps, in this order:

      + [/_yuka/action/<name>]: the action call ([POST] with a JSON body;
        answers as described for {!Action.reject}), else 405.
        [/_yuka/<file>]: the file of [assets] for [GET] and [HEAD], else
        405; a [.] or [..] segment, or no [assets], gives a plain 404 with
        [no-store]. A path under a [public] prefix: the file of its
        directory, by the same rules. These paths are never routed.
      + A path with a trailing slash or an empty segment: 308 to the path
        without them, query kept.
      + [find] with the percent-decoded segments and the query pairs.
      + [Redirect]: 308 (permanent) or 307, query kept.
      + [Missing]: the [missing] page, 404. [Wrong_method]: 405 with
        [allow] (the methods, [HEAD] after [GET], then [OPTIONS]); for
        [OPTIONS], 204 with the same [allow].
      + Guards, one after another. A {!stop} skips the rest.
      + A handler with [same_origin]: 403 when [Origin] differs from [Host].
      + A handler: its response, after the rule headers (the handler's win)
        and the rule [cache-control] unless it set one. [HEAD]: no body.
      + A page: the prerendered file when [config] has [prerendered] and
        it applies; else [load], then status 200 with the rule headers,
        [content-type], [vary: Yuka-Navigate] and the rule
        [cache-control]. [HEAD] stops here, with no body.
      + The document, streamed. Each layer's children are inside
        [<yuka-outlet data-k="KEY" style="display:contents">]. The entry
        module script is written once, before the first island, and
        {!fill_script} only when the shell has a pending [await], so a page
        without islands or pending [await] loads no JavaScript. An [<a>] whose [href] is the
        request path gets [aria-current="page"], except inside an island,
        whose markup must match the client render. With a [Yuka-Navigate]
        header, the settled document in one string.

      A 404 or 500 page has the root [headers] and [no-store]. A failure
      before the response is returned (shell, or a fill that already
      failed) gives the 500 page. After it the status is sent: the failure
      goes to [log_error], nothing more is written (no [</body></html>]),
      and the [Stream] function's [Async] succeeds once the writes already
      started have finished, so the adapter ends the response normally.
      When the error page itself fails, the answer is a plain-text 500.
      Every answer to [HEAD] has an empty body: for a file, the cycle
      answers 200 with the headers it knows (no [content-type] for a client
      or public file) when [exists] says so, else the plain 404.

      A {!stop} [Redirect] must use 301, 302, 303, 307 or 308 and a
      location without CR or LF; otherwise it is a logged 500. An [Action]
      always sends [cache-control: no-store]; a handler response that is
      not 2xx gets [no-store] unless it set [cache-control]. [vary] values
      are joined. A path with a literal backslash is the 404 page. *)

  type http_response = response

  (** What a server provides to run the cycle. *)
  module type ADAPTER = sig
    type request
    type response
    type 'a io

    val meth : request -> Router.meth
    val target : request -> string
    val header : request -> string -> string option
    (** Case-insensitive. *)

    val body : request -> string Async.t
    val respond : http_response -> response io
    (** Sends the status, the headers and the body; a [Stream] body is
        written as it comes. *)

    val file : request -> root:string -> path:string -> headers:(string * string) list -> response io
    (** Sends a file, or 404 with [cache-control: no-store]. *)

    val exists : root:string -> path:string -> bool
    (** Whether the file [root/path] exists. The cycle asks it for a
        prerendered page and to answer [HEAD] on a file without sending the
        file. *)

    val of_async : 'a Async.t -> 'a io
    val bind : 'a io -> ('a -> 'b io) -> 'b io
    val sleep : float -> unit Async.t
  end

  module Make (A : ADAPTER) : sig
    val handler : config -> A.request app -> A.request -> A.response A.io
  end

  (** {2 Prerender}

      The pure parts of a prerender; [Yuka_dream.prerender] runs them with
      a server. *)

  val prerender_seeds : 'req app -> string list
  (** The [prerender] paths of {!val-app}. *)

  val prerenderable : config -> 'req app -> 'req -> string -> bool
  (** Whether a [GET] of this path matches a page or an endpoint whose
      rules say [prerender]. A path that {!handle} serves as a file
      ([/_yuka/], a [public] prefix) is not, even when a route such as a
      catch-all would match it. The query and fragment are ignored. *)

  val links : string -> string list
  (** The paths of the links of an HTML text: each [href="/..."], entities
      decoded, query and fragment removed, once each, in order. A link to
      another origin ([//host]) is not one. *)

  val prerender_file : string -> string option
  (** The file of a path, relative to the output directory: [/] gives
      [index.html], [/a/b] gives [a/b/index.html], and a last segment with
      a [.] ([/feed.xml]) gives [feed.xml]. Segments are percent-decoded;
      the query and fragment are ignored. [None] when a segment is empty,
      [.] or [..], or holds a slash, a backslash or a NUL byte after
      decoding. *)

  val missing_page : config -> 'req app -> sleep:(float -> unit Async.t) -> response Async.t
  (** The 404 page of the app, as for an unknown path: the [404.html] of a
      prerender. *)
end
