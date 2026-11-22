val make :
  fallback:'k Kind.element ->
  children:(unit -> 'k Kind.element) ->
  unit ->
  'k Kind.element
(** A pending boundary. In mlx:
    [<Yuka.Pending fallback=(...)>(fun () -> ...)</Yuka.Pending>], or
    markup children, which the ppx puts in a function. The children run
    one time, with no tracking. Make the sources in the function: a source
    that a hole makes starts only when the hole runs, and on the server
    that is too late to hold the boundary.

    A source is an {!Async.memo}, a {!Remote.make} or an [Yuka.Await] with no
    [loading] made under the boundary. It joins the nearest [Pending]
    above it.

    - [fallback] shows until every source under the boundary has its
      first value. Then the children show. In the browser the children
      are made off the page and move in at that time.
    - After that, when sources run again, the old view stays. When the
      last run settles, all new values are written in one batch, so the
      view changes one time. A failed run settles too; its [Failed]
      value changes with the others.
    - A read of a State that is not a source changes at once: hold the
      two parts in step by reading the input from the data.
    - Each [Pending] holds and changes alone. An inner [Pending] waits
      only for its own sources.
    - On the server the children are made one time. When every source is
      settled at the end, the children print in place. Else a streamed
      render prints [fallback] and later sends the children in one part;
      a render that does not stream prints [fallback].
    - At hydration, when every source has its value, the children use
      the server HTML. When a source is still pending, the server HTML
      stays as it is, with no event handlers, until the sources settle;
      then new nodes replace it one time. *)

val busy : unit -> bool State.read
(** The busy State of the nearest [Pending] above the code that runs now:
    [true] from the time a source under it starts a run until the
    boundary changes the view. Call it where [Yuka.Context.get] works (a
    component function, a hole, a list row or an effect under the
    boundary) and keep the result. With no [Pending] above, it gives a
    State that is always [false], and a dev build writes a console
    error. Code outside the boundary cannot read it: put a spinner
    inside the children. *)

(**/**)

val boundary : (unit -> 'a) -> 'a * bool State.read
(** Runs the function under a new pending boundary, in a new owner that the
    current owner disposes. A {!Async.memo} or a {!Remote.make} made in it
    joins the boundary: while one of them has a run in flight, the status
    writes wait, and the read is [true]. When the last run settles, every
    waiting write is done in one batch and the read becomes [false]. For
    the tests of Yuka. *)
