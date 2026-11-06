val to_string : (unit -> Yuka.server Yuka.element) -> string
(** The tree as HTML, with hydration markers. The function builds the tree
    with effects off, so component bodies do not run effects. *)

val page :
  ?head:string ->
  ?early:bool ->
  ?import_map:(string * string) list ->
  ?title:string ->
  ?styles:string list ->
  ?scripts:string list ->
  (unit -> Yuka.server Yuka.element) ->
  string
(** A full HTML document. [styles] are stylesheet URLs, [scripts] are module
    script URLs. [head] is raw HTML added inside [<head>]. [import_map] is
    written as an import map script before any other script. With [early],
    module scripts get the [async] attribute, so they run while the stream
    continues. *)

val import_map : url:string -> dir:string -> (string * string) list
(** Lists the package directories under [dir/node_modules] (scoped packages
    as [@scope/name]) and maps ["pkg/"] to ["url/node_modules/pkg/"], sorted
    by name. A missing directory gives []. *)

val fill_script : string
(** [Yuka.Internal.fill_script]. *)

val stream :
  ?head:string ->
  ?early:bool ->
  ?import_map:(string * string) list ->
  ?timeout:float ->
  ?title:string ->
  ?styles:string list ->
  ?scripts:string list ->
  (unit -> Yuka.server Yuka.element) ->
  (string -> unit Lwt.t) ->
  unit Lwt.t
(** Writes the document head and the shell at once. For each pending
    [Yuka.await] and each pending [Codec.async] value, it writes a chunk
    when the value settles, in settle order, including parts that appear in
    streamed content. It returns when all have settled, or after [timeout]
    seconds (default 10): then each pending await is filled with its [failed]
    element for the message [timeout], each pending async value gets
    [{error: timeout}], and the stream ends. *)

val render_settled :
  ?timeout:float -> (unit -> Yuka.server Yuka.element) -> string Lwt.t
(** Waits until every pending value settled (or [timeout] seconds, default
    10, as in [stream]) and returns the HTML as [to_string] would print it
    if the values had been settled at print time. The scripts of the async
    props ([data-yuka-async]) follow the document, as [stream] writes them.
    For tests. *)

val respond :
  ?status:Dream.status ->
  ?request:Dream.request ->
  ?head:string ->
  ?early:bool ->
  ?import_map:(string * string) list ->
  ?timeout:float ->
  ?title:string ->
  ?styles:string list ->
  ?scripts:string list ->
  (unit -> Yuka.server Yuka.element) ->
  Dream.response Lwt.t
(** [stream] as a Dream streaming response, with [Vary: Yuka-Navigate].
    When [request] has the header [Yuka-Navigate: 1], the page is sent in one
    response instead: a full document (without the fill script) whose body
    is [render_settled], including the async value scripts. *)

module Action : sig
  val reject : string -> 'a
  (** Raised inside an implementation to refuse the input. The route answers
      400 [{"error": message}], and [Yuka.Action.call] on the server fails
      with the message. Any other exception stays 500 with a generic message. *)

  val implement : ('i, 'o) Yuka.Action.t -> ('i -> 'o Lwt.t) -> unit
  (** Registers the implementation of a declared action, and makes
      [Yuka.Action.call] run it directly on the server. Raises
      [Invalid_argument] if the name is already implemented. *)
end

val route : Dream.route
(** [POST /_yuka/action/:name]. The body is the JSON input. The answer is
    [{"ok": output}] (200) or [{"error": message}] with 400 (bad JSON or
    input), 403 (Origin differs from Host), 404 (unknown action), 415
    (Content-Type is not application/json) or 500 (the implementation
    failed; the message is generic). *)

module Async : sig
  val of_lwt : 'a Lwt.t -> 'a Yuka.Async.t
  (** Follows the promise. A rejected promise fails the [Async] with the
      generic message ["failed"]; the exception goes to [Dream.error]. *)
end
