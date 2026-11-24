(** Runs a Yuka app on its own HTTP/1.1 server: the
    {{:https://github.com/davesnx/ache} ache} library on Lwt, one process,
    one thread. No TLS and no HTTP/2: put a proxy in front for those. *)

type sessions
(** How the server makes session ids and CSRF tokens. *)

val sessions : ?secure:bool -> ?lifetime:float -> ?max_lifetime:float -> secret:string -> unit -> sessions
(** Signed cookie sessions, with no store on the server. [secret] signs the
    session cookie and the CSRF tokens: give every process the same one,
    keep it across restarts and keep it out of the source code. A new
    secret ends every session. Raises [Invalid_argument] when [secret] is
    shorter than 32 bytes, when [lifetime] is not a positive number of at
    most 10{^12} seconds, or when [max_lifetime] is not a number from
    [lifetime] to 10{^12} seconds.

    - The cookie is [yuka-session], with [Path=/], [HttpOnly] and
      [SameSite=Lax]. Its value holds a random id of 18 bytes, the time the
      session started, the time the cookie expires and an HMAC-SHA256 of
      the three.
    - [lifetime] (default: 14 days) is the life of a cookie in seconds. A
      session with less than half of it left gets a new cookie with the same
      id and the same start time.
    - [max_lifetime] (default: 30 days, or [lifetime] when it is longer) is
      the absolute life of a session in seconds from its start. A new cookie
      never expires after it, and a request after it gets a new session id.
    - [secure] (default: [false]) adds [Secure] and names the cookie
      [__Host-yuka-session]. Set it when the site is on HTTPS.
    - A CSRF token is bound to the session id and is valid for one hour,
      or for [lifetime] when it is shorter.
    - The cookie is read, checked and made only when the cycle or the app
      asks for the session or a CSRF token, so a page that does not ask gets
      no [set-cookie] and can be cached. A cookie that is absent, expired or
      not signed with [secret] gives a new session.

    There is no store, so one session cannot be ended before it expires: a
    stolen cookie is valid until then, and a holder who uses it at least
    once in each half [lifetime] keeps the session until [max_lifetime]
    from its start. *)

type connection
(** One accepted socket. *)

val peer : connection -> Unix.sockaddr
(** The address of the client. *)

type handler = connection -> Ache.Request_descriptor.t -> unit
(** What answers each request of a connection. *)

val handler :
  ?node:Yuka.Server.Live.node ->
  ?sessions:sessions ->
  ?log_requests:bool ->
  Yuka.Server.config ->
  Yuka.Server.app ->
  handler
(** Answers every request with the request cycle
    ([Yuka.Server.Adapter.Make]), the WebSocket of {!Yuka.Live} at
    [/_yuka/live] included. For your own routes, write a {!type-handler}
    that answers them and calls this one for the rest. Without [~sessions],
    a request has no session: [/_yuka/csrf] and [/_yuka/live] answer 500.

    Log: messages go to the [log] of the config, else to the default sink
    of Yuka ({!Yuka.Server.set_default_log}). With [log_requests] (default:
    [true]), each request gives one line at [`Info] when its answer ends:
    the method, the path without the query, the status and the time in
    milliseconds. A failure after the head of an answer was sent goes to
    the log at [`Error]; a client that left during an answer at [`Debug].

    Framing: ache reads the request. A request with both
    [Transfer-Encoding] and [Content-Length], or with a [Content-Length]
    that is not a number, gets 400 with [connection: close] before the
    cycle runs. A body that ends before its framing ends fails, so it never
    reaches an action. A body that the cycle did not read is dropped by its
    framing, never parsed as a next request. The server sets the framing of
    each answer: the [content-length] and [transfer-encoding] of the app are
    dropped (an answer to [HEAD] keeps the headers that the cycle gave). An
    answer to [HEAD], and a 1xx, 204 or 304 answer, has no body bytes. An
    answer that ache cannot send (a status out of 200-599, a header name
    that is not a token) becomes a plain 500 and a log message.

    Files: [content-type] from the file name ([text/html] gets
    [charset=utf-8]) unless the cycle gave one, [content-length] from the
    file, sent in parts of 64 KiB. The file is closed when the answer ends,
    also when the client leaves.

    Live socket: when the protocol ends, or when it closes the socket and
    the client does not answer, the server closes the connection after
    5 seconds. *)

val error_handler : connection -> Ache.Server_connection.error_handler
(** Answers a request that ache cannot read (400, or 408, 414, 431, 501,
    505 as ache says) and an exception that escapes a request (500) with a
    fixed plain text and [connection: close]. The exception text is never
    sent. Each error goes to the default sink of Yuka. *)

val connection :
  ?write_timeout:float -> ?live_timeout:float -> handler -> Unix.sockaddr -> Lwt_unix.file_descr -> unit Lwt.t
(** Serves one accepted socket with the handler and {!error_handler}, for
    example from [Lwt_io.establish_server_with_client_socket]. Ignore
    [SIGPIPE] first. The promise resolves when the connection is closed.
    Raises [Invalid_argument] when a timeout is not a positive number.

    Time limits, in seconds:
    - A request head must be complete 10 seconds after its first byte (else
      408).
    - A connection with no request for 60 seconds is closed, and so is a
      request body that sends no byte for 60 seconds.
    - [write_timeout] (default: 30): a write of an answer (its head, a part
      of a file, a part of a stream or a live message) that sends no byte
      for that long closes the connection; the file of the answer is closed
      and the stream gets a failed write. A slow client that reads keeps
      going: only a write with no progress counts, not the whole answer.
    - [live_timeout] (default: 60): a live socket that receives no byte for
      that long is closed. The browser client of {!Yuka.Live} sends a ping
      every 25 seconds, so a client that is gone without closing the socket
      is closed after at most this time. The server sends no WebSocket
      ping: [Ache_lwt.Websocket] has no way to send one. *)

val serve :
  ?interface:string ->
  ?port:int ->
  ?stop:unit Lwt.t ->
  ?listening:(int -> unit) ->
  ?write_timeout:float ->
  ?live_timeout:float ->
  ?max_connections:int ->
  ?drain_timeout:float ->
  handler ->
  unit Lwt.t
(** Listens on [interface] (an IP address, default ["127.0.0.1"]) and
    [port] (default 8080) until [stop] resolves (default: never). Port 0
    lets the system choose; [listening] gets the real port. Ignores
    [SIGPIPE] for the whole process. Each connection is served by
    {!connection} with [write_timeout] and [live_timeout].

    - At most [max_connections] (default: 1024) connections are open at a
      time. At the limit, the server accepts no connection until one
      closes; the system queues the next ones (up to 1024) and answers
      nothing. Keep it under the file descriptor limit of the process
      ([ulimit -n]).
    - An accept that fails (no file descriptor left) goes to the default
      sink once and is tried again after 0.1 seconds, so the process does
      not stop.
    - Drain: when [stop] resolves, the server closes the listening socket,
      closes the connections that wait for a next request, sends close code
      1001 on each live socket, and lets the answers in progress end, then
      resolves. A connection still open [drain_timeout] (default: 10)
      seconds after [stop] is closed.
    - A bind that fails (a port in use) closes the socket and fails. When
      [stop] fails, [serve] drains and fails with that exception.

    Raises [Invalid_argument] when [interface] is not an IP address, [port]
    is not in 0-65535, a timeout is not a positive number or
    [max_connections] is less than 1. *)

val run :
  ?interface:string ->
  ?port:int ->
  ?sessions:sessions ->
  ?node:Yuka.Server.Live.node ->
  ?log_requests:bool ->
  ?write_timeout:float ->
  ?live_timeout:float ->
  ?max_connections:int ->
  ?drain_timeout:float ->
  Yuka.Server.config ->
  Yuka.Server.app ->
  unit
(** [serve] of {!handler} under [Lwt_main.run], until SIGINT or SIGTERM.
    The first signal starts the drain of {!serve} and returns when it ends;
    a second signal exits the process at once with code 1. *)

val request : Yuka.Server.request -> Ache.Request_descriptor.t option
(** The ache request of a request that {!handler} made, for a loader,
    guard, handler or action that needs it. [None] for a request from
    another adapter or from [Yuka.Server.Testing.request]. *)

val to_async : 'a Lwt.t -> 'a Yuka.Async.t
(** A failed promise gives a failed [Async] with the exception text. *)

val to_lwt : 'a Yuka.Async.t -> 'a Lwt.t
(** A failed [Async] gives a promise failed with [Failure]. *)
