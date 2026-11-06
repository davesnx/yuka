# Effects

Scope: what effects (side effects of a component) can look like in an OCaml view library that targets Melange (JS) and native (server rendering).

## Sources

- https://x.com/javierwchavarri/status/1079588586507378689 — failed (HTTP 402 from X). Nitter mirror also failed (nitter.net now serves a shutdown notice). A web search for the quoted text found nothing. The only thing known is the title in the notes: "Effects as ppx". No tweet content is used below.
- https://github.com/reduxjs/redux/issues/455 — read ("modeling side-effects", 2015).
- https://github.com/reduxjs/redux/issues/1528 — read ("Reducer Composition with Effects", 2016).
- https://www.npmjs.com/package/derivable — failed (HTTP 403 from npm). Read the project README on GitHub instead (https://github.com/ds300/derivablejs). The README does not state glitch-freedom or laziness guarantees, so none is claimed here.
- https://github.com/melange-re/melange (Melange status) — partly read. See the Melange item in Key ideas.
- Background knowledge, not fetched, marked "(memory)" below: Eio, Elm Cmd/Sub, redux-loop, redux-saga, js_of_ocaml effects, OCaml 5 effect API.

## Key ideas

Redux issues (read):
- Effects as data returned by the reducer, run by the store. The store can skip them on replay (time travel). (#455)
- Hard problems named in #455: cancellation of in-flight work, undo does not undo an effect, how effects combine when reducers are split.
- Elm's `(state, action) -> (state, effect)` shape does not compose with `combineReducers`. Redux-loop composes, but you wrap and unwrap tuples at every level. (#1528)
- Proposal in #1528: reducers `perform` an effect and the store handles it and resumes the reducer. This keeps ordinary function calls and plain composition. Critics: resuming with a value makes control flow hard to test; sync reducers force queueing.
- Generator reducers (`yield` effect descriptions, `yield*` for sub-reducers) were tried in practice (redux-side-effects). Drawback: `yield*` does not cross callbacks such as `List.map`. (#455, #1528) OCaml 5 handlers do not have this limit (see below).
- A declarative effect descriptor can be diffed against outstanding work, like DOM diffing. (#1528)
- Effects should run after the reducer and react to state transitions, like hooks. (#455, vladar)

derivable (README read):
- Atoms (mutable cell holding immutable value), derivations (computed values, dependencies found by tracking `.get()` calls), reactors (run side effects when a derivable changes, no value of their own).
- A reactor has a `when` gate: it is active only while a derivation is truthy. Lifecycle of an effect is tied to a condition, not only to a change.
- `transact` batches many sets so reactors see the final state once.
- No dependency array: dependencies are the reads.

OCaml 5 effects (memory):
- `Effect.perform`, deep and shallow handlers, one-shot continuations. Effects are declared as extensible GADT constructors. They are not tracked in types: an unhandled effect raises `Effect.Unhandled` at run time.
- Handlers see calls through callbacks (`List.iter`, closures). This is the thing generators lacked.

Melange and effects (verified as far as possible):
- Melange 2.0 announcement (read): "Melange doesn't yet include support for effect handlers and some of the multicore OCaml primitives." That post dates from the OCaml 5.1 period.
- Melange 5.0 announcement (read): targets OCaml 5.3 type checking; no mention of effect handlers.
- GitHub issue search in melange-re/melange for "effect handlers": zero results (the search tool matches poorly, so this is weak evidence).
- Conclusion: no evidence that Melange supports effects now. Treat as unsupported. I could not read the Melange changelog (404 on the path tried), so "unsupported today" is unconfirmed.
- Why it is hard (memory): JS has no stack switching. js_of_ocaml supports effects with a CPS transform, which slows and enlarges code (memory). Melange emits direct-style JS, so it would need a similar transform or generators.

Eio (memory):
- Structured concurrency. Fibers run inside a `Switch`. A switch ends only when all its fibers end; resources attached to the switch release when it ends; cancelling a switch cancels its fibers. Built on OCaml 5 effects. Native only.

Elm (memory):
- `update : Msg -> Model -> (Model, Cmd Msg)`. `Cmd` is a description of work; the runtime runs it and sends the result back as a `Msg`.
- `subscriptions : Model -> Sub Msg`. The runtime diffs the subscription set after each update and starts or stops sources. This is "effects as a function of state", the same as a React effect with a dependency array, but the runtime owns the diff.
- Cmd and Sub compose with `Cmd.batch`, `Cmd.map`. Every effect has a clear cause: a Msg in the log.

redux-loop and redux-saga (memory):
- redux-loop: reducer returns `loop(state, Cmd)`. `Cmd.batch`, `Cmd.map`, `Cmd.list` compose. Combining reducers needs the loop-aware `combineReducers`.
- redux-saga: generator functions yield descriptions (`call`, `put`, `take`, `fork`, `race`). An interpreter runs them. Tests step the generator and compare descriptions. Cancellation is built in.

## What this means for the library

### Three styles

| Style | What an effect is | Why it ran | Compose | Melange | Native |
|---|---|---|---|---|---|
| Data description (Elm Cmd/Sub, saga) | a value | read the value and the trigger | `batch`, `map` | yes | yes |
| Monad or applicative (`let*`, `let+`) | a value with bind | trace through binds | bind, `and+` | yes | yes |
| Effect handlers (`perform`) | a call in direct style | needs tracing in the handler | plain function calls | **no** (unsupported) | yes |

Recommendation: make the core a data description with a small applicative layer on top, because it is the only option that works on both targets and the only one that answers "why did this run" without extra tooling. Offer handlers only as a native-side implementation detail, never in the public API.

### Data description, with a reason attached

```ocaml
type trigger =
  | Mount
  | Deps_changed of { name : string }
  | Unmount

type 'dep t = {
  name : string;
  deps : 'dep;
  equal : 'dep -> 'dep -> bool;
  run : trigger -> (unit -> unit) option;   (* returns cleanup *)
}
```

The runtime keeps the previous `deps`. After commit it compares with `equal`. If different, it calls cleanup, then `run (Deps_changed {name})`. A devtool or test hook logs `name` and the trigger. This answers "why this effect runs" with a fact stored in the runtime, not a guess.

The notes' `Effect.xxx ~equal ()` fits this shape directly. Make `~equal` required or default to a typed comparator per dep. Reason: Melange compares dependency values with JS `===` in the React bindings. Variants with payloads, records, tuples and nested options (`Some None`) are fresh objects when rebuilt on each render (`Some x` with `x` not an option compiles to `x` itself), so an effect would re-fire every render (see the melange-advanced skill). Polymorphic `=` is a poor default: it raises on functions and costs time.

### Tracked reads instead of a deps list

Derivable-style: `State.get a` inside an effect records `a` as a dependency, so there is no list to get wrong.

```ocaml
Effect.make ~name:"sync-title" (fun () ->
  let n = State.get count in
  Document.set_title (string_of_int n);
  fun () -> ())
```

The runtime knows the dependencies from the reads, so "why it ran" is "`count` changed from 3 to 4". Trade-off: reads must go through `State.get` (the notes already propose this), and a read behind a branch changes the dependency set, so the runtime must recompute it on each run. Works on both targets because it is plain mutable state and closures.

### Relating effects to renders

Pick one rule and state it:
- Render is pure: reads state, builds a tree, never runs effects.
- Commit: tree applied to DOM (or serialised on native).
- After commit: pending effects run, in tree order, cleanups before runs.
- Native server render: render only; effects never run. Encode this in the type: effects are values stored in the tree and the server printer simply ignores them. This is cleaner than React's rule "effects don't run on the server".

If the library goes signal-based (Lwd, derivable), effects attach to signals and are independent of renders: a render is itself a derivation. That removes the render/effect relation but also removes the batch boundary, so add a `transact`.

### Composition

```ocaml
val both : unit Effect.t -> unit Effect.t -> unit Effect.t
val map_msg : ('a -> 'b) -> 'a Cmd.t -> 'b Cmd.t
val batch : 'a Cmd.t list -> 'a Cmd.t
```

Two separate things to compose:
1. Setup/cleanup effects (sync with the outside world): compose like resources. `both a b` runs `a` then `b`, cleans in reverse order.
2. Commands (one-shot work that reports back): compose like Elm: `batch`, `map`.

Do not merge these; Elm keeps `Cmd` and `Sub` separate for the same reason.

### A scope model borrowed from Eio, without effect handlers

Eio's useful idea is lifetime nesting: work belongs to a switch; ending the switch ends the work. Component mount is a switch.

```ocaml
module Scope : sig
  type t
  val on_cleanup : t -> (unit -> unit) -> unit
  val fork : t -> (unit -> unit) -> unit        (* cancelled when t ends *)
  val sub : t -> t                              (* child scope *)
  val close : t -> unit                         (* runs cleanups, cancels forks *)
end
```

Each component instance owns a scope. An effect run gets a child scope, which closes before the next run and on unmount. This gives cancellation (redux #455's problem) by structure. Pass the scope explicitly. It is plain OCaml, so it works under Melange. On native you can back `fork` with Eio fibers.

### Where OCaml 5 effects do help (native only)

- Replace the global "current component" variable that hook-style APIs need (`use_state` reads it). With concurrent requests on Eio fibers, a global is wrong. A handler installed per render gives each render its own context.
- A per-request context (like React context): `perform (Get_context key)` handled at the root.
- Do not expose this. Keep one internal interface, `Runtime.current : unit -> ctx`, with a Melange implementation (a global, safe since JS is single-threaded and render is synchronous) and a native implementation (effect handler or explicit passing).

### Effects as ppx

I could not read the tweet, so I do not know what the original idea was. A ppx can do these without runtime support: generate the `name` from the source location, generate the deps list by capturing free variables, or desugar `let%effect` into the `Effect.make` record. The first two address "why did this run" and "missing dependency" at compile time. Treat as an option to evaluate once the tweet content is recovered.

## Tensions

- Direct style (`perform`) is the nicest to write but does not exist on Melange. The notes ask for "universal code from the start". So direct-style handlers cannot be the portable core.
- Data descriptions answer "why it ran" best but make sequencing awkward (callbacks or binds). Direct style makes sequencing trivial but hides causes.
- Tracked reads remove the deps list but need runtime cost per run and make the dependency set dynamic. A deps list with `~equal` is explicit and cheap but easy to get wrong. The notes want to "remove the rules of hooks"; a deps list is one of those rules.
- Elm's runtime-owned effects fit a global model. This library has local state per component, so each component would need its own mini `update`, which pulls toward a component-local Elm architecture. That conflicts with "components are functions with local state".
- Redux #1528: effects that compose without wrapping need continuations, but continuations are hard to test. The same trade-off returns with OCaml 5 handlers.
- Melange value identity (`===`) vs OCaml structural equality: dependency comparison behaves differently across targets unless `~equal` is explicit.
- Server rendering ignores effects; effect types that return values to render (like `use_resource`) cannot be ignored. See type-safety.md for the Suspense angle.

## Open questions

- What did the "Effects as ppx" tweet propose? (Needs the user or another source.)
- Is the target model render-based (React-like, effects after commit) or signal-based (Lwd, derivable)? Effect design follows from this.
- Required `~equal` or tracked reads? Can both exist, with tracked reads as the default and `~equal` for opt-out?
- Should commands (Elm `Cmd`) exist as a separate concept, or is every one-shot just an effect with a cleanup?
- Does the user want effects on the server (for example data loading before render)? That is the one case where effects must run on native.
- Check Melange's current status directly (changelog or the maintainers) and decide whether to track a future effects port or a CPS-based approach.
- Does Eio's switch model map to a single-threaded JS runtime, or is a plain `Scope` enough?
