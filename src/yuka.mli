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
      previous run are disposed. Inside a {!Catch} or an island, an exception
      in the body, or in a cleanup that runs during a State change or an
      event handler, goes to that boundary. A cleanup that raises when its
      owner is disposed by a direct call (the function returned by {!owner},
      {!Client.hydrate}, or {!unmount}) raises to that
      caller. Elsewhere, an exception in one effect does not stop other
      effects; the first one is raised again after all pending effects
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

  val return : 'a -> 'a t
  (** A value that is already [Done]. *)

  val failed : string -> 'a t
  (** A value that is already [Failed] with this message. *)

  val status : 'a t -> 'a status
  (** The status now. *)

  val on_settled : 'a t -> ('a status -> unit) -> unit
  (** Callbacks run in registration order; now, if already settled. *)

  val on_result : 'a t -> (('a, string) result -> unit) -> unit
  (** Like [on_settled], without the [Pending] case. *)

  val map : ('a -> 'b) -> 'a t -> 'b t
  (** Applies the function to the value when it is [Done]. A failure stays a
      failure with the same message. *)

  val bind : 'a t -> ('a -> 'b t) -> 'b t
  (** Like [map], with a function that gives an [Async]. *)

  val watch : 'a t -> 'a status State.read
  (** A State that follows the status. *)
end

module Codec : sig
  type 'a t = { encode : 'a -> Json.t; decode : Json.t -> ('a, string) result }

  val int : int t
  (** [`Int]. *)

  val float : float t
  (** Decoding accepts [`Int] too. *)

  val string : string t
  (** [`String]. *)

  val bool : bool t
  (** [`Bool]. *)

  val unit : unit t
  (** [`Null]. *)

  val list : 'a t -> 'a list t
  (** [`List]. Decoding stops at the first element that fails. *)

  val array : 'a t -> 'a array t
  (** As [list]. *)

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
      A failure message goes to the [log_error] of {!Server.config} and never into the page,
      except for a [Server.Action.reject] message, which is sent. Outside a streaming render, a pending value is
      written as [{"$async":"aN","error":"pending at render"}]. Decoding a
      bare reference gives, after [render ~islands], the value that the page
      writes for that id; before it or outside the browser, a failed
      [Async]. *)

  val encode : 'a t -> 'a -> Json.t
  (** [encode c v] is [c.encode v]. *)

  val decode : 'a t -> Json.t -> ('a, string) result
  (** [decode c j] is [c.decode j]. The error names the expected kind and
      the start of the JSON text. *)
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
  (** The [value] property of the event target. *)

  val target_checked : t -> bool
  (** The [checked] property of the event target. *)

  val key : t -> string
  (** The [key] of a keyboard event. *)

  val meta_key : t -> bool
  (** Whether the Meta key was down. *)

  val ctrl_key : t -> bool
  (** Whether the Control key was down. *)

  val prevent_default : t -> unit
  (** Calls [preventDefault] on the event. *)

  val stop_propagation : t -> unit
  (** Stops the event: no other Yuka handler of an outer element receives
      it, and it does not propagate in the DOM. *)

  val target_tag : t -> string
  (** The lowercase tag name of the event target. *)

  val shift_key : t -> bool
  (** Whether the Shift key was down. *)

  val alt_key : t -> bool
  (** Whether the Alt key was down. *)
end

val text : string -> 'kind element
(** A text node. The server escapes it. *)

val int : int -> 'kind element
(** The text of [string_of_int]. *)

val float : float -> 'kind element
(** Printed as JSON prints a float: [1.0], [2.5]. Not-a-number and the
    infinities are printed as [NaN], [Infinity] and [-Infinity]. *)

val list : 'kind element list -> 'kind element
(** The same as [fragment]. *)

val array : 'kind element array -> 'kind element
(** Like [list], for an array. *)

val empty : 'kind element
(** Nothing. *)

val fragment : 'kind element list -> 'kind element
(** The elements one after another, with no wrapper element. *)

val lower : string -> 'kind attribute list -> 'kind element list -> 'kind element
(** [lower tag attributes children]: an HTML element. The ppx makes it from
    [<tag ...>]. [tag] is a letter followed by letters, digits and [-],
    else [Invalid_argument] when the server prints it (the DOM refuses it in
    the browser). A [script] or [style] element (any case) takes no child,
    one {!text} or one {!hole} that gives a text, else [Invalid_argument]
    (server and client); the ppx joins the texts of [<script>] and
    [<style>] into one. In HTML the server prints that text as written (no
    HTML escaping), with every [</] printed as [<\/] and, in a JavaScript
    [script], [<!--] as [<\!--]; in a [script] of another [type] (JSON,
    import map, template), every [<] is printed as [\u003c]. Inside [svg]
    and [math] (but not in the [foreignObject] of an [svg]), and inside
    [select], the text is escaped. *)

val attr : string -> string -> 'kind attribute
(** [attr name value]: an attribute with a fixed value. The server escapes
    the value. URL check, for every attribute the server prints and the
    browser sets, with the element: the value of a URL attribute ([href], [src], [action],
    [formaction], [xlink:href], [poster], [cite], [data], [background],
    [longdesc], [manifest], [codebase], [icon], any case; [values], [to],
    [from], [by] of SVG animations) is read as the browser does (leading
    spaces and control characters dropped, tabs and newlines dropped, any
    case). A [javascript:] or [vbscript:] URL becomes
    ["about:blank#blocked"]; so does a [data:] URL where it would load or
    open a document ([href] of [a], [area] and [use], [action],
    [formaction], [xlink:href], [src] of [iframe], [frame], [embed] and
    [object], [data] of [object]). A [data:] image or media URL stays. The server logs the
    first block with the [log_error] of {!Server.config}; a dev build logs the first one in
    the console. [data:] is also blocked on [src] of [script] and [href] of
    [script]. [srcdoc] of [iframe] and [href] of
    [base] become [""] and are logged the same way; only a literal one in
    [.mlx] is kept. A [name] that is empty, starts with [on] (any case:
    use {!on}), or has a space, a control character, a quote, [<], [>], [/]
    or [=] raises [Invalid_argument] (in the browser here, on the server
    when printed). *)

(**/**)

val attr_unchecked : string -> string -> 'kind attribute
val hole_attr_unchecked : string -> (unit -> string option) -> client attribute
(** For the ppx, for names it proved are not URL attributes. They raise on a
    URL attribute name, [srcdoc], or a name that {!attr} refuses (an [on]
    name too). *)

val url_attr : string -> string -> string -> 'kind attribute
val url_hole_attr : string -> string -> (unit -> string option) -> client attribute
(** For the ppx: [url_attr tag name value] is {!attr} that knows the
    element. *)

(**/**)

val hole : (unit -> client element) -> client element
(** A part that changes after the first render. The function runs once; it
    runs again when a State it read changes, and its output replaces the old
    output. *)

val hole_attr : string -> (unit -> string option) -> client attribute
(** An attribute whose value changes. [None] removes the attribute. On the
    client, [value], [checked] and [selected] are set as properties. A URL
    attribute gets the check of {!attr} on each value. *)

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
  (** A fixed text. *)

  val element : string -> attr list -> shape list -> shape
  (** [element tag attrs children]: an HTML element. *)

  val part : int -> shape
  (** The child at this place is part [i], made with [child]. *)

  val fixed : string -> string -> attr
  (** [fixed name value]: an attribute with a fixed value, checked by
      {!Yuka.template_of_shape}. *)

  val part_attr : int -> attr
  (** The attribute at this place is part [i], made with [attribute] or
      [attribute_option]. *)

  (**/**)

  val make :
    shape ->
    html:string ->
    walk:int array ->
    kids:int array ->
    attrs:int array ->
    values:(int * string) array ->
    t
  (** [make shape ~html ~walk ~kids ~attrs ~values]: for tests, which give
      [html] and the paths by hand. Nothing is checked: the browser puts
      [html] in the page as given and the server prints a fixed [srcdoc] or
      [base] [href] as given, so a template written by hand uses
      {!Yuka.template_of_shape}. The client checks the parsed [html] against
      [shape] once. *)

  (**/**)

  val child : 'kind element -> 'kind part
  (** The value of a {!val-part}. *)

  val attribute : 'kind attribute -> 'kind part
  (** The value of a {!part_attr}. *)

  val attribute_option : 'kind attribute option -> 'kind part
  (** The value of a {!part_attr}; [None] writes no attribute. *)

  val instance : t -> 'kind part array -> 'kind element
  (** The tree of [t] with its parts filled in. It prints and hydrates as the
      same tree made with [lower]. Fresh client creation parses the HTML of
      the template once, clones it and goes to each part with its paths. *)
end

val template_of_shape : Template.shape -> Template.t
(** A template written by hand: checks the tag names and the fixed
    attributes (names, and URLs, [srcdoc] and [base] [href] as {!attr} does,
    with the element known) and computes its HTML and the paths to its
    parts. Raises [Invalid_argument] on a bad tag or attribute name. *)

(**/**)

val template_coded :
  string ->
  html:string ->
  walk:int array ->
  kids:int array ->
  attrs:int array ->
  values:(int * string) array ->
  clones:int ->
  Template.t
(** For the ppx only: [code] is the shape in the form of
    [Template_build.encode], and the other arguments are computed from it at
    build time, where the ppx also checks the fixed attributes and lowers a
    tree that the HTML parser would change. [clones]: bit 1 when the parse
    of [html] in a [<template>] keeps the tree, bit 2 when its parse inside
    an [<svg>] does; the client clones only in such a context and otherwise
    builds the tree element by element, which needs {!Client.hydrate}. The
    browser clones [html] as given and the server prints a fixed [srcdoc]
    or [base] [href] as given. The client decodes [code] only to hydrate
    and in a dev build. *)

val template_child : 'kind element -> 'kind Template.part
val template_attribute : 'kind attribute -> 'kind Template.part
val template_attribute_option : 'kind attribute option -> 'kind Template.part
val template_instance : Template.t -> 'kind Template.part array -> 'kind element

(**/**)

module Slot : sig
  val make : server element -> slot
  (** A slot with this server content. *)
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

val suspend :
  loading:server element ->
  ?failed:(string -> server element) ->
  server element Async.t ->
  server element
(** Shows [loading] until the element is settled, then the element, or
    [failed message] (default: nothing). It streams as [<Yuka.Await>] does.
    Build the argument with [Async.map (fun data -> <View data />) fetch].
    Server only: in an island, use [<Yuka.Await>], which builds the element
    in the island's owner. *)

module Catch : sig
  val make :
    fallback:(error:string -> reset:(unit -> unit) -> 'k element) ->
    children:(unit -> 'k element) ->
    unit ->
    'k element
  (** An error boundary. In mlx:
      [<Yuka.Catch fallback=(fun ~error ~reset -> ...)> children </Yuka.Catch>];
      the ppx passes the children as a function.

      The children run in a new owner. An exception raised while they
      render, in an effect or a hole that runs again (or its cleanup), in a
      memo that one of them reads, or in an event handler attached in them,
      disposes that owner (effects stop, cleanups run) and shows
      [fallback ~error ~reset] in place of the children. [error] is the
      exception as text. [reset ()] disposes the fallback and renders the
      children again from their first state; State made outside the
      boundary keeps its value. An exception in the fallback goes to the
      boundary above. A failed {!Async} or a {!Status.Failed} is a value,
      not an exception: show it with [Await] or [Show].

      In an island with no [Catch] above, the island is the boundary: it
      stops, its DOM stays as it is, and the error goes to [console.error]
      and to the [on_error] of {!render}.

      On the server, an exception in the children prints the fallback with
      [~error:"server error"] and sends the exception to
      the [log_error] of {!Server.config}; the HTML never has the detail. In an island, the
      client then hydrates the fallback, and [reset] renders the children in
      the browser. *)
end

module Status : sig
  (** Why a remote call failed. *)
  type error =
    | Rejected of string
        (** The server refused the input ({!Server.Action.reject}, bad
            input). The message is for the user. *)
    | Forbidden  (** The origin check failed. *)
    | Not_found  (** Unknown action. *)
    | Server  (** The implementation raised or failed; the detail is in the server log. *)
    | Network of string  (** No answer: offline, aborted, timeout. *)
    | Protocol of string  (** The answer did not decode. *)

  (** The state of data that loads. [Loading (Some x)]: a new load runs and
      [x] is the last good data. *)
  type 'a t =
    | Idle  (** Not enabled. *)
    | Loading of 'a option  (** A request runs; the option is the last good data. *)
    | Ready of { data : 'a; stale : bool }  (** [stale] is [false] for remote data. *)
    | Failed of { error : error; last : 'a option }

  val data : 'a t -> 'a option
  (** [data] of [Ready], [last] of [Failed], the option of [Loading]. *)

  val map : ('a -> 'b) -> 'a t -> 'b t

  val error_to_string : error -> string
  (** [Rejected m] is [m]; the others are short English text. *)

  val error_codec : error Codec.t
  (** [{"kind": "rejected", "message": m}], [{"kind": "server"}], ... *)
end

module Show : sig
  val make :
    status:(unit -> 'a Status.t) ->
    loading:'k element ->
    ?failed:(Status.error -> 'k element) ->
    children:('a -> 'k element) ->
    unit ->
    'k element
  (** [<Yuka.Show status loading failed> (fun data -> ...) </Yuka.Show>]: a
      hole over [status ()]. [Ready] and [Loading (Some data)] show
      [children data], so data stays on screen while it loads again; [Idle]
      and [Loading None] show [loading]; [Failed] shows [failed error]
      (default: nothing). The children render again only when the data
      changes ([==]). *)
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

type stylesheet
(** A CSS file of a module, made by [module Css = [%yuka.css "file.css"]].
    The ppx gives [Css.stylesheet] and one [string] per class of the file,
    [Css.row] for [.row], with a name scoped to the file. *)

val stylesheet : string -> stylesheet
(** For generated code: the sheet served at this URL. A top-level value, so
    that a client bundle does not keep {!Private}. *)

val use_css : stylesheet -> 'k element -> 'k element
(** [use_css sheet element] is [element] with [sheet] in the page. On the
    server, the page gets [<link rel="stylesheet">] once, before the first
    element that uses it; the sheets of an island are printed before its
    [<yuka-island>]. In the browser, a [link] is added to [<head>] if the
    document has none for this sheet. The ppx calls it in every function
    named [make] that comes after [[%yuka.css]] in the same file. *)

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
      [yuka-islands] build it. Pass it to [Yuka.render]. *)

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
  (** [then] of a JavaScript promise. For the code of [yuka-islands]. *)

  val lazy_entry : name:string -> (unit -> entry promise) -> lazy_entry
  (** [lazy_entry ~name load]: an island whose code is loaded on demand.
      [load] is called, at most once, when the start strategy of an island
      named [name] fires, for example with a dynamic import of the module
      that defines the entry. If it fails, the island keeps its server HTML
      and the error is logged. *)

  val hydrate : container -> (unit -> 'k element) -> unit -> unit
  (** [hydrate container f] adopts the server DOM in [container] (written
      with the markers of DESIGN.md), attaches handlers and starts holes.
      Where the DOM does not match, it creates the missing nodes. Unless the bundler
      defines [__YUKA_DEV__] as [false], each mismatch (a missing node,
      another tag, another text, an extra node) logs one [console.warn] with
      the island name, the expected and the found node, and a short path. Returns a function
      that stops all effects and handlers. Browser only. *)

end

module Optimistic : sig
  (** Pending changes over a base value that lives elsewhere (a State, the
      data of a {!Status.t}). *)

  type 'c t
  (** The pending changes, in the order they were added. *)

  type id

  val empty : 'c t
  val add : 'c t -> 'c -> 'c t * id
  val remove : 'c t -> id -> 'c t
  (** After the change succeeded or failed. *)

  val apply : ('a -> 'c -> 'a) -> 'c t -> 'a -> 'a
  (** The base with every pending change applied, oldest first. *)

  val is_empty : 'c t -> bool
end

module Action : sig
  type ('i, 'o, 'kind) t
  (** ['kind] is [[ `Mutation ]] for {!declare} and [[ `Query ]] for
      {!query}. *)

  val declare :
    name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Mutation ]) t
  (** An action named [name]: the server and the client must declare it with
      the same name and codecs. The server runs it after
      {!Server.Action.implement}. *)

  val query :
    name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Query ]) t
  (** Like {!declare}, for a read with no side effect: a server render may
      run it and {!Remote.use} may retry it. Same endpoint and wire format. *)

  val name : (_, _, _) t -> string
  (** The name given to [declare]. *)

  val call : ('i, 'o, _) t -> 'i -> 'o Async.t
  (** Encodes the input, sends it to the server (in the browser after
      [render ~islands], as [POST /_yuka/action/<name>]; on the server, to the
      implementation), decodes the output. A decode error is [Failed]. *)
end

module Remote : sig
  (** Server data read through a query ({!Action.query}). *)

  type 'o t

  type retry = { attempts : int; delay_ms : int -> int }
  (** [attempts] more tries after the first; [delay_ms n] waits before try
      [n + 1]. *)

  val default_retry : retry
  (** Two more tries, after 500 ms and 1500 ms. *)

  val no_retry : retry

  val use :
    ?retry:retry -> ?enabled:(unit -> bool) -> ('i, 'o, [ `Query ]) Action.t -> (unit -> 'i) -> 'o t
  (** Runs the query for the input that the function returns, and again
      when a State that the function or [enabled] reads changes. Call it in
      a component body: when its owner is disposed, the request in flight
      is aborted.

      - The key of a request is the query name and the JSON of the input;
        the query runs again only when the key changes. A new key,
        {!refetch} or {!invalidate} aborts the request in flight, and only
        the latest request writes the status.
      - [enabled ()] false gives [Idle] and aborts the request.
      - [Network] and [Server] errors are tried again by [retry] (default
        {!default_retry}); the others fail at once.
      - In a server render it runs the implementation once. If it settles
        during the render, the status is [Ready] or [Failed]; else
        [Loading None]. Inside an island the answer is written in the page
        ([<script data-yuka-answer>], after the island), and the client
        reads it on the first run instead of sending a request; a pending
        answer is streamed later.
      - Outside the browser and outside a render (tests), it calls the
        implementation directly. *)

  val status : 'o t -> 'o Status.t
  (** Tracked read, with the pending {!mutate} changes applied to the data. *)

  val refetch : 'o t -> unit
  (** Sends the request again (the manual retry after [Failed]). *)

  val invalidate : (_, _, [ `Query ]) Action.t -> unit
  (** {!refetch} every mounted use of this query, for every input. *)

  val mutate : 'o t -> ('o -> 'o) -> ?commit:('r -> 'o -> 'o) -> (unit -> 'r Async.t) -> 'r Async.t
  (** [mutate r change run] shows [change] on the data at once, then calls
      [run ()]. When it succeeds the change is removed and the data becomes
      [commit result data] (default [change data]); when it fails the
      change is removed (rollback). A new answer while the change is pending
      gets the change on top. The result is the [Async] of [run ()]. *)
end

module Topic : sig
  (** A kind of live state ({!Live}): a name, the codec of its key and the
      codec of its state. One topic has one state per key. *)

  type ('k, 's) t

  val declare : name:string -> key:'k Codec.t -> state:'s Codec.t -> ('k, 's) t
  (** The server and the client must declare it with the same name and
      codecs. *)

  val name : (_, _) t -> string
end

module Live : sig
  (** Server state that the server pushes to the page over one WebSocket
      ([GET /_yuka/live]) when it changes. Each message is the full state of
      one key. The server side is {!Server.Live}. *)

  type 's t

  val use : ('k, 's) Topic.t -> (unit -> 'k) -> 's t
  (** Subscribes to the state of the key that the function returns, and
      again when a State that the function reads changes the key. Call it
      in a component body; the subscription ends when its owner is disposed.

      - In a server render it runs the topic's [allow] with the context of
        the page request ([Failed Forbidden] when it refuses), then reads
        the state (the current one of the handler's node, else the topic's
        loader) and, inside an island, writes it in the page with
        a CSRF token for the socket; the client starts from it with no
        wait. A page that has such a use holds a per-session token and
        state that [allow] passed for this request, so its route must not
        use a shared cache (the cycle sends [private, no-store] when the
        shell has such a use), and it cannot be prerendered.
      - In the browser, one socket serves every use of the page. It opens
        on the first use and closes 2 s after the last one ends.
      - The status is [Loading None] until the first state, then [Ready].
        When the socket closes it is [Ready { stale = true }] (or
        [Loading None] with no data) while the client reconnects, after
        250 ms, 500 ms, 1 s, 2 s, 4 s, then every 5 s (half to all of each
        delay, at random), or when the browser comes back online. Each
        reconnect gets the full state again.
      - [Failed]: the server refused the key ([Forbidden], [Not_found],
        [Rejected] from the loader, [Server]); this use does not subscribe
        again. An unsupported protocol gives [Protocol] to every use.
      - Token: the client keeps the newest token it saw (from the page, the
        server [hello] and each [pong]). When the server refuses it (an
        expired token), the client gets a fresh one once from
        [GET /_yuka/csrf] and connects again; if that fails too, every use
        is [Failed Forbidden] until a new use (after a navigation) connects
        again with the token of its page. *)

  val status : 's t -> 's Status.t
  (** Tracked read, with the pending {!mutate} changes applied. *)

  val mutate : 's t -> ('s -> 's) -> (unit -> 'r Async.t) -> 'r Async.t
  (** [mutate t change run] shows [change] at once and calls [run ()],
      which should call an action that publishes the new state. When it
      fails, the change is removed. When it succeeds, the change stays until
      the server confirms, on the socket, that every state it had for this
      subscription when the answer arrived was sent: the published state
      then holds the change, in whatever order the HTTP answer and the
      socket message arrived. While the socket is down, the confirmation
      comes after the reconnect. *)
end

module Form : sig
  (** Forms that post with no JavaScript and submit through {!Action.call}
      in an island. [[@@deriving form]] on a record writes the field type,
      the field names and a [('i, 'f) t]; the same decoder runs on the
      server and in the browser. *)

  type 'f errors = ('f option * string) list
  (** [None] is an error for the whole form. *)

  type 'a kind
  (** How one field reads from the posted strings and writes back. *)

  val string : string kind
  (** The first value; ["Missing"] when the field is absent. *)

  val int : int kind
  (** ["Not a whole number"] when it does not parse. *)

  val float : float kind
  val bool : bool kind
  (** A checkbox: present is [true], absent is [false]. *)

  val option : 'a kind -> 'a option kind
  (** Absent or empty is [None]. *)

  val list : 'a kind -> 'a list kind
  (** Every value of the field, in order. *)

  val custom : (string -> 'a option) -> ('a -> string) -> 'a kind
  (** ["Not valid"] when [of_string] gives [None]. *)

  type ('i, 'f) t
  (** The fields of a form: decode, encode and names. *)

  type ('i, 'o, 'f) action = ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t

  type 'f decoding

  val fields :
    names:('f * string) list ->
    decode:('f decoding -> ('i, 'f errors) result) ->
    encode:('i -> (string * string) list) ->
    ('i, 'f) t
  (** Used by the code that [[@@deriving form]] writes. *)

  val field : 'f decoding -> 'f -> string -> 'a kind -> 'a option
  val get : 'a option -> 'a
  val finish : 'f decoding -> (unit -> 'i) -> ('i, 'f errors) result
  val put : string -> 'a kind -> 'a -> (string * string) list

  val decode : ('i, 'f) t -> (string * string) list -> ('i, 'f errors) result
  (** Every field error, in field order. *)

  val encode : ('i, 'f) t -> 'i -> (string * string) list
  val name : ('i, 'f) t -> 'f -> string

  val action :
    name:string ->
    fields:('i, 'f) t ->
    output:'o Codec.t ->
    ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t
  (** An action whose input is a form: {!Action.call} sends the encoded
      fields; the answer is [Ok o] or the field errors. *)

  type ('o, 'f) form
  (** What the children of {!make} get. *)

  val value : ('o, 'f) form -> 'f -> string
  (** The value sent for the field when the page answers a failed post
      (422), else [""]. *)

  val error : ('o, 'f) form -> 'f -> string option
  (** Tracked read of the first error of the field. *)

  val error_view : ('o, 'f) form -> 'f -> (string -> 'k element) -> 'k element
  (** A hole: the view of the field's error, or nothing. *)

  val form_errors : ('o, 'f) form -> string list
  val form_error_view : ('o, 'f) form -> (string -> 'k element) -> 'k element
  (** The errors for the whole form. *)

  val pending : ('o, 'f) form -> bool
  (** Tracked: true while an island submit waits for its answer. Read it in
      a hole ([Yuka.hole]); read in the children directly, it renders the
      enclosing component again, with a new form. *)

  val make :
    action:('i, ('o, 'f errors) result, [ `Mutation ]) Action.t ->
    ?key:string ->
    ?run:('i -> ('o, 'f errors) result Async.t) ->
    ?on_ok:('o -> unit) ->
    children:(('o, 'f) form -> 'k element) ->
    unit ->
    'k element
  (** [<Yuka.Form action>(fun form -> ...)</Yuka.Form>]: a
      [<form method="post">] with no [action] attribute (it posts to the
      page URL) and a hidden [_yuka_action] field, so it works with no
      JavaScript. Give [key] to tell apart two forms of one action on a
      page: after a failed post (422) only the form with the posted key
      shows the sent values and errors. In an island, they stay for the
      life of that [<form>] element (a new render of the form shows them
      again) until a submit in the browser. In an island, a submit is handled
      in the browser: the fields (with the submit button's [name] and
      [value]) are decoded first (an error shows at once, with no request),
      then [run input] (default: the action call) runs while [pending] is
      true; field errors show, and on [Ok o] [on_ok o] runs, or else the page
      follows the server's [redirect] (with [run], the page URL) with a
      client navigation, as a post with no JavaScript does. A [redirect] to
      another origin is not followed: it shows as a form error. Raises
      [Invalid_argument] when [action] is not from {!val-action}. *)
end

module Browser : sig
  val on_window : string -> (Event.t -> unit) -> unit
  (** Listens on [window] until the current owner is disposed. Browser only:
      call it inside [Effect.run]. *)

  val navigate : string -> unit
  (** Loads the URL. After [render ~islands] with navigation (the default), it
      is a client navigation, as a click on a link; see {!render}. Otherwise it
      does [location.assign url]. A [javascript:], [vbscript:] or [data:]
      URL (read as {!attr} reads a URL) does nothing; a dev build logs the
      first one. *)

  val focus : string -> unit
  (** Focuses the element with this id. *)

  val scroll_into_view : string -> unit
  (** Scrolls the element with this id into view. *)
end

(**/**)

module Private : sig
  type node = private
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
    | Catch of {
        children : unit -> node;
        fallback : error:string -> reset:(unit -> unit) -> node;
        client : Obj.t option -> node;
      }

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

  val parser_changes : svg:bool -> Template.shape -> bool
  (** The build-time nesting check of the ppx: [true] when the HTML parser
      could build another tree from the HTML of the shape, parsed in a
      [<template>] ([svg:false]) or in an [<svg>] in a [<template>]
      ([svg:true]). The ppx lowers such a template with {!lower}. *)

  val node : 'kind element -> node

  val dev_events :
    state:(unit -> string) -> sleep:(float -> unit Async.t) -> (string -> unit Async.t) -> unit Async.t
  (** The body of [/_yuka/dev] for a state function (tests). *)

  val dev_script : string -> string
  (** The script that a page gets with [YUKA_DEV=1], for the state JSON
      given (tests). *)

  val element : node -> 'kind element

  val hole : (unit -> node) -> node
  (** [Hole f]. [node] is private, so that a test cannot build a node kind
      without the constructor that installs its client code. *)

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
    | Pending_answer of { key : string; answer : Json.t Async.t }

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

  val action_codecs : ('i, 'o, _) Action.t -> 'i Codec.t * 'o Codec.t

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

  val set_csrf : session -> (unit -> string) -> unit
  val reset_live : unit -> unit

  val set_form :
    session -> string * string * (string * string) list * (string option * string) list -> unit
  (** The form state of a failed post: action name, form key, sent fields,
      errors by field name. *)

  val query : string -> (string * string) list
  (** The decoded query pairs of a request target, as the cycle reads them
      ([+] is a space). *)

  val preload_urls :
    manifest:string -> base:string -> ?metafile:string -> unit -> string -> string option

  val handle_action :
    name:string -> header:(string -> string option) -> body:string -> (int * string) Async.t

  val render : Client.container -> (unit -> 'k element) -> unit -> unit
  (** [render container f] clears [container], builds the DOM of [f ()] and
      returns a function that stops the effects and handlers of this tree,
      for tests. Browser only. *)
end

(**/**)

module Router : sig
  (** The members that the code generated by [yuka-routes] calls: the
      shared [Routes] module (route type, [href], [find]) is written from
      [Routes.ml]. See "yuka.router" in DESIGN.md. *)

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
    (** For a path param, [None] means the path does not match. For a
        search field, the value is dropped: an optional field gets [None],
        a field with a default gets the default, and a list field leaves
        the value out. *)

    val to_string : t -> string
    (** The inverse of [of_string]. [href] encodes the result. *)
  end

  (**/**)

  (** For the generated code only. Not covered by semantic versioning: any
      release can change these values. *)

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

  (**/**)
end

val render :
  ?islands:Client.registry ->
  ?navigation:bool ->
  ?prefetch:[ `Hover | `Visible | `Off ] ->
  ?transitions:bool ->
  ?on_error:(string -> unit) ->
  ?root:Client.container * (unit -> 'k element) ->
  unit ->
  unit
(** The client start. Give [~islands] for a page that the server rendered,
    [~root] for a tree that only the client builds, or both:

    {[
      let () = Yuka.render ~islands ()
      let () = Yuka.render ~root:(container, app) ()
    ]}

    [yuka.ppx] rewrites a bare [~islands] in a [Yuka.render] call into
    [~islands:Yuka_islands.registry], the islands of the app.

    [~root:(container, app)] clears [container] and builds the DOM of
    [app ()] in it. {!unmount} stops the effects and handlers of this tree;
    the DOM stays. It runs before the islands start.

    With [~islands], it installs the browser runtime and the action
    transport, then hydrates every [yuka-island] element of the document with the entry of the same
    name, following each island's start strategy. Props come from the
    [script] element with the same [data-yuka-props] id. It also watches the
    document, so islands that arrive later (streaming, fills) start when
    their props script is complete. An island that cannot start is logged
    with [console.error] and keeps its server HTML. An island is not started
    twice. An exception that no {!Catch} in the island catches stops the
    island and keeps its DOM as it is; the message
    ["yuka island ID (NAME): ..."] goes to [console.error] and to
    [on_error], for example to send it to an error reporting service. The
    other islands keep working. The action transport sends [POST /_yuka/action/<name>] with the
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

    A client navigation loads the URL with the header [Yuka-Navigate] set
    to the [data-k] keys of the [<yuka-outlet>] elements of the page, in
    document order, separated by spaces ([-] when there is none). With a
    [Yuka-Outlet: KEY] answer it stops only the islands inside that outlet
    (and aborts their action calls), replaces its content, sets
    [document.title] from [Yuka-Title] (the raw value if it does not
    decode), and sets [aria-current="page"] on the links outside the outlet
    and outside islands whose [href] is the new path and that have no
    [aria-current], removing it from the others that have [page]; islands
    outside the outlet keep running. If that outlet is not on the page, it
    does [location.assign]. Without [Yuka-Outlet] it stops every island and
    replaces [<body>] and [document.title] with those of the response. Then it starts
    the new islands, pushes a history entry (after the page loaded) and
    scrolls to the fragment or to the top. A navigation started while
    another one loads aborts the first. Any 2xx or 4xx/5xx status is shown
    in place. If the request fails, the status is 1xx or 3xx, the response
    is not [text/html], its [Yuka-Build] differs from the
    [<meta name="yuka-build">] of the page, or it was redirected to another
    origin, it does [location.assign url].

    Prefetch ([prefetch], default [`Hover]): 50 ms after the pointer or the
    focus enters a link that a click would navigate, or at once on
    [touchstart] or a [pointerdown] of the main button with no modifier
    key, the page is loaded with the navigation headers and
    [Yuka-Prefetch: 1]. The server answers it as any navigation, so the
    guards and loaders of a [GET] page must be safe to run for a link the
    user may never click: no side effects. [`Visible] also prefetches every such link
    when it becomes visible; with [`Hover], only links with
    [data-yuka-prefetch="visible"] do. [data-yuka-prefetch="off"] on a link
    and [`Off] turn it off, and so does [navigator.connection.saveData].
    A navigation to a URL whose prefetch is in flight waits for it.

    Answers are kept by URL and outlet keys, at most 30, by the
    [Cache-Control] of the answer: with [max-age=N] (and no [no-store] or
    [no-cache]) for N seconds, also for back and forward; otherwise a
    prefetched answer is used once, within 10 s, and a visited page is not
    kept. An action call that succeeds empties the cache, and an answer
    requested before it is not kept. [render ~islands] and {!unmount} empty it and
    abort the prefetches nobody waits for; after {!unmount} no navigation
    updates the page.

    With [~transitions:true], where [document.startViewTransition] exists,
    the page update runs inside a view transition, and [<html>] has
    [data-yuka-nav="push"], ["back"] or ["forward"] until the last one
    ends. The URL, history and navigation state change before the
    transition starts; an exception in the update is thrown again in a
    task, as an uncaught error.

    With [~navigation:false] only the islands start and links load full
    pages. Calling [render ~islands] again is safe: the listeners are not
    added twice.

    Without [~islands], [~navigation], [~prefetch], [~transitions] and
    [~on_error] do nothing. Raises [Failure] outside the browser, and
    [Invalid_argument] without [~islands] and [~root]. An app that does not
    pass [~islands] contains no island, action or navigation code. *)

val unmount : unit -> unit
(** Stops every tree that {!render} started: each [~root] tree and every
    island. Effects, handlers and document listeners are removed, start strategies that did not fire yet are
    cancelled, and action requests in flight are aborted (their [Async]
    fails with ["cancelled"]). It also stops navigation: the [click] and
    [popstate] listeners are removed, a navigation in flight is aborted, and
    {!Browser.navigate} does [location.assign] again. The DOM stays.
    {!render} works again afterwards, for example on a new body. *)

module Server : sig
  (** The server side: the request cycle, actions, forms and live topics.

      Reserved paths. The cycle answers these paths itself, before any
      route, so a [Routes.ml] node or a [public] prefix cannot use them:

      - [/_yuka/action/NAME]: an action call ({!Action}, {!Form}).
      - [/_yuka/csrf]: a fresh CSRF token for the live socket.
      - [/_yuka/css/FILE]: the sheets of [[%yuka.css]] (when [config] has
        [css]).
      - [/_yuka/dev]: the dev reload events (when [config] has [~dev:true]).
      - [/_yuka/live]: the WebSocket of {!Yuka.Live}.
      - [/_yuka/app/FILE]: the client JavaScript of [assets].

      Any other path under [/_yuka/] is a 404. The app must be served at
      the root of its origin: there is no base path. *)

  val to_string : (unit -> server element) -> string
  (** The tree as HTML. Hydration markers are written only inside an island,
      because the browser hydrates nothing else. The function builds the tree
      with effects off, so component bodies do not run effects. *)

  type context
  (** The request that runs an action, a form action or a live [allow]. *)

  module Context : sig
    val header : context -> string -> string option
    (** A request header, case-insensitive. For a live [allow], the
        headers of the WebSocket upgrade request. *)

    val session : context -> string option
    (** The session id of the request, from the adapter ([Dream.session_id]
        for Dream). [None] outside a request: an {!Yuka.Action.call} on the
        server that no request runs (for example in a test). With Dream,
        raises when the app has no session middleware. *)

    val meth : context -> Router.meth
    (** The request method. *)

    val path : context -> string
    (** The request path, without the query. *)
  end

  module Action : sig
    val implement : ('i, 'o, _) Action.t -> (context -> 'i -> 'o Async.t) -> unit
    (** Registers the implementation of a declared action, and makes
        [Action.call] run it directly on the server. Raises
        [Invalid_argument] if the name is already implemented.

        Any page can call any action: [POST /_yuka/action/NAME] runs no
        route guard, and a form post runs the guards of the page it is
        posted to, not of a page that shows the form. So an action checks
        permissions itself, with its [context] (a session, a cookie header).
        On the server, [Action.call] during a render gets the context of
        the rendered request; outside a request it gets a context with no
        header and no session. *)

    val reject : string -> 'a Async.t
    (** A failed [Async] that refuses the input: the action call answers
        400 [{"error": message}], [Action.call] on the server fails with the
        message, and a form renders the page again with the message as a
        form error. Any other failure or exception is a 500 with a generic
        message. *)
  end

  module Live : sig
    (** The server side of {!Yuka.Live}. A publish reaches the sockets of
        this node; with a bus ({!use_bus}) it also tells the other server
        nodes, which load the key again for their own sockets. Sessions and
        the secret must be the same on every node and across restarts
        (Dream: [cookie_sessions] or SQL sessions, and [Dream.set_secret]);
        with memory sessions or a random secret, every [hello] after a
        restart, or on another node, is refused and the page needs a
        reload. *)

    type node
    (** The live state of one server node: its subscriptions, sockets,
        [seq] counter, limits and bus. A process has one default node, which
        every function uses when [?node] is not given. *)

    val node : ?log_error:(string -> unit) -> ?per_session:int -> ?total:int -> unit -> node
    (** A new, empty node, for example for a second handler in one process.
        [log_error] gets the failures of loaders and of the bus. Without it
        (and for the default node), the node logs to the [log_error] of the
        config of the last request that a handler served on this node, and
        to [prerr_endline] before the first request. [per_session] (default 16) and [total] (default
        10,000) are the most open live sockets per session and on this node;
        a socket over a limit is closed with 1013 before its [hello], and
        the page tries again later. *)

    val serve :
      ?allow:(context -> 'k -> bool) -> ('k, 's) Topic.t -> ('k -> 's Async.t) -> unit
    (** Registers the loader of a topic: the full state of a key, run when
        a key that has no current state gets a subscriber, and by a server
        render. The loaded state of a key is shared by every subscriber
        of the key on the node, so the loader gets no request and must not
        depend on who asks: [allow] decides who may read a key. [allow] (default: always) runs on each subscribe, with the
        context of the WebSocket upgrade request, and on each server render
        of {!Yuka.Live.use}, with the context of the page request; false
        refuses it ([Forbidden]). A loader that fails with {!Action.reject}
        gives [Rejected]; any other failure gives [Server] and a log
        message. Raises [Invalid_argument] when the topic is already
        served. *)

    val publish : ?node:node -> ('k, 's) Topic.t -> 'k -> 's -> unit
    (** The new full state of a key, sent to each subscriber of the key on
        the node; with a bus, a note tells the other nodes that the key
        changed. With no bus it does nothing when the key has no
        subscriber. A publish while the loader runs wins over the loaded
        state. [allow] decides at subscribe time: a subscriber gets every
        publish of its key until it unsubscribes, its socket reconnects
        (each connection checks [allow] again), or {!revoke} closes it. *)

    val changed : ?node:node -> ('k, 's) Topic.t -> 'k -> unit
    (** The key changed: the node loads it again with the topic's loader
        for its subscribers, and the bus tells the other nodes, which do
        the same. Use it when the action does not have the new state. *)

    val revoke : ?node:node -> (context -> bool) -> unit
    (** Closes, with code 4401, every live socket of the node whose context
        matches. The page reconnects, and [allow] decides again for each
        key. Call it on logout
        ([revoke (fun c -> Context.session c = Some id)]) and after a
        permission change. It does not go over the bus: with more than one
        node, the app must call it on every node (for example from its own
        message between nodes). *)

    type bus = private {
      send : string -> unit Async.t;  (** One short note to every node, this one too. *)
      listen : (string -> unit) -> unit Async.t;
          (** Calls the function with each note; settles when listening
              started. *)
      on_restart : (unit -> unit) -> unit;
          (** Calls the function after the bus reconnects: notes may have
              been lost. *)
      close : unit -> unit Async.t;  (** Stops the bus and frees its resources. *)
    }
    (** How server nodes tell each other that a key changed. A note is
        [{"n":NODE,"t":TOPIC,"k":KEY,"p":N}], under 7,900 bytes (Postgres
        [NOTIFY] takes 8,000); a publish whose note would be longer is not
        sent and is logged. The order of notes between nodes does not
        matter. *)

    val bus :
      send:(string -> unit Async.t) ->
      listen:((string -> unit) -> unit Async.t) ->
      on_restart:((unit -> unit) -> unit) ->
      close:(unit -> unit Async.t) ->
      bus
    (** A bus with these functions. *)

    val close_bus : bus -> unit Async.t
    (** Calls the [close] function of the bus. A node that uses the bus
        hears no more notes, and its notes are not sent (each failure is
        logged). *)

    val use_bus : ?node:node -> name:string -> bus -> unit Async.t
    (** Joins the bus as the node [name] (a name unique to this process,
        such as the host name and the port). For each note from another
        node about a key that has subscribers here, the node runs the
        topic's loader again and sends the result; one load per key at a
        time, and notes that come during a load make one more load after
        it. After [on_restart], every key with subscribers here loads
        again. Raises [Invalid_argument] when the node already has a bus or
        [name] is empty. Settles when the bus listens. Each node must load
        from the same storage. *)

    type memory
    (** A bus inside one process (tests, two nodes in one process). *)

    val memory : unit -> memory

    val memory_bus : memory -> bus
    (** Every node that uses a bus of this memory gets each note at once.
        Closing the bus removes only its own listeners. *)

    type connection
    (** One open WebSocket, text frames. *)

    val connection :
      send:(string -> unit Async.t) ->
      receive:(unit -> string option Async.t) ->
      close:(int -> unit Async.t) ->
      connection
    (** For an adapter's [upgrade]. [receive] gives [None] when the client
        closed the socket. [close code] closes it with this code; the live
        protocol calls it once, when it ends the protocol itself (a limit,
        a failed send or receive, {!revoke}), and never after the client
        closed the socket. *)
  end

  module Form : sig
    val implement :
      ('i, 'o, 'f) Form.action ->
      ?redirect:('o -> string) ->
      (context -> 'i -> ('o, 'f Form.errors) result Async.t) ->
      unit
    (** Registers a form action (see {!Yuka.Form}). It answers the island
        path ([POST /_yuka/action/<name>], JSON) like {!Action.implement},
        with [redirect o] in the answer (checked as for the 303 below: a
        bad one answers 500 [action failed] and is logged), and the form
        post of a page. The request cycle checks the origin (403), runs the
        guards of the page the form is posted to (a refusal answers as for
        [GET] and the function does not run), reads at most 1 MiB of body
        (413), decodes the posted fields, calls the function, and answers
        303 to [redirect o] (default: the page URL) on [Ok o], or renders
        the page again with status 422 and the sent values and errors on
        [Error], a decode error or {!Action.reject}. The form field
        [_yuka_action] names the action, so a post to any [GET] page can run
        any form action: the function checks permissions itself, as for
        {!Action.implement}. Only [application/x-www-form-urlencoded] posts
        reach a form action; a [multipart/form-data] post (a file input) is
        a 405. The 303, 403 and 413 carry the page's rule headers. A
        [redirect o] that is not a path ([/x], not [//x]) or an [http:] or
        [https:] URL of the request [Host] or of [config ~origins] (the
        island answer too), or that holds a control character (below space,
        or DEL; a browser drops TAB from a URL, so [/\t/x] would go to
        [//x]), gives the 500 page and a log message instead of a 303.
        Raises [Invalid_argument] when the action is not from
        {!Yuka.Form.val-action}. *)
  end

  (** {2 Request cycle}

      The types and functions that a [Routes.ml] and its loaders, guards
      and handlers use. The cycle has no server dependency: a server
      implements {!Adapter.S}. See "Request cycle" in DESIGN.md. *)

  (** Why a guard or a loader stops a request. *)
  type stop =
    | Not_found  (** The not-found page of the route, status 404. *)
    | Forbidden
        (** A plain-text 403 with the root rule headers and
            [cache-control: no-store]. *)
    | Redirect of { location : string; kind : [ `See_other | `Temporary | `Permanent ] }
        (** A redirect on this site: 303, 307 or 308, no body. [location]
            must be a path ([/x], not [//x]) or an [http:] or [https:] URL
            of the request [Host] or of [config ~origins], without a control
            character; otherwise the request gets the 500 page and a log
            message. So a [?next=] value from the request cannot send the
            user to another site. *)
    | Redirect_off_site of { location : string; kind : [ `See_other | `Temporary | `Permanent ] }
        (** A redirect to any location without a control character, for
            example to another site's login page. Do not give it a value
            from the request. *)
    | Fail of string
        (** The error page, status 500. The message goes to [log_error],
            never to the page. *)

  type page
  (** What a page function returns: a title, extra head HTML and the body. *)

  val page : ?title:string -> ?head:string -> (unit -> server element) -> page
  (** [page ~title body]. The cycle calls [body] when it renders, for
      [HEAD] too (to send the length of the [GET] answer). [head] is raw
      HTML added to the document head. *)

  type cache
  (** The [cache-control] value of a route rule. In [Routes.ml], the
      [~cache] value is read with [Yuka.Server] opened:
      [~cache:(public ~max_age:60 ())]. *)

  val no_store : cache
  (** [no-store] *)

  val no_cache : cache
  (** [no-cache]: a cache must ask the server before it uses a copy. *)

  val private_ : max_age:int -> cache
  (** [private, max-age=N] *)

  val public : ?s_max_age:int -> max_age:int -> unit -> cache
  (** [public, max-age=N], and [, s-maxage=M] when given. *)

  val immutable : cache
  (** [public, max-age=31536000, immutable] *)

  type body =
    | String of string
    | Stream of ((string -> unit Async.t) -> unit Async.t)
        (** The adapter calls the function with its write function and ends
            the response when the result settles. *)

  type response = private { status : int; headers : (string * string) list; body : body }
  (** A handler's answer. A header name may repeat (two [set-cookie]). A
      header name or value with CR, LF or NUL makes the cycle answer a
      plain 500 instead, with a log message. *)

  val response : ?status:int -> ?headers:(string * string) list -> body -> response
  (** Default status: 200; default headers: none. [response (Stream f)]
      streams. *)

  val text : ?status:int -> ?headers:(string * string) list -> string -> response Async.t
  (** A [text/plain; charset=utf-8] response. Default status: 200. A
      [content-type] in [headers] replaces the default one. *)

  val html : ?status:int -> ?headers:(string * string) list -> string -> response Async.t
  (** Like {!text}, with [text/html; charset=utf-8]. *)

  val json : ?status:int -> ?headers:(string * string) list -> Json.t -> response Async.t
  (** Like {!text}, with [application/json]. *)

  val see_other : string -> response Async.t
  (** 303 to the location, no body. *)

  type 'req app
  (** The routes of an app, from the code generated by [yuka-routes
      --server]. ['req] is the request type of the adapter: the generated
      code passes the request to each loader, guard and handler. *)

  type assets
  (** Where the client JavaScript is. The cycle serves it under
      [/_yuka/app/]. *)

  val modules :
    dir:string -> entry:string -> manifest:string -> packages:string list -> digest:string -> assets
  (** The Melange module tree. [dir] is the emit directory, [entry] the path
      of the entry module in it (served as [/_yuka/app/<entry>]), [manifest]
      the JSON text that [yuka-islands --manifest] prints (paths relative to
      the directory of [entry]), and [packages] the npm packages under
      [dir/node_modules] for the import map. [digest] stands for the content
      of the files (for example [Yuka_dream.tree_digest dir]): it goes into
      the build id, so new JavaScript gives a new build id. Files get
      [cache-control: no-cache]. Raises [Invalid_argument] when [manifest]
      is not a JSON object of strings. *)

  val bundle :
    dir:string -> entry:string -> manifest:string -> metafile:string -> assets
  (** An esbuild bundle. [dir] is the directory esbuild ran in, so that the
      [outputs] keys of the [metafile] JSON text are paths in it; [entry] is
      the path of the entry output. Outputs other than [entry] get
      {!immutable}; other files get {!no_cache}. Raises [Invalid_argument]
      when [manifest] or [metafile] is not valid JSON of that shape. *)

  type config

  val config :
    ?assets:assets ->
    ?public:(string * string) list ->
    ?prerendered:string ->
    ?styles:string list ->
    ?css:(string * string) list ->
    ?head:string ->
    ?timeout:float ->
    ?dev:bool ->
    ?origins:string list ->
    ?log_error:(string -> unit) ->
    unit ->
    config
  (** [public] maps URL prefixes to directories ([("/static", "static")]).
      A prefix with no segment (["/"]) raises [Invalid_argument]: files
      under a prefix are never routed, so it would hide every route.
      [prerendered] is the directory that a prerender wrote: a [GET] or
      [HEAD] of a page whose rules say [prerender], without a query and
      without [Yuka-Navigate], is answered with its file there when the file
      exists ({!Prerender.file}), after the guards and instead of the
      loaders. [styles] are stylesheet URLs and [head] raw HTML for the head
      of every page. [css] lists the sheets of [[%yuka.css]], as file name
      and text; the generator [yuka-css] writes it ([Yuka_css.sheets]). The
      cycle serves each at [/_yuka/css/FILE] with {!immutable} (the name
      has a hash of the text); another path under [/_yuka/css/] is a 404
      with [no-store]. [timeout] (default 10 seconds) bounds a streamed
      render.

      [dev] (default false) is for [yuka dev] only: the cycle answers
      [GET /_yuka/dev] with Server-Sent Events of the state file named by
      the environment variable [YUKA_DEV_FILE], full pages get the reload
      script in their head, and [prerendered] is not used. Never set it in
      production: [/_yuka/dev] streams that file. A prerender turns it off
      ({!Prerender.config}).

      [origins] lists the origins that an action, a form post, an endpoint
      with an unsafe method, [/_yuka/csrf] and the live socket accept, as
      [scheme://host[:port]] (["https://app.example"]), compared without
      case. Without it, the [Origin] header must have the authority of the
      [Host] header; behind a proxy that rewrites [Host], give [origins].
      Either way, a request without [Origin] passes only when
      [Sec-Fetch-Site] is [same-origin], so a request with neither header
      (an old browser, a client that is not a browser) is refused.

      [log_error] (default [prerr_endline]) gets what the client must not
      see: an action that failed, a failed render, a failed async value, a
      refused redirect or header. *)

  (** {2 Adapters} *)

  module Adapter : sig
    (** What a server provides to run the cycle. *)
    module type S = sig
      type request

      type reply
      (** The response type of the server. *)

      val meth : request -> Router.meth
      (** The request method. *)

      val target : request -> string
      (** The path and query, as sent. *)

      val header : request -> string -> string option
      (** Case-insensitive. *)

      val body : request -> limit:int -> string option Async.t
      (** The request body, or [None] when it is longer than [limit] bytes.
          Give [None] with no read when a [Content-Length] is over [limit];
          else stop reading past [limit + 1] bytes. With [None], close the
          request body so the server drops the rest. *)

      val session : request -> string
      (** The session id of the request (Dream: [Dream.session_id]). Called
          only by {!Context.session}, and by the live socket to count the
          sockets of a session. *)

      val csrf_token : request -> string
      (** A CSRF token bound to the session of the request (Dream:
          [Dream.csrf_token]). It is written in a page only when the page
          has a {!Yuka.Live.use}, answers [GET /_yuka/csrf], and renews the
          token of the live socket; raise when the request has no session. *)

      val verify_csrf : request -> string -> bool Async.t
      (** Whether a token from {!csrf_token} is valid for the session of
          the request (Dream: [Dream.verify_csrf_token]). The live socket
          checks the token of its [hello] with it. *)

      val respond : response -> reply Async.t
      (** Sends the status, the headers (in order, a repeated name once per
          value) and the body; a [Stream] body is written as it comes. *)

      val file :
        request -> root:string -> path:string -> headers:(string * string) list -> reply Async.t
      (** Sends the file [root/path] with [headers], or 404 with
          [cache-control: no-store] when it does not exist. [path] has no
          empty, [.] or [..] segment. *)

      val exists : root:string -> path:string -> bool
      (** Whether the file [root/path] exists. The cycle asks it for a
          prerendered page and to answer [HEAD] on a file without sending
          the file. *)

      val upgrade : request -> (Live.connection -> unit Async.t) -> reply Async.t
      (** Answers 101 and runs the function on the open WebSocket. The
          function closes the socket when it ends the protocol; when the
          client closed it, nothing closes it again. *)

      val sleep : float -> unit Async.t
      (** Resolves after this many seconds. The cycle uses it for [timeout]
          and the live socket for its timeouts. *)
    end

    (** A request handler for the server of [A]. *)
    module Make (A : S) : sig
      val handler : ?node:Live.node -> config -> A.request app -> A.request -> A.reply Async.t
      (** Answers one request. [node] (default: the process node) is the
          live node of the sockets of [/_yuka/live] and of the server render
          of {!Yuka.Live.use}; a second handler in one process with its own
          {!Live.type-node} is a second node. Steps, in this order:

          + A reserved path (see {!Server}): [/_yuka/action/<name>], the
            action call ([POST] with a JSON body; answers as described for
            {!Action.reject}), else 405. From the headers first: the origin
            (403, see [config ~origins]), the action name (404) and the
            content type (415); then at most 1 MiB of body (413).
            [/_yuka/csrf]: for [GET] and [HEAD] with the same origin rule,
            [{"csrf":TOKEN}] from {!S.csrf_token} with [no-store] (the live
            client renews an expired token with it); 403 for another
            origin, 405 for another method. [/_yuka/live]: for [GET] with
            the same origin rule and [Upgrade: websocket], [A.upgrade] with
            the live protocol; 403 for another origin, 426 without the
            upgrade header, 405 for another method, and a 500 with a log
            message when {!S.session} raises (no session middleware). [/_yuka/app/<file>]: the
            file of [assets] for [GET] and [HEAD], else 405; a [.] or [..]
            segment, or no [assets], gives a plain 404 with [no-store]. A
            path under a [public] prefix: the file of its directory, by the
            same rules. These paths are never routed.
          + A path with a trailing slash or an empty segment: 308 to the
            path without them, query kept.
          + [find] with the percent-decoded segments and the query pairs.
          + [Redirect]: 308 (permanent) or 307, query kept.
          + [Missing]: the not-found page, 404. [Wrong_method]: 405 with
            [allow] (the methods, [HEAD] after [GET], then [OPTIONS]); for
            [OPTIONS], 204 with the same [allow].
          + An endpoint or action whose method is not [GET], [HEAD] or
            [OPTIONS]: 403 when the origin check fails, before the guards,
            unless its node has [~cross_origin:true].
          + Guards, one after another. A {!stop} skips the rest.
          + A handler: its response, after the rule headers (a header name
            of the handler replaces that name of the rules) and the rule
            [cache-control] unless it set one. [HEAD]: no body.
          + A page: the prerendered file when [config] has [prerendered]
            and it applies; else the loaders, then status 200 with the rule
            headers, [content-type], [vary: Yuka-Navigate] and the rule
            [cache-control]. When the shell of the page rendered a
            {!Yuka.Live.use} (its state passed [allow] for this request) and
            that [cache-control] is shared ([public] or [s-maxage]), the
            answer has [cache-control: private, no-store] instead, and the
            first such answer for a path logs a message. A [Live.use] that
            renders only in a streamed fill comes after the headers and is
            not covered: give such a route a private cache.
          + The document, streamed. Each layer's children are inside
            [<yuka-outlet data-k="KEY" style="display:contents">]. The
            entry module script is written once, before the first island,
            and the fill script only when the shell has a pending [await],
            so a page without islands or pending [await] loads no
            JavaScript. An [<a>] whose [href] is the request path gets
            [aria-current="page"], except inside an island, whose markup
            must match the client render.
          + With a [Yuka-Navigate] header (the outlet keys of the page):
            let [n] be the length of the common prefix of the sent keys and
            the layer keys of the page (or of the fallback, for a 404 or
            500). [n = 0]: the settled document in one string. [n >= 1]:
            only what goes inside outlet [n], settled, with the headers
            [Yuka-Outlet] (its key) and [Yuka-Title] (percent-encoded);
            island, await and async ids get the prefix [KEY-]. Both have
            [Yuka-Build] ({!build_id}).

          A 404 or 500 page has the root [headers] and [no-store]. A
          failure before the response is returned (shell, or a fill that
          already failed) gives the 500 page. After it the status is sent:
          the failure goes to [log_error], nothing more is written (no
          [</body></html>]), and the [Stream] function's [Async] succeeds
          once the writes already started have finished, so the adapter
          ends the response normally. When the error page itself fails, the
          answer is a plain-text 500. Every answer to [HEAD] has an empty
          body. A [HEAD] on a page renders it as for [GET]: when the [GET]
          answer is one string, [HEAD] has its [content-length]; when [GET]
          streams, so does [HEAD], with no body. For a file, the cycle
          answers 200 with the headers it knows (no [content-type] for a
          client or public file) when [exists] says so, else the plain 404.

          An [Action] always sends [cache-control: no-store]; a handler
          response that is not 2xx gets [no-store] unless it set
          [cache-control]. [vary] values are joined. A path with a literal
          backslash is the 404 page. An answer with a header name or value
          that holds CR, LF or NUL becomes a plain 500 and a log message. *)
    end

    val build_id : config -> 'req app -> string
    (** The build id: a digest of the route tree and, with [assets], of the
        entry, the manifest and the packages or the metafile. Every full
        document has [<meta name="yuka-build" content="ID">], and a response
        to [Yuka-Navigate] has the header [Yuka-Build: ID]; the client loads
        the page in full when the two differ. *)
  end

  (** {2 Prerender}

      The pure parts of a prerender; [Yuka_dream.prerender] runs them with
      a server. *)

  module Prerender : sig
    val config : config -> config
    (** The config a prerender renders with: [dev] off, whatever [~dev]
        says, so no static file gets the dev script or the dev state; and a
        page that renders a {!Yuka.Live.use} gives the 500 page and a log
        message instead of a file, since its state depends on the request.
        {!missing_page} uses it too. *)

    val seeds : 'req app -> string list
    (** The paths of the nodes with no param whose rules say
        [prerender]. *)

    val prerenderable : config -> 'req app -> 'req -> string -> bool
    (** Whether a [GET] of this path matches a page or an endpoint whose
        rules say [prerender]. A path that the cycle serves as a file
        ([/_yuka/], a [public] prefix) is not, even when a route such as a
        catch-all would match it. The query and fragment are ignored. *)

    val links : string -> string list
    (** The paths of the links of an HTML text: each [href="/..."],
        entities decoded, query and fragment removed, once each, in order.
        A link to another origin ([//host]) is not one. *)

    val file : string -> string option
    (** The file of a path, relative to the output directory: [/] gives
        [index.html], [/a/b] gives [a/b/index.html], and a last segment
        with a [.] ([/feed.xml]) gives [feed.xml]. Segments are
        percent-decoded; the query and fragment are ignored. [None] when a
        segment is empty, [.] or [..], or holds a slash, a backslash or a
        NUL byte after decoding. *)

    val missing_page : config -> 'req app -> sleep:(float -> unit Async.t) -> response Async.t
    (** The 404 page of the app, as for an unknown path: the [404.html] of
        a prerender. *)

    val css_files : config -> (string * string) list
    (** The sheets of [css] as paths relative to the site root
        ([_yuka/css/FILE]) and text. A prerender writes them. *)

    val served_dirs : config -> (string * string) list
    (** The URL prefixes and directories that the cycle serves files from:
        [("/_yuka/app", dir)] of [assets], then each [public] prefix. A
        prerender copies them. *)
  end

  (**/**)

  (** For the code generated by [yuka-routes --server] only. Not covered by
      semantic versioning: any release can change it. *)
  module Generated : sig
    type rules
    (** The merged route rules of one node. *)

    val rules :
      headers:(string * string) list list -> ?cache:cache -> prerender:bool -> unit -> rules
    (** [headers] holds one list per node from the root down. A header name
        (case-insensitive) of a later list replaces that name of the
        earlier ones; a name repeated in one list is kept. *)

    type layer = { key : string; data : bool; wrap : server element -> server element }
    (** A layout on the path of a route. [key] names its outlet; [data] is
        true when the layout takes a loader result, so a client navigation
        renders it again instead of keeping it; [wrap] puts the layout
        around its children. *)

    type plan = { layers : layer list; page : page }
    (** What a page route renders. [layers] are outermost first. *)

    type fallback = { layers : layer list; not_found : string -> page; error : unit -> page }
    (** The pages for a 404 ([not_found] gets the request path) and a 500,
        inside [layers]. *)

    val default_not_found : string -> page
    (** An [<h1>Not Found</h1>] page, for a [Routes.ml] without
        [not_found]. *)

    val default_error : unit -> page
    (** An [<h1>Internal Server Error</h1>] page, for a [Routes.ml] without
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
          action : bool;  (** An [Action] node: always [no-store]. *)
          cross_origin : bool;  (** No origin check for an unsafe method. *)
          guards : (unit -> (unit, stop) result Async.t) list;
          run : unit -> response Async.t;
        }

    val loaded :
      ('a, stop) result Async.t -> ('a -> ('b, stop) result Async.t) -> ('b, stop) result Async.t
    (** Chains a loader result. An [Error], a failed [Async] or an exception
        of the function gives an [Error]; the last two give [Fail]. *)

    val app :
      build:string ->
      headers:(string * string) list ->
      prerender:string list ->
      find:(Router.meth -> string list -> (string * string) list -> 'r Router.lookup) ->
      resolve:('req -> 'r -> target) ->
      missing:fallback ->
      'req app
    (** [build] is a digest of the route tree. [headers] are the rule
        headers of the root, sent with every 404 and 500 page. [prerender]
        lists the paths where {!Prerender.seeds} starts. [missing] gives the
        page when no route matches. *)
  end

  (** For Yuka's tests. Not covered by semantic versioning. *)
  module Testing : sig
    val context : ?header:(string -> string option) -> ?session:string -> unit -> context

    val live_run :
      ?node:Live.node ->
      sleep:(float -> unit Async.t) ->
      context ->
      verify_csrf:(string -> bool Async.t) ->
      token:(unit -> string) ->
      Live.connection ->
      unit Async.t
    (** Runs the live protocol on one socket until it closes, as
        [/_yuka/live] does:

        - The first message is [{"t":"hello","v":1,"csrf":T}]; another
          version closes with 4426, a token that [verify_csrf] refuses with
          4403, any other first message with 4400. The answer
          [{"t":"hello","v":1,"csrf":T'}] carries [token ()] for the next
          [hello] of the page.
        - [sub] ([id], [topic], [key]), [unsub] ([id]), [sync] ([id],
          [ref]) and [ping]. A subscription gets [state] messages ([id],
          [seq], [state]), or one [error] ([id], [code]: [unknown_topic],
          [bad_key], [forbidden], [rejected] with [message], [server],
          [limit]). [sync] is answered by [synced] after the latest state
          of the subscription.
        - On a slow socket, a newer state replaces a state that still waits
          to be sent.
        - Limits: a message over 64 KiB closes with 1009; more than 64
          subscriptions gives [limit]; a message out over 1 MiB is sent and
          logged; more than 256 replies waiting on a slow socket close it
          with 1008. No [hello] within 10 s, or no message for 60 to 120 s
          after it, closes with 4408. A [pong] carries a fresh token too.
        - [synced] with [ref] [R] answers every [sync] of the subscription
          with a [ref] up to [R].
        - A [sync] with [after] ([[[NODE, N], ...]], from the [live] mark of
          the action answer) waits until this node has heard note [N] of
          [NODE] (or [NODE] is this node) and every load of the key that
          those notes started has finished; then [synced] comes after the
          latest state. It waits 5 s at most (a lost note).
        - The function closes the socket once, when it ends the protocol
          itself (a limit, a failed send or receive, {!Live.revoke}); it
          does not close a socket that the client closed. *)

    val live_mark : ?node:Live.node -> unit -> (string * int) option
    (** The node name and the number of notes it sent. An action answer
        carries the mark of the handler's node as [live]: a [Live.mutate]
        that settles on another node waits until that node has heard those
        notes and loaded the key again. *)

    val set_log : (string -> unit) -> unit
    (** Where messages go outside a request: a render without the cycle,
        an [Action.call] on the server outside a render, and the default
        log of a {!Live.node}. Default: [prerr_endline]. *)

    val memory_down : Live.memory -> bool -> unit
    (** [memory_down m true] drops notes; [false] brings the bus back and
        calls each [on_restart] function. *)
  end

  (**/**)
end
