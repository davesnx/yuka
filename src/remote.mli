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
