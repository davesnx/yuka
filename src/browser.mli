val on_window : string -> (Event.t -> unit) -> unit
(** Listens on [window] until the current owner is disposed. The handler
    runs in a {!Yuka.batch}. Browser only: call it inside [Effect.after]. *)

val navigate : string -> unit
(** Browser only: raises [Invalid_argument] on native. Loads the URL. After [render ~islands] with navigation (the default), it
    is a client navigation, as a click on a link; see {!Yuka.render}. Otherwise it
    does [location.assign url]. A [javascript:], [vbscript:] or [data:]
    URL (read as {!Yuka.attr} reads a URL) does nothing; a dev build logs the
    first one. *)

val back : unit -> unit
(** Browser only: raises [Invalid_argument] on native. Closes the overlay
    that a client navigation to a route with [?overlay] showed: when the
    history entry before it is the page under the overlay, it does
    [history.back()], which removes the overlay with no request; else it
    is a client navigation to the URL of the page under the overlay.
    Without an overlay it does [history.back()]. *)

val navigating : bool State.read
(** [true] while a client navigation is in flight: from the click on a
    link, [popstate] or {!navigate} (also while the navigation code
    loads) until the new page is shown (for a streamed answer, its first
    part, with the [loading] content of the pending [await]s), a full page
    load starts in its place, or {!Yuka.stop}. A navigation that a newer one aborts leaves it
    [true] for the newer one. Read it with {!Yuka.State.get} in an island, for
    example to show a progress bar. Always [false] on the server and
    without client navigation. *)

val replace_url : string -> unit
(** Browser only: raises [Invalid_argument] on native. Sets the URL of the current
    history entry ([history.replaceState]) and loads nothing: no request,
    no new entry, the page and its islands stay. A reload, back and
    forward to this entry, and a client navigation back to it load the
    new URL. Use it to keep the state of a page, such as a filter, in its
    query, so the URL can be shared. A URL on another origin, or a
    [javascript:], [vbscript:] or [data:] URL, does nothing; a dev build
    logs the first one. Islands that read the route ([Routes.current]) do not see the new
    URL; to change the route of the page, use [Routes.replace]. *)

val set_cookie :
  ?max_age:int ->
  ?path:string ->
  ?same_site:[ `Lax | `Strict | `None ] ->
  ?secure:bool ->
  string ->
  string ->
  (unit, string) result
(** Browser only: raises [Invalid_argument] on native. [set_cookie name value]
    writes a cookie with [document.cookie], so the server reads it in the
    next request. [value] is encoded as UTF-8 and percent-encoded: each
    byte other than [A-Z a-z 0-9 - . _ ~] becomes [%XX], so decode it on
    the server. [max_age] is in seconds; without it the
    cookie ends with the browser session, and [~max_age:0] removes it.
    [path] defaults to ["/"], [same_site] to [`Lax]. [`None] also sets
    [Secure], as browsers require. Gives [Error] for a name that is not a
    cookie token (letters, digits and [! # $ % & ' * + - . ^ _ ` | ~]) and
    for a path that does not start with ['/'] or holds a [';'] or a control
    character, and for a value that is not valid UTF-16 (a lone surrogate);
    then nothing is written. *)

val focus : string -> unit
(** Focuses the element with this id; does nothing when no element has
    it. Inside a {!Yuka.batch} (an event handler), it runs after the batch
    updated the DOM, so it finds an element that a write of the handler
    creates. Browser only: raises [Invalid_argument] on native. *)

val scroll_into_view : string -> unit
(** Scrolls the element with this id into view; does nothing when no
    element has it. Inside a {!Yuka.batch}, it runs as {!focus} does. Browser
    only: raises [Invalid_argument] on native. *)

val on_frame : (float -> unit) -> unit
(** Calls the handler before each repaint of the browser
    ([requestAnimationFrame]) until the current owner is disposed, with the
    time of the frame in milliseconds, on the clock of {!now}. The handler
    runs in a {!Yuka.batch}. Browser only: call it inside [Effect.after]. *)

val now : unit -> float
(** Milliseconds since the page opened, with a fraction
    ([performance.now]). Browser only: raises [Invalid_argument] on native. *)

val count_elements : string -> int
(** The number of elements in the document that match the CSS selector
    ([querySelectorAll]). Browser only: raises [Invalid_argument] on native. *)
