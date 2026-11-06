# Elm-likes: Cycle.js, re-frame, Hyperapp

Marks: "(src)" = from a source I read. "(mine)" = my own knowledge, not checked in this session.

## Sources

- https://cycle.js.org/components.html : failed. The fetch returned only the site header and navigation, no body (the page is rendered by script). Read the same text from the project's docs source instead: https://raw.githubusercontent.com/cyclejs/cyclejs/master/docs/content/documentation/components.md : read. I assume it matches the site page but did not compare them.
- https://day8.github.io/re-frame/application-state : read. It covers `app-db` and the single store only. It says nothing on subscriptions, handlers, effects, or local component state.
- https://day8.github.io/re-frame/subscriptions/ : read (extra source, to fill the gap).
- https://day8.github.io/re-frame/Effects/ : read (extra source, to fill the gap).
- https://github.com/jorgebucaran/hyperapp : read (README only). It says nothing on local state, components, or effects as data.
- Not fetched: re-frame's page on local state and Reagent form-2 components, Cycle's `@cycle/state` (onionify) docs. Points about them are (mine).

## Key ideas

Cycle.js
- A component is a function `sources -> sinks`. The whole app is also one, so any app can be a component in a larger app. (src)
- Example `LabeledSlider`: sources `DOM` and `props` (a stream); sinks `DOM` (vdom stream) and `value` (a stream). (src)
- Parent composes by passing a subset of its own sources plus child-specific streams, then reading the child's sinks as ordinary streams. (src)
- State is a stream inside the component: events mapped to values, seeded with `startWith(props)`, shared with `remember()`. No mutable variables. (src)
- Problem: two instances of one component both select `.slider` in the shared DOM source, so moving one moves both. Rule: a component's sources must not be affected by other components' sources, and its sinks must not affect other sinks. (src)
- `isolate(Component, scope)` fixes this by scoping the DOM source and tagging the sink. With no explicit scope it generates a unique one on each call, so it is not referentially transparent. Explicit scope string = pure. (src)
- A shared store across components, with each component seeing a slice (lenses), is `@cycle/state`. (mine, unverified)

re-frame
- All state is in one place, `app-db`: a Reagent atom holding a map. Think of it as an in-memory database. (src)
- One source of truth means no code to sync state between components. One `reset!` acts "like a transactional commit". (src)
- A schema can validate all application data after every event handler. Other benefits listed: undo/redo through snapshots, time-travel debugging. (src)
- Subscriptions are derived data from `app-db`. The Signal Graph is a DAG: `app-db` (layer 1) -> extractors (layer 2, read `app-db` directly) -> materialised views (layer 3, read other subscriptions) -> view functions (layer 4, produce hiccup). Each node is a pure function. (src)
- The graph is built backward from what views ask for, and nodes are destroyed when no view needs them. (src)
- Propagation pruning: when a node's inputs change its function re-runs. If the new output equals the old (Clojure `=`), nothing flows downstream. Layer-2 extractors act as "circuit breakers". (src)
- `reg-event-fx` handlers return an effects map: a description of the effects, not the effects. Since v1.1.0 best practice is to return only `:db` and `:fx` (ordered list of effects). `:db` runs first. (src)
- A `do-fx` interceptor, inserted at the front of the chain, runs the effects after the handler, by calling handlers registered with `reg-fx`. Effects can be stubbed with a no-op handler in tests or replay. (src)
- Local component state in Reagent (atoms inside form-2 components) coexists with `app-db`. The docs I read do not discuss it. (mine, unverified)

Hyperapp
- Single global state. Actions are functions that return a new state. Views are plain functions that use `h()` and `text()`. About 1 kB. (src)
- Effects and subscriptions come from packages (`@hyperapp/http`, `@hyperapp/time`, `@hyperapp/events`). The README shows no effects-as-data detail. (src)
- Hyperapp 2 effects are `[fn, props]` pairs returned alongside state, and subscriptions are functions of state returning such pairs. (mine, unverified)
- No local state or component story in the README. The idiom is views as functions of global state. (src, by absence)

## What this means for the library

The common problem: one store, but components that are reusable and isolated. Each system answers differently.

| System | Store | Component isolation |
|---|---|---|
| Cycle | none global; streams | `isolate` scopes sources and sinks by name |
| re-frame | one `app-db` | none needed; components read subscriptions by id |
| Hyperapp | one state | none; views are functions |
| Elm | one model | none; flat or nested `update` |

Options for OCaml:

1. Slice by lens (Cycle state, Elm nested update, done once).
   - A component gets a typed lens into the parent state. The runtime applies it, so the parent writes no wiring.
   ```ocaml
   type ('whole, 'part) lens = { get : 'whole -> 'part; set : 'part -> 'whole -> 'whole }
   val Component.scope : ('w, 'p) lens -> ('p, 'msg) component -> ('w, 'msg) component
   ```
   Isolation falls out of the type: the child cannot see more than its slice. Cost: a lens per child, and `set` always builds a new parent record. That defeats lazy at the parent (see `elm.md`, roots-lazy note).

2. Derived reads, re-frame style, for fine-grained caching.
   - View reads through named selectors. A selector re-runs when its input changes and stops propagation when its output is `equal`.
   ```ocaml
   val Selector.make : ('s -> 'a) -> equal:('a -> 'a -> bool) -> 'a Selector.t
   val Selector.map  : 'a Selector.t -> ('a -> 'b) -> equal:('b -> 'b -> bool) -> 'b Selector.t
   ```
   This gives memoised derived data without a per-view `lazy` call. It is the same idea as Elm lazy but at the data layer, and as the notes' `lwd` and `derivable`.

3. Effects as data, re-frame style.
   ```ocaml
   type 'msg effect =
     | Dispatch of 'msg
     | Http of { url : string; on_done : (string, error) result -> 'msg }
     | Custom of { id : string; run : unit -> unit }   (* registered handler by id *)
   type 'msg update_result = { state : 'state; fx : 'msg effect list }
   ```
   Runtime runs `fx` in order after committing state. Tests compare the list instead of running it. Replay replaces the runtime with a no-op, as re-frame does with a no-op `reg-fx`. A closed variant gives exhaustiveness; an open string id (re-frame) gives extensibility. Pick closed variant plus one `Custom` escape.

4. Local state as a slice at a path.
   - Keep one store (re-frame, Elm) but give each component instance a typed slot keyed by its position or key. The component reads and writes only its slot. The store can be dumped (time travel, SSR hydration) and each component looks local.
   ```ocaml
   val Local.use : key:'k Key.t -> init:'a -> 'a Slot.t   (* typed key, not call order *)
   ```
   Typed keys instead of call order remove the rules of hooks. A GADT key table in the runtime keeps types honest. Cost: users must create keys, or a ppx generates them per definition site.

5. Cycle-style props as input and sinks as output.
   - A component function takes `props` plus a `'msg -> unit` for events upward, and returns the node. This is the React model with explicit "sinks": the only way out is what the component emits. Use it for public component boundaries.

Recommended combination to test first: option 4 (one dumpable store, typed local slots) + option 2 (selectors with `equal`, default `==`) + option 3 (effects as a variant). It keeps Elm's pure view and effects-as-data, and gives React-like local state without nested update code.

## Tensions

- Cycle isolation exists because shared DOM selection leaks between instances. In a vdom library with owned instances this problem mostly disappears, but the same issue returns for any shared name space: CSS classes, element ids, effect ids, store keys.
- Cycle's implicit `isolate` scope is non-deterministic per call. Any "automatic key" scheme (ppx-generated, position-based) has the same risk: hot reload, SSR vs. client, and conditional rendering can shift keys and attach state to the wrong instance.
- re-frame's single store gives undo, replay, validation. Local state stored outside it loses all three. Local slots inside the store keep them, but then components depend on the store's shape.
- Selectors (re-frame) and `lazy` (Elm) are two answers to the same problem. They compose badly: lazy compares inputs by `==`, selectors by `equal`. Pick one primary mechanism.
- Effects as data needs a closed vocabulary or registered handlers. Components that ship their own effects need open registration, which re-frame has and a closed variant lacks.
- Streams (Cycle) vs. `update` functions (Elm, re-frame, Hyperapp): streams compose well but make the "why does this run" question harder, which the notes want answered.
- Hyperapp shows the floor: no local state, no components, 1 kB. It is a data point that a single global state is enough for many apps, and does not show how large apps scale.

## Open questions

- Single store with typed slots (option 4), or per-instance state owned by the runtime tree? Which is easier to dump for SSR hydration?
- Who creates local keys: the user, a ppx, or the runtime by position? What happens to the state when the position moves?
- Selectors with `equal`, or `lazy` by `==`, or both? Does the library need either if rendering is fine-grained?
- Closed effect variant or registered handlers by id?
- Is the `component` boundary (option 5) public API, with the store an app-level choice, or the other way round?
- I could not read how re-frame treats local state, or Cycle's `@cycle/state`. A follow-up fetch of those two would settle the table above.
