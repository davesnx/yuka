type 'a status = Pending | Done of 'a | Failed of string
type 'a t

val make : unit -> 'a t * ('a -> unit) * (string -> unit)
(** A pending value and its resolve and fail functions. It settles once;
    later calls are ignored. *)

val return : 'a -> 'a t
(** A value that is already [Done]. *)

val failed : string -> 'a t
(** A value that is already [Failed] with this message. *)

val status : 'a t -> 'a status

val on_settled : 'a t -> ('a status -> unit) -> unit
(** Callbacks run in registration order; now, if already settled. *)

val on_result : 'a t -> (('a, string) result -> unit) -> unit
(** Like [on_settled], without the [Pending] case. *)

val map : ('a -> 'b) -> 'a t -> 'b t
(** Applies the function to the value when it is [Done]. A failure stays a
    failure with the same message. An exception that the function raises
    gives [Failed] with the exception as text. *)

val bind : 'a t -> ('a -> 'b t) -> 'b t
(** Like [map], with a function that gives an [Async]. *)

val watch : 'a t -> 'a status State.read
(** A State that follows the status. *)

val memo : ?equal:('a -> 'a -> bool) -> (unit -> ('a, Status.error) result t) -> 'a Status.t State.read
(** A derived value from an [Async], as {!State.memo} is for a sync value.
    [Async.memo (fun () -> Action.call search (State.get filter))] gives the
    status of the latest search.

    - The function runs at once, and again when a State that it reads
      changes. Its reads are tracked; the callbacks of the [Async] that it
      gives are not.
    - Only the latest run writes the status. An older run that settles
      later is ignored.
    - Each run has its own owner. The next run, or the disposal of the owner
      of the memo, disposes it, so a query {!Action.call} of an older run is
      aborted.
    - The status starts as [Loading None]. [Ok data] gives
      [Ready { data; stale = false }]. [Error error] gives
      [Failed { error; last }]. A failed [Async], or an exception in the
      function, gives [Failed { error = Server; last }], and its message
      goes to the log: the console in the browser, the server log in a
      server render. A new run that is pending gives
      [Loading (Some last)], where [last] is the last data.
    - [equal] compares the data of two [Ready] values: equal data is not a
      change. Default: every new status is a change.
    - In the browser, a query {!Action.call} in the first run reads the
      answer that the server render of the island wrote in the page, if
      there is one, and sends no request.
    - In a server render, the function runs one time. *)

(**/**)

val guard : ('a -> 'b t) -> 'a -> 'b t
