# reativa: does its Effect API fit Yuka?

## Sources

- Repository: https://github.com/brnrdog/reativa, commit
  `c6d6e5fd62bb3aaa970d6481afc79a29edf07a48` (2026-08-05, "docs: housekeeping").
  Cloned with `--depth 1`. License: MIT (`README.md:319`).
- Files read in full: `src/signals/effect.ml`, `signal.ml`, `computed.ml`,
  `core.ml`, `scheduler.ml`, `id.ml`, `src/reativa.ml`, `test/test_signals.ml`,
  `README.md`. Read in part: `src/view.ml` (lines 1-120, 255-345, 400-420),
  `ppx/reativa_mlx_ppx.ml` (lines 25-110).
- Not read: the router, the backends, the website, the examples.
- reativa is a port of the ReScript library brnrdog/xote (`src/view.ml:3-4`,
  `src/signals/core.ml:17-21`). The model is SolidJS's: no virtual DOM, effects
  write to the DOM nodes that read a signal (`src/view.ml:3-7`).

## The Effect API

The whole module is 36 lines (`src/signals/effect.ml`).

| Function | Signature | Source |
|---|---|---|
| `Effect.run` | `?name:string -> (unit -> (unit -> unit) option) -> unit` | `effect.ml:36` |
| `Effect.run_with_disposer` | `?name:string -> (unit -> (unit -> unit) option) -> disposer` | `effect.ml:6-34` |
| `type disposer` | `{ dispose : unit -> unit }` | `effect.ml:4` |

Signatures are inferred from the code; the module has no `.mli`.

```ocaml
Effect.run (fun () ->
  Printf.printf "count: %d\n" (Signal.get count);
  None)

let d =
  Effect.run_with_disposer (fun () ->
    let id = start_timer (Signal.get delay) in
    Some (fun () -> stop_timer id))
in
d.dispose ()
```

The State side that Effect depends on:

| Function | Signature | Source |
|---|---|---|
| `Signal.make` | `?name:string -> ?equals:('a -> 'a -> bool) -> 'a -> 'a t` | `signal.ml:15` |
| `Signal.get` | `'a t -> 'a`, tracked | `signal.ml:22` |
| `Signal.peek` | `'a t -> 'a`, not tracked | `signal.ml:28` |
| `Signal.set` | `'a t -> 'a -> unit` | `signal.ml:32` |
| `Signal.update` | `'a t -> ('a -> 'a) -> unit` | `signal.ml:43` |
| `Signal.batch` | `(unit -> 'a) -> 'a` | `signal.ml:46`, `scheduler.ml:268` |
| `Signal.untrack` | `(unit -> 'a) -> 'a` | `signal.ml:47`, `scheduler.ml:282` |
| `Computed.make` | `?name:string -> ?equals:('a -> 'a -> bool) -> (unit -> 'a) -> 'a Signal.t` | `computed.ml:56` |
| `Computed.dispose` | `'a Signal.t -> unit` | `computed.ml:62` |

A computed is a `'a Signal.t` (`computed.ml:24`), so it is read with
`Signal.get`. Nothing in the types stops `Signal.set` on a computed.

## How it works

- **Dependency tracking: automatic.** `Signal.get` records a link from the
  signal to the node that is running (`signal.ml:22-25`,
  `scheduler.ml:82-85`). Each run re-records the links and removes the ones
  not read this time (`scheduler.ml:105-118`, `122-140`). `Signal.peek` and
  `Signal.untrack` read without a link.
- **When it runs.**
  - First run: immediately and synchronously, when the effect is created
    (`effect.ml:15-24`). This first run records the dependencies.
  - After a write: `Signal.set` compares with `equals`, and if the value
    changed it queues the subscribers and flushes synchronously, before `set`
    returns (`signal.ml:32-41`, `scheduler.ml:214-251`).
  - In `Signal.batch`, the flush waits until the batch ends
    (`scheduler.ml:268-280`). Test: `test_signals.ml:86-90`.
  - Flush order: pending computeds first, then effects, each list sorted by
    level (`scheduler.ml:187-206`). The level is one more than the deepest
    computed the node reads (`scheduler.ml:89-101`). It is computed once,
    when the level is 0 (`scheduler.ml:173`, `181`).
  - Computeds are lazy: they recompute when read (`scheduler.ml:254-264`).
    This lazy read makes the diamond case glitch-free
    (`test_signals.ml:149-166`).
- **Cleanup.** The body returns `Some cleanup` or `None`. The cleanup runs
  before the next run and on dispose (`effect.ml:10-13`, `27-33`). Test:
  `test_signals.ml:60-71`.
- **Disposal and ownership.** `run_with_disposer` returns a `dispose`
  function (`effect.ml:26-34`). `run` throws it away (`effect.ml:36`), so the
  effect lives as long as its signals. The core has **no owner tree**.
  - The `View` layer collects the disposers of the effects *it* creates
    through a `register` function (`view.ml:71-75`, `82-115`, `261-268`), and
    a `Dynamic` region disposes them before it re-renders (`view.ml:282-306`).
  - An effect that user code creates with `Effect.run` is not registered
    anywhere. Inferred from the code, and the mechanism is checked below
    (check 1): an `Effect.run` inside a region that re-renders is never
    disposed. Each re-render adds one more live effect.
- **Previous value and equality.**
  - Equality lives on the source, not on the effect. The default is physical
    equality `==` (`signal.ml:12`, `17`).
  - A computed without `~equals` counts every recompute as a change
    (`computed.ml:7-24`). With `~equals`, an unchanged result stops the
    effects below it (`computed.ml:31-54`, `test_signals.ml:170-183`).
  - An equality that raises counts as "changed" (`signal.ml:34`,
    `computed.ml:38`).
  - The effect body never gets the previous value.
- **Async and cancellation: not covered.** There is no promise, async,
  `Lwt` or abort anywhere in `src` or the README (searched with
  `grep -rniE "promise|async|lwt|abort"`).
- **Errors.**
  - An exception in the first run restores the tracking state and re-raises
    (`effect.ml:18-24`).
  - An exception during a flush leaves the flush and comes out of the
    `Signal.set` that started it (`scheduler.ml:204-206`). The effects
    queued in the same batch after it do not run. They keep their "pending"
    flag, and `add_effect_to_pending` skips nodes with that flag
    (`scheduler.ml:20-24`). So they never run again (check 4).
- **Server.** reativa has no server rendering: no `to_string`, no SSR, no
  hydration (same grep). The core runs on native only for tests
  (`test_signals.ml:1-3`). `View.child` classifies a child at runtime with
  JavaScript `typeof` and `Obj.magic` (`view.ml:400-419`), which cannot run
  on native.
- **The ppx.** In mlx, a prop or child that contains `Signal.get` outside a
  nested `fun` is wrapped as `dynamic (fun () -> ...)`. A `fun` literal is
  dynamic, and anything else is static (`reativa_mlx_ppx.ml:43-96`,
  `README.md:134-141`). The match is on the last module name `Signal` before
  `get` (`reativa_mlx_ppx.ml:46-51`). So `open Signal` with `get s`, or a
  module alias, is not seen.

## Checks

Project:
`/tmp/claude-2020/-home-me-workplace-davesnx-yuka/49cf5768-41a7-44d9-9d3e-d5dbfb9b5d22/scratchpad/reativa-check`.
`rcore/` is a copy of reativa's `src/signals/*.ml`, unchanged. `yfx/yfx.ml` is
a Yuka-style layer of about 60 lines on top of it: `State`, an owner, `root`,
`Effect.run` and `Effect.on_change`. `cases/cases.ml` holds the cases, and both
targets run them.

```sh
eval "$(opam env --switch=5.2.0 --set-switch)"
dune build                                  # exit 0, native and Melange
./_build/default/test/run.exe               # exit 0
node _build/default/js/out/js/run.js        # exit 0
diff native.txt node.txt                    # no difference
```

Output, the same on native and node:

```
1 reativa nested effect: one write to b ran 3 inner effects
2 owned nested effect: one write to b ran 1 inner effects
3 parent dispose: runs after dispose = 0, inner cleanups = 1
4 reativa: set raised the effect's exception
4 reativa: other effect runs: initial+set1 = 1, after set 2 = 1
5 reativa: effects created a,b,c run on set in order c,b,a
6 reativa: effect writing its own dependency: value 3, runs 4
7 on_change: calls 0->1 1->5 (no call on first run, none for an equal write)
```

1. An effect created inside another effect is not disposed when the outer one
   runs again. After two outer re-runs, three inner effects are alive.
2. With an owner: the outer effect owns the effects created during its run and
   disposes them before it runs again. Only one inner effect stays alive.
3. Disposing a root stops every effect under it and runs the inner cleanups.
   This is "a parent can cancel effects", with no `graph` argument.
4. An exception in one effect stops another effect of the same flush for
   good.
5. Effects of the same level run in reverse order of subscription, not in
   creation order.
6. An effect that writes the signal it reads runs again inside the write,
   recursively, until the value stops changing.
7. `on_change` on top of `Effect.run` gives `~prev ~next`, skips the first
   run, and skips equal writes.

## Against Yuka's current direction

| Yuka item | Fit | Why |
|---|---|---|
| Abstract State: `make`, `get`, `set`, `update` | Fits | Same API: `Signal.make/get/set/update` (`signal.ml:15-43`). reativa also has `peek`, which Yuka needs for untracked reads. |
| `State.memo` returns a State | Fits, same gap | `Computed.make` returns a `'a Signal.t` (`computed.ml:24`). reativa has the same hole as Yuka: `set` on a computed type-checks. It does not solve read-only State. |
| The ppx marks holes from `State.get` | Fits | It is the same rule (`reativa_mlx_ppx.ml:55-96`). It also has the same limits: `open`, aliases, and reads hidden inside other functions. Yuka's lint that bans `open Yuka.State` closes part of this. |
| Effects fire on first render or on a State change | Fits | Run at creation, then on each change of a tracked read (`effect.ml:15-24`, `scheduler.ml:214-251`). |
| Effects compare prev/next with an equality | Partial | Equality exists, but on the source (`Signal.make ~equals`, `Computed.make ~equals`), not on the effect. There is no previous value. `on_change` adds it in a few lines (check 7). |
| A parent can cancel effects | Conflicts as is | The core has no owner. User effects leak (check 1). An owner layer fixes it (checks 2 and 3). |
| The tree renders once | Fits | "A component body runs once, when the view is built" (`README.md:231-234`). |
| Islands: effects only in client code | Not covered | reativa is client-only and has no boundary. |
| Server on native, effects never run there | Conflicts as is | On native, `Effect.run` runs the body (`test_signals.ml`). Yuka must make `Effect.run` do nothing in the server build. |
| No `let*`/`let+`, no `graph` argument | Fits | Plain closures. The tracking target is a global ref (`scheduler.ml:5`). |
| Timer wrappers (`Effect.interval`, `Effect.timeout`) | Not covered | They are easy to build on `run` with a cleanup (sketch below). |
| Propagation order (open) | Partial answer | Computeds first, then effects by level. Lazy pull of computeds keeps it glitch-free. Same-level effects run in reverse subscription order (check 5), not parent-first or creation order. |
| Async and cancellation | Not covered | Nothing in reativa. |
| Errors | Conflicts | One failing effect stops others for good (check 4). |

## What to take, what to change, what to leave out

### Take as is

The shape of `Effect.run`: automatic tracking, a first run at creation, and an
optional cleanup that runs before the next run and on dispose.

```ocaml
Yuka.Effect.run (fun () ->
  Document.set_title (string_of_int (Yuka.State.get count));
  None)

Yuka.State.peek count
Yuka.batch (fun () -> Yuka.State.set a 1; Yuka.State.set b 2)
Yuka.untrack (fun () -> Yuka.State.get other)
```

Also worth taking: the scheduler's design (links reused across runs, lazy
computeds, level order) as a base for Yuka's core. It is plain OCaml, builds
on native and Melange, and is MIT licensed. Checked: the copy builds and runs
the same on both targets.

### Change

- **Ownership.** Each `Effect.run` registers with the current owner. An effect
  owns what its run creates. The island mount creates the root. Checked
  (checks 2 and 3; `yfx/yfx.ml`, `with_owner`, `root`, `Effect.run`).

  ```ocaml
  (* inside Yuka, not user code *)
  let (), dispose = Yuka.root (fun () -> mount_island ...) in
  (* navigation or unmount *)
  dispose ()
  ```

- **Previous value.** Add `on_change` for the prev/next case. Keep `run` for
  the "read what you need" case. Checked (check 7).

  ```ocaml
  Yuka.Effect.on_change ~equal:String.equal query (fun ~prev ~next ->
    log (prev ^ " -> " ^ next))
  ```

- **Error isolation.** Catch the exception for each effect in the flush,
  clear its pending flag, report it, and continue with the others. Not
  checked.
- **Server.** In the native build, `Effect.run` and `on_change` do nothing.
  This could be a dune virtual module, which reativa already uses for `Dom`
  (`src/dune`). Not checked.
- **Timers**, on top of `run`. Not checked.

  ```ocaml
  let interval ms f =
    Yuka.Effect.run (fun () ->
      let id = Js.Global.setInterval ~f ms in
      Some (fun () -> Js.Global.clearInterval id))
  ```

- **Order.** If Yuka wants parent-first or creation order for effects of the
  same level, sort by `(level, id)`. Node ids already increase with creation
  (`id.ml`). Not checked.

### Leave out

- `run_with_disposer` in the public API. Owners replace manual disposal. Keep
  `root` internal, or for tests only.
- `View.child`'s runtime `typeof` with `Obj.magic` (`view.ml:400-419`). It is
  JavaScript-only. Yuka's ppx and the element types decide this at compile
  time.
- Physical equality `==` as the default. It behaves differently on native and
  Melange for strings and floats. Yuka's default equality is still open.
- Recursive re-entry on self-writes (check 6). It works, but it uses one stack
  frame per step. A queue would be safer. Not checked.

## Verdict

- The Effect API fits Yuka's mental model. "Runs at first render and on a
  State change, cleanup before the next run" is exactly the 2026-11-04
  direction, and reativa's `Signal` API is the State API Yuka chose on
  2026-11-06 (`make`, `get`, `set`, `update`), plus `peek`.
- The ppx rule is the one Yuka decided: an eager `get` becomes a hole. Its
  weak points are the same too.
- reativa alone is not enough for Yuka:
  - no owner, so user effects leak (check 1) and a parent cannot cancel;
  - no previous value;
  - no async and no cancellation;
  - one failing effect stops others (check 4);
  - no server.
- Each gap except async is closed by a thin layer. The owner and `on_change`
  took about 60 lines and behave the same on native and Melange
  (checks 2, 3 and 7).
- reativa does not settle Yuka's open questions: read-only State, the default
  equality, the propagation order of same-level effects, and async.
- Recommendation: take `Effect.run`'s shape and the scheduler as the base.
  Add owners, `on_change`, error isolation and a native no-op. Design Async
  and cancellation separately.
