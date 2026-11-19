# State, memos and effects

This page explains how a Yuka component updates the page. It is for a
reader who knows React or Solid. The exact API is in
[`src/state.mli`](https://github.com/davesnx/yuka/blob/main/src/state.mli) and
[`src/yuka.mli`](https://github.com/davesnx/yuka/blob/main/src/yuka.mli).

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

## Reducers

Yuka has no `useReducer` hook. React needs one to keep the state and a
stable `dispatch` across renders. A Yuka component runs one time, so a
State and a function that calls `State.update` are enough:

```ocaml
type action = Increment | Decrement | Reset of int

let reduce count = function
  | Increment -> count + 1
  | Decrement -> count - 1
  | Reset n -> n

let[@client] make ~(initial : int) () =
  let count = Yuka.State.make initial in
  let dispatch action = Yuka.State.update count (fun c -> reduce c action) in
  <div>
    <button on_click=(fun _ -> dispatch Decrement)> "-" </button>
    (Yuka.int (Yuka.State.get count))
    <button on_click=(fun _ -> dispatch Increment)> "+" </button>
    <button on_click=(fun _ -> dispatch (Reset initial))> "Reset" </button>
  </div>
```

`State.reducer reduce initial` does the same and returns the State
read-only, so only `dispatch` can write it:

```ocaml
let count, dispatch = Yuka.State.reducer reduce initial in
```

- `dispatch action` writes `reduce value action` of the current value.
- A reducer that returns a new record is a change, also when its contents
  are equal. Pass `~equal:( = )` to compare contents.
- Each event handler runs in a batch, so several `dispatch` calls in one
  handler update the page one time. Elsewhere, wrap them in `Yuka.batch`.

## Holes

In an `.mlx` file, each child and each attribute value of an HTML tag is a
hole, except a constant. A hole is the only part of the markup that changes
after the first render.

A constant is an expression that the ppx can prove reads no State:

- a literal, a name (`label`, `item.title`), a function (an event
  handler), or a tuple, record, list or constructor of constants;
- an HTML tag, `<Yuka.Client>`, or a component tag whose props are
  constants;
- `if`, `match` and `let` made of constants;
- an operator or a function of the standard library that calls no
  function you give it (`^`, `+`, `=`, `string_of_int`, `Int.to_string`,
  `String.sub`, `List.length`), applied to constants;
- `List.map`, `List.filter` or `List.init` (also on `Array`) with a
  function whose body is a constant;
- a function defined with `let` in the same file whose body is a
  constant, such as `let badge ~count = <b>(Yuka.int count)</b>`, applied
  to constants;
- `Yuka.text`, `Yuka.int`, `Yuka.float`, `Yuka.fragment`, `Yuka.each`,
  `Yuka.hole`, `Yuka.with_unique_id`, `Yuka.Form.value`,
  `Yuka.Form.field_error_view`, `Yuka.Form.form_errors_view` and
  `Yuka.Status.error_to_string` applied to constants.

A call of a function from another module, `(Model.label issue)`, is a
hole: the ppx cannot see whether it reads a State.

```ocaml
<p class_=(if Yuka.State.get active then "on" else "off")>
  (Yuka.text (Yuka.State.get name))
</p>
```

This paragraph has two holes. A write to `active` sets the `class`
attribute. A write to `name` sets the text. Each write touches one place
in the DOM.

A read inside a function that the hole calls counts too. Here the text
updates when `name` changes:

```ocaml
let label () = Yuka.text (Yuka.State.get name) in
<p>"Name: " (label ())</p>
```

A hole runs one time when it is mounted, and again after each change of a
State that it read. A hole that reads no State never runs again, but it
keeps its place in the scheduler and its markers, as any hole.

A component tag and a plain call are different in a hole:

- A component tag, `<View />`, inside a hole runs its body untracked. The
  hole does not run the body again when a State that the body reads
  changes, so a State that the body makes stays. The props are read by the
  hole around the tag.
- A plain call, `(view ())`, belongs to the hole that contains it. When the
  call reads a State, a change runs `view` again, and a State that `view`
  makes is made again. Use a tag for a part that makes a State. A tag
  inside the body of `view` is not untracked.

`Yuka.hole (fun () -> ...)` makes a hole by hand, for example in code
without mlx.

A hole that returns elements, not text, removes its old elements and
creates new ones each time it runs. Keep such a hole small, or read the
State deeper in the tree, so that less is created again.

## Keyed lists

`Yuka.each` shows a list whose rows keep their DOM nodes. Give it a key
for each item, a function that reads the items (a hole), and the view of
one item:

```ocaml
(Yuka.each ~key:(fun (issue : Issue.t) -> issue.id)
   (fun () -> Array.of_list (Yuka.State.get issues))
   (fun (issue : Issue.t) -> <li>(Yuka.text issue.title)</li>))
```

A row whose key stays keeps its nodes, and renders again only when
`equal` says its item changed (default: identity, `==`). Give
`~equal:( = )` for items that are rebuilt with the same content. Of two
items with the same key, only the first shows. `each` keeps the items,
not the array: to show a change, give a new array.

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
level of `Yuka.with_owner`, it runs at once.

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

`Yuka.with_owner body` runs `body` and returns a function that stops everything `body`
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
  <Yuka.Context.Provide context=theme value=dark>
    <Layout> <Save /> </Layout>
  </Yuka.Context.Provide>
```

Read it in a component below:

```ocaml
module Save = struct
  let make () =
    let theme = Yuka.Context.get_exn theme in
    <button class_=(Theme.button (Yuka.State.get theme))> "Save" </button>
end
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

### Contexts that reach islands

An island reads what a component inside the island gave. A value that the
page gives reaches the islands below it only when the context has a codec:

```ocaml
let theme : Theme.t Yuka.Context.t =
  Yuka.Context.make ~name:"theme" ~codec:Theme.codec ()
```

The server writes the value into the HTML one time for each `Provide`, the
first time it prints an island below it. In the browser, the first
`Yuka.Context.get theme` in an island decodes that value, so hydration
shows what the server printed. Islands under the same `Provide` share the
decoded value. A context with a codec needs a `~name` of `a-z`, `0-9`, `.`,
`_` and `-`; it is the key of the value in the HTML, so give each context
its own name. `make` raises `Invalid_argument` without one.

Everybody who loads the page can read the value. Do not give a secret, and
do not use it to decide what a user may do: guards, loaders and actions
check the user from the request again.

A context without a codec does not reach an island: `get` gives `None`
there, and `get_exn` says that the context has no codec.

A value that must follow a client navigation is a State, with
`Yuka.Codec.state`:

```ocaml
let user : User.t Yuka.State.read Yuka.Context.t =
  Yuka.Context.make ~name:"user" ~codec:(Yuka.Codec.state User.codec) ()
```

The browser keeps one State for each `Provide`. When a client navigation
renders that `Provide` again with a new value, the State gets the value
before the new islands start, so an island that keeps running (in a layout)
shows it, and only the holes that read the State run again. With a plain
codec, an island keeps the value of its first read.

The route of the page is such a context; read it with `Routes.current`. See
[Router](router.md).

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
