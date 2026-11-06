# Reactivity and incremental computation as a state model

Scope: signals vs vdom re-render vs incremental graphs, for an OCaml view library (Melange to JS, native for SSR).

Convention: claims marked (src) come from a page I read in this session. Claims marked (bg) come from my background knowledge and were not checked against a source here. Verify (bg) claims before relying on them.

## Sources

| Source | Status |
|---|---|
| https://romgrk.com/posts/reactivity-is-easy | read. It is about selector stores in React (`useSelector`), not signals. The signals post is announced as "future". |
| https://github.com/janestreet/incremental | read, but the README is only an intro. Details are in `src/incremental_intf.ml`, which I did not read. |
| https://blog.janestreet.com/introducing-incremental/ | read. It does not cover cutoff, heights, bind cost or memory. |
| https://github.com/janestreet/bonsai | read, but the README is thin. It does not explain `Bonsai.t`, `Effect`, or how state is scoped without hook order. |
| https://github.com/let-def/lwd | read (README only). Nottui and tyxml-lwd are only mentioned. I did not read their code. |
| https://mobx.js.org/the-gist-of-mobx.html | read. Disposal is not covered there. |
| https://www.npmjs.com/package/derivable | failed (HTTP 403). I used the GitHub README https://github.com/ds300/derivablejs instead (read). Its lifecycle and equality details were not on the page. |
| https://vanjs.org (about page) | read, but it says little. |
| https://vanjs.org/advanced (GC section) | read. |
| https://github.com/tc39/proposal-signals | read. |
| https://github.com/dbuenzli/note | read (README only). Brr integration is only mentioned. The README says nothing on steps, logger or effects. |
| https://docs.solidjs.com/concepts/intro-to-reactivity | read. It says nothing on owners, cleanup or SSR. |
| https://docs.solidjs.com/reference/secondary-primitives/create-root | failed (HTTP 404). |

Gaps: Solid ownership and SSR, Incremental cutoff and heights, Bonsai internals, Note steps and effects, Nottui and tyxml-lwd code. Items on these gaps are (bg).

## Key ideas

- Selector stores are the cheapest step away from re-render-everything. A store holds state and a set of listeners. Each reader subscribes with a selector, keeps the selected value, and re-renders only if it changes. The store, not the state, goes in context, so the root does not re-render. (romgrk)
- React concurrent mode can tear external stores. React added `useSyncExternalStore` for this. (romgrk) Any library that owns its scheduler avoids this problem.
- Incremental: inputs are `Var`s. `map`/`map2` build a static DAG. `bind` builds nodes at run time, so the dependency shape changes. `observe` marks which nodes are needed. Changes do not propagate until `stabilize`. (Jane Street blog)
- Incremental node cost is about 30 ns per fired node. It pays off when node work is large, or the graph is large and little of it changes. (Jane Street blog)
- Incremental folds with an inverse (`unordered_array_fold`) give O(1) or O(log n) updates for sums and merges. (Jane Street blog)
- Bonsai: components are "purely functional state machines". Every value is incremental, not only the view. State is not tied to tree position, so there is no hook order. The mechanism is not in the README. `component` takes a `graph` argument annotated `@ local`. (Bonsai README)
- Bonsai's `@ local` graph argument suggests a build-time builder that cannot escape its scope. This is my reading of the README, not a stated mechanism. (bg for the mechanism)
- Lwd: `var`/`set`/`peek`, `get` to enter the graph, `map`, `map2`, `join`. `join` (the monad) "should generally be avoided". Dependencies are explicit. (Lwd README)
- Lwd roots: `observe`, `sample`, `release`. A root is released, sampled or damaged. A changed input calls `on_invalidate` and marks the root damaged. Forgetting `release` leaks the graph. Invalidation has no diffing: the whole dependent branch is recomputed. (Lwd README)
- Lwd is positioned as a replacement for the DOM layer, not a layer on top. `tyxml-lwd` (js_of_ocaml) updates the DOM from Lwd. (Lwd README)
- MobX: observables, lazy `computed`, reactions (`autorun`, `reaction`, `when`), `action` as a transaction. Tracking is implicit: any observable read inside a tracked function is a dependency. Derivations are atomic, so no intermediate values are seen. Updates are synchronous. (MobX)
- DerivableJS: `atom`, `derive`, reactors with a `when` option, and `transact`. `.get()`/`.set()` are explicit. A reactor runs only while its `when` is truthy. (derivablejs README)
- TC39 signals: `State`, `Computed`, `Watcher`. Equality is a per-node `equals`, default `Object.is`. Computeds are lazy and pulled, so there are no glitches. Watchers push only a "dirty" notice, and `notify` cannot read or write signals. There is no built-in `effect`: scheduling is left to frameworks. Errors are cached and rethrown. Unwatched computeds are garbage collected. (TC39 proposal)
- Solid: a signal is tracked only if read inside a tracking scope (an effect, or JSX). Reads in component setup are untracked. (Solid docs)
- VanJS: a state holds references to every DOM node bound to it. This leaks when nodes are replaced. VanJS removes bindings whose node has `isConnected = false`. It does this periodically and before re-render. A `derive` created inside a binding dies with that binding's DOM node. (VanJS advanced)
- Note: push/pull, no weak references. Output lifetime is managed by the user, which the author says is needed in browsers anyway. Re-observing a stopped signal is forbidden. `value` is safe to call because it pulls. Depth-first DAG traversal visits every node that might be affected. (Note README)
- Lesson from Lwd, Note and VanJS together: on JS there are no weak references that give prompt cleanup. Ownership scopes must be explicit or tied to the DOM.

## What this means for the library

### Where the models differ

| | vdom re-render (React, Elm) | signals (Solid, MobX, TC39) | incremental graph (Incremental, Bonsai, Lwd) |
|---|---|---|---|
| Unit of recompute | a component or whole view | a binding or an effect | a graph node |
| Dependency discovery | the programmer (hook deps) or none | implicit, at read time | explicit combinators (`map`, `bind`) |
| Order rules | hook order | tracking scope rules | none; the graph is a value |
| Output | a vdom tree, then diff | direct DOM writes | a value, or a DOM patch, per node |
| Dynamic structure | free (any `if`) | free, but tracking scope matters | needs `bind`/`join` or keyed combinators, which cost more |
| Cost per update | diff size | few DOM writes | few DOM writes, plus graph overhead |
| Native SSR | trivial | needs a no-tracking mode | needs a one-shot sample, then release |

Push vs pull:
- Pure push (Note, Lwd invalidation) is simple. Without heights it can run a node twice, which is a glitch.
- Pure pull (TC39 computed) is glitch-free by construction. It needs a push "dirty" notice to know when to pull.
- Push-dirty, then pull-on-demand, is the common modern answer (TC39, MobX, Solid per my memory (bg)). Incremental sorts by node height and uses `stabilize` (bg for the height detail).
- Glitch freedom matters for effects. A derived value must never be seen half-updated. Rule: run effects only after the graph has settled. This is `stabilize`, MobX `action`, and `transact`.

### Option A: vdom plus a state store, no tracking

Keep React's re-render model. Remove hook order by creating state in a setup phase.

```ocaml
(* setup runs once at mount; render runs on every update *)
type ('props, 'view) component = {
  setup : 'props Signal.t -> ('props -> 'view);
}
let counter = {
  setup = fun _props ->
    let count = State.make 0 in
    fun _props -> button ~on_click:(fun _ -> State.update count succ) [ text (string_of_int (State.get count)) ]
}
```

- `State.get` records the current component as a subscriber in a global slot (the "current renderer"). This is the romgrk selector idea, with automatic selectors.
- The setup closure replaces hook order: state sits in closure slots, so there is no position-based identity. This is the same shape as Elm-like `init`/`view` and Brisk-style reconcilers (bg).
- Cost: it still diffs. It is the least surprising for React users.
- Native: `render` runs once. `State.get` needs no subscription. Cheap.

### Option B: signals with ownership scopes (Solid-like)

```ocaml
module State : sig
  type 'a t
  val make : ?equal:('a -> 'a -> bool) -> 'a -> 'a t * ('a -> unit)
  val get : 'a t -> 'a                  (* tracked inside a Scope *)
  val peek : 'a t -> 'a                 (* untracked *)
end
module Derived : sig
  val make : ?equal:('a -> 'a -> bool) -> (unit -> 'a) -> 'a State.t
end
module Effect : sig
  (* auto-tracked: reruns when any State.get inside changes *)
  val sync : ?equal:('a -> 'a -> bool) -> (unit -> 'a) -> ('a -> (unit -> unit)) -> unit
  (* explicit: the deps are values, so there is no stale closure *)
  val on : ?equal:('a -> 'a -> bool) -> 'a State.t -> (prev:'a -> next:'a -> (unit -> unit)) -> unit
end
```

- This maps the notes directly. `State.make` returns `(a, set_a)`, `State.get a` reads, `Effect.on a (fun ~prev ~next -> ...)` is the second sketch. `Effect.sync` is the third. The `~equal` is the cutoff on the node.
- Dependency tracking: a global "current observer" ref. It is safe on Melange (single thread). On native, use one per domain (`Domain.DLS`), or avoid the global with a context argument.
- Alternative tracking with OCaml 5 effects: `State.get` performs an effect and the scope handler records the read. It is clean and needs no global. I do not know if Melange supports it; see Open questions.
- Ownership: every component and every effect runs inside an owner `Scope`. Disposing a scope disposes children and runs effect cleanups. A `derive` made inside a scope dies with it. This is VanJS's rule, but explicit and not based on `isConnected`.
- Effect returns its cleanup. This replaces React's `useEffect` return value and gives "why this effect runs": the dependency is named in the code.
- Dynamic lists: need a keyed combinator `Each.keyed ~key list (fun item_signal -> node)` so each row keeps its own scope. This also answers the notes' "key args" question: the key is a required labelled argument of the one list combinator, not a convention.

### Option C: explicit graph (Lwd / Incremental / Bonsai-like)

```ocaml
module Graph : sig
  type 'a t
  val var : 'a -> 'a t * ('a -> unit)
  val map : 'a t -> f:('a -> 'b) -> 'b t
  val map2 : 'a t -> 'b t -> f:('a -> 'b -> 'c) -> 'c t
  val switch : 'a t -> ('a -> 'b t) -> 'b t    (* bind/join: use sparingly *)
  val cutoff : equal:('a -> 'a -> bool) -> 'a t -> 'a t
end
(* with let+ and and+ *)
let view =
  let+ n = count and+ name = name in
  div [ text name; text (string_of_int n) ]
```

- No tracking magic and no hook order. The graph is a plain OCaml value, which fits the type-safety goal in the notes.
- State inside a component is a graph node created while building the graph. Bonsai does this (bg for the details); its README says state is not tied to tree position.
- `let+`/`and+` is standard OCaml, so no ppx is needed. This matches "remove need for compiler".
- Cost: every use of the current value needs `let+`. Conditionals need `switch`, which is the costly `bind`. Lwd itself says to avoid `join`. Syntax noise is the main trade-off.
- Output: either a vdom per node (then diff) or direct DOM patches (tyxml-lwd style).

### Recommended starting point

Option B for the runtime, with two properties of option C:
- explicit `~equal` on nodes (all sources have it: TC39 `equals`, Incremental cutoff);
- `Effect.on` with named dependencies as the default effect, and `Effect.sync` as the escape hatch.

Reason: B has the fewest rules for authors, matches the notes' `State`/`Effect` sketch, and has simple SSR. C is stricter and more type-safe but costs ergonomics. Option A is the fallback if direct DOM writes are too far from the other notes.

### Equality

- Put `~equal` on `State.make`, `Derived.make` and `Effect.*`. Default to physical equality `==`: it is cheap and never loops. TC39 uses `Object.is`, the same idea. (TC39)
- On Melange, `==` on OCaml values does not always mean what it means natively, because Melange's value representation (options, variants, records, int64) differs from native. Load the `melange-advanced` skill before fixing the default. (bg)
- Structural `=` on cyclic or function-containing values can raise or loop. Do not make it the default.

### SSR on native

- No DOM and one render. Skip subscription entirely: in server mode `State.make` returns a plain cell, `get` is a read, `Derived` evaluates once, and `Effect` bodies do not run.
- This needs a mode flag in the root. A type-level split is more honest but heavier. With option C, `observe`, one `sample`, `release` is the exact Lwd root life cycle (Lwd README), and works as is.
- Hydration on the client: re-run `setup` against existing DOM. Initial state must be serialized by the server. This is outside this note.

### Melange vs native

- JS: no weak references for prompt cleanup, so ownership scopes are required (Note, VanJS evidence). A global "current observer" is safe.
- Native: multiple domains or threads need per-request graphs. Avoid any global mutable graph state in the server path, or each request leaks into the next.
- Both: keep the reactive core free of DOM types, so one core compiles to both targets.

## Tensions

- Elm: a single model and a pure `view` call for re-running `view` on each message. A graph or signal runtime wants local state and fine-grained updates. Compromise: one root `Signal` holding the Elm model, with `Derived`/selectors per component slice. The romgrk store and `reselect` pattern is the same idea. Memoization in Elm (`lazy`) becomes a `Derived` with `~equal`.
- Elm: effects as data (`Cmd`) vs effects as running code. `Effect.on` runs code. A `Cmd`-like value would need a separate layer. Leave to the types-effects note.
- React: components re-run on every update, so locals are cheap. In option B or C a component function runs once, and ordinary `let x = State.get a` in the body goes stale. This is the biggest user trap. The Solid docs warn about it (reads outside a tracking scope are not tracked). The type system can help in option C: a plain `'a` cannot be used where `'a t` is required. In B it cannot.
- Hook rules: B and C remove hook order, but B adds "reads only count in a scope". That is a new rule to teach.
- Notes ask for "relate effects and renders" and "why this effect runs". Explicit `Effect.on` answers both. Auto-tracked `Effect.sync` hides the answer.
- Notes ask for type-safe children and attributes. These fit all three options, but option C lets a node's type carry the view kind.
- Async and Suspense ideas in the notes (`useDeferredValue`, `useOptimistic`) have no obvious home in B or C. Both need a scheduler. Incremental's explicit `stabilize` is a clean place to batch; Solid-like auto-flush is not.
- Incremental's per-node overhead of about 30 ns is small, but a node per DOM attribute across a large list is a lot of nodes. Granularity needs a measured choice.

## Open questions

- Does the library accept implicit tracking (B), or require explicit combinators (C)? This decides ergonomics and the SSR story.
- Does Melange support OCaml 5 effects for tracking? If not, global current-observer is the only option on JS.
- Who flushes: synchronous after each `set`, a microtask batch, or an explicit `stabilize`? MobX and derivable batch in a `transact`; TC39 leaves it to the framework.
- Is the root a single Elm-style model, local state per component, or both?
- Do effects run in server mode never, or only an opt-in subset (for example, data loading)?
- Keyed list combinator: what is the minimal API so each row has its own scope and signal?
- What is the default `~equal`, and is it safe on Melange for options and variants? Needs a test on compiled output.
- Should dynamic structure (`switch`) be allowed freely? Lwd advises against `join`; Incremental allows `bind` at a cost I did not confirm from a source.
- To read before deciding: `incremental_intf.ml`, Bonsai guide (state scoping), Note's `note.brr` TodoMVC, tyxml-lwd source, Solid owner and SSR docs.
