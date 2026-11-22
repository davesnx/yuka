val on_window : string -> (Event.t -> unit) -> unit
(** Listens on [window] until the current owner is disposed. The handler
    runs in a {!Yuka.batch}. Browser only: call it inside [Effect.after]. *)

val navigate : ?replace:bool -> ?keep_scroll:bool -> string -> unit
(** Browser only: raises [Invalid_argument] on native. Loads the URL. After [render ~islands] with navigation (the default), it
    is a client navigation, as a click on a link; see {!Yuka.render}. Otherwise it
    does [location.assign url]. The navigation adds a history entry, except
    to the URL shown, where it replaces the current entry. With
    [~replace:true] (default [false]) it always replaces the current entry
    and does [location.replace url] in place of [location.assign url], so
    Back goes to the page before. With [~keep_scroll:true] (default
    [false]) a client navigation does not scroll to the top or to the URL
    fragment, so the scroll position stays as it was; focus and the
    announcer change as for other navigations. A [javascript:], [vbscript:] or [data:]
    URL (read as {!Yuka.attr} reads a URL) does nothing; a dev build logs the
    first one. *)

val refresh : unit -> unit
(** Browser only: raises [Invalid_argument] on native. Loads the URL shown
    again from the server (the fragment does not count), with no cached
    answer, and swaps in the new content. Use it after an [Action.call]
    to show the new server data. After [render ~islands] with navigation,
    it is a client navigation that replaces the current history entry,
    does not scroll, does not change the announcer, and keeps the focus:
    on the focused element when it is still in the page, else on the new
    element with the same [id], else on the new element at the same place
    with the same tag. When it finds no such element, the focus moves as
    for other navigations. {!navigating} is [true] until the new content
    shows, as for other navigations. Otherwise it does
    [location.replace] with the URL shown, a full page load. A form
    success with no redirect and no [on_ok] calls it. *)

val block : (target:string -> bool) -> unit
(** [block check] keeps the user on the page until the current owner is
    disposed. Browser only: call it inside [Effect.after]. Before a client
    navigation starts (a click on a link or {!navigate}), it calls
    [check ~target], with [target] as in {!navigation}. When [check] gives
    [true], the user stays: the navigation does not start. When it gives
    [false], the navigation continues. With more than one [block], the
    navigation stops at the first [check] that gives [true]. {!refresh},
    Back and Forward do not call [check].

    While one or more [block]s exist, closing or reloading the tab, and a
    full page load, show the prompt of the browser. The browser does not
    show it before the user interacted with the page. Register the [block]
    only while there is something to lose, for example:
    {[
      Effect.after (fun () ->
          if State.get dirty then
            Browser.block (fun ~target:_ -> not (Browser.confirm "Discard the draft?")))
    ]} *)

val confirm : string -> bool
(** [confirm message] shows [message] in the dialog of the browser
    ([window.confirm]) and gives [true] when the user accepts. Browser
    only: raises [Invalid_argument] on native. *)

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

type navigation = {
  url : string;
      (** The target: the path and query for a URL of the page origin (the fragment does not count), else the full URL. *)
  from : string;  (** The path and query of the page shown when the navigation started. *)
  kind : [ `Push | `Replace | `Traverse | `Reload ];
      (** [`Push] adds a history entry. [`Replace] replaces the current
          entry: {!navigate} with [~replace:true], a link with
          [data-yuka-replace], or a navigation to the URL shown.
          [`Traverse] is Back or Forward ([popstate]). [`Reload] is {!refresh}. *)
}

val navigation : navigation option State.read
(** The client navigation in flight: [Some] for the same time as
    {!navigating} is [true], else [None]. A newer navigation replaces the
    value. Read it with {!Yuka.State.get} in an island, for example to
    mark the link of the target while the page loads, to show no progress
    bar for a [`Reload], or to animate Back and Forward. [Routes.pending]
    gives the target as a typed route. Always [None] on the server and
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
