(** Server state that the server pushes to the page over one WebSocket
    ([GET /_yuka/live]) when it changes. Each message is the full state of
    one key. The server side is {!Server.Live}. *)

type 's t

val use : ('k, 's) Topic.t -> (unit -> 'k) -> 's t
(** Subscribes to the state of the key that the function returns, and
    again when a State that the function reads changes the key. Call it
    in a component body; the subscription ends when its owner is disposed.

    - In a server render it runs the topic's [allow] with the context of
      the page request ([Failed Forbidden] when it refuses), then reads
      the state (the current one of the handler's node, else the topic's
      loader) and, inside an island, writes it in the page with
      a CSRF token for the socket; the client starts from it with no
      wait. A page that has such a use holds a per-session token and
      state that [allow] passed for this request, so its route must not
      use a shared cache (the cycle sends [private, no-store] when the
      shell has such a use), and it cannot be prerendered.
    - In the browser, one socket serves every use of the page. It opens
      on the first use and closes 2 s after the last one ends.
    - The status is [Loading None] until the first state, then [Ready].
      When the socket closes it is [Ready { stale = true }] (or
      [Loading None] with no data) while the client reconnects, after
      250 ms, 500 ms, 1 s, 2 s, 4 s, then every 5 s (half to all of each
      delay, at random), or when the browser comes back online. Each
      reconnect gets the full state again.
    - [Failed]: the server refused the key ([Forbidden], [Not_found],
      [Rejected] from the loader, [Server]); this use does not subscribe
      again. An unsupported protocol gives [Protocol] to every use.
    - Token: the client keeps the newest token it saw (from the page, the
      server [hello] and each [pong]). When the server refuses it (an
      expired token), the client gets a fresh one once from
      [GET /_yuka/csrf] and connects again; if that fails too, every use
      is [Failed Forbidden] until a new use (after a navigation) connects
      again with the token of its page. *)

val status : 's t -> 's Status.t
(** Tracked read, with the pending {!mutate} changes applied. *)

val mutate :
  ?commit:('r -> 's -> 's) ->
  's t ->
  change:('s -> 's) ->
  (unit -> ('r, Status.error) result Async.t) ->
  ('r, Status.error) result Async.t
(** [mutate live ~change run] shows [change] at once and calls [run ()],
    which should call an action that publishes the new state. On [Error]
    or a failed [Async], the change is removed. On [Ok result], the change
    becomes [commit result] (default [change]) and stays until
    the server confirms, on the socket, that every state it had for this
    subscription when the answer arrived was sent: the published state
    then holds the change, in whatever order the HTTP answer and the
    socket message arrived. While the socket is down, the confirmation
    comes after the reconnect. *)
