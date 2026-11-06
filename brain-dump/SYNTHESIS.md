# Synthesis of the brain-dump

Goal: a view library in OCaml. It compiles to JS with Melange and to native for server rendering. Components are functions with props. They compose, hold local state, and run effects that sync with the outside world. Many ideas come from Elm.

Source files, in `brain-dump/`: `00-original-notes.md`, `type-safety.md`, `effects.md`, `reactivity.md`, `elm.md`, `elm-likes.md`, `react-internals.md`, `async-react.md`, `prior-art-libraries.md`, `universal-and-resumability.md`.

Established facts used below:
- Melange has no evidence of OCaml 5 effect handler support. Direct-style `perform` cannot be the portable core.
- In Melange, `Some x` with `x` not an option compiles to `x` itself, so identity is kept. Tuples, records, variants with payloads, nested options and int64 are fresh JS objects when rebuilt. So `===` on them fails after a rebuild.

## Where the research agrees

- Render must be pure. Effects run only after commit, never during render. A render that mutates breaks batching, async work and SSR. (react-internals, async-react, effects)
- Keep an element tree as data, and a host interface behind it. One core then drives the DOM, a server string and tests. (react-internals, prior-art-libraries, elm)
- On the server, run render once. Effects and subscriptions never run. Type the effect as a value stored in the tree, and let the server printer ignore it. (effects, react-internals, reactivity)
- Hook call order is only a way to give state an identity without a name. Three other ways exist: setup that runs once, typed handles, or state outside render. Any of them removes the rule. (type-safety, react-internals, prior-art-libraries, reactivity)
- brisk-reconciler types its hook tape but still keeps the order rule. No library read has removed the rule. (prior-art-libraries, type-safety)
- Dynamic lists get one list constructor with a required `key` argument. There is then no keyless dynamic list. (type-safety, react-internals, reactivity, prior-art-libraries)
- Add a dev-mode check for duplicate keys. Types cannot see `fun _ -> "0"`. (type-safety, prior-art-libraries)
- Equality must be explicit, as `~equal`. Default to physical equality `==`. Do not default to polymorphic `=`. It raises on functions, can loop, and costs time. (effects, reactivity, elm, react-internals)
- On Melange, `==` on rebuilt records, tuples and payload variants is false. An explicit `equal` is the fix. A wrong default re-fires effects on every render. (effects, elm, reactivity, react-internals, universal-and-resumability)
- Suspense cannot be type-safe if it is thrown (an exception or an OCaml 5 effect). Make pending and failed part of the value. (type-safety, async-react, effects)
- Effects are one-shot work or setup and cleanup. Elm keeps `Cmd` and `Sub` apart for this reason. Compose them separately. (effects, elm, elm-likes)
- An effect that returns its cleanup is the right shape. Scopes give cancellation by structure: ending the scope ends the work. (effects, reactivity, prior-art-libraries)
- "Why this effect runs" needs a fact stored in the runtime: a name and a trigger, or the changed dependency with its old and new value. Reading code cannot answer it. (effects, elm, elm-likes, prior-art-libraries)
- Updates are best as a queue of `Set v | Update f`, applied at render or flush time. This makes batching and optimistic layers correct. (async-react, react-internals, prior-art-libraries)
- Interruptible rendering (Fiber) is a large cost. A pure render plus one commit covers most real needs. Leave room for it and do not build it first. (async-react, react-internals, prior-art-libraries)
- Scheduler, time and promises sit behind the host interface. Native makes the scheduler a no-op. (react-internals, async-react)
- Avoid global mutable runtime state on the server path. A global "current component" is safe on JS and wrong with concurrent native requests. (effects, reactivity, async-react, react-internals)
- Dependency scopes must be explicit on JS. There are no weak references that clean up on time (Lwd, Note, VanJS). (reactivity)
- Elm `lazy` and selectors or signals solve the same problem. Use one primary mechanism. (elm, elm-likes, reactivity)
- Resumability needs a reactive graph the build step can see. Re-run-and-diff does not give that. (universal-and-resumability, reactivity)
- Anything that differs between server and client (time, random, window size) should be typed as client-only and readable only in effects and handlers. (universal-and-resumability)
- Browser APIs should live in a library that does not exist on native. A server reference is then a link error, not a run-time crash. (universal-and-resumability)
- Keep the core free of DOM types. (reactivity, react-internals, prior-art-libraries)

## Decisions to make

In dependency order. Each decision narrows the next one.

### 1. What does render do?

Options:
- **A. Re-run and diff.** The component function runs again on each update. It returns a tree. The runtime diffs. This is React, Elm, Preact, brisk-reconciler.
- **B. Fine-grained signals.** The component body runs once. Reads inside a tracking scope (a text binding, an effect) re-run on change. These write directly to the DOM. This is Solid, VanJS, MobX.
- **C. Explicit graph.** The view is a value built from `map`, `let+` and `and+`. Nodes are created once. Dependencies are the combinators. This is Lwd, Incremental, Bonsai.

What each option allows or blocks:

| | A. Re-run + diff | B. Signals + scopes | C. Explicit graph |
|---|---|---|---|
| Resumability (no client re-run) | Blocked. The function must run to rebuild the tree. | Possible with a build step that lifts closures. Bindings are closures, so a ppx must mark them. | Possible and easiest. The graph is a value. A ppx must still make nodes serialisable. |
| Elm `lazy` | Natural. Compare arguments with `==`, skip the subtree. | Not needed. A derived node with `~equal` replaces it. Mixing both is probably wrong. | Same as B. `cutoff` replaces it. |
| Stale reads | Rare. Every render re-reads. | The main trap. `let x = State.get a` in the body is read once and stays stale. | Typed away. A plain `'a` is not an `'a t`. |
| SSR | Trivial. Render once. | Needs a no-tracking mode. State is a plain cell, effects do not run. | One `observe`, one `sample`, `release`. Fits as is. |
| Async and transitions | Fits React's model: speculative tree, old tree on screen. Needs alternate trees. | Hard. Signals update in place. A transition needs a copy or version of state. | Clean place to batch: `stabilize`. Transitions still need a version of state. |
| Devtools and replay | Easy. State and tree are data. | Medium. Needs names on nodes. A graph dump is possible. | Easy to dump the graph. Logging fired nodes gives "why". |
| Cost of an update | Size of the diff. | A few DOM writes. | A few DOM writes plus about 30 ns per fired node (Jane Street blog). |
| Author rules | Hook order or ids. | "Reads count only in a scope." | Everything flows through `let+`. Conditionals need `switch`, which is costly. |

Recommendation: **B (signals with explicit ownership scopes)**, with two things taken from C: `~equal` on every node, and named effects. Reason:
- It has the fewest author rules.
- It matches the notes' `State`/`Effect` sketch.
- SSR stays simple.
- It keeps the door open for resumability (decision 8).
- It removes the need for a compiler to memoize.

The stale-read trap must get a guard (see decision 3). If the user wants strict types over ergonomics, choose C. Choose A only if staying close to React matters more than resumability. A is the fallback in `reactivity.md` too.

### 2. Who owns state?

Options:
- **Local cells.** Each cell is a typed handle created in the component. The owner scope holds it. Nothing is global.
- **One store with typed slots.** All state is in one dumpable store. A component gets a typed slot keyed by instance path (re-frame, Elm, Cycle `isolate`).
- **Hybrid.** Local cells, plus an optional name and codec on a cell so the runtime can dump and restore it.

What each makes possible or impossible:
- Local cells: simple code, components truly local, no nested-update boilerplate. Opaque closures can be hidden in them, so time travel, replay and SSR state transfer are impossible without extra work.
- Store: undo, replay, schema checks and hydration come for free (re-frame). It couples components to the store shape. A lens `set` rebuilds the parent record and defeats lazy at the parent (elm, elm-likes). It is closer to Elm, and further from "components are functions with local state".
- Hybrid: keeps local code. Only cells with a codec cross the server boundary or enter a dump. A cell with no codec is client-only. It cannot be read during server render. This makes the client-only rule a type rule.

Recommendation: **hybrid**. Default is a local cell. `~codec` and `~name` are optional. A cell that is read during SSR needs a codec, enforced by the type of the server entry point. Reason: it keeps the notes' "local state", and it gives replay and hydration where they are needed. Choosing a full store later stays possible: a store is a cell of a record type.

Depends on decision 1: under A, the component state needs a position or a name. Under B and C, state is a handle and needs neither.

### 3. How does state get an identity? (hook order, props)

Options:
- **Setup once.** The component body is the setup. State is created in lexical order, in the body. No conditionals around state creation are possible in practice, because it is closure state, not slot state. (B or C makes this natural.)
- **Typed tape (brisk).** Hook order stays, and the type system checks it. Heavy types, and a ppx.
- **Call-site ids by ppx.** Order stops mattering. Hot reload and refactors change ids.

Under B the component is a plain function that runs once. Props that never change are plain values. Props that change over time are `State.t` or `Signal.t`. This removes the "props getter" problem in `type-safety.md` and keeps "props are plain function arguments".

Recommendation: **setup once**, no ppx. Add one guard for the stale-read trap: in dev mode, `State.get` called outside a tracking scope during component build logs a warning with the cell name. Optionally make `State.t` abstract and give `text` and `attr` a thunk argument. Then the common case type-checks only when written correctly.

The notes' sketch has `type 'value t = 'value`. That makes `State.t` transparent, so a plain value and a cell are the same type. This defeats the guard. Make `State.t` abstract.

### 4. How do effects work?

Options:
- **Tracked reads.** The effect body reads `State.get`. Dependencies are the reads. No deps list.
- **Explicit `Effect.on`.** The effect names the cells it depends on. It receives `~prev` and `~next`.
- **Data descriptions.** An effect is a value (`Cmd`, `Sub`) that the runtime runs, as in Elm and re-frame.

Facts:
- The Melange constraint removes the `perform` style from the core.
- Data descriptions work on both targets and allow replay (the runtime can use a no-op handler). They need a closed set of commands plus an escape hatch, or registered handlers.
- Tracked reads hide why an effect ran. `effects.md` says tracking records "count changed from 3 to 4". `reactivity.md` says auto-tracking "hides the answer". The two files disagree. The truth depends on whether the runtime logs the changed cell. It can. The dependency set is then dynamic and the log is only as good as the cell names.

Recommendation: **`Effect.on` as the default, `Effect.sync` (tracked) as the escape hatch, `Cmd` as a separate small layer.**
- `Effect.on` is the notes' own `Effect.xxx a (fun prev next -> ...)`.
- Every effect has a `~name`, and the runtime stores the trigger (`Mount`, `Changed`, `Unmount`). That answers "why this effect runs".
- Every effect runs in its own child `Scope`. The scope closes before the next run and on unmount. This gives cancellation (Eio's idea, no OCaml 5 effects needed).
- `Cmd` is for one-shot work that reports back (HTTP). `Effect` is for setup and cleanup. Do not merge them.
- Make the dependency comparison `~equal` with a typed default per common type (`Effect.on_int`, or `Equal.int`). Do not default to `=`.

### 5. Async: how does loading and failure show up?

Options:
- **Explicit `Remote.t` (`Loading | Failed | Ready`)**, matched by the component. Type-safe, verbose.
- **Phantom `Suspends`** on node types, removed by `Suspense.boundary`. Type-safe, and straight-line code. Long error messages. Every ancestor type carries it until the boundary.
- **Exception** `Suspend` caught by the boundary. Portable and simple. Not type-safe.
- **OCaml 5 effect** `Await`. Native only. Out.

What it affects:
- Streaming SSR needs the boundary as a core concept on both targets. The boundary decides what flushes first.
- Transitions and `useDeferredValue` need two versions of state. They are hard under decision 1 option B.
- `useOptimistic` can be a derived layer: base state plus a pending list. An `Action` value that carries the transition makes "set outside an action" a type error.

Recommendation: **`Remote.t` as the data, `Resource.use` with the phantom `Suspends` as sugar, one `Suspense.boundary` as the core concept.** One error type per app at first (`Boundary.catch : App_error.t -> node`). Skip row-typed errors until the messages prove readable. Do **not** build transitions or deferred values in v1. Build the `Action` value and the batch rule (microtask flush) instead.

### 6. Equality and laziness

Options:
- `==` by default, `~equal` overrides (TC39 `equals`, Incremental `cutoff`).
- A ppx that generates a field-wise `equal` for prop records (elm.md).
- Deep structural `=`: rejected.

Effect: with B or C, `~equal` on a node is the cutoff, and no `lazy` exists. With A, `lazy` compares arguments with `==`, and a record argument fails because the record is new each time.

Recommendation: `~equal` on `State.make`, `Derived.make` and `Effect.*`, default `==`. Document that rebuilt records, tuples and payload variants are not `==` on Melange. Ship `Equal.int`, `Equal.string`, `Equal.option`, `Equal.list`. A `[@@deriving equal]` (ppx_deriving) fills the rest. Do not add a `lazy` node unless decision 1 picks A.

### 7. Keys, children and attributes

Options and effects: see `type-safety.md`. They do not depend on decisions 1 to 6, except that a signals list needs per-row scope.

Recommendation:
- Keys: `Each.keyed ~key list render` is the only dynamic list. Under B, `render` gets a `'a State.t` per row, and each row owns a scope. Dev duplicate-key check.
- Children: a small phantom kind (`Text | Element | Fragment`), not the full HTML content model. Test mlx error messages before widening.
- Attributes: typed values, with a ppx that checks names per tag (level 2 + 3 of `type-safety.md`). This matches "same errors as React".

### 8. Server and client

Options: hydrate (A), islands with typed props (B), resumable with lifted handlers (C). See `universal-and-resumability.md`.

Effect on others: only (C) needs decision 1 to be B or C. Only (A) works with a re-run-and-diff core. A cell needs a codec in all three.

Recommendation: **start with hydrate, and design the cell and the handler so that (C) stays possible.**
- Native writes `(id, encoded)` for each cell with a codec. Melange reads them by id. The id is the instance path plus the cell name. Do not use creation order alone.
- Keep browser APIs in a library that does not exist on native.
- Type `Client_only.t` for time, random and window size.
- Do not promise resumability in v1. It needs a ppx for handlers, a bundler step, and a dependency map. Prototype it later on one component.

### 9. Flush and batching

Options: flush at once after each `set`; flush in a microtask; explicit `stabilize`/`transact`.

Recommendation: coalesce all `set` calls in one event or tick into one flush with `queueMicrotask`, and offer `Batch.run` for synchronous groups. Effects run after the flush, in tree order, cleanups before runs. Reads after `set` return the old value until the flush. State this rule once. (async-react says to pick a rule and name it.)

## Notes items, answered

Bullets of `00-original-notes.md`, in order.

| Note | Short answer | Read |
|---|---|---|
| Ensure key args are present in List stuff? Not need them? | Yes. One dynamic list constructor with a required `~key`. No keyless dynamic list. A bad key is not caught by types, so add a dev duplicate check. "Not need them" works only with signal lists, which key by reference and meet the Melange `===` issue. | type-safety |
| Type-safe children, Button only accepts Text | Yes, with a phantom kind on `node`. Use few kinds. Full HTML content models make wrapper components hard. | type-safety |
| Remove the hook order | Yes. Setup once (components run once), typed handles, or state outside render. Nothing in the libraries read has done it. | type-safety, react-internals, prior-art-libraries |
| Suspense catches errors and is type-safe | Yes, if pending and failed are values (`Remote.t`) and the boundary removes a phantom. Not with a thrown promise or an OCaml 5 effect. | type-safety, async-react |
| Safety around attributes | Typed values plus a ppx that checks names per tag. | type-safety |
| Minimum safety like tyxml | Same. Full tyxml typing (per-tag attribute types) is stronger and costs error messages. | type-safety |
| Take advantage of the effect system / effects as ppx | The tweet could not be read. Do not use OCaml 5 effects in the core: Melange lacks them. A ppx can give each effect a name and a deps list at compile time. Treat as optional. | effects |
| Redux issues 455 and 1528 | Both discuss effects as data and the cost of composing them. They name cancellation, replay and composition as the hard problems. Scopes answer cancellation. | effects |
| Why this effect runs (monads? Eio model?) | Name plus trigger stored in the runtime. A monad does not add this. Eio's idea of a scope fits; Eio itself is native only. | effects |
| A way to compose effects | `both` for setup and cleanup effects (reverse cleanup order). `batch` and `map_msg` for commands. Keep the two kinds apart. | effects |
| Relate effects and renders | Render is pure. Commit applies the tree. Effects run after commit, in tree order. Native never runs them. | effects, react-internals |
| `derivable` | Atoms, derivations, reactors with a `when` gate, and `transact`. Reactors map to `Effect.on`, and `transact` maps to `Batch.run`. | effects, reactivity |
| Better integration with Melange | Give explicit `equal` everywhere. Watch value identity. Do not rely on OCaml 5 effects. Use a thin host interface. | effects, elm, universal-and-resumability |
| Focused on universal code from the start | Shared core, host interface, a browser-only library absent on native, `Client_only.t`. The dune claim in the research file is wrong: see the check below. | universal-and-resumability |
| Remove rules of hooks | See "Remove the hook order". The deps array is also a rule. `Effect.on` drops it. | react-internals, effects |
| Remove the need for a compiler (Melange or ppx does the hard work) | Setup once means no per-render closures to memoize, so a React-compiler equivalent is not needed. Collides with: resumability and `[%handler]` (needs a ppx and a bundler), and "effects as ppx". | async-react, react-internals, universal-and-resumability |
| Props | Static props are plain arguments. Changing props are cells. A record of props needs a field-wise `equal` (ppx) if `lazy` exists. | type-safety, elm |
| Embrace elm/ui and elm/html patterns | Pure view, effects as data, typed layout, `lazy` by `==`. Elm refuses components. This library wants local state. Take the data-shaped effects and typed children. | elm, elm-likes |
| Embrace mobx? | Take implicit tracking, lazy deriveds and `action` as a transaction. Do not take implicit global tracking as the only way. | reactivity |
| Check Preact v11 | Mostly cleanup. Take: small core, `ref` as a plain prop, LIS child moves, stable hydration markers, explicit `Object.is`-style equality. | prior-art-libraries |
| Study Jane Street incremental, Lwd | `map`, `bind`, `observe`, `stabilize`, cutoff. Cost about 30 ns per fired node. Lwd: avoid `join`. This is Candidate C. | reactivity |
| Study async React (Fiber) | Pure render, work loop, commit. Keep the split; skip the work loop in v1. | async-react, react-internals |
| Non-blocking vs blocking | Urgent by default. Non-blocking is opt-in. Do not build in v1. | async-react |
| useDeferredValue, useOptimistic | `Deferred = { live; shown }`. Optimistic as a derived layer. Both need an `Action` value. Optimistic is easier than deferred. | async-react |
| setState vs dispatch multiple rerenders | No difference in re-render count by the React docs: both batch and both bail out on equal values. The difference is where the logic lives. | async-react |
| Lazy from Elm | `===` check on arguments, last result only. Not needed under signals or graph. Needed under re-run-and-diff. | elm |
| Server and client resumability possible? | Yes in principle (Qwik, brumate). OCaml helps: a ppx sees free variables and codecs are typed. It needs a reactive graph, a handler-lifting ppx, a bundler step and a runtime loader. Start with hydrate. Collides with Elm's re-run `view`. | universal-and-resumability |
| Implement hooks? | A hook runtime is about 150 lines (Fre). Not needed if components run once. | prior-art-libraries, react-internals |
| romgrk reactivity | Selector stores: cheapest step from re-render-all. Tearing in concurrent React is avoided if the library owns its scheduler. | reactivity |
| Build your own React (list) | All show one model: element tree, instance tree, render, commit, hook slots. Unmount cleanup, keys and effect timing are the usual gaps. | react-internals |
| Prior-art list (fre, pure, brisk, superfine, vanjs, tachys...) | brisk-reconciler is the closest base. Superfine shows the minimal core. VanJS shows fine-grained bindings. The `_developit` tweet could not be read. | prior-art-libraries |
| cycle.js, re-frame | Cycle: `isolate` scopes state. re-frame: one store, subscriptions with output pruning, effects as a map. | elm-likes |
| `State.make` sketch: `type 'value t = 'value` | Make `State.t` abstract. A transparent type allows stale reads with no warning. | reactivity |
| `State.get a` | Fine. Reads count only in a tracking scope. | reactivity |
| `Effect.xxx ~equal=???` | Required `~equal` with a default of `==` and typed helpers. | effects, reactivity |
| `Effect.xxx a (fun (prevA nextA) -> ...)` | `Effect.on`: the dependency is the first argument. `~prev` is `'a option` on mount. | reactivity |
| `Effect.xxx a (fun (a) -> ...)` (repeated twice) | Same shape with only the new value. Offer it as `Effect.on_value`, or ignore `~prev`. | reactivity |

Collisions between notes:
- **Remove need for compiler** vs **effects as ppx** vs **resumability**: the last two need a ppx, and resumability needs a bundler.
- **Embrace Elm** vs **embrace mobx / lwd / incremental**: Elm re-runs `view` on one model. The others update a graph. See decision 1.
- **Elm lazy** vs **lwd/incremental/mobx**: both solve skipped work. Use one.
- **Resumability** vs **Elm `view`**: resumability needs a graph the build step sees.
- **Remove hook order** vs **implement hooks**: pick one.
- **Why this effect runs** vs **derivable and mobx**: implicit tracking hides the cause unless the runtime logs it.
- **Type-safe Suspense** vs **suspend like React**: a thrown suspension cannot be typed, and OCaml 5 effects do not exist on Melange.
- **Effect system (OCaml 5)** vs **Better integration with Melange** vs **universal**: the first is native only.
- **Props as plain arguments** vs **setup once**: a changing prop must be a cell.
- **Keys not needed** vs **type-safe keys**: only signal lists can avoid keys, and then `===` identity matters.
- `Effect` as a module name collides with `Stdlib.Effect` on OCaml 5 (my observation, unchecked). brisk-reconciler renamed `effect` to `use_effect` for the 5.3 keyword. Choose a name that avoids both.

## Candidate designs

All sketches share these names. `Node` holds element builders; `div`, `button`, `text` are builders. `text_s` is a static string node. `text` takes a thunk and is a tracking scope.

### Design A: cells and scopes (recommended)

Components run once. Signals update bindings. Owner scopes hold effects and rows.

```ocaml
module State : sig
  type 'a t
  val make : ?name:string -> ?codec:'a Codec.t -> ?equal:('a -> 'a -> bool) -> 'a -> 'a t
  val get : 'a t -> 'a
  val peek : 'a t -> 'a
  val set : 'a t -> 'a -> unit
  val update : 'a t -> ('a -> 'a) -> unit
end
module Effect : sig
  val on :
    name:string -> equal:('a -> 'a -> bool) -> 'a State.t ->
    (prev:'a option -> next:'a -> (unit -> unit)) -> unit
end
```

Counter:

```ocaml
let counter ~initial =
  let count = State.make ~name:"count" ~codec:Codec.int initial in
  button ~on_click:(fun _ -> State.update count succ)
    [ text (fun () -> string_of_int (State.get count)) ]
```

Keyed list:

```ocaml
let todo_list (todos : Todo.t list State.t) =
  ul [] [
    Each.keyed ~key:(fun (t : Todo.t) -> t.id) todos
      (fun (todo : Todo.t State.t) ->
         li [] [ text (fun () -> (State.get todo).title) ])
  ]
```

Fetch with a Suspense-like boundary. `Resource.use` marks the node `Suspends`. The boundary removes it.

```ocaml
let user_card (id : int State.t) =
  let user = Resource.make ~name:"user" ~equal:Int.equal id Api.fetch_user in
  Suspense.boundary ~fallback:(text_s "Loading")
    ~catch:(fun (e : App_error.t) -> text_s (App_error.show e))
    (Resource.use user (fun u -> div [] [ text (fun () -> u.name) ]))
```

Effect with explicit dependencies:

```ocaml
let title_sync (count : int State.t) =
  Effect.on ~name:"sync-title" ~equal:Int.equal count (fun ~prev:_ ~next ->
    Document.set_title (string_of_int next);
    fun () -> ())
```

Melange: component bodies run once under an owner scope. A global "current observer" is safe (JS is single-threaded). Bindings write DOM nodes. Effects run after the flush. Hydration reads the cells that have a codec, by id.

Native SSR: `State.make` returns a plain cell with no subscribers. `text` is evaluated once. `Effect.on` and `Resource` effects do not run. `Suspense.boundary` flushes the fallback first and the content when the resource resolves. No global observer: a per-request context is passed to the build.

Costs: the stale-read trap (guard in decision 3). Resumability needs a ppx that marks thunks. Transitions need versioned state.

### Design B: Elm per component, one dumpable store

Components are TEA records. The runtime owns each instance's state in one store, keyed by path. The view re-runs and is diffed. `lazy` compares by `==`.

```ocaml
type ('props, 'state, 'msg) component = {
  init   : 'props -> 'state;
  update : 'props -> 'state -> 'msg -> 'state * 'msg Cmd.t;
  view   : 'props -> 'state -> 'msg Html.t;
  subs   : 'props -> 'state -> 'msg Sub.t;
}
val mount : ?key:string -> ('p, 's, 'm) component -> 'p -> 'out Html.t
```

Counter:

```ocaml
type msg = Incr
let counter = {
  init = (fun initial -> initial);
  update = (fun _ n Incr -> (n + 1, Cmd.none));
  view = (fun _ n -> button ~on_click:Incr [ text (string_of_int n) ]);
  subs = (fun _ _ -> Sub.none);
}
```

Keyed list (the key is a required argument; each row is a mounted component):

```ocaml
let todo_list todos =
  ul [] [ Html.keyed ~key:(fun (t : Todo.t) -> t.id) todos
            (fun t -> mount ~key:t.id todo_row t) ]
```

Fetch with loading (the model holds a `Remote.t`; the boundary matches it):

```ocaml
type model = { user : (User.t, App_error.t) Remote.t }
let update _ m = function
  | Load id -> ({ user = Loading }, Cmd.http (Api.fetch_user id) ~on_done:(fun r -> Loaded r))
  | Loaded r -> ({ user = Remote.of_result r }, Cmd.none)
let view _ m =
  Boundary.remote m.user ~loading:(text "Loading") ~failed:(fun e -> text (App_error.show e))
    ~ready:(fun u -> div [] [ text u.name ])
```

Effect with explicit dependencies (a `Sub` keyed by the dependency):

```ocaml
let subs _ n =
  Sub.on ~name:"sync-title" ~key:n ~equal:Int.equal (fun n -> Cmd.set_title (string_of_int n))
```

Melange: the runtime diffs `Html.t` and blits to the DOM. The runtime diffs `Sub` sets after each update and starts or stops sources. Replay is possible: swap in a no-op handler.

Native SSR: `view` runs once and prints a string. `Cmd` and `Sub` are values and are ignored. Hydration needs the store dump: easy, since all state is data.

Costs: hidden per-instance state still sits in a store keyed by path (positions can shift). A lens or path `set` rebuilds parents, which defeats `lazy` at the parent. More boilerplate than A. No route to resumability, since `view` re-runs.

### Design C: explicit graph (Lwd or Bonsai style)

The view is a value built with `let+` and `and+`. State is a graph node made while building.

```ocaml
module Graph : sig
  type 'a t
  type build
  val state : build -> ?equal:('a -> 'a -> bool) -> 'a -> 'a t * (('a -> 'a) -> unit)
  val map : 'a t -> f:('a -> 'b) -> 'b t
  val switch : 'a t -> ('a -> 'b t) -> 'b t
  val ( let+ ) : 'a t -> ('a -> 'b) -> 'b t
  val ( and+ ) : 'a t -> 'b t -> ('a * 'b) t
  val on : build -> name:string -> equal:('a -> 'a -> bool) -> 'a t ->
           (prev:'a option -> next:'a -> (unit -> unit)) -> unit
end
```

Counter:

```ocaml
let counter ~initial g =
  let count, update = Graph.state g initial in
  let+ n = count in
  button ~on_click:(fun _ -> update succ) [ text_s (string_of_int n) ]
```

Keyed list:

```ocaml
let todo_list g (todos : Todo.t list Graph.t) =
  let+ rows = Graph.each g ~key:(fun (t : Todo.t) -> t.id) todos
                (fun _g (todo : Todo.t Graph.t) -> let+ t = todo in li [] [ text_s t.title ]) in
  ul [] rows
```

Fetch with loading (the resource is a graph of `Remote.t`):

```ocaml
let user_card g (id : int Graph.t) =
  let user = Resource.make g ~name:"user" ~equal:Int.equal id Api.fetch_user in
  let+ u = user in
  match u with
  | Loading -> text_s "Loading"
  | Failed e -> text_s (App_error.show e)
  | Ready u -> div [] [ text_s u.name ]
```

Effect with explicit dependencies:

```ocaml
let title_sync g count =
  Graph.on g ~name:"sync-title" ~equal:Int.equal count (fun ~prev:_ ~next ->
    Document.set_title (string_of_int next); fun () -> ())
```

Melange: build the graph once, observe the root, and patch the DOM per node. Flush with `stabilize` after a microtask. Release the root on unmount.

Native SSR: `observe`, one `sample`, `release`. Effects are registered but never run. Streaming needs the boundary to be a node kind.

Costs: every read needs `let+`. Conditionals need `switch`. A node per attribute in a large list is many nodes. Error messages from `let+` types may be long. In return: no stale reads (types stop them) and the graph is easy to dump.

### Comparison

| | A cells + scopes | B Elm + store | C graph |
|---|---|---|---|
| Closest to the notes' sketch | yes | no | partly |
| Stale reads | guard only | none | none (typed) |
| Resumability later | possible | no | possible |
| Replay and devtools | needs names | easy | easy |
| Boilerplate | low | high | medium |
| Transitions | hard | possible | hard |

## Check run: dune with `(modes ...)` for Melange and native

The universal file says that dune cannot put both modes on one library directly (a background claim). I ran this check.

Tools found: `which dune` gave `/home/me/.opam/parseff-oxcaml/bin/dune` on the default path. No `melc` was on that path. The opam switch `~/.opam/5.2.0` has `dune` 3.21.1 and `melc`: `Melange 6.0.1-52 (Using OCaml:5.2.0+Melange)`. I used that switch with `PATH=$HOME/.opam/5.2.0/bin:$PATH`.

Project: `$TMPDIR/yuka-dune-check` (that is `/tmp/claude-2020/yuka-dune-check`, a fresh directory).

`dune-project`:

```
(lang dune 3.8)
(using melange 0.1)
```

`lib/dune`:

```
(library
 (name core)
 (modes :standard melange))
```

`lib/core.ml`: `let x = Some 1`.

Command: `dune build` in that directory. Result: exit code 0, no output. The build produced `_build/default/lib/core.cma`, `core.cmxa` and `.core.objs/melange/core.cmj`. The library has both native and Melange artifacts.

Second run: I changed the stanza to `(modes native melange)`. `dune build` exited 0 with no output.

Conclusion: the claim in `universal-and-resumability.md` is false for a simple library. A single library can list the native and Melange modes together. Limits of this check: the module has no dependencies and no browser APIs. I did not run `melange.emit`. I did not test a library that depends on a Melange-only library. Whether the shared core can stay free of such dependencies is still open, so the per-platform part (`implements`, `select`) still stands as unverified.

## Unverified claims to check

Claims that the candidate designs rely on, and that the files mark as memory, background, or unread.

Runtime and platform:
1. Melange has no effect handler support today. Evidence is two old announcements and a weak issue search. The changelog was not read. (effects)
2. A global "current observer" is safe on Melange because JS is single-threaded and render is synchronous. It may fail if render can suspend or yield. (reactivity, effects; mine)
3. Per-domain observer state on native (`Domain.DLS`) or an explicit context. Not tested. (reactivity)
4. Melange emits one ES module per OCaml module, so a lifted handler maps to a chunk. Dynamic `import()` bindings can load it. (universal; unmarked, unchecked)
5. `==` on OCaml values behaves differently on Melange and native for options, variants, records and int64. Established by the parent session for Melange. The native side and the effect on `Equal.*` helpers need a test on compiled output. (reactivity)
6. A shared library with both modes and no Melange-only dependency builds and emits. Only the trivial case was run (see above). The `implements` and `select` setup is unchecked. (universal)
7. Naming: `Effect` as a module name may shadow `Stdlib.Effect` on OCaml 5. Not checked. `effect` is a keyword from OCaml 5.3 (read in brisk-reconciler history). (prior-art-libraries)

Reactive model (Design A and C):
8. Push-dirty then pull-on-demand is the common modern design in Solid and MobX. (reactivity, bg)
9. Incremental uses node heights and `stabilize`. Cutoff and `bind` cost were not read in the code. (reactivity, bg)
10. Bonsai scopes state without hook order, and `@ local` on `graph` is a build-time builder. The mechanism is the reading of a README. (reactivity, bg)
11. Solid ownership, cleanup and SSR rules. Not read. (reactivity)
12. Lwd `Nottui` and `tyxml-lwd` update the DOM directly. Code not read. (reactivity)
13. About 30 ns per fired Incremental node. Source read (Jane Street blog). It still needs a measurement for a DOM-sized graph. (reactivity)
14. Note: re-observing a stopped signal is forbidden. Brr integration is only mentioned. (reactivity)

Types (all designs):
15. TyXML phantom variants, `Html_types` aliases, and the quality of their error messages. Memory only. (type-safety)
16. server-reason-react checks attributes per tag in its ppx. Memory only. (type-safety)
17. brisk-reconciler: a conditional hook fails to compile because the tape type differs. Not tested. (prior-art-libraries, type-safety)
18. mlx hides polymorphic-variant kinds with readable errors. Needs a test with real error output. (type-safety)
19. The phantom `Suspends` flows through every ancestor type. `[> ]` hides it but errors get long. Needs a prototype. (type-safety)

Effects and async (all designs):
20. The "Effects as ppx" tweet and the `_developit` tweet were unreadable. Content unknown. (effects, prior-art-libraries)
21. Eio's switch model and OCaml 5 effect rules (one-shot continuations, `Unhandled`). Memory only. (effects)
22. Elm `Cmd` and `Sub` internals, re-frame local state, Hyperapp 2 effects, Cycle `@cycle/state`. Memory or unread. (elm, elm-likes, effects)
23. In React's source `useState` is `useReducer` with a basic reducer. Background. (async-react)
24. React's lane model and `flushSync` detail. Not fetched. (async-react)
25. The tracked-read log "count changed from 3 to 4" is real. It depends on cell names and a dynamic dependency set. Contradicts a claim in `reactivity.md` (see below). Needs a prototype. (effects, reactivity)

Server and resumability (Design A, B, C):
26. brumate's serialisation format is inferred from one compiled counter. Not documented. (universal)
27. Marko 6 compiles to fine-grained signals and serialises only crossing values. Background. (universal)
28. React hydration, selective hydration and mismatch recovery. Background. (universal)
29. Js_of_ocaml compiles bytecode to JS, with effects through a CPS transform. Background and memory. (universal, effects)
30. A `[%handler]` ppx can reject non-serialisable captures. It sees syntax only. Whether a `Codec.t` witness per capture is enough is untested. (universal)
31. Preact v11 branches, Hydration 2.0 RFC. Not read. (prior-art-libraries)
32. Resumability size gain: OCaml's runtime (`Printf`, `Format`, polymorphic compare) may remove it. Not measured. (universal)

## Contradictions between the research files

- **dune claim:** `universal-and-resumability.md` says dune supports both modes only through `:standard` plus `melange.emit`, and the sketch lists `(modes melange native)` as a risk. The check above built a library with `(modes :standard melange)` and with `(modes native melange)`. The claim is wrong for a simple library.
- **Why an effect ran under tracking:** `effects.md` says tracked reads answer "why" ("`count` changed from 3 to 4"). `reactivity.md` says auto-tracked `Effect.sync` hides the answer. Both can hold only if the runtime logs the changed cell. Decide, and prototype.
- **Where state lives:** `elm-likes.md` recommends one dumpable store with typed slots. `reactivity.md` and `react-internals.md` recommend local cells made in setup. `elm.md` names this as an open choice. This is decision 2.
- **Option naming:** `reactivity.md` Option A uses a setup closure with a re-run render, and records "`State.get` records the current component as a subscriber". `type-safety.md` and `react-internals.md` use the same setup closure with no subscription. The shape matches. The subscription mechanism does not.
- **Stale reads in B:** `reactivity.md` says that in option C the type system stops a plain `'a` where `'a t` is needed, and then says "In B it cannot", which is ambiguous. I read it as: B cannot catch the error by types. The notes' own sketch `type 'value t = 'value` makes this worse.
- **Lazy and signals:** `elm.md` says mixing lazy and a fine-grained design is probably wrong. `elm-likes.md` says lazy and selectors compose badly. `prior-art-libraries.md` leaves "mixing was not studied" open. They agree on the caution but not on a rule.
- **Hook order:** `type-safety.md` presents typed hooks as removing the rule in the type. `prior-art-libraries.md` says brisk's typed tape does not remove the rule. Treat the rule as kept.
