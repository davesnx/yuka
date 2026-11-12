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
open Yuka

let[@client] make ~(initial : int) () =
  let count = State.make initial in
  let double = State.memo (fun () -> State.get count * 2) in
  Effect.run (fun () ->
      print_endline ("count is " ^ string_of_int (State.get count)));
  <button on_click=(fun _ -> State.update count succ)>
    "Double: "
    (Yuka.int (State.get double))
  </button>
```

A click writes `count`. The memo `double` is then out of date, so the hole
that reads it computes it again and sets the text of one text node. The
effect prints the new count. The body of `make` does not run again, so
`count` and `double` are created one time and there is no rule about the
order of the calls.

## State

`State.make v` creates a State that holds `v`.

- `State.get s` reads the value. Inside a hole, a memo or an effect, the
  read is recorded.
- `State.peek s` reads the value and records nothing.
- `State.set s v` writes a value. `State.update s f` writes `f` of the
  current value.

A write is a change only when the new value differs from the old one.
Readers do not run for a write that is not a change. The default test is
identity: two ints, bools, strings or floats with the same value are the
same, and a new record, tuple or list is a change, also when its contents
are equal. Pass `~equal:( = )` to compare contents:

```ocaml
let filter = State.make ~equal:( = ) { status = Open; mine = false }
```

## Holes

In an `.mlx` file, a child or an attribute value that contains `State.get`
becomes a hole. A hole is the only part of the markup that changes after
the first render.

```ocaml
<p class_=(if State.get active then "on" else "off")>
  (Yuka.text (State.get name))
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

`State.memo f` is a value computed from other States. Use it when a
computation is costly, or when several readers need the same result.

```ocaml
let visible =
  State.memo (fun () ->
      List.filter (matches (State.get filter)) (State.get issues))
```

- A memo is read-only: `State.set` on it does not compile.
- A memo computes one time when you create it. After that it computes
  again only when a State it read changed and something reads the memo. A
  memo that nothing reads does no work.
- A memo has the same change test as a State. When it computes a value
  equal to the old one, its readers do not run.
- A reader never sees a memo that is out of date. In the example at the
  top, no code can observe the new `count` together with the old `double`.

## Effects

An effect connects a component to something outside Yuka: a timer, a
socket, a browser API, a log.

`Effect.run f` runs `f` now, and again each time a State it read changes.

`~cleanup` receives the result of the previous run. Yuka calls it before
the next run and when the component is removed. Here `connect` and
`close` are your own functions:

```ocaml
Effect.run ~cleanup:close (fun () -> connect (State.get room))
```

When `room` changes, Yuka closes the old connection and opens a new one.
When the component is removed, Yuka closes the last connection.

`Effect.on_change s f` calls `f ~prev ~next` when `s` changes. It does not
call `f` for the first value.

To read a State in an effect without a re-run when it changes, use
`State.peek`, or wrap the code in `State.untrack`.

Do not use an effect to copy one State into another. Use a memo. An effect
that writes a State it reads runs again and again. After 100 rounds Yuka
stops and raises `Failure`.

## When updates run

A write updates the page before `State.set` returns: the holes and the
effects that read the State have run.

`Yuka.batch f` delays that work to the end of `f`, so readers run one time
for several writes:

```ocaml
Yuka.batch (fun () ->
    State.set first "Ada";
    State.set last "Lovelace")
```

Each event handler already runs in a batch. Two writes in one `on_click`
update the page one time.

## Lifetime

Effects and memos belong to the component, hole or list row that created
them. When Yuka removes that part of the page, it stops its effects, runs
their cleanups and drops its memos. An effect created inside another
effect is stopped before the outer effect runs again.

`Yuka.owner f` runs `f` and returns a function that stops everything `f`
created. Use it for effects that must live outside a component.

## On the server

The server calls the component one time to print HTML.

- A hole prints its current value.
- A memo computes one time.
- `Effect.run` and `Effect.on_change` do nothing: the body and the cleanup
  do not run. Code that needs the browser belongs in an effect or an
  event handler.

A State that you create inside a component is new for each request. A
State at the top level of a module is different: the server process has
one copy, and every request reads and writes that copy. One user could see
the data of another. For that reason this is a compile error:

```ocaml
let dialog_open = State.make false
```

Create the State inside a function. When a State must be global in the
browser, for example one flag that several islands read, mark it:

```ocaml
let dialog_open = State.make false [@@yuka.shared]
```

`[@@yuka.shared]` is your statement that only code that runs in the
browser (event handlers and effects) writes this State. The compiler does
not check the statement. On the server the State keeps its first value for
every request.
