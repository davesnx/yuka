# melact

## Sources

- https://github.com/jongleb/melact, commit `9a6073f6c9c182d4d591b7bd34029771dd5dd878`
  (2026-11-05, message `wip`; the history is one squashed commit, so no history was read).
- Read: `README.md`, `docs/vision.md`, `docs/compiler.md` (first 80 lines), `CLAUDE.md`,
  `react/runtime/instance.ml`, `react/runtime/*.mli`, `react/react.ml` (hooks), `react/reactDOMServer.ml`,
  `melhole/runtime/view.mli`, `melhole/runtime/served.ml`, `melhole/compiler/free.ml` (part),
  `meltea/program.ml(i)`, `meltea/cmd.ml`, `meltea/sub.ml`, `meltea/html.ml`, `ppx/meltea/fields.ml` (part).
- Not done: I did not build it or run its tests or benchmarks. Size, speed and test counts below
  are the README's claims, not checked.
- Paths below are relative to the repo root.

## What melact is

- Two front ends on one compiler:
  - **Melact** keeps the reason-react API (`useState`, hooks, `[@react.component]`), so an
    existing reason-react app moves to it by changing two `dune` lines (`README.md:46-53`).
  - **Meltea** is the Elm architecture: model, msg, `update`, `view`, `Cmd`, `Sub`
    (`meltea/program.mli:29-46`).
- It works like Svelte. A ppx turns each JSX site into a static HTML `<template>`, cloned for
  each mount, plus "holes" for the dynamic parts. It also generates a `refresh` function for
  each template. That function compares each local the view reads with its last value (one
  `===` per local) and writes only the holes that read a changed local (`docs/compiler.md:21-44`).
- It is **re-run, not run-once**. A setter marks its component instance dirty
  (`react/runtime/instance.ml:268-280`). One microtask re-runs dirty instances, parents first,
  in document order (`instance.ml:163-184`). The component body and all its hooks run again.
- The README rules out signals: "There is no reactive graph" (`README.md:455`).
- Change detection is physical equality everywhere: hook deps (`react/react.ml:145-161`),
  props (`instance.ml:227`), setState (`react.ml:96`).
- Melange only: each library declares `(modes melange)` (`react/dune`, `melhole/runtime/dune`).
  - The server renderer runs in JS, into a detached DOM element (`melhole/runtime/served.ml:112-123`).
  - "SSR on native OCaml" is listed under "Not yet" (`README.md:390`).
- Suspense, concurrent rendering and `useTransition` are non-goals (`README.md:452`).
  - `Suspense.make` returns its children and ignores the fallback (`react/react.ml:46-48`).
  - `startTransition` runs its argument at once (`react.ml:256-257`).

## P1–P20

| # | Problem | melact |
|---|---|---|
| P1 | Composition | Functions as components (Melact), or Elm views with `Html.map` (Meltea). Same as reason-react. |
| P2 | Local state | Hook slots in call order (Melact). Only one model (Meltea). |
| P3 | Props | Plain values. Each prop is compared with `===`; if none changed, the component is skipped without `memo` (`instance.ml:226-232`). |
| P4 | Derived/memo | `useMemo` with `==` deps (`react.ml:133-140`). In addition, each hole is computed only when its free variables change (`docs/compiler.md:21-44`). |
| P5 | Granularity | Re-render per component, then write per hole. Hole-level writes with no virtual DOM. |
| P6 | One-shot effects | `useEffect0` (`react.ml:162`); `Cmd` in Meltea. |
| P7 | Long-lived effects | `useEffect` with cleanup. `Sub` in Meltea, matched by source and rank and stopped when gone (`meltea/sub.ml:60-95`). |
| P8 | "When X changes" | `useEffectN` with `==` deps (`react.ml:112-131, 163-169`). No prev value given to the callback. |
| P9 | Cleanup/cancel | Cleanups run on re-run and unmount (`react.ml:113-126`). No cancellation of async work. `Cmd.perform` ignores the promise result once it is sent and cannot cancel it (`meltea/cmd.ml:20-30`). |
| P10 | Async/loading | Not handled. No Suspense (`react.ml:46-48`). |
| P11 | Keyed lists | Strong. Common prefix and suffix, then longest increasing run, gives the fewest DOM moves (`README.md` "Keyed lists"; `melhole/runtime/reconcile.ml`). Rows are skipped when the item is physically the same and its projection did not change (`README.md:192-199`). |
| P12 | Batching | Setters only mark dirty. One microtask flushes, parents first (`instance.ml:268-280, 163-184`). Meltea has one redraw per microtask (`meltea/program.ml`). |
| P13 | Transitions/optimistic | Not handled. `useTransition` returns `(false, run_now)` (`react.ml:256-257`). No optimistic API. (Here `Transition` means CSS enter/leave animation, not React transitions.) |
| P14 | Errors | Not handled: no error boundary in `react/react.mli` (searched). A setter called during render raises (`instance.ml:269-271`). Hooks called out of order raise at run time (README "Hooks are typed"). |
| P15 | SSR/hydration | JS-only `renderToString`. Hydration takes over the server's nodes through the compiled walk, and falls back to a full mount on mismatch (`served.ml:125-135`). No state transfer: the client runs the view again from its own initial state (`meltea/program.ml:31-35`). No streaming. |
| P16 | Testing | Law-based tests (QCheck, fast-check in jsdom). One suite is built twice, against React 18 and against Melact (`CLAUDE.md`; `test/dual`). Not run by me. |
| P17 | Debugging | Not handled beyond error messages. `setDisplayName` does nothing (`react.ml:79`). |
| P18 | Footguns | Mutating in place updates nothing (`README.md:287`). It has React's stale-closure and deps footguns. Polymorphic hook state gets a weak type (`README.md:391`). |
| P19 | Boilerplate | Same as reason-react: `useEffect1..7`, `useMemo1..7` (`react.ml:161-196`). |
| P20 | Typing | Strong for hooks: each hook call site gets a `Type.Id` key from the ppx, so a slot is read back with no `Obj.magic`. Using one key at two types is a compile error (README "Hooks are typed by their call site"; `react/runtime/hook.mli`). |

## Against Yuka's direction

- **State as a getter (`count ()`)**: not compatible, and Yuka's choice is not worse.
  - melact's guards use free-variable analysis. An application `f x` reads `f` and `x`
    (`melhole/compiler/free.ml:49-50`). `count ()` therefore reads `count`, and `count` is a
    closure that never changes physically.
  - So a melact-style guard would never refresh a hole that reads a getter.
  - The two models do not mix: melact needs **values** in scope, and Yuka passes **readers**.
- **Users write `fun () ->` in views**: here melact is better on ergonomics.
  - Its ppx finds the dynamic parts and their dependencies itself, so users write plain
    expressions.
  - The cost: a ppx that understands the view, and the rule that rendering must be pure
    (`docs/compiler.md:9-11`).
  - If Yuka accepts a ppx later, this is the strongest argument to drop hand-written `fun () ->`.
- **`State.memo`**: same idea as `useMemo`. Yuka tracks dependencies itself; melact needs a deps
  argument. Yuka is better here: no deps list to keep in sync.
- **Fixed graph**: not covered. melact re-runs component bodies; its "graph" is the instance tree
  (`instance.ml:12-22`).
- **Props unboxed, always the latest value**: same as melact. melact also answers the open Yuka
  question "what happens to a child when a plain prop changes": compare each prop with `===`,
  and re-run the child if one changed (`instance.ml:226-232`).
  - Yuka cannot copy this, because its tree runs once.
  - Inferred: this is evidence that run-once plus plain props needs an explicit rule, such as
    remount or wrap in State.
- **prev/next effects**: worse in melact. Deps are compared with `==` and the callback never sees
  the previous value (`react.ml:112-131`).
- **Function-level loading, Suspense and optimistic updates**: not covered (non-goals,
  `README.md:452`).
- **Parent cancel**: not covered. Cleanups exist; cancellation of async work does not
  (`meltea/cmd.ml:20-30`).
- **No `let*` and no graph argument**: same. melact has neither.
- **Render once on the server, then resume or stream on the client**: not covered, and the
  opposite approach.
  - Server rendering runs in JS only, and the client re-runs everything from its own initial
    state (level-1 hydration without a state transfer).
  - The useful part for Yuka: the client adopts the server's nodes through the same compiled
    walk it uses to clone a template, so no element is created (`served.ml:42-110, 125-135`).
- **mlx**: same. Examples and README use mlx (`CLAUDE.md`, "Examples and README code use mlx").
- **Collections**: melact is better today, because Yuka has no model yet.
  - Keyed reconcile with longest increasing run.
  - Per-row selector projections, so selecting one row of 1,000 re-renders two (`README.md:192-199`).
  - Lists are whole values compared physically: the "plain list" option from `finger-trees.md`,
    made fast by the compiler.
- **Propagation order**: different problem. melact orders dirty *instances* by document position,
  with depth as the fallback (`instance.ml:173-181`). There is no derived-value graph to order.
  - Layout effects run after each patch. Passive effects run after the whole flush, in a later
    frame (`instance.ml:183-192`).
  - Cleanups run before effects inside one commit (`instance.ml:78-89`).

## What Yuka could take

- **Typed slot keys from a ppx** (`Type.Id` per call site). If Yuka ever needs a stable identity
  for a state (for resume or for serialisation), a per-call-site key plus the instance path is
  a typed, deterministic identity.
  - Inferred: this is more robust than the creation counter proposed in `DECISIONS.md`, because
    it does not depend on the order in which async nodes are created.
- **Template plus holes as the DOM layer**, under any reactivity model.
  - A getter-driven Yuka could compile static markup to a cloned `<template>` and give each
    `fun () ->` hole a direct node to write.
  - This is the same output Solid's compiler produces. melact shows it works in Melange with
    mlx and a ppx.
- **Hydration by adopting nodes through the compiled walk**, with fallback to a fresh mount on
  mismatch (`served.ml:125-135`).
- **Keyed list algorithm** (`melhole/runtime/reconcile.ml`, 94 lines): a direct input to the
  Collections question.
- **Event delegation** to `document` for the bubbling events, with the handler stored as a
  property on its element, so replacing a handler costs one property write (README "Events are
  delegated").
- **Controlled inputs**: after an input event, write the last value back if the DOM differs
  (README "Inputs show the state"). Yuka will need the same rule.
- **The dual test suite**: run the same tests against a reference implementation. For Yuka the
  reference could be the native renderer against the Melange renderer.

## What Yuka should avoid

- Physical equality as the only change test. It is cheap and sound only for immutable data, and
  it is a different test on native and Melange for strings and floats (see `DECISIONS.md`).
  melact can use it because it is Melange-only.
- A compiler that must understand every expression. `free.ml` must list the mutable reads it
  knows (`!`, `:=`, `.contents`, `.current`, `Random`, `Sys`; `free.ml:36-53`). Anything it
  misses is a stale hole that is hard to see.
- Copying React's surface. melact's goal is migration, so it keeps `useEffect1..7`, deps lists
  and hook order: the parts Yuka is trying to remove.

## Verdict

Not superior for Yuka's goals. It is the better project today, because it exists, has tests and
claims benchmarks. But it solves a different problem: run React or Elm semantics fast in the
browser.

- **Where melact wins:**
  - working code;
  - a compiler that removes `fun () ->` from user code;
  - keyed lists;
  - hydration that adopts the server's nodes;
  - typed hook slots;
  - a small runtime (README claims 5.6 kB for the counter; not checked).
- **Where Yuka's direction wins, on paper only (nothing is built):**
  - universal native and Melange;
  - run once, with no re-run of component bodies;
  - effects that see prev and next;
  - async, Suspense, optimistic updates and cancellation (melact declares all of these out of
    scope);
  - resume with state transfer.
- **Not compatible:** melact's guards need values; Yuka's state is a getter. Yuka can take the
  DOM layer (templates, walks, keyed moves, delegation, adopting hydration). It cannot take the
  change detection.
- **The real question it raises for Yuka:** will Yuka have a ppx?
  - If yes, the compiler can insert the `fun () ->` wrappers, as Solid does, or guard values,
    as melact does.
  - If no, users write `fun () ->` by hand. melact shows how much that ppx removes.
