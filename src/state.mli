type scope = Signal.scope
(** What {!get} needs. Yuka gives one to the function of a {!memo}, an
    effect, a hole, a hole attribute, the array function of [each], the
    [status] function of [Show] and {!untrack}; there is no other way to
    get one. A read with a scope that a function kept after it returned,
    as in an event handler made in a hole, compiles and is not tracked,
    as {!peek}. *)

type ('a, 'access) signal
(** A value that tracks its readers. ['access] is [[ `Write ]] for a State
    made with {!make} and [[ `Read ]] for a {!memo}. A function that only
    reads takes [('a, _) signal] and accepts both. *)

type 'a t = ('a, [ `Write ]) signal
(** A State that {!set} and {!update} can write. *)

type 'a read = ('a, [ `Read ]) signal
(** A read-only State: {!set} and {!update} on it do not compile. *)

val make : ?equal:('a -> 'a -> bool) -> 'a -> 'a t
(** [equal] decides whether a write is a change. Default: identity, as
    JavaScript [===]: the same value ([==]), or two ints, chars, bools,
    constant constructors, strings or floats with the same value. A new
    record, tuple, list, array or constructor with arguments is a change
    even when its contents are equal; pass [~equal:( = )] for structural
    equality. The default never raises, also for functional values. In the
    browser, [Some value] is [value] itself, so a new [Some value] that wraps the same
    [value] is not a change there; on native it is. An exception raised by
    [equal] counts as a change. *)

val get : scope -> ('a, _) signal -> 'a
(** [get scope state] reads the value, tracked: a change of [state] runs
    the function that got [scope] again. The read is tracked also when it
    raises. In a component body, an event handler or at the top level,
    where there is no scope, use {!peek} or {!untrack}. *)

val peek : ('a, _) signal -> 'a
(** Reads the value without tracking. Use it in a component body, an event
    handler and at the top level. Outside a {!Yuka.batch}, an effect and a
    memo, a read that makes a memo compute again runs the effects that the
    new value makes pending before it returns, and raises their
    exception. *)

val set : 'a t -> 'a -> unit
(** Writes the value. On the server, raises [Invalid_argument] for a
    State made before the first server render or request of the process
    (a module-level State): the process has one copy for every request. *)

val update : 'a t -> ('a -> 'a) -> unit
(** Like [set], with a function of the current value. *)

val memo : ?equal:('a -> 'a -> bool) -> (scope -> 'a) -> 'a read
(** A derived value. It recomputes when a State it read changes. A
    recompute is a change only if [equal] says the new value differs.
    Default: the same equality as {!make}.

    When the function raises, the read of the memo raises that exception,
    and the next read computes again. A memo that raises counts as changed:
    an effect or a memo that read it runs again and gets the exception at
    its read. The exception of a memo that nothing reads in that update is
    not raised.

    A memo that writes a State it reads computes again until its value
    settles; a reader sees only the settled value. After 100 computes
    without an end, the read raises the [Failure] of {!Yuka.Effect.after}. *)

val deferred : ?equal:('a -> 'a -> bool) -> ('a, _) signal -> 'a read
(** A copy of a State that changes after the next paint. It starts with the
    value of the source. In the browser, after a change of the source, it
    takes the latest value of the source after the browser paints the next
    frame; values in between are skipped. A change made in a
    {!Yuka.Browser.on_frame} handler waits for the paint of that frame. All
    deferred States that wait change in one {!Yuka.batch}. Read it for a slow
    part of the page, and read the source for a fast part: the fast part
    paints first. The slow update is not shorter and not interruptible; it
    only comes later. When its owner is disposed, a waiting change is
    dropped. On the server and on native it always has the value of the
    source. [equal] is as in {!make}. *)

external read_only : 'a t -> 'a read = "%identity"
(** The same State, typed so that {!set} and {!update} on it do not
    compile. *)

val untrack : (scope -> 'a) -> 'a
(** Runs the function with a scope and returns its result. Its reads are
    not tracked: inside an effect or a memo, a change of such a State does
    not run it again. Use it to read [Remote.status], [Live.status] and
    [Form.field_error], [Form.form_errors] or [Form.pending] in an event
    handler, a component body, or untracked in an effect. *)

(**/**)

val on_change : ?equal:('a -> 'a -> bool) -> ('a, _) signal -> (prev:'a -> next:'a -> unit) -> unit
external signal : ('a, _) signal -> 'a Signal.t = "%identity"
external of_signal : 'a Signal.t -> ('a, _) signal = "%identity"
