(** Runs a Yuka app on Dream. *)

val handler :
  ?node:Yuka.Server.Live.node -> Yuka.Server.config -> Dream.request Yuka.Server.app -> Dream.handler
(** Answers every request with the request cycle
    ([Yuka.Server.Adapter.Make]), the WebSocket of {!Yuka.Live} at
    [/_yuka/live] included. Put Dream middleware (logger, sessions) around
    it. To send the cycle's error messages to the Dream log, give the
    config [~log_error:(fun m -> Dream.error (fun log -> log "%s" m))].

    The live socket needs Dream sessions shared by every process and stable
    across restarts ([Dream.cookie_sessions] with [Dream.set_secret]).
    Known risk until httpun-ws is fixed
    (https://github.com/camlworks/dream/issues/467): a publish written to a
    client that reset its connection just before can freeze the server at
    100% CPU. [node] is the live node of the sockets and of the server
    render of [Yuka.Live.use] (default: the process node); a second handler
    in one process with its own {!Yuka.Server.Live.type-node} is a second
    node. *)

val prerender :
  out:string -> Yuka.Server.config -> Dream.request Yuka.Server.app -> unit Lwt.t
(** Writes the pages of the app to the directory [out]:

    - It starts from [Yuka.Server.Prerender.seeds] and renders each path
      with a [GET] through the request cycle. A 2xx answer is written to
      [Yuka.Server.Prerender.file]; any other status prints a warning on
      stderr and is skipped.
    - In each HTML answer it follows [Yuka.Server.Prerender.links]: a path
      is added when [Yuka.Server.Prerender.prerenderable] says so. Each path
      is rendered once.
    - It writes [404.html] ([Yuka.Server.Prerender.missing_page]) and
      copies [Yuka.Server.Prerender.served_dirs] under their prefixes.

    It renders with [Yuka.Server.Prerender.config]: dev mode is off, and a
    page that renders a [Yuka.Live.use] is a 500 with a log message, so it is
    not written. A file in the [prerendered] directory of the config is not
    read. Files already in [out] are replaced; running it twice gives the
    same files. Raises [Invalid_argument] at once when [out] is inside a
    directory of [Yuka.Server.Prerender.served_dirs]. *)

val tree_digest : string -> string
(** A digest of the paths and contents of every file under a directory
    (symbolic links followed), for the [digest] of [Yuka.Server.modules].
    Compute it once at start. *)

val to_async : 'a Lwt.t -> 'a Yuka.Async.t
(** A failed promise gives a failed [Async] with the exception text. *)

val to_lwt : 'a Yuka.Async.t -> 'a Lwt.t
(** A failed [Async] gives a promise failed with [Failure]. *)
