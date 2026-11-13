(** Runs a Yuka app on tapak, in direct style on Eio. One domain. *)

val handler :
  sw:Eio.Switch.t ->
  fs:_ Eio.Path.t ->
  ?node:Yuka.Server.Live.node ->
  Yuka.Server.config ->
  Tapak.Request.t Yuka.Server.app ->
  Tapak.handler
(** Answers every request with the request cycle
    ([Yuka.Server.Adapter.Make]), the WebSocket of {!Yuka.Live} at
    [/_yuka/live] included. Put {!sessions} around it, and the tapak
    middleware or router you want. [fs] reads the files of [assets] and
    [public]; it is the root of the absolute paths of the config.

    Each request gets its own switch, a child of [sw], that lives until the
    response body (a stream or the WebSocket) ends. {!switch} gives it.
    When the response ends, the switch is cancelled: the timers of the
    cycle and the fibers of {!async} on it end with the request.

    When the request has a body that the cycle did not read to its end
    (refused, or answered before it was read), the response has
    [connection: close], and the rest of the body is read and dropped
    after the response is sent, so it is never parsed as a next request.
    A [HEAD] answer has the headers of the [GET] answer and no body bytes.

    When the config has no [log], messages go to the [Logs] source
    ["yuka"]. *)

val sessions : Tapak.middleware
(** Gives each client a session id cookie ([yuka-session]) and a CSRF
    secret cookie ([yuka-csrf]), both [HttpOnly] and [SameSite=Lax], when
    the request has none, or one that is not 32 letters and digits. A new cookie is also added to the request, so the
    first request already has a session. The live socket and
    [/_yuka/csrf] need it. *)

val switch : unit -> Eio.Switch.t
(** The switch of the current request, inside {!handler}. Raises
    [Invalid_argument] outside a request. *)

val await : 'a Yuka.Async.t -> 'a
(** Waits for the value. A failed [Async] raises [Failure] with its
    message. *)

val async : sw:Eio.Switch.t -> (unit -> 'a) -> 'a Yuka.Async.t
(** Runs the function in a new fiber on [sw]. An exception gives a failed
    [Async] with its text; a cancellation is raised again and leaves the
    [Async] pending. *)
