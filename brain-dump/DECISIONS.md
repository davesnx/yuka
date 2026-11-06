# Decisions

## Terms

- **element**: what a JSX expression makes. Type `'kind Yuka.element`.
  The module structure is flat: no `Element` module, no `El`.
- **server element**: `Yuka.server Yuka.element`. No handlers, no dynamic
  values. A page is a server element.
- **client element**: `Yuka.client Yuka.element`. Can have handlers and
  dynamic values. The body of a client component is a client element.
- **island**: what `<Yuka.Client>` makes: a server element that holds one
  client component.
- **hole**: a part of an element that can change after the first render.
  `Yuka.hole (fun () -> ...)`, made by the ppx, never written by the user.
  Yuka calls it once, records the States it reads, and calls it again when
  one of them changes. A hole makes a client element.
- **slot**: a server element passed as `children` into a client component.
  Rendered on the server and adopted on the client. `Yuka.slot` (inserted by
  the ppx only) puts it in the client body.

## Agreed

- ~~An effect that runs after every render is named `Effect.always`.~~
  Withdrawn (2026-11-04): the tree renders once, so "every render" has no meaning.

## Direction set by the user (2026-11-04)

- ~~State: `let count, set_count = State.of 0`; `count` is the getter.~~
  Reversed (2026-11-06): see the 2026-11-06 section.
- Views take functions for dynamic parts; users write `fun () ->` themselves.
- `State.memo (fun () -> ...)` caches a derived value.
- Default equality: open.

- A fixed graph, as in Bonsai: state identity is its place in the graph.
- ~~Props are boxed (`'a Value.t`), so a change is visible.~~ Reversed
  (2026-11-04): props are not boxed and are always the latest value. State is
  boxed. Open: what happens to a child when a plain prop changes.
- Local state.
- Effects compare prev/next with an equality to decide whether to run.
- Loading, Suspense-like grouping and optimistic updates work at the function
  level, not at the component level.
- A parent can cancel effects.
- No `let*` / `let+` in user code, and no `graph` argument passed around.
- Under discussion: the server sends the graph to the client in the HTML.
- Three concepts: `State`, `Effect`, `Async`.
  - `State`: local state. `State.of` takes a value, `State.make` takes a
    function (names open). Every state is serialisable and has an equality;
    both constructors take labelled arguments for serialise, deserialise and
    equal. The return shape (value, value + setter, getter + setter) is open.
  - `Effect`: fires on a state change, or when a component first renders.
  - `Async`: remote data; works with `State` and `Effect`.
- The tree renders once, mainly on the server. The client resumes the
  server's work asynchronously, or receives it as a stream.
- Suspense and loading states have two forms: components, and imperative APIs.
- User proposal for the return shape: `let (state, set, get) = State.of 4 in`.
  `state` is the box (for views, effects, children); `set` writes; `get`
  reads the current value inside closures such as handlers.
- ~~Revised by the user: the state is the getter itself (`count ()`), so a box
  received as a prop can be read. With that, the shape is `(count, set)`.
  Checked on native and Melange: an effect finds the states a getter reads by
  calling it once while tracking. Derived values and constants are plain
  functions.~~ Reversed (2026-11-06).
- No `Value` module. Read-only and derived values are expressed with `State`.
- `State.make` takes the value (was `State.of`); serialise, deserialise and equal are labelled
  arguments, not a positional type description.
- Views are written in mlx (JSX for OCaml). Components are mlx components.
- `Effect.always` has no meaning if the tree renders once. Yuka still needs
  wrappers for browser APIs such as `setInterval` and `setTimeout`. Under
  discussion: `Effect.interval`, `Effect.timeout`, on a generic mount primitive.

## Direction set by the user (2026-11-05)

- Yuka has a ppx: it is needed for JSX. The hand-written `fun () ->` may be
  removed later by the ppx or by other design; not decided.
- Take from melact (see `melact.md`):
  - The DOM layer: templates with holes, keyed list reconcile with fewest
    moves, hydration that adopts server nodes, events delegated to `document`.
  - A typed key per call site, given by the ppx. Candidate use: node identity
    on resume, with the component's position in the tree.
  - Not taken: change detection by the compiler's free-variable reads (it
    cannot see getters), physical equality as the only change test, the
    React hook surface.
- Tests run on native and Melange, to keep the two targets compatible. The
  pattern: one library of test cases, run by Alcotest on native and by
  melange-testing-library on Melange.
- Islands (decided 2026-11-05). The page is server HTML. Client code runs only
  in islands. An island takes its props from the server (a prop can be async)
  and mounts on the server's holes. This narrows "the client resumes the
  server's work" (2026-11-04) to the islands.
- Two marks for client code (decided 2026-11-05), each with its own role:
  - `<Yuka.Client>` at the call site: says explicitly that a client slot is
    made here.
  - `let%client` on the definition: checks that the props have a codec for
    the client, plus other checks.
  See `client-boundary.md`.
- `<Yuka.Client>` takes a `loading` prop. Its values: open.
- The server streams to the client as RSC does in server-reason-react.
- Each client component defines a contract for its props with the server. The
  server encodes the values at the outermost `<Yuka.Client>` boundary. A
  client nested inside another client gets plain client values, with no
  encode or decode.
- An async prop on the boundary is an `Async.t` value.
- A `<Yuka.Client>` inside client code has no meaning: once inside the
  boundary, the code is already on the client. It is a type error
  (decided 2026-11-05): `<Yuka.Client>` returns `Yuka.server Yuka.element`, a client body
  is `Yuka.client Yuka.element`. A `<Yuka.Client>` in a server-rendered slot stays valid.
- Each `<Yuka.Client>` gets its own payload. Ids inside it carry the island's
  prefix, so ids in different islands do not collide.
- An `Async.t` can start on the server, as an RSC promise does. The server
  writes an RSC payload into the HTML; the client finds each async value by
  its id.
- Cancel on navigation: yes, through a `yuka.router`, built later.
- Lowercase tags (decided 2026-11-05): the ppx turns `<div ...>` into
  `Yuka.lower "div" attributes children`. As in html_of_jsx's ppx, it accepts
  only valid DOM attributes for that tag, plus `data-*`. Attributes carry the
  element kind: `'kind Yuka.attribute`; an event handler or a dynamic value is
  a `Yuka.client Yuka.attribute`. Checked in the scratch project
  (`client-boundary.md`).
- html_of_jsx's ppx is the baseline only. Yuka adds a lot on top: the kind
  on attributes, a typed event per handler attribute (types defined on native
  too), property vs attribute on the client (`value`, `checked`, `selected`),
  and one static analysis that emits both the server string and the client
  template with holes.
- Take React 19 tests as a reference (decided 2026-11-05): port the behaviour
  cases from React 19's own test files (effect order, cleanup, keyed reorder,
  hydration mismatch, Suspense) as Yuka test cases. For each case, Yuka
  keeps, changes or rejects React's behaviour on purpose, and records which.
  Not taken: one suite run against both reason-react and Yuka.

## Direction set by the user (2026-11-06)

- State is an abstract value: `let count = Yuka.State.make 0`. Read with
  `Yuka.State.get count`, write with `Yuka.State.set count v`. Reason: JSX
  and component code then use Yuka's own API explicitly. This replaces the
  getter `count ()` and the `(count, set)` shape.
- `State.of` cannot exist: `of` is an OCaml keyword (`State.of 0` gives
  "Syntax error", checked with ocamlc 5.2.0).
- Consequences (checked in the scratch project, `client-boundary.md`): the
  `?state:tag` trick is gone; a closure passed where a State is expected is a
  plain type error ("This expression should not be a function, the expected
  type is int Yuka.State.t").
- `Yuka.State.update count (fun c -> c + 1)` (decided 2026-11-06). Checked
  in the scratch project.
- `State.memo` returns a `'a State.t`, read with `State.get` (decided
  2026-11-06). Consequence: `State.set` on a memo must be prevented, so a
  read-only State is now needed (open: phantom permission type or a separate
  type).
- The ppx has a lint phase that bans `open Yuka.State` (decided 2026-11-06),
  so a read is always written `State.get` and the ppx can mark holes from the
  syntax. Open: also ban local opens (`Yuka.State.(get c)`), module aliases
  (`module S = Yuka.State`) and value aliases (`let g = Yuka.State.get`);
  reads hidden inside another function are still not seen.
- Open: a second constructor (a State from a function, for a lazy initial
  value); a derived value now uses `State.memo`.

- Effect base (decided 2026-11-06): copy reativa's core (signals, scheduler,
  effect; MIT, keep its licence notice) and adapt it to Yuka's design. See
  `reativa.md`. Adaptations known so far: owner tree (parent dispose and
  cancel), `Effect.on_change ~prev ~next`, error isolation, no-op on native,
  `State` names (`make`, `get`, `set`, `update`, `peek`), read-only memo.
- `Effect.run` takes the cleanup as a labelled argument `~cleanup`, not as a
  return value and not as `Effect.cleanup` inside the body (decided
  2026-11-06). Type (decided 2026-11-06): `?cleanup:('r -> unit) ->
  (unit -> 'r) -> unit`: the body returns its resource (a timer id) and the
  cleanup receives it (checked on native: `clear 1`, `clear 2`). Known weak
  point: without `~cleanup`, a body result is ignored silently.
- `Yuka.mount` is the top level (decided 2026-11-06): it creates the root
  owner and returns a function that disposes everything under it. Today it
  takes a function; it will take the DOM target when the DOM layer exists.
- Code layout (decided 2026-11-06): `dune-project` at the yuka root, library
  in `src/` (modes native melange), shared test cases in `test/cases/`, run
  by Alcotest in `test/native/` and on Melange in `test/melange/`.

## Direction set by the user (2026-11-06, build)

- The user gave the design to the agent: "research the best way to implement
  Yuka entirely". Goal: a mini Linear demo, built while Yuka is built:
  server, client, bundle, server actions, everything. Execution is part of
  the map. Design: `DESIGN.md`. Plan: `.workplace/plans/yuka-v0.1_PLAN.md`.
- From here, new decisions go in `DESIGN.md` (the v0.1 design) and the plan,
  not in this file.

The items below came before this direction; check each one against it.

## Proposed, not yet agreed

- Dependencies are a typed list: `Effect.on [ count; name ] (fun count name -> ...)`.
  The list type defines its own `[]` and `::`. Checked on native and Melange
  (dune 3.21.1, Melange 6.0.1). Reason syntax `[count, name]` is not checked.
- `Effect.on` passes plain values. `Effect.on_change` passes
  `Initial v | Changed { prev; next } | Same v` for each dependency.
- The previous value is kept per effect, not per cell. Reason: batched sets and
  effects created late would see the wrong `prev`.
- ~~Cleanup is registered with `Effect.cleanup (fun () -> ...)` inside the run,
  not returned from the callback.~~ Replaced (2026-11-06) by `~cleanup` on `Effect.run`.
- Default equality is structural `=`; `~equal:(==)` is the opt-in. Reason: `==`
  gives different results on native and Melange for strings and floats.

## Open

- Collections: what a list state is (plain list, `Map` with diffs, persistent
  sequence with cached measures) and whether `each` receives whole values or
  edits. See `finger-trees.md`.
- Propagation order after a `set`: in what order derived values and effects
  run (no glitches, parent before child, creation order).
  - Candidate (not tested): number each node at creation and run dirty nodes
    lowest number first, with `Set.Make (Int)` as the queue. This is a
    topological order because a node can only read nodes that already exist.
    It breaks when an old node reads a newer one (a state holding a getter).
    Choices for that case: forbid, detect and raise, or Incremental-style
    heights. The same number could identify nodes on resume, if creation is
    deterministic on server and client.
  - A finger tree does not model the dependency graph: it is a sequence, and
    dependencies form a graph.

- Client boundary (`<Yuka.Client>`): proposal in `client-boundary.md`, not
  decided except islands and the two marks. Open points: the `loading`
  values; the error type of an `Async.t` prop and its codec; the island prefix
  itself must be unique (two islands from one call site in a list need the
  position too); the codec of an `Async.t`; the extra
  checks `let%client` does; the `client`/`server` phantom type on
  elements; a State shared across islands or values only; the default start.
- Server actions: request incomplete; waiting for the user.
- Shared test cases on native have no DOM: they can check state, effects and
  server HTML strings. DOM cases (events, hydration) run only on Melange.

- Decision 1: what render does (signals, re-run and diff, or explicit graph).
  See `SYNTHESIS.md`.
