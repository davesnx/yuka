# State, memos and effects

This page explains how a Yuka component updates the page. It is for a
reader who knows React or Solid. The exact API is in
[`src/yuka.mli`](../src/yuka.mli).

## A component runs once

A component is a function. Yuka calls it one time and keeps the DOM nodes
it returns. Yuka does not call it again when data changes, and it has no
virtual DOM to compare.

Three things run again after the first render:

- a hole: a part of the markup that reads a State,
- a memo,
- an effect.

Each of them records the States it reads. A write to one of those States
runs it again. You do not write a list of dependencies.

```ocaml
let[@client] make ~(initial : int) () =
  let count = Yuka.State.make initial in
  let double = Yuka.State.memo (fun () -> Yuka.State.get count * 2) in
  Yuka.Effect.after (fun () -> Yuka.Console.log ("count is " ^ Int.to_string (Yuka.State.get count)));
  <button on_click=(fun _ -> Yuka.State.update count succ)>
    "Double: "
    (Yuka.int (Yuka.State.get double))
  </button>
```

A click writes `count`. The memo `double` is then out of date, so the hole
that reads it computes it again and sets the text of one text node. The
effect prints the new count. The body of `make` does not run again, so
`count` and `double` are created one time and there is no rule about the
order of the calls.

## State

`State.make value` creates a State that holds `value`.

- `State.get state` reads the value. Inside a hole, a memo or an effect, the
  read is recorded.
- `State.peek state` reads the value and records nothing.
- `State.set state value` writes a value. `State.update state change` writes `change` of the
  current value.

A write is a change only when the new value differs from the old one.
Readers do not run for a write that is not a change. The default test is
identity: two ints, bools, strings or floats with the same value are the
same, and a new record, tuple or list is a change, also when its contents
are equal. Pass `~equal:( = )` to compare contents:

```ocaml
let filter = Yuka.State.make ~equal:( = ) { status = Open; mine = false }
```

## Holes

In an `.mlx` file, a child or an attribute value that contains `State.get`
becomes a hole. A hole is the only part of the markup that changes after
the first render.

```ocaml
<p class_=(if Yuka.State.get active then "on" else "off")>
  (Yuka.text (Yuka.State.get name))
</p>
```

This paragraph has two holes. A write to `active` sets the `class`
attribute. A write to `name` sets the text. Each write touches one place
in the DOM.

The ppx looks for `State.get` in the expression itself. It does not see a
read inside another function that the expression calls. Wrap such a call:
`(Yuka.hole (fun () -> label ()))`.

A hole that returns elements, not text, removes its old elements and
creates new ones each time it runs. Keep such a hole small, or read the
State deeper in the tree, so that less is created again.

## Memos

`State.memo compute` is a value computed from other States. Use it when a
computation is costly, or when several readers need the same result.

```ocaml
let visible =
  Yuka.State.memo (fun () ->
      List.filter (matches (Yuka.State.get filter)) (Yuka.State.get issues))
```

- A memo is read-only: `State.set` on it does not compile.
- A memo computes one time when you create it. After that it computes
  again only when a State it read changed and something reads the memo. A
  memo that nothing reads does no work.
- A memo has the same change test as a State. When it computes a value
  equal to the old one, its readers do not run.
- A reader never sees a memo that is out of date. In the example at the
  top, no code can observe the new `count` together with the old `double`.

## Deferred State

`State.deferred source` is a read-only copy of `source` that changes after
the next paint. Use it when a click must show at once, but part of the page
is slow to update.

```ocaml
let filter = Yuka.State.make All in
let shown = Yuka.State.deferred filter in
```

The filter chips read `filter` and the chart reads `shown`. A click writes
`filter`. The chips update and the browser paints them. Then `shown` takes
the new value and the chart updates.

- It starts with the value of `source`.
- After a change of `source`, it waits for the next frame, then the browser
  paints, then it takes the latest value of `source`. Values in between are
  skipped.
- A change of `source` in a `Browser.on_frame` handler waits for the paint
  of that frame.
- All deferred States that wait change in one batch, so a reader of
  several of them runs one time.
- A change of `source` that comes after the frame and before the slow
  update joins that update.
- The slow update is not shorter, and Yuka cannot stop it. It only comes
  after the paint of the fast one.
- When its owner goes away, a waiting change is dropped.
- A tab in the background gets no frame, so the change waits until the tab
  shows again.
- On the server it has the value of `source`, so the HTML is the same as
  without it.

## Effects

An effect connects a component to something outside Yuka: the DOM, a
timer, a socket, a browser API, a log. There are two kinds. They differ
only in when they run.

`Effect.after body` runs `body` after the DOM is up to date, and again each time
a State it read changes. Use it for most effects.

- The first run comes after Yuka puts the elements of the component in
  the page, so `body` can find them.
- A later run comes after the holes, the lists and the `Effect.before`
  effects of the same change, so `body` sees the new DOM.

`Effect.before body` runs `body` at once, in the component body, before the
elements of the component exist. Use it for a value that the markup of the
component needs. A later run comes in the same round as the holes and the
lists of the same change, before the `Effect.after` effects. A hole or a
list of the same component can run before it, so do not use it to read the
DOM before a change.

`~cleanup` receives the result of the previous run. Yuka calls it before
the next run and when the component is removed. Here `connect` and
`close` are your own functions:

```ocaml
Yuka.Effect.after ~cleanup:close (fun () -> connect (Yuka.State.get room))
```

When `room` changes, Yuka closes the old connection and opens a new one.
When the component is removed, Yuka closes the last connection. When Yuka
removes the component before the first run, the effect never runs.

`Effect.on_change state handler` calls `handler ~prev ~next` when `state` changes, with the
timing of `Effect.after`. It does not call `handler` for the first value.

To read a State in an effect without a re-run when it changes, use
`State.peek`, or wrap the code in `State.untrack`.

Do not use an effect to copy one State into another. Use a memo. An effect
that writes a State it reads runs again and again. After 100 rounds Yuka
stops and raises `Failure`.

## When updates run

A write updates the page before `State.set` returns. Yuka does the work in
rounds. In a round, the holes, the lists and the `Effect.before` effects
that read the State run first. The `Effect.after` effects run when none of
them is left. A write inside an effect starts a new round.

`Yuka.batch body` delays that work to the end of `body`, so readers run one time
for several writes:

```ocaml
Yuka.batch (fun () ->
    Yuka.State.set first "Ada";
    Yuka.State.set last "Lovelace")
```

Each event handler already runs in a batch. Two writes in one `on_click`
update the page one time. `Yuka.render` and hydration also run in a batch,
so a write in a component body updates the page when the render ends.

The first run of an `Effect.after` effect also waits for the end of the
batch or the update that creates it. Outside both, for example at the top
level of `Yuka.owner`, it runs at once.

`Yuka.Browser.on_frame handler` calls `handler` before each repaint, in a
batch, until its owner is disposed. Call it in an effect: when the effect
runs again or its component goes away, the calls stop. This effect animates
while `playing` is true:

```ocaml
Yuka.Effect.after (fun () ->
    if Yuka.State.get playing then
      Yuka.Browser.on_frame (fun time -> Yuka.State.set angle (time /. 10.)))
```

`Yuka.Browser.now ()` gives the time on the same clock, in milliseconds.

A `State.deferred` changes later than the rest: after the next paint, in
its own batch. See [Deferred State](#deferred-state).

## Lifetime

Effects and memos belong to the component, hole or list row that created
them. When Yuka removes that part of the page, it stops its effects, runs
their cleanups and drops its memos. An effect created inside another
effect is stopped before the outer effect runs again.

`Yuka.owner body` runs `body` and returns a function that stops everything `body`
created. Use it for effects that must live outside a component.

## Context

A context gives a value to every component below one place of the page,
with no argument on the components between. Make the context one time, at
the top of a module, and write its type:

```ocaml
let theme : Theme.t Yuka.State.read Yuka.Context.t = Yuka.Context.make ~name:"theme" ()
```

Give a value with the `<Yuka.Context.Provide>` tag:

```ocaml
let page () =
  <Yuka.Context.Provide of_=theme value=dark>
    <Layout> <Save /> </Layout>
  </Yuka.Context.Provide>
```

Read it in a component below:

```ocaml
let save () =
  let theme = Yuka.Context.get_exn theme in
  <button class_=(Theme.button (Yuka.State.get theme))> "Save" </button>
```

`Yuka.Context.get` gives `None` when no component above gave a value.
`Yuka.Context.get_exn` raises `Invalid_argument` with the name of the
context. The nearest `Provide` above wins.

The value is fixed. To give a value that changes, give a State, as above.
A change then runs the holes that read the State, and no component runs
again.

Call `get` in the component body and keep the result. A timer and an
`Async` callback run outside the page, so `get` gives `None` there.

Without mlx, `Yuka.Context.provide theme dark (fun () -> children)` is the
same as the tag. `Yuka.Context.provide_all [ Yuka.Context.bind a x;
Yuka.Context.bind b y ] (fun () -> children)` gives several values in one
call.

The tag passes its children as a function, so the components inside it run
after the value is given. A component that receives `children` as an
argument gets them already built: if it calls `provide` around them, their
holes read the value and their component bodies do not. Use the tag at
the place where the children are written.

An island reads only what a component inside the island gave. See
[Islands](islands.md#limitations).

## On the server

The server calls the component one time to print HTML.

- A hole prints its current value.
- A memo computes one time.
- `Effect.after`, `Effect.before` and `Effect.on_change` do nothing: the
  body and the cleanup do not run. Code that needs the browser belongs in an effect or an
  event handler.

A State that you create inside a component is new for each request. A
State at the top level of a module is different: the server process has
one copy for every request. If a request wrote it, one user could see the
data of another.

```ocaml
let dialog_open = Yuka.State.make false
```

The browser accepts this State. On the server, Yuka counts a State as
module-level when it was made before the first server render or request.
After that point, `State.set` or `State.update` on such a State raises
`Invalid_argument`. A read is allowed, so a render can show its value.
Writes before the first render or request are allowed, for example to set
a start value.

When only the browser writes the State (event handlers and effects), the
server never writes it, and every request sees its first value. In all
other cases, create the State inside a component.
