# Prior art: small and alternative view libraries

Research date: 2026-11-04. Facts come from the sources below. Where I give a number or claim I did not read in a source, I say so.

## Sources

| Source | Status |
|---|---|
| https://github.com/frejs/fre | read (cloned; README, `src/hook.ts`, `src/schedule.ts`; v2.8.9, last commit 2026-11-04). No size figure in the README (only a brotli badge). |
| Preact v10 vs v11 | read: https://preactjs.com/guide/v11/upgrade-guide/ and the GitHub releases API for preactjs/preact (11.0.0 published 2026-09-30, plus rc.0 to rc.2). Not read: the individual PRs, the open branches, the Hydration 2.0 RFC. |
| https://github.com/lpalmes/pure | read (cloned; README, folder layout, `specs/style.md`). I did not read `reconciler.re` (480 lines) in detail. Last commit 2018-12-03. |
| https://github.com/briskml/brisk-reconciler | read (cloned; Readme, `src/hooks.mli`, `src/heterogenous_list.mli`, `src/brisk_reconciler.mli`, `docs/hooks-idioms.md`, `jsx/brisk_ppx.ml` in part, `tests/components.mlx`). Last commit 2026-07-05. |
| https://github.com/jorgebucaran/superfine | read (cloned; README, `index.js` grep only). Last commit 2021-04-02. |
| https://vanjs.org | read in part: `/about` and `/tutorial` via a summarising fetch, not raw pages. No absolute size given on those pages. |
| https://x.com/_developit/status/905250269306474497 | failed: fetch returned HTTP 402; a web search did not find the tweet. Nothing is claimed about its content. |
| https://github.com/joshburgess/tachys | read (cloned; README, `ARCHITECTURE.md` head; v0.1.2, last commit 2026-05-02). |
| reason-react | read in part: GitHub repo page only (summarised). Little detail. |
| Revery | read in part: GitHub README only (summarised). Little detail. |

## Libraries

### brisk-reconciler (OCaml, most relevant)

- Core model: a host-agnostic reconciler. The host defines an output node type and callbacks (`insertNode`, `deleteNode`, `moveNode`, `configureInstance`). Components are "stateful functions". The reconciler walks the element tree and calls the host callbacks for each diff.
- Hooks are typed. A component body threads a hooks tape `('remaining, 'result) Hooks.t`. Each hook consumes one slot, and the type of the slot appears in `'remaining`. For example:
  ```ocaml
  val state :
    'value -> ('value State.t -> 'c, 'd) t
    -> ('value * (('value -> 'value) -> unit)) * ('c, 'd) t
  ```
  Under the hood the tape is a GADT heterogeneous list (`heterogenous_list.mli`: `[] : nil t` and `(::) : 'a valueContainer * 'l t -> ('a -> 'l) t`). A PPX (`let%hook`, `let%component`, `let%nativeComponent`) hides the threading. A lint in the PPX checks that `let%hook` is used correctly.
- Hook set is small: `state` (setter takes an updater function), `reducer`, `ref`, `use_effect`, `use_latest`. Slots are matched by order, and the docs still say "no conditional hooks". So the rule of hooks remains. The typing only encodes the tape in the types. It does not remove the rule. (My reading: a branch that runs different hooks would have different tape types, so mostly it fails to compile. I did not test that.)
- Effects use a closed variant for the condition, not a deps array:
  ```ocaml
  type 'a condition =
    | Always : always condition
    | OnMount : onMount condition
    | If : ('a -> 'a -> bool) * 'a -> 'a condition
    | OnMountAndIf : ('a -> 'a -> bool) * 'a -> 'a condition
  type handler = unit -> (unit -> unit) option   (* returns cleanup *)
  ```
  The dependency has any type and the comparator is user supplied. This answers the `~equal` question in the notes. Pitfall: `If`'s comparator means "changed when true", so callers pass `(<>)`. The docs call this out as unintuitive.
- Keys: abstract `Key.t`, minted with `Key.create ()`, `Key.none` for positional matching. Keys are not required. A list with different lengths is matched only by key. Keyed matching is not enforced by types.
- Driving the tree: `add_stale_tree_handler` tells the host a setter ran. The host then calls `flush_pending_updates`, `execute_host_view_updates`, `execute_pending_effects`. Rendering, view updates and effects are three separate steps, run by the host.
- Size: `src/` is about 2,500 lines of OCaml. The reconciler core is 1,372 lines.
- Unique: a typed hook tape, an OCaml-native host interface, and no VDOM tied to the DOM. State setters are stable and queue updates in the instance. The tape is flushed in one pass, and unchanged state returns the same physical value, so "any change?" is a `!=` check.
- Steal: the host callback interface (one reconciler for DOM, native and server), the effect condition variant, `use_latest`, the stale-handler plus explicit flush loop (good for server rendering and testing).
- Avoid: ordering rules that rely on a PPX, `Always`/`OnMount` names that copy React, the reversed `If` comparator, GADT error messages leaking to users, and `ref`-based escape hatches as the main way to read the previous value.

### reason-react and Revery

- reason-react: components are a `let make` function with a `[@react.component]` PPX that turns labelled args into props. It binds to the real React. The repo page says nothing about hooks. It warns ReScript users to use `@rescript/react` instead. Value: it shows how much of React's runtime a Melange library can reuse. Cost: it inherits React's rules and its size.
- Revery: native UI in OCaml that draws its own widgets (no native widgets). Its README credits brisk-reconciler as "the native React" implementation. Hot reload is on its roadmap. I found no hooks documentation on the page. Value: evidence that brisk-reconciler can drive a non-DOM host.

### Preact (v10 and v11)

- Core model: small VDOM with React-compatible hooks. `preact/compat` adds React API parity. Core stays small.
- v11 (11.0.0 on 2026-09-30) is mostly cleanup, not a new model:
  - ESM only. Browser floor Chrome 71 and up. TypeScript 5.1 and up.
  - `ref` is a normal prop, so `forwardRef` is not needed.
  - Hook arguments compare with `Object.is`. `NaN` no longer re-renders forever.
  - Features moved from core to `compat`: automatic `px` on numeric styles, `defaultProps`. `SuspenseList` removed. `render()` third parameter and `Component.base` removed.
  - `createPortal` is in core. `use`, `useEffectEvent`, `getServerSnapshot` added in compat.
  - On unmount, passive effect cleanup runs after paint.
  - Hydration 2.0: async boundaries may render zero or many DOM nodes. Stable comment markers make streamed SSR hydrate.
  - rc.0 notes: child moves computed with a longest increasing subsequence (#5174), `moveBefore` used when present (#5161), batched `flushSync` (#5175).
  - Many diff fixes were backported to v10.
- Size: I did not read a size figure from these sources.
- Steal: moving features out of the core into an opt-in layer; the LIS move algorithm; stable markers for hydration boundaries; passing `ref` as an ordinary prop; `Object.is` style equality being explicit.
- Avoid: copying React's full API surface just for compatibility.

### Fre

- Core model: fiber-style concurrent VDOM in about 940 lines of TypeScript (`src/`: reconcile 323, commit 134, hook 147, schedule 55).
- Hooks: a global `cursor` is reset per render. Each hook reads a slot by index (`getSlot(cursor++)`). So the hook order rule is the same as React. `useState` is `useReducer` with a null reducer.
- Effects: a `deps` array and an `isChanged` check, with two phases: `effect` and `layout`.
- Scheduler: a task queue with a 5 ms time slice. It uses `MessageChannel`, `queueMicrotask`, or `setTimeout`. A job returns its next callback to continue later (a coroutine style).
- Features claimed in the README: keyed diff, Suspense, memo, ErrorBoundary, offscreen, SSR hydration.
- Steal: shows the full hook runtime is about 150 lines. A job-returns-continuation scheduler is simple and easy to port to OCaml.
- Avoid: hidden global cursor state, which breaks as soon as an effect or exception interrupts a render.

### pure (lpalmes)

- Core model: "Pure Reason", an experiment in cross-platform UI in Reason with a fiber-style reconciler (`reconciler/reconciler.re`, 480 lines). Separate packages for core, DOM, macOS (Cocoa bindings plus Flex layout) and a no-op host.
- Status: old (last commit 2018), browser target "broken for now", PPX "nothing working". It is a design study.
- Steal: the package split (core, reconciler, host renderers); a no-op host for tests.
- Avoid: nothing specific found. I did not read the reconciler's hook code.

### Superfine

- Core model: `h(tag, props, children)`, `text(s)`, `patch(node, vdom)`. No state, effects or subscriptions. About 1 kB min+gzip (README claim). `index.js` is 258 lines.
- Keyed diffing exists (`getKey`, a `keyed` map in the middle-range diff). The README's example re-calls `patch` from its own `setState`.
- Steal: a view is a pure function from data to a tree; the whole runtime is a `patch`; state lives outside. This is the Elm architecture in about 250 lines. It is a good baseline for a tree/patch core.
- Avoid: pushing state, effects and subscriptions entirely to the user, since the goal here is to replace React including local state.

### VanJS

- Core model: no VDOM. State objects have a `val` getter/setter. A function passed as a prop or child is a binding. It reruns when states read inside it change. `van.derive` makes derived state and runs as a microtask since 1.5.0. `rawVal` reads without tracking.
- Size: the site says "more than 100 times smaller than React". It gave no absolute figure.
- Mini-Van is a stateless version for server-side use. `van.hydrate` exists. I did not read how SSR works.
- Unique: auto-tracked dependencies from reading `.val`, tag functions through `Proxy` (`van.tags`), no JSX and no build step.
- Steal: fine-grained updates with no tree diff; separate, smaller stateless build for the server.
- Avoid: implicit tracking via a global "current binding" (hard to type in OCaml, and breaks with async code). The page did not describe cleanup of bindings, so I cannot judge it.

### Tachys

- Core model: React-like hooks on a VDOM using Inferno's LIS keyed diff. Three scheduler lanes (Sync, Default, Transition), fiber-style yield, two-phase commit for transitions with rollback.
- Size: README claims about 36 KB min and 11 KB gzip for the full core. Lean entry points drop the scheduler and Suspense. Benchmark claim (README, not verified by me): parity with Inferno on total time (1.007x geomean) and about 18% less script time.
- Unique: V8 tuning (monomorphic calls, bitwise flags, object pooling). Dev-mode checks for duplicate keys and hook-order violations, stripped in production.
- Steal: separate "sync core" and "concurrent" builds; dev-only checks for keys; `useSyncExternalStore` with a sync lane to avoid tearing.
- Avoid: the React-compat surface and V8-specific tuning. Neither suits a Melange target, where OCaml values compile to JS objects.

## Comparison

| Library | Rendering model | State model | Effect model | Keys | Typed? | SSR? |
|---|---|---|---|---|---|---|
| brisk-reconciler | Tree of components, host callbacks, explicit flush steps | Hooks tape (`state`, `reducer`, `ref`), stable setters | `use_effect` with `Always`/`OnMount`/`If (eq, dep)`; returns cleanup option | Optional abstract `Key.t`, else by position | Yes, typed tape (GADT) | Not built in (host-agnostic; non-DOM hosts) |
| Preact 10/11 | VDOM diff, LIS child moves | React hooks | `useEffect` with deps (`Object.is` in v11) | `key` prop | TS types only | Yes, v11 streamed hydration |
| Fre | Fiber VDOM, 5 ms slices | Hooks by index cursor | `useEffect`/`useLayout` with deps | `key`, keyed diff | TS | Hydration claimed in README |
| pure | Fiber-style VDOM, many hosts | Not read | Not read | Not read | Reason | No |
| Superfine | VDOM `patch`, about 1 kB | None (external) | None | `key` | No | No (DOM only) |
| VanJS | No VDOM, bindings update DOM nodes | `van.state` with `.val` | `van.derive` (microtask) | n/a | No | Mini-Van; hydrate exists |
| Tachys | VDOM + lanes + LIS | React hooks | React-style, deps arrays | `key`, dev duplicate check | TS | Yes, string and streaming |
| reason-react | Real React | React hooks via bindings | `useEffect` bindings | `key` | Reason/OCaml bindings | Via React |

## What this means for the library

1. brisk-reconciler is the closest base. Its host callback interface suits one core for Melange (DOM) and native (server string). Read its `brisk_reconciler_internal.ml` before writing a new core.
2. Hook order is still a rule in brisk-reconciler. Two ways to remove it, both beyond what I read in these libraries:
   - Allocate state by a typed handle created at component creation, not by position. Sketch:
     ```ocaml
     (* a component = a record of typed slots made once, plus a render function *)
     type ('props, 'node) component = {
       init : unit -> 'local;                 (* creates state handles once *)
       render : 'local -> 'props -> 'node element;
     }
     ```
     Each handle is a first-class value, so conditional use cannot shift other slots. This is close to how VanJS and the notes' `State.make` idea work.
   - Keep brisk's typed tape and accept the rule, but enforce it with types.
3. Effects: copy brisk's variant, but fix its two weak points. Use `~equal` with the meaning the name suggests, and add the dependency as a typed value:
   ```ocaml
   module Effect : sig
     type 'a deps = Always | Once | When of { equal : 'a -> 'a -> bool; value : 'a }
     val run : 'a deps -> (unit -> (unit -> unit) option) -> unit
   end
   ```
   This matches the notes' `Effect.xxx ~equal`. The reason an effect ran can be one more argument: `fun ~prev ~next -> ...`.
4. Keys: brisk makes them optional and untyped. The notes ask for keys that are required for lists. A `keyed_list : ('a -> Key.t) -> 'a list -> ...` function as the only way to make a dynamic child list does this, with no `key` prop.
5. From Preact v11: keep the core small, move compat features out, use LIS for moves, mark async boundaries in the DOM with stable comments so streamed SSR can hydrate.
6. From Superfine and Fre: the minimum viable core is about 250 lines (patch) plus about 150 lines (hooks plus scheduler). Do not plan for a large runtime.
7. From VanJS: fine-grained bindings are a real alternative to re-render-and-diff. It fits the notes on mobx, lwd and incremental. It is a separate model, so decide early (see below).

## Open questions

- One core, or two? Re-render and diff (brisk, Preact, Fre, Superfine) versus fine-grained bindings (VanJS, lwd). Mixing them in one runtime was not studied here.
- Does the library drop the rule of hooks, or keep it with types? Neither brisk nor any other library read here has removed it.
- How should "why this effect ran" be exposed? No library read here has a built-in answer.
- Should the host interface be brisk's four callbacks, or a smaller "patch" interface like Superfine's?
- Is concurrent rendering needed in v1? Fre and Tachys include it. Superfine and VanJS do not.
- Preact v11 branches and PRs, the Hydration 2.0 RFC, and the `_developit` tweet were not read. Check them if hydration design matters.
- brisk's `Effect.Always` and hook flush order against OCaml 5 effect handlers was not studied. The hook was renamed from `effect` to `use_effect` because `effect` became a keyword in OCaml 5.3. This affects naming in the new library.
