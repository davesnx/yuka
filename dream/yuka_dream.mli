(** Runs a Yuka app on Dream. *)

val handler :
  ?live:Yuka.Server.Live.instance -> Yuka.Server.config -> Dream.request Yuka.Server.app -> Dream.handler
(** Answers every request with the request cycle ([Yuka.Server.handle]).
    Put Dream middleware (logger, sessions) around it. Sets
    [Yuka.Server.log_error] to [Dream.error].

    It also answers [GET /_yuka/live], the WebSocket of {!Yuka.Live}; this
    needs Dream sessions shared by every process and stable across restarts
    ([Dream.cookie_sessions] with [Dream.set_secret]). Known risk until
    httpun-ws is fixed (https://github.com/camlworks/dream/issues/467): a
    publish written to a client that reset its connection just before can
    freeze the server at 100% CPU. [live] is the live node of the sockets
    (default: the process one); a second handler in one process with its
    own {!Yuka.Server.Live.type-instance} is a second node. *)

val prerender :
  out:string -> Yuka.Server.config -> Dream.request Yuka.Server.app -> unit Lwt.t
(** Writes the pages of the app to the directory [out]:

    - It starts from [Yuka.Server.prerender_seeds] and renders each path with
      a [GET] through the request cycle. A 2xx answer is written to
      [Yuka.Server.prerender_file]; any other status prints a warning on
      stderr and is skipped.
    - In each HTML answer it follows [Yuka.Server.links]: a path is added
      when [Yuka.Server.prerenderable] says so. Each path is rendered once.
    - It writes [404.html] ([Yuka.Server.missing_page]) and copies
      [Yuka.Server.served_dirs] under their prefixes.

    A file in the [prerendered] directory of the config is not read. Files
    already in [out] are replaced; running it twice gives the same files. *)

val tree_digest : string -> string
(** A digest of the paths and contents of every file under a directory
    (symbolic links followed), for the [digest] of [Yuka.Server.modules].
    Compute it once at start. *)

val to_async : 'a Lwt.t -> 'a Yuka.Async.t
(** A failed promise gives a failed [Async] with the exception text. *)

val to_lwt : 'a Yuka.Async.t -> 'a Lwt.t
(** A failed [Async] gives a promise failed with [Failure]. *)
