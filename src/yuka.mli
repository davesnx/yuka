val owner : (unit -> 'a) -> 'a * (unit -> unit)
(** [owner body] runs [body] in a new owner. Effects and memos created during [body]
    belong to it. The returned function disposes all of them: it stops the
    effects and runs their cleanups. The new owner is detached: disposing
    the owner that was current when [owner] was called does not dispose it,
    so call the returned function yourself. An exception in an effect of the
    new owner goes to the same {!Catch} or island as the current owner. *)

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
      browser, [Some value] is [value] itself, so a new [Some value] that wraps the same
      [value] is not a change there; on native it is. An exception raised by
      [equal] counts as a change. *)

  val get : ('a, _) signal -> 'a
  (** Reads the value. Inside an effect or a memo, the read is tracked. *)

  val peek : ('a, _) signal -> 'a
  (** Reads the value without tracking. *)

  val set : 'a t -> 'a -> unit
  (** Writes the value. On the server, raises [Invalid_argument] for a
      State made before the first server render or request of the process
      (a module-level State): the process has one copy for every request. *)

  val update : 'a t -> ('a -> 'a) -> unit
  (** Like [set], with a function of the current value. *)

  val memo : ?equal:('a -> 'a -> bool) -> (unit -> 'a) -> 'a read
  (** A derived value. It recomputes when a State it read changes. A
      recompute is a change only if [equal] says the new value differs.
      Default: the same equality as {!make}. *)

  val deferred : ?equal:('a -> 'a -> bool) -> ('a, _) signal -> 'a read
  (** A copy of a State that changes after the next paint. It starts with the
      value of the source. In the browser, after a change of the source, it
      takes the latest value of the source after the browser paints the next
      frame; values in between are skipped. A change made in a
      {!Browser.on_frame} handler waits for the paint of that frame. All
      deferred States that wait change in one {!batch}. Read it for a slow
      part of the page, and read the source for a fast part: the fast part
      paints first. The slow update is not shorter and not interruptible; it
      only comes later. When its owner is disposed, a waiting change is
      dropped. On the server and on native it always has the value of the
      source. [equal] is as in {!make}. *)

  external read_only : 'a t -> 'a read = "%identity"
  (** The same State, typed so that {!set} and {!update} on it do not
      compile. *)

  val untrack : (unit -> 'a) -> 'a
  (** Runs the function and returns its result. Its {!get} reads are not
      tracked: inside an effect or a memo, a change of such a State does not
      run it again. *)
end

val batch : (unit -> 'a) -> 'a
(** [batch body] runs [body] and returns its result. Effects that the writes in
    [body] make pending run once, after [body] returns, not after each write.
    Memos read inside [body] are up to date. A [batch] inside a [batch] (or
    inside an effect) runs its pending effects when the outermost one ends.
    When [body] raises, the pending effects still run, then the exception of
    [body] is raised again. Each event handler that {!on} or
    {!Browser.on_window} attaches runs in a [batch]: the DOM updates and
    the effects run once, after the handler returns. When the handler
    raises, its writes still update the DOM, then its exception and any
    exception of the update go to the {!Catch} or island around it. *)

module Effect : sig
  val after : ?cleanup:('r -> unit) -> (unit -> 'r) -> unit
  (** Runs the body after the DOM is up to date, and again after each change
      of a State it read with [State.get]. Use it for code that reads or
      changes the DOM, and for most other effects. The first run waits for the
      end of the current {!batch} or update; {!render}, hydration and the
      creation of a list row run in one, so the first run of an effect created
      in a component finds the elements of the component in the document.
      Outside a batch or an update, as at the top level of {!owner}, the first
      run is at once. A later run comes after the holes, the attributes, the
      lists and the {!before} effects that the same change runs. An effect
      whose owner is disposed before its first run never runs.

      During a server render it does nothing: the body and [cleanup] do not
      run. Before each re-run and when its owner is disposed, [cleanup]
      receives the result of the previous run, and effects created inside the
      previous run are disposed. Inside a {!Catch} or an island, an exception
      in the body, or in a cleanup that runs during a State change or an
      event handler, goes to that boundary. A cleanup that raises when its
      owner is disposed by a direct call (the function returned by {!owner},
      or {!stop}) raises to that caller. Elsewhere, an exception in one
      effect does not stop other effects; the first one is raised again after
      all pending effects ran. If effects and memos keep changing States they
      read for more than 100 update rounds, the pending work is dropped and
      [Failure] is raised. *)

  val before : ?cleanup:('r -> unit) -> (unit -> 'r) -> unit
  (** As {!after}, with other timing. The first run is at once, in the
      component body, before the elements of the component exist. A later run
      comes together with the holes, attributes and lists of the same change,
      parent effects first, so it can see the DOM before that change. Use it
      to compute a value that the markup of the component needs, or to read
      the DOM before it changes. An exception in the first run, outside a
      {!Catch} or an island, stops the effect and is raised to the caller. *)

  val on_change :
    ?equal:('a -> 'a -> bool) -> ('a, _) State.signal -> (prev:'a -> next:'a -> unit) -> unit
  (** Calls the function when the value changes, with the previous and the
      next value, with the timing of {!after}: the DOM is up to date. Not
      called for the value at creation, and never during a server render.
      Default [equal]: as in {!State.make}. *)
end

type trigger = [ `Idle | `Visible | `Interaction ]
(** An event that starts an island: the browser is idle, the island is
    visible, or the first interaction with it. *)

type start = [ `Load | trigger | `Lazy of trigger ]
(** When the browser downloads and starts an island, given as
    [<Yuka.Client start=`Idle> <Counter /> </Yuka.Client>]. An island
    component cannot have a prop named [start].
    - [`Load] (default): download and start when the page opens.
    - A trigger: download when the page opens, start at the trigger.
    - [`Lazy trigger]: download and start at [trigger]. Events before the
      start are recorded and replayed. The server prints no preload link for
      it.

    The early download of a non-lazy island happens through the
    [<link rel="modulepreload">] that the server prints from the manifest
    given to [Server.modules] or [Server.bundle]. With [Server.bundle], the
    server also preloads each chunk that the island or the entry imports
    statically, directly or through other chunks. An island without a
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
  (** A number without ['.'], ['e'] or ['E'] that fits an [int] is [`Int];
      any other number is [`Float]. An [int] has 63 bits on native and 32
      bits in the browser, so a number such as [5000000000] is [`Int] on the
      server and [`Float] in the browser; {!Codec.int} accepts both. Arrays
      and objects nested more than 512 levels are an error. *)
end

module Async : sig
  type 'a t = 'a Async.t
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
      failure with the same message. An exception that the function raises
      gives [Failed] with the exception as text. *)

  val bind : 'a t -> ('a -> 'b t) -> 'b t
  (** Like [map], with a function that gives an [Async]. *)

  val watch : 'a t -> 'a status State.read
  (** A State that follows the status. *)
end

module Codec = Codec

type server
(** The kind of an element that only the server prints. *)

type client
(** The kind of an element that can run in the browser: it can have
    handlers ({!on}) and holes ({!hole}). *)


type +'kind element = 'kind Kind.element
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

  val client_x : t -> float
  (** The horizontal position of the pointer, in CSS pixels from the left
      edge of the viewport ([clientX]). For a mouse or pointer event only. *)

  val client_y : t -> float
  (** The vertical position of the pointer, in CSS pixels from the top edge
      of the viewport ([clientY]). For a mouse or pointer event only. *)
end

val text : string -> 'kind element
(** A text node. The server escapes it. *)

val int : int -> 'kind element
(** The text of [string_of_int]. *)

val float : float -> 'kind element
(** Printed as JSON prints a float: [1.0], [2.5]. Not-a-number and the
    infinities are printed as [NaN], [Infinity] and [-Infinity]. *)

val empty : 'kind element
(** Nothing. *)

val fragment : 'kind element list -> 'kind element
(** The elements one after another, with no wrapper element. *)

val element : string -> 'kind attribute list -> 'kind element list -> 'kind element
(** [element tag attributes children]: an HTML element. The ppx makes it from
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
    first block with the [log] of {!Server.val-config} (level [`Warn]); a dev build logs the first one in
    the console. [data:] is also blocked on [src] of [script] and [href] of
    [script]. [srcdoc] of [iframe] and [href] of
    [base] become [""] and are logged the same way; only a literal one in
    [.mlx] is kept. A [name] that is empty, starts with [on] (any case:
    use {!on}), or has a space, a control character, a quote, [<], [>], [/]
    or [=] raises [Invalid_argument] (in the browser here, on the server
    when printed). *)

val hole : (unit -> client element) -> client element
(** A part that changes after the first render. The function runs once; it
    runs again when a State it read changes, and its output replaces the old
    output. *)

val hole_attr : string -> (unit -> string option) -> client attribute
(** An attribute whose value changes. [None] removes the attribute. On the
    client, [value], [checked] and [selected] are set as properties. A URL
    attribute gets the check of {!attr} on each value. *)

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
      a hole over [Async.watch]. On the server it is printed as a hole.
      In a server render, [message] is the message of a
      {!Server.Action.reject}, else ["server error"], and the failure
      message goes to the [log] of {!Server.val-config}, so the HTML never has the
      detail. *)
end

val suspend :
  loading:server element ->
  ?failed:(string -> server element) ->
  server element Async.t ->
  server element
(** Shows [loading] until the element is settled, then the element, or
    [failed message] (default: nothing), with the [message] rule of
    {!Await.make}. It streams as [<Yuka.Await>] does.
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
      the [log] of {!Server.val-config}; the HTML never has the detail. In an island, the
      client then hydrates the fallback, and [reset] renders the children in
      the browser. *)
end

module Status = Status

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
      changes, by the default equality of {!State.make}. *)
end

val on : string -> (Event.t -> unit) -> client attribute
(** [on "click" handler]. *)

val each :
  ?equal:('a -> 'a -> bool) ->
  key:('a -> string) ->
  (unit -> 'a array) ->
  ('a -> client element) ->
  client element
(** A keyed list. The array function is tracked as a hole. An item whose key
    stays keeps its DOM nodes; it renders again when [equal] says its value
    changed. Default [equal]: identity, as in {!State.make}. Two items with
    the same key raise [Failure] on an update. [each] reads the array only
    while it renders: it keeps the items, not the array, so a later write
    into that array changes nothing on the page. To show a change, give a
    new array ({!State.set} with the same array is no change). For a list,
    [fun () -> Array.of_list (State.get items)]. *)

type stylesheet
(** A CSS file of a module, made by [module Css = [%yuka.css "file.css"]].
    The ppx gives [Css.stylesheet] and one [string] per class of the file,
    [Css.row] for [.row], with a name scoped to the file. *)

val use_css : stylesheet -> 'k element -> 'k element
(** [use_css sheet element] is [element] with [sheet] in the page. On the
    server, the page gets [<link rel="stylesheet">] once, before the first
    element that uses it; the sheets of an island are printed before its
    [<yuka-island>]. In the browser, a [link] is added to [<head>] if the
    document has none for this sheet. The ppx calls it in every function
    named [make] that comes after [[%yuka.css]] in the same file. *)

module Client : sig
  type registry
  (** The islands of an app. [yuka islands] writes it; pass it to
      {!render}. *)

  type container
  (** A DOM element that holds a rendered tree. *)

  val container : string -> container option
  (** The element with this id. [None] when the document has no such
      element, and outside the browser. *)
end

module Action : sig
  type ('i, 'o, 'kind) t = ('i, 'o, 'kind) Action.t
  (** ['kind] is [[ `Mutation ]] for {!mutation}, [[ `Query ]] for {!query}
      and [[ `Form ]] for {!Form.val-action}. *)

  val mutation :
    name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Mutation ]) t
  (** An action named [name] that can change data: the server and the client
      must declare it with the same name and codecs. The server runs it
      after {!Server.Action.make}. *)

  val query :
    name:string -> input:'i Codec.t -> output:'o Codec.t -> ('i, 'o, [ `Query ]) t
  (** Like {!mutation}, for a read with no side effect: a server render may
      run it and {!Remote.use} may retry it. Same endpoint and wire format. *)

  val name : (_, _, _) t -> string
  (** The name given to {!mutation} or {!query}. *)

  val call : ('i, 'o, _) t -> 'i -> ('o, Status.error) result Async.t
  (** Encodes the input, sends it to the server (in the browser after
      [render ~islands], as [POST /_yuka/action/<name>]; on the server, to the
      implementation), decodes the output. The [Async] is always [Done]:
      - [Ok output]: the output.
      - [Error (Rejected message)]: the server refused the input (400); [message] is
        for the user.
      - [Error Forbidden]: the origin check failed (403).
      - [Error Not_found]: no implementation has this name (404).
      - [Error Server]: the implementation raised or failed (500); the
        detail is in the server log.
      - [Error (Network message)]: no answer. [message] is ["cancelled"] when the owner
        of the call was disposed or {!stop} ran.
      - [Error (Protocol message)]: the answer or the output did not decode. *)
end

module Remote = Remote

module Topic : sig
  (** A kind of live state ({!Live}): a name, the codec of its key and the
      codec of its state. One topic has one state per key. *)

  type ('k, 's) t = ('k, 's) Topic.t

  val declare : name:string -> key:'k Codec.t -> state:'s Codec.t -> ('k, 's) t
  (** The server and the client must declare it with the same name and
      codecs. *)

  val name : (_, _) t -> string
end

module Live = Live

module Form = Form

module Browser : sig
  val on_window : string -> (Event.t -> unit) -> unit
  (** Listens on [window] until the current owner is disposed. The handler
      runs in a {!batch}. Browser only: call it inside [Effect.after]. *)

  val navigate : string -> unit
  (** Browser only: raises [Failure] on native. Loads the URL. After [render ~islands] with navigation (the default), it
      is a client navigation, as a click on a link; see {!render}. Otherwise it
      does [location.assign url]. A [javascript:], [vbscript:] or [data:]
      URL (read as {!attr} reads a URL) does nothing; a dev build logs the
      first one. *)

  val navigating : bool State.read
  (** [true] while a client navigation is in flight: from the click on a
      link, [popstate] or {!navigate} (also while the navigation code
      loads) until the new page is shown, a full page load starts in its
      place, or {!stop}. A navigation that a newer one aborts leaves it
      [true] for the newer one. Read it with {!State.get} in an island, for
      example to show a progress bar. Always [false] on the server and
      without client navigation. *)

  val replace_url : string -> unit
  (** Browser only: raises [Failure] on native. Sets the URL of the current
      history entry ([history.replaceState]) and loads nothing: no request,
      no new entry, the page and its islands stay. A reload, back and
      forward to this entry, and a client navigation back to it load the
      new URL. Use it to keep the state of a page, such as a filter, in its
      query, so the URL can be shared. A URL on another origin, or a
      [javascript:], [vbscript:] or [data:] URL, does nothing; a dev build
      logs the first one. *)

  val focus : string -> unit
  (** Focuses the element with this id; does nothing when no element has
      it. Inside a {!batch} (an event handler), it runs after the batch
      updated the DOM, so it finds an element that a write of the handler
      creates. Browser only: raises [Failure] on native. *)

  val scroll_into_view : string -> unit
  (** Scrolls the element with this id into view; does nothing when no
      element has it. Inside a {!batch}, it runs as {!focus} does. Browser
      only: raises [Failure] on native. *)

  val on_frame : (float -> unit) -> unit
  (** Calls the handler before each repaint of the browser
      ([requestAnimationFrame]) until the current owner is disposed, with the
      time of the frame in milliseconds, on the clock of {!now}. The handler
      runs in a {!batch}. Browser only: call it inside [Effect.after]. *)

  val now : unit -> float
  (** Milliseconds since the page opened, with a fraction
      ([performance.now]). Browser only: raises [Failure] on native. *)

  val count_elements : string -> int
  (** The number of elements in the document that match the CSS selector
      ([querySelectorAll]). Browser only: raises [Failure] on native. *)
end

module Console : sig
  (** Messages for the developer, from code that runs on the server and in
      the browser. In the browser, each function calls the [console] method
      of its name. On the server, it sends the level and the message to the
      [log] of {!Server.val-config} during a server render of a request, and
      to the default sink otherwise ({!Server.Testing.set_log}). A prototype:
      the API can change. *)

  val log : string -> unit
  (** [console.log]; level [`Info] on the server. *)

  val info : string -> unit
  (** [console.info]; level [`Info] on the server. *)

  val warn : string -> unit
  (** [console.warn]; level [`Warn] on the server. *)

  val error : string -> unit
  (** [console.error]; level [`Error] on the server. *)

  val debug : string -> unit
  (** [console.debug]; level [`Debug] on the server. *)
end

(**/**)

(** {1 Runtime}

    The types and values from here to {!Private} are for the code that
    [yuka.ppx], [[@@deriving codec]], [[@@deriving form]], [[%yuka.css]]
    and [yuka islands] write. They are not part of the API: they are not
    covered by semantic versioning, and any release can change or remove
    them. Do not call them. *)

type runtime_template
(** A compiled element tree: the ppx makes one per lowercase JSX tree, at
    the top of the module. *)

type 'kind runtime_part
(** The value of one part of a {!type-runtime_template}. *)

type runtime_entry
(** What the browser knows about an island. The island modules expose it
    as [register]. *)

type runtime_lazy_entry
type 'a runtime_promise
(** A JavaScript promise, as made by a dynamic [import]. *)

type runtime_router
(** The value [router] of the module [yuka/navigation.js]. *)

type 'f runtime_form_decoding

val runtime_attr : string -> string -> 'kind attribute
val runtime_hole_attr : string -> (unit -> string option) -> client attribute
(** {!attr} and {!hole_attr} for names that the ppx proved are not URL
    attributes. They raise [Invalid_argument] on a URL attribute name,
    [srcdoc], or a name that {!attr} refuses (an [on] name too). They do
    not refuse [to], [from], [values] and [by], which are URL names only on
    SVG animation elements: there the client checks the value, or raises
    [Failure] when the app links no URL check. *)

val runtime_url_attr : string -> string -> string -> 'kind attribute
val runtime_url_hole_attr : string -> string -> (unit -> string option) -> client attribute
(** [runtime_url_attr tag name value] is {!attr} that knows the element. *)

val runtime_template :
  string ->
  html:string ->
  walk:int array ->
  kids:int array ->
  attrs:int array ->
  values:(int * string) array ->
  clones:int ->
  runtime_template
(** [code] is the shape in the form of [Template_build.encode], and the
    other arguments are computed from it at build time, where the ppx also
    checks the fixed attributes and lowers a tree that the HTML parser would
    change. [clones]: bit 1 when the parse of [html] in a [<template>] keeps
    the tree, bit 2 when its parse inside an [<svg>] does; the client clones
    only in such a context and otherwise builds the tree element by element.
    The browser clones [html] as given and the server prints a fixed
    [srcdoc] or [base] [href] as given. The client decodes [code] only to
    hydrate and in a dev build. Part numbers count from 0. *)

val runtime_child : 'kind element -> 'kind runtime_part
val runtime_attribute : 'kind attribute -> 'kind runtime_part
val runtime_attribute_option : 'kind attribute option -> 'kind runtime_part
(** [None] writes no attribute. *)

val runtime_instance : runtime_template -> 'kind runtime_part array -> 'kind element
(** The tree of the template with its parts filled in. It prints and
    hydrates as the same tree made with {!val-element}. *)

val runtime_stylesheet : string -> stylesheet
(** The sheet served at this URL. *)

val runtime_island :
  ?start:start -> name:string -> props:Json.t -> (unit -> client element) -> server element
(** A client component placed in a server tree. The server prints its HTML
    and its props. *)

val runtime_slot : server element option -> client element
(** The children of an island: [Some] content on the server, [None] on the
    client, which keeps the DOM nodes the server printed. *)

val runtime_entry : name:string -> (Json.t -> (unit -> client element, string) result) -> runtime_entry
(** It decodes the props and gives the function that builds the
    component. *)

val runtime_lazy_entry : name:string -> (unit -> runtime_entry runtime_promise) -> runtime_lazy_entry
(** An island whose code is loaded on demand. [load] is called, at most
    once, when the start strategy of an island named [name] fires. If it
    fails, the island keeps its server HTML and the error is logged. *)

val runtime_promise_map : ('a -> 'b) -> 'a runtime_promise -> 'b runtime_promise
(** [then] of a JavaScript promise. *)

val runtime_registry :
  ?lazy_entries:runtime_lazy_entry list ->
  ?navigation:(unit -> runtime_router runtime_promise) ->
  runtime_entry list ->
  Client.registry
(** [navigation] loads the client navigation code with a dynamic [import]
    of [yuka/navigation.js]. Without it, {!render} starts the islands only,
    as with [~navigation:false]. *)

val runtime_form_fields :
  names:('f * string) list ->
  decode:('f runtime_form_decoding -> ('i, 'f Form.errors) result) ->
  encode:('i -> (string * string) list) ->
  ('i, 'f) Form.t

val runtime_form_field : 'f runtime_form_decoding -> 'f -> string -> 'a Form.kind -> 'a option
val runtime_form_get : 'a option -> 'a
(** Raises [Invalid_argument] on [None]. *)

val runtime_form_finish : 'f runtime_form_decoding -> (unit -> 'i) -> ('i, 'f Form.errors) result
val runtime_form_put : string -> 'a Form.kind -> 'a -> (string * string) list

(** {1 Private}

    For the tests of Yuka. Not covered by semantic versioning: any release
    can change or remove it. *)

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
        start : start;
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
        items : unit -> 'a array;
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

  and template = runtime_template
  and part = Child of node | Attribute of attr | No_attribute
  and slot

  module Template : sig
    type shape
    type attr

    val text : string -> shape
    (** A fixed text. *)

    val element : string -> attr list -> shape list -> shape
    (** [element tag attrs children]: an HTML element. *)

    val part : int -> shape
    (** The child at this place is part [index], made with {!runtime_child}. *)

    val fixed : string -> string -> attr
    (** [fixed name value]: an attribute with a fixed value, checked by
        {!template}. *)

    val part_attr : int -> attr
    (** The attribute at this place is part [index], made with
        {!runtime_attribute} or {!runtime_attribute_option}. *)

    val make :
      shape ->
      html:string ->
      walk:int array ->
      kids:int array ->
      attrs:int array ->
      values:(int * string) array ->
      template
    (** A template with [html] and the paths given by hand. Nothing is
        checked: the browser puts [html] in the page as given and the server
        prints a fixed [srcdoc] or [base] [href] as given. The client checks
        the parsed [html] against [shape] once. *)
  end

  val template : Template.shape -> template
  (** A template written by hand: checks the tag names and the fixed
      attributes (names, and URLs, [srcdoc] and [base] [href] as {!attr}
      does, with the element known) and computes its HTML and the paths to
      its parts with the code that the ppx runs at build time. Raises
      [Invalid_argument] on a bad tag or attribute name. *)

  val recompile : template -> template
  (** [template (template_shape original)]: the template again, with its HTML and
      paths computed at run time. Tests compare it with what the ppx
      emitted. *)

  val template_plan :
    template -> int array * int array * int array * (int * string) array
  (** The [walk], [kids], [attrs] and [values] given to {!Template.make}. *)

  val parser_changes : svg:bool -> Template.shape -> bool
  (** The build-time nesting check of the ppx: [true] when the HTML parser
      could build another tree from the HTML of the shape, parsed in a
      [<template>] ([svg:false]) or in an [<svg>] in a [<template>]
      ([svg:true]). The ppx lowers such a template with {!val-element}. *)

  val node : 'kind element -> node

  val dev_events :
    state:(unit -> string) -> sleep:(float -> unit Async.t) -> (string -> unit Async.t) -> unit Async.t
  (** The body of [/_yuka/dev] for a state function (tests). *)

  val dev_script : string -> string
  (** The script that a page gets with [Server.config ~dev:true], for the
      state JSON given (tests). *)

  val element : node -> 'kind element

  val hole : (unit -> node) -> node
  (** [Hole compute]. [node] is private, so that a test cannot build a node kind
      without the constructor that installs its client code. *)

  val owned : (unit -> 'a) -> 'a * (unit -> unit)
  (** Like {!owner}, but the new owner belongs to the current owner: it is
      disposed with it. *)

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
  (** The tree of a template instance, as {!val-element} would make it. *)

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
  (** Where [Codec.async] decoding finds the value of a bare reference.
      Default: a failed [Async]. [render ~islands] sets it to read the
      values that the page writes; that reader is installed by the first
      [Codec.async] decoding of a bare reference, and a call before it raises
      [Failure]. *)

  val render_html : (unit -> node) -> string
  (** Like [to_html], but also builds the tree with [server_rendering] true,
      so effects in component bodies do nothing. *)

  val to_html : node -> string
  (** Prints the tree as HTML with its hydration markers. Holes
      and lists run once. [server_rendering] is true during the call. *)

  val entry_name : runtime_entry -> string
  val entry_decode : runtime_entry -> Json.t -> (unit -> node, string) result

  val slot : slot -> client element
  (** Puts the slot where its content goes. *)

  module Slot : sig
    val make : server element -> slot
    (** A slot with this server content. *)

    val empty : unit -> slot
    (** A slot with no content, as the client decodes it. *)
  end

  val slot_content : slot -> node option
  (** The server element of the slot, if it has one. *)

  val slot_dom : slot -> Obj.t list ref
  (** The DOM nodes the client captured for the slot. Empty at first. *)

  val owner_size : unit -> int
  (** The number of live disposers of the current owner (0 outside an
      owner). For tests. *)

  val has_readers : ('a, _) State.signal -> bool
  (** Whether an effect or a memo reads the State. For tests. *)

  val call_action : (string -> Json.t -> (Json.t, Status.error) result Async.t) ref
  (** The transport of [Action.call]. Default: [Error (Network _)].
      [render ~islands] sets it to the browser transport; that transport is
      installed by the first [Action.call] or island form submit, and a call
      before it raises [Failure]. *)

  val server_rendering : bool ref
  (** When true, [Effect.after] and [Effect.before] do nothing. *)

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
    client_x : Event.t -> float;
    client_y : Event.t -> float;
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
    ?preload:(string -> string list) ->
    sleep:(float -> unit Async.t) ->
    write:(string -> unit Async.t) ->
    (unit -> server element) ->
    unit Async.t
  (** The streamed document that the request cycle sends, for tests. *)

  val settled :
    ?timeout:float ->
    ?preload:(string -> string list) ->
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
    manifest:string -> base:string -> ?metafile:string -> ?entry:string -> unit -> string -> string list
  (** The URLs to preload for an island name. Without [metafile]: the
      manifest path under [base]. With [metafile]: the output of the island
      and every output it reaches through static imports, then the outputs
      that [entry] reaches the same way, without [entry] itself. *)

  val handle_action :
    name:string -> header:(string -> string option) -> body:string -> (int * string) Async.t

  val render : Client.container -> (unit -> 'k element) -> unit -> unit
  (** [render container app] clears [container], builds the DOM of [app ()] and
      returns a function that stops the effects and handlers of this tree,
      for tests. Browser only. *)

  val hydrate : Client.container -> (unit -> 'k element) -> unit -> unit
  (** [hydrate container app] adopts the server DOM in [container] (written
      with the markers of {!to_html}), attaches handlers and starts holes.
      Where the DOM does not match, it creates the missing nodes. In a dev
      build (see {!render}), each mismatch (a missing node, another tag,
      another text, an extra node) logs one [console.warn] with the island
      name, the expected and the found node, and a short path. Returns a
      function that stops all effects and handlers. Browser only. *)
end

(**/**)

module Router : sig
  (** The members that the code generated by [yuka routes] calls.

      The tree in [Routes.ml] is not compiled. It is in its own syntax,
      written with OCaml expressions, that only [yuka routes] reads. The
      names [Router.make], [Router.group], [Router.route],
      [Router.endpoint], [Router.action] and [Router.redirect] are nodes of
      that syntax, not values of this module, so an editor does not check
      the file; [yuka routes] reports each error with its location in
      [Routes.ml]. The file ends with the tree, [Router.make ... [ nodes ]].
      Items before it ([open], [let], [module], [type]) go as written to the
      top of the server module only, so attachments can be short
      ([~page:home] after [open Pages]); the shared module does not get
      them. A file with items binds the tree as
      [let routes = Router.make ...]. A file with only the tree:
      {[
        Router.make ~not_found:Pages.not_found ~error:Pages.error
          [
            Router.route Home ~path:"/" ~page:Pages.home;
            Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue
              [ Router.route Issue ~path:"/" ~page:Pages.issue ];
            Router.endpoint Feed ~path:"/feed.json" ~method_:`GET
              ~handler:Handlers.feed;
            Router.redirect ~path:"/old" ~to_:(Permanent "/");
          ]
      ]}
      Attachments such as [~page], [~layout], [~handler], [~guard],
      [~not_found] and [~error] are value paths of the app; the generated
      code calls them.

      [yuka routes --shared --source Routes.ml] writes the shared [Routes]
      module: the route type [t]; a link function for each named node, named
      as the node in lowercase, that takes each path param as a labelled
      argument, each search field as an optional argument, then
      [?fragment], and [()] ([Routes.issue ~id:"YUK-1" ()] is
      ["/issue/YUK-1"]; [Routes.issue ~id:"YUK-1" ~fragment:"comments" ()]
      is ["/issue/YUK-1#comments"]; [~fragment:""] adds [#] alone); [href], which
      turns a [Routes.t] (for example from [find]) into a URL; and [find]. A
      node name whose link function is an OCaml keyword or [href], [find],
      [with_query] or [with_fragment] is a build error, and so is a param,
      search field or loader named [fragment]. Then
      [yuka routes --server --shared-module Routes --source Routes.ml] writes the
      server module with [app]. *)

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

  (** How a path param or a search field turns into a value and back. A
      custom type is written with its module path, [:tab<Model.tab>] in a
      path or [optional Model.tab] in a search, and uses the value of the
      codec rule: [Issue_id.t] uses [Issue_id.param], and [Model.tab] uses
      [Model.tab_param]. *)
  module Param = Router_param

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
  (** [Param.decode Param.int], which the generated code calls inline. Use
      {!Param.int}. *)

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
    [~islands:Yuka_islands.registry], the islands of the app. After a
    top-level [open Yuka], a bare [render] call is rewritten the same way,
    up to the next top-level [open]. The rewrite does not apply where a
    binding of [islands] is in scope (a [let], a function parameter or a
    [match] or [function] case), or, for the bare [render], where a binding
    of [render] is in scope. Names that an [open] or an [include] brings in
    are not seen.

    [~root:(container, app)] clears [container] and builds the DOM of
    [app ()] in it. {!stop} stops the effects and handlers of this tree;
    the DOM stays. It runs before the islands start. Get [container] with
    {!Client.val-container}.

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
    requested before it is not kept. [render ~islands] and {!stop} empty it and
    abort the prefetches nobody waits for; after {!stop} no navigation
    updates the page.

    With [~transitions:true], where [document.startViewTransition] exists,
    the page update runs inside a view transition, and [<html>] has
    [data-yuka-nav="push"], ["back"] or ["forward"] until the last one
    ends. The URL, history and navigation state change before the
    transition starts; an exception in the update is thrown again in a
    task, as an uncaught error.

    The code that fetches and swaps pages is not in the JavaScript that the
    page loads at start. It is loaded with a dynamic [import] of
    [yuka/navigation.js] on the first click on such a link, [popstate],
    {!Browser.navigate}, or pointer, focus or touch on a link that it would
    prefetch (at once with [`Visible] prefetch or a
    [data-yuka-prefetch="visible"] link). Until it arrives, the click is
    already prevented and the events wait in order. If the load fails, or
    does not finish within 3 s of the first such event, it is logged once
    with [console.error], the waiting navigations do [location.assign], and
    until the next {!render} there is no new attempt: links, [popstate] and
    {!Browser.navigate} load full pages.

    With [~navigation:false] only the islands start, links load full pages
    and the navigation code is never loaded. Calling [render ~islands] again is safe: the listeners are not
    added twice.

    Without [~islands], [~navigation], [~prefetch], [~transitions] and
    [~on_error] do nothing. Raises [Failure] outside the browser, and
    [Invalid_argument] without [~islands] and [~root]. An app that does not
    pass [~islands] contains no island, action or navigation code.

    Dev checks: unless the bundler defines the global [__YUKA_DEV__] as
    [false] (for example esbuild [--define:__YUKA_DEV__=false]), the client
    runs dev checks: hydration mismatch warnings, blocked URL logs and other
    [console] messages. When [__YUKA_DEV__] is not defined at all, the
    checks are on, so a production bundle must define it. *)

val stop : unit -> unit
(** Stops every tree that {!render} started: each [~root] tree and every
    island. Effects, handlers and document listeners are removed, start strategies that did not fire yet are
    cancelled, and action requests in flight are aborted (their [Async]
    gives [Error (Network "cancelled")]). It also stops navigation: the [click] and
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

  type log_level = [ `Error | `Warn | `Info | `Debug ]
  (** The level of a message to the server log ([log] of {!val-config}). *)

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
    val make : ('i, 'o, _) Action.t -> (context -> 'i -> 'o Async.t) -> unit
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
        400 [{"error": message}], [Action.call] on the server gives
        [Error (Rejected message)], and a form renders the page again with
        the message as a form error. Any other failure or exception is a 500
        with a generic message ([Error Server] for [Action.call] on the
        server). *)
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

    val node : ?log:(log_level -> string -> unit) -> ?per_session:int -> ?total:int -> unit -> node
    (** A new, empty node, for example for a second handler in one process.
        [log] gets the failures of loaders and of the bus. Without it
        (and for the default node), the node logs to the [log] of the
        config of the last request that a handler served on this node, and
        to the default sink (see {!Testing.set_log}) before the first request. [per_session] (default 16) and [total] (default
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
        ([revoke (fun context -> Context.session context = Some id)]) and after a
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
        path ([POST /_yuka/action/<name>], JSON) like {!Action.make},
        with [redirect output] in the answer (checked as for the 303 below: a
        bad one answers 500 [action failed] and is logged), and the form
        post of a page. The request cycle checks the origin (403), runs the
        guards of the page the form is posted to (a refusal answers as for
        [GET] and the function does not run), reads at most 1 MiB of body
        (413), decodes the posted fields, calls the function, and answers
        303 to [redirect output] (default: the page URL) on [Ok output], or renders
        the page again with status 422 and the sent values and errors on
        [Error], a decode error or {!Action.reject}. The form field
        [_yuka_action] names the action, so a post to any [GET] page can run
        any form action: the function checks permissions itself, as for
        {!Action.make}. Only [application/x-www-form-urlencoded] posts
        reach a form action; a [multipart/form-data] post (a file input) is
        a 405. The 303, 403 and 413 carry the page's rule headers. A
        [redirect output] that is not a path ([/x], not [//x]) or an [http:] or
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
      implements {!Adapter.Backend}. *)

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
        (** The error page, status 500. The message goes to [log],
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
  (** Default status: 200; default headers: none. [response (Stream producer)]
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
  (** The routes of an app, from the code generated by [yuka routes
      --server]. ['req] is the request type of the adapter: the generated
      code passes the request to each loader, guard and handler. *)

  type assets
  (** Where the client JavaScript is. The cycle serves it under
      [/_yuka/app/]. *)

  val modules :
    dir:string -> entry:string -> manifest:string -> packages:string list -> digest:string -> assets
  (** The Melange module tree. [dir] is the emit directory, [entry] the path
      of the entry module in it (served as [/_yuka/app/<entry>]), [manifest]
      the JSON text that [yuka islands --manifest] prints (paths relative to
      the directory of [entry]), and [packages] the npm packages under
      [dir/node_modules] for the import map. [digest] stands for the content
      of the files (for example [Yuka_dream.tree_digest dir]): it goes into
      the build id, so new JavaScript gives a new build id. Files get
      [cache-control: no-cache]. Raises [Invalid_argument] when [manifest]
      is not a JSON object of strings. *)

  val bundle :
    dir:string -> entry:string -> manifest:string -> metafile:string -> assets
  (** An esbuild bundle. [metafile] is the text of the JSON report that
      esbuild writes with [--metafile=FILE]: the server reads the hashed
      name of each output and its static imports from it. [dir] is the directory esbuild ran in, so that the
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
    ?log:(log_level -> string -> unit) ->
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
      and text; the generator [yuka css] writes it ([Yuka_css.sheets]). The
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

      [log] gets what the client must not see, as [`Error] (an action that
      failed, a failed render, a failed async value, a refused redirect or
      header) or [`Warn], and the {!Yuka.Console} calls of a server render
      of a request. Without it, the adapter may give its own log
      ({!Adapter.default_log}); else messages go to the default sink: one
      line on stderr, [yuka: LEVEL MESSAGE], without [`Debug]. This is a
      prototype: the sink type can change. *)

  (** {2 Adapters} *)

  module Adapter : sig
    (** What a server provides to run the cycle. *)
    module type Backend = sig
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

    (** A request handler for the server of [Backend]. *)
    module Make (Backend : Backend) : sig
      val handler : ?node:Live.node -> config -> Backend.request app -> Backend.request -> Backend.reply Async.t
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
            [{"csrf":TOKEN}] from {!Backend.csrf_token} with [no-store] (the live
            client renews an expired token with it); 403 for another
            origin, 405 for another method. [/_yuka/live]: for [GET] with
            the same origin rule and [Upgrade: websocket], [Backend.upgrade] with
            the live protocol; 403 for another origin, 426 without the
            upgrade header, 405 for another method, and a 500 with a log
            message when {!Backend.session} raises (no session middleware). [/_yuka/app/<file>]: the
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
          + Guards, one after another. A {!type-stop} skips the rest.
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
            let [shared] be the length of the common prefix of the sent keys and
            the layer keys of the page (or of the fallback, for a 404 or
            500). [shared = 0]: the settled document in one string. [shared >= 1]:
            only what goes inside outlet [shared], settled, with the headers
            [Yuka-Outlet] (its key) and [Yuka-Title] (percent-encoded);
            island, await and async ids get the prefix [KEY-]. Both have
            [Yuka-Build] ({!build_id}).

          A 404 or 500 page has the root [headers] and [no-store]. A
          failure before the response is returned (shell, or a fill that
          already failed) gives the 500 page. After it the status is sent:
          the failure goes to [log], nothing more is written (no
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

    val default_log : (log_level -> string -> unit) -> config -> config
    (** [default_log sink config] is [config] with [log] set to [sink]
        when [config] has no [log], else [config]. An adapter calls it to
        send messages to the log of its server ([Yuka_dream.handler] uses
        [Dream.sub_log "yuka"]). *)

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

  (** For the code generated by [yuka routes --server] only. Not covered by
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
        carries the mark of the handler's node as [live]: a [Live.optimistic]
        that settles on another node waits until that node has heard those
        notes and loaded the key again. *)

    val set_log : (log_level -> string -> unit) -> unit
    (** Replaces the default sink: where messages go outside a request (a
        render without the cycle, an [Action.call] on the server outside a
        render, a {!Yuka.Console} call outside a render), and the log of a
        config without [log] and of a {!Live.node} without [log]. Default:
        one line on stderr, [yuka: LEVEL MESSAGE], without [`Debug]. *)

    val memory_down : Live.memory -> bool -> unit
    (** [memory_down memory true] drops notes; [false] brings the bus back and
        calls each [on_restart] function. *)
  end

  (**/**)
end
