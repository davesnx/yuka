(** Server data read through a query ({!Action.query}). *)

type 'o t

type retry

val retry : attempts:int -> delay_ms:(int -> int) -> retry
(** [attempts] more tries after the first; [delay_ms attempt] waits before try
    [attempt + 1]. *)

val default_retry : retry
(** Two more tries, after 500 ms and 1500 ms. *)

val no_retry : retry

val make :
  ?retry:retry -> ?enabled:(unit -> bool) -> ('i, 'o, [ `Query ]) Action.t -> (unit -> 'i) -> 'o t
(** Runs the query for the input that the function returns, and again
    when a State that the function or [enabled] reads changes. Call it in
    a component body: when its owner is disposed, the request in flight
    is aborted.

    - The key of a request is the query name and the JSON of the input;
      the query runs again only when the key changes. The uses of a key
      share one request in flight: a use that starts (mounted with no
      answer in the page, enabled, a new key) waits on it, and
      {!refetch} or {!invalidate} replaces it, so an answer from before
      them is not written. A use that moves on stops waiting, and the
      request is aborted when no use waits on it.
    - [enabled ()] false gives [Idle] and aborts the request.
    - [Network] and [Server] errors are tried again by [retry] (default
      {!default_retry}); the others fail at once.
    - In a server render it runs the implementation once. If it settles
      during the render, the status is [Ready] or [Failed]; else
      [Loading None]. Inside an island the answer is written in the page
      ([<script data-yuka-answer>], after the island), and the client
      reads it on the first run instead of sending a request; a pending
      answer is streamed later. After a client navigation, a use that
      stays on the screen (in a kept layout) also reads an answer of its
      key that came with the new content, also one streamed later; an
      error answer does not replace its data.
    - Outside the browser and outside a render (tests), it calls the
      implementation directly. *)

val state : 'o t -> 'o Status.t State.read
(** The status, with the pending {!optimistic} changes applied to the data.
    Read it with {!State.get}. *)

val refetch : 'o t -> unit
(** Sends the request again (the manual retry after [Failed]), for every
    use with the same key, with one request and this use's [retry]. *)

val invalidate : (_, _, [ `Query ]) Action.t -> unit
(** Sends again every mounted use of this query, for every input, with one
    request per key: the uses with the same input share it, with the
    [retry] of the first. *)

val optimistic :
  ?commit:('r -> 'o -> 'o) ->
  'o t ->
  change:('o -> 'o) ->
  (unit -> ('r, Status.error) result Async.t) ->
  ('r, Status.error) result Async.t
(** [optimistic remote ~change run] shows [change] on the data at once, then calls
    [run ()], for example an {!Action.call}. On [Ok result] the change is
    removed and the data becomes [commit result data] (default
    [change data]); on [Error] or a failed [Async] the change is removed
    (rollback). A new answer while the change is pending gets the change
    on top. The result is the [Async] of [run ()]. *)
