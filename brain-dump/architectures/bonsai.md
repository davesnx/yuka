# Bonsai

Scope: how Jane Street's Bonsai works, as of the `master` branch of `janestreet/bonsai` and `janestreet/bonsai_web` (read 2026-11-04, version string `v0.18~preview.133.03+642`). No recommendation for Yuka.

API version described: the current one. It has a single type `'a Bonsai.t` and a `graph` argument written `(graph @ local)`. Components are `graph -> 'a Bonsai.t`. The library calls this API `Cont` (`bonsai/src/cont.mli`; `bonsai.mli` says Cont is "the default, recommended, and supported api").

Older APIs, in short:
- Arrow API (`Bonsai_arrow_deprecated`), the first one. Now deprecated.
- `Proc` API (`Computation.t` and `Value.t`, `let%sub`, `let%arr`). Replaced in late 2023 (source: `how_bonsai_works.md`; `CHANGES.md` for v0.17.0 says "Rewrote entire bonsai API. The new version is inside of the `Bonsai.Cont` namespace"). The `local_ graph` form is the newer one. Both `Proc` and `Cont` still exist in the tree. The internals did not change; `Bonsai.t` is the old `Value.t`, and `graph` builds the old `Computation.t` behind the scenes.

Most code on the web, including old blog posts and the bonsai.red guide, shows `Proc`. Do not copy it as current.

## Model

**Two layers.** `bonsai` is a general library for incremental, composable state machines. It does not know about the web. `bonsai_web` adds the browser: Vdom, RPC effects, the runtime loop. `bonsai_term` does the same for terminals (README of `bonsai`). Bonsai is not compiled with Melange. It targets Js_of_ocaml (the opam description says so).

**What a component is.** A component is an ordinary OCaml function:

```ocaml
val component : ... -> (graph @ local) -> Vdom.Node.t Bonsai.t
```

`'a Bonsai.t` means "an `'a` that changes over time" (doc comment in `cont.mli`). It is a node in an incremental graph. Functions that do more than pure computation take `graph`. `graph` is a builder.

**Two phases.** The `bonsai_web` docs describe two times when code runs.
1. Graph building. Runs once, at start. Code that takes `graph`, and code outside a `let%arr`, runs here.
2. Stabilization. Runs many times. The body of a `let%arr` runs here.

`graph` is `local_`, so the compiler (when it enforces modes) refuses to let closures capture it. Closures are where runtime code lives. So you cannot create state at runtime (`how_bonsai_works.md`). Whether stock OCaml enforces this, or only the OxCaml compiler does, I did not check (memory: only OxCaml enforces modes). The opam file asks for `ocaml >= 5.1.0`.

**State and identity.** State is created by calling a primitive with `graph`: `Bonsai.state`, `state'`, `state_opt`, `toggle`, `state_machine`, `actor`. Each call returns the current value as a `Bonsai.t` and a setter as a `Bonsai.t` holding a function that returns an `Effect.t`. The setter is a `Bonsai.t` because the state queue does not exist until graph building is over (`bonsais_lifecycle.md`).

Identity comes from the place in the static graph, not from call order and not from a component instance. The runtime keeps all state in one Incremental `Var`. Its shape follows the graph: a `Sub` is a pair, an `assoc` is a `Map`, a leaf is the model. An action is a path in that tree (`how_bonsai_works.md`). `Bonsai.path` exposes a unique path as a value.

**The graph is static.** There is no `bind`. `'a Bonsai.t Bonsai.t` is not allowed. Nested `let%arr` is a compile error. The reason given: the graph can be optimized and instrumented at start, and Incremental's dynamism is slow (`thinking_in_bonsai.md`). Variable structure comes from three primitives instead:
- `match%sub`: each arm is a separate sub-graph with its own state.
- `Bonsai.assoc`: one sub-graph instance per key of a map.
- `Bonsai.scope_model`: an `assoc` with exactly one key. Used to keep one copy of state per key.

A node in an unselected arm or a removed key is inactive. It is not destroyed. Its state is kept (`bonsais_lifecycle.md`).

**Incremental underneath.** `Bonsai.t` is a wrapper over `Incr.t` from Jane Street's `incremental` library. `let%arr` makes a node that depends on other nodes. `stabilize` visits changed nodes in order of non-decreasing "height", recomputes each at most once, and adds the parents of a node only if the node's value changed. "Changed" means `phys_equal` by default and can be replaced by a cutoff function (`incremental_intf.ml`).

**View.** The root result is a `Vdom.Node.t Bonsai.t`. `Vdom` comes from `virtual_dom`, a vendored OCaml wrapper over Matt Esch's JavaScript virtual-dom library (`virtual_dom/README.md`). You write nodes with `Vdom.Node.*`, or with the `{%html| ... |}` ppx (`ppx_html`, JSX-like). Since the graph is static, view fragments from children enter the parent as `Vdom.Node.t` values after `let%arr`.

**Startup.** `Bonsai_web.Start.start component` (`bonsai_runtime.md`):
1. Run `graph -> Vdom.Node.t Bonsai.t` to build the static `Computation.t`.
2. Optimize it. Create one Incremental `Var` for the whole model and a queue for pending actions.
3. Compile to a `Vdom.Node.t Incr.t`, stabilize once, build the DOM, attach it.

**Frame loop** (`bonsai_runtime.md`). Each frame:
1. Update the clock; run due clock effects.
2. Apply queued actions. Stabilize before an action only if it is a `state_machine_with_input` action.
3. Stabilize.
4. Run `before_display` lifecycle effects. Apply actions and stabilize again until none are left.
5. Diff and patch the DOM.
6. Run the other lifecycle effects (`on_deactivate`, `on_activate`, `after_display`, `on_change` with `After_display`). State changes made here wait for the next frame.
7. Schedule the next frame with `requestAnimationFrame`, with a 1000 ms `setTimeout` as a fallback for background tabs.

**Effects.** `Effect.t` is `Ui_effect.t` from `virtual_dom`. It is a value that describes work. It runs only when the runtime schedules it, usually from an event handler or lifecycle hook. Effects compose with `let%bind.Effect`, `Effect.all_parallel`, `Effect.Many`. Async work enters through `Effect.of_deferred_fun` (Async).

## Problems

### P1 Unit of composition

A component is a function from `graph` (and plain OCaml arguments, and `Bonsai.t` inputs) to a `Bonsai.t`. By convention it lives in a module: `Counter.component graph`. Reusable pure view code goes in a separate `view` function that returns a `Vdom.Node.t` (`bonsai_best_practices.md`).

Parent to child: pass `Bonsai.t` values as arguments.

Child to parent: return values. The old API forced one return value, so people returned tuples inside one `Bonsai.t`. Now a component can return a tuple or record of several `Bonsai.t`s, for example `(view, value, set_value)`. The doc says so in the upgrade guide.

State sharing: the docs recommend "controllable" components. A component takes an optional `?state:'a Bonsai.t * ('a -> unit Effect.t) Bonsai.t`. If given, the parent owns the state; if not, the component creates its own (`organizing_state.md`). Bonsai says other frameworks make each component pick one of these two modes; here a component can offer both.

Far-away communication: `Bonsai.Dynamic_scope`, which the docs compare to React Context (`dynamic_scope.md`). `Bonsai.Memo` shares one stateful computation between several users.

Cost: every `Bonsai.t` must be unwrapped with `let%arr` before use in a view. You cannot write `<%{Counter.component graph} />` in `ppx_html`. You call the component, then `let%arr` on the result (`thinking_in_bonsai.md`).

### P2 Local state

Created by `Bonsai.state initial graph` and related functions (see Model). Identity is the position in the static graph. Each `assoc` key and each `match%sub` arm gets its own copy.

- `Bonsai.state` replaces the whole value. `Bonsai.state'` takes `old -> new`. The docs say to prefer `state'` when the update depends on old state, because two async setters can overwrite each other with a stale record (`thinking_in_bonsai.md`).
- `state_machine`: a model, an action type, `apply_action`.
- `actor`: like `state_machine`, but `recv` also returns a value that goes back to the caller's effect.
- State is kept while a node is inactive. To clear it: `Bonsai.with_model_resetter` (returns a reset effect) or `Bonsai.scope_model` (one copy per key).

Cost: state lives outside the view tree, in one big model value. You cannot read it except through a `Bonsai.t`. The setter is also a `Bonsai.t`, so event handlers need `let%arr ... and set_x` first.

### P3 Props and inputs

Every input that can change is a `Bonsai.t`. A change reaches a child through the graph: the child's `let%arr` node has the parent's node as a dependency, so it recomputes when that node changes value. There is no "props object" and no re-render of the child function. The child function ran once, at graph building.

Plain OCaml values (such as `~log`) can be passed too. They are constants for the lifetime of the graph.

A state machine that needs a changing input uses `state_machine_with_input`. Its `apply_action` receives `Active input | Inactive`. If the node is in an inactive branch, there is no fresh input (`quick_start.md`).

### P4 Derived state and memoization

Derived values are `let%arr` nodes. They are memoized by construction: a node recomputes only if a dependency changed value.

Who decides equality: the default is `phys_equal` (`bonsais_lifecycle.md`). You override it with:
- `Bonsai.cutoff ~equal` on a node. The docs' example normalizes a query string into a fresh list; without a cutoff the filter reruns on every keystroke.
- `?equal` on `Bonsai.state` (used by `assoc` and `match%sub` to save memory, per the doc comment).
- Destructuring in `let%arr { a; _ } = r`. The ppx adds a cutoff for the ignored fields. `let%map` does not. The best-practice doc says always use `let%arr` and destructure.

Footgun: the default is physical equality, so two equal but separately built values count as changes.

### P5 Update granularity

After a state change, Incremental recomputes only the nodes that depend, directly or through other nodes, on that state, and stops at nodes whose value did not change. Granularity is one `let%arr` or primitive, not one component. A view function inside a `let%arr` runs as a unit: if one of its inputs changes, the whole body reruns and returns a new `Vdom.Node.t`.

Then `virtual_dom` diffs the root vdom against the previous one (memory: the JavaScript virtual-dom library skips subtrees whose old and new objects are the same reference; I did not read this in the source). The diff still starts at the root every frame that the view changed.

Cost, from `tips_and_tricks.md`:
- `assoc` keeps separate state and nodes per key, which is expensive, and grows "exponentially" when `assoc`s are nested (their wording).
- If an `assoc` body creates no graph nodes (no state, no lifecycle, no `match%sub`), Bonsai replaces it with `Incr_map.mapi`, which has a constant number of nodes. The rule of thumb: for maps with thousands of keys, create nothing with `graph` inside the `assoc`, except `Bonsai.path`.
- `match%sub` has "significant overhead", especially nested.
- Vdom list diffing is naive: it compares by index.

### P6 One-shot effects

An event handler returns `unit Effect.t`. The effect is a value; it runs when the handler returns it to the runtime (`quick_start.md`). Example: a click handler returns `fetch ... |> bind ... set_state`.

Sources of effects: setters and injectors from state primitives; `Effect.of_sync_fun`, `Effect.of_thunk`; `Effect.of_deferred_fun` (Async, used in `bonsai_examples/effect_poller`); `Rpc_effect.Rpc.dispatcher`, which gives `query -> response Or_error.t Effect.t`; `Effect.of_js_promise`.

Cost:
- An effect closes over values from the moment the `let%arr` last ran. Reading a `Bonsai.t` value in the middle of an effect chain gives the old value. Use `Bonsai.peek` (see P18).
- Doing expensive work while building the effect (not inside it) runs on every recompute (`bonsai_best_practices.md`).

### P7 Long-lived effects

`Bonsai.Edge.lifecycle ~on_activate ~on_deactivate ~before_display ~after_display graph`. Each argument is a `unit Effect.t Bonsai.t` (so it can depend on reactive values).

Lifetime = activity of the node (`bonsais_lifecycle.md`):
- A node at the top level is active for the whole app. `on_activate` runs once; `on_deactivate` never.
- A node under `match%sub`, `assoc` or `scope_model` is active while its arm or key is present.
- `scope_model` runs `on_deactivate` first, with access to the old key's state, then `on_activate` with the new key's state (`state_per_key.md`).
- Order in a frame: `before_display`, then the display update, then `on_deactivate`, `on_activate`, `after_display`.
- `before_display` and `after_display` run every frame while active. The doc says "almost never what you want".

Timers: `Bonsai.Clock.every ~when_to_start_next_effect period effect graph` (four modes for overlap). Time that changes: `Clock.approx_now ~tick_every`, `Clock.Expert.now` (every frame, use with care).

Polling data from a server: `Rpc_effect.Rpc.poll` and `Polling_state_rpc.poll`, which allow only one in-flight request, and the docs prefer polling over pushed `Pipe_rpc` streams for web clients. The reason given is background tabs: the frame loop slows to a crawl and a push queue grows (`rpcs.md`).

There is no built-in "subscription" primitive for sockets. You hold the handle in state (or elsewhere) and write open and close in `on_activate` and `on_deactivate`. See the chat room.

### P8 "When X changes, do Y"

`Bonsai.Edge.on_change ~equal value ~callback graph`, and `on_change'` which also gets the previous value (`'a option`) (`cont.mli`).

Properties from the doc comment:
- The callback always runs the first time the node becomes active.
- It runs at most once per frame, with the latest value. Intermediate values within one frame are lost.
- `?trigger`: `` `Before_display`` (default) or `` `After_display``.
- State set from a callback takes effect in a later frame.

Related: `Edge.Poll.effect_on_change` (run an effect on each input change; keep the result); `Bonsai_kernel_mirror.mirror` for two-way sync with external state such as the URL.

The docs discourage it: "Edge-triggered effects make programs less declarative"; do not use `on_change` to keep two states in sync; derive instead (`bonsai_best_practices.md`, `organizing_state.md`).

### P9 Cleanup and cancellation

Cleanup: `on_deactivate`, as in P7. There is no return-a-cleanup-function pattern. You write the matching close yourself.

Cancellation: Bonsai has none for effects. The `Effect_throttling` doc says: "`Effect` does not support cancellation in general" (`cont.mli`). What exists instead:
- `Edge.Poll.effect_on_change` and `manual_refresh` number each run. A result from an older run is dropped if a newer run already finished (source: `proc.ml`, `manual_refresh_implementation`: `if seqnum < model.last_seqnum then model`). The older request still runs.
- `Effect_throttling.poll`: at most one run at a time; new calls queue, and only the latest queued call is kept. Dropped calls return `Aborted`. If the effect raises, no later run starts ("CAUTION" in the doc).
- `Rpc_effect.Rpc.poll` sends no new request until the previous one completes.

An effect in flight when its node deactivates keeps running. What happens when it later calls an injector of an inactive node, I did not verify.

### P10 Async data, loading and error states

No built-in "resource" type. Patterns:
- `Edge.Poll.effect_on_change Starting.empty input ~effect` gives `'o option Bonsai.t`. `None` means "no result yet". Input changes start a new effect. The previous result stays until a newer one arrives (source: `proc.ml`, the state holds `last_result`).
- `Rpc_effect.Rpc.poll ~output_type`. `Response_state_with_details` gives `No_response_yet | Ok {query; response; ...} | Error {query; error; last_ok_response; ...}` (`rpcs.md`).
- `Or_error.t` in the data and `match%arr` in the view (`quick_start.md`).

The query is included in the result so the view can tell which input a response belongs to.

### P11 Keyed lists and dynamic collections

`Bonsai.assoc (module Key) map ~f graph` returns `Key.t -> 'a` map as a `Bonsai.t`. `f` gets `key t`, `value t` and `graph`, so each row can own state and lifecycle. Rows are matched by key; a row's state is kept when the key disappears.

Variants: `assoc_set`, `assoc_list ~get_key` (O(n log n) on any change, returns `` `Duplicate_key `` as a possible error), `all_map`.

The input must be a `Map` (or `Set`, or a list with a key function) with a comparator module. Views: `Vdom.Node.Map_children.div` takes the map and diffs by key (`tips_and_tricks.md`). The plain `Vdom.Node.div (Map.data m)` diffs by index.

### P12 Batching and scheduling of updates

Everything is batched per frame (see the frame loop in Model).
- Many state actions can be applied before one stabilization. The queue is drained fully before stabilizing, so chained effects that each set state run within one frame.
- The view is computed once per frame, then diffed once.
- `before_display` effects can retrigger each other within a frame; each effect runs at most once per frame, so the loop ends.
- Lifecycle effects and `on_change` (with `After_display`) run after the DOM patch. Their state changes wait for the next frame.
- Frames follow `requestAnimationFrame`.

### P13 Concurrency: transitions, deferred values, optimistic updates

Transitions and deferred values: not addressed. There is no priority between updates and no interruptible rendering. Stabilization is synchronous.

Optimistic updates: no primitive. You model it yourself: keep pending items in state next to confirmed items, and remove a pending one when the server answers. See the chat room. `Edge.Poll` ordering (P9) covers the stale response case only.

### P14 Error handling

Guidance (`quick_start.md`, `bonsai_best_practices.md`): put fallible values in `Or_error.t Bonsai.t`, match in the view, and "never" raise exceptions. The reason given is performance: exceptions are slow in Js_of_ocaml.

For effects: `Effect.try_with`, `try_with_or_error`, `iter_errors`, `protect`, `lower_or_error` (`ui_effect_intf.ml`). `Rpc_effect` returns `Or_error.t`.

Exceptions in `let%arr` bodies: I found no error boundary. Incremental says if `stabilize` raises, all later calls raise (`incremental_intf.ml`). Whether Bonsai catches this before it reaches Incremental, I did not verify. `Bonsai.Private.set_perform_on_exception` exists.

### P15 Server rendering and hydration

None. The `url_var.md` doc says: "Bonsai does not currently support server-side rendering". I found no hydration code in `bonsai`, `bonsai_web` or the Vdom wrapper (grep for hydrat, ssr, prerender found nothing).

Related facts that matter if someone tries:
- `Bonsai_driver` (used for tests) runs the graph outside the browser and produces a `Vdom.Node.t` (`how_bonsai_works.md`). Tests print vdom as text. This is not an HTML renderer for the server.
- The frame loop, `Clock`, `Effect`s and `Rpc_effect` assume a browser event loop in `Bonsai_web.Start`.
- Pages are served as a single-page app; the docs tell you to disable server-side routing for client routes.

### P16 Testing

`Bonsai_web_test` (and `Bonsai_test` for non-web) with `ppx_expect`.
- `Handle.create (Result_spec.vdom Fn.id) component` wraps a `graph -> 'a Bonsai.t`.
- `Handle.show` runs one frame and prints the vdom as text. `Handle.show_diff` prints a diff.
- `Handle.click_on`, `Handle.input_text` (selector-based) trigger event handlers.
- `Handle.do_actions` injects values through a custom `Result_spec` (to test setters).
- `Handle.advance_clock_by` mocks time.
- RPCs: `Handle.create ~rpc_implementations:[...]`, with `Bonsai_web_test_async` and `Handle.flush_async_and_bonsai`.
- A vdom linter is available (`Handle.lint_vdom`).

Limits from `testing.md`: tests run in Node, not a browser; events do not bubble; Vdom hooks and widgets do not run; async tests need the `deasync` package and are "several magnitudes slower" and unstable. The doc says to avoid async tests when you can. The RPC section says the tools are "still in their infancy".

### P17 Debugging

From `cont.mli` (`Bonsai.Debug`):
- `Debug.on_change_print_s value sexp_of graph`, and `Debug.debug_node ~name` (logs when a `Bonsai.t` changes, with old and new values if you give `sexp_of`).
- `Debug.watch_computation ~f graph`: logs when an outside value used inside `f` changes, with source positions of the nodes that caused it. No-op until enabled with external tools, so it can stay in production code.
- `Debug.to_dot` (Graphviz of the graph), `Debug.bonsai_node_counts`.
- `Debug.enable_incremental_annotations`.
- `~sexp_of_model` and `~sexp_of_action` on state primitives give the debugger more data.
- `?here` source positions are threaded through most combinators.
- `Rpc_effect` calls show in Chrome DevTools performance traces as custom tracks (`rpcs.md`).
- A browser debugger existed: `startBonsaiDebugger` and `stopBonsaiDebugger` (`changelog.md`, 2021, "opens a new tab in bonsai-bug"). Whether it works today, I did not check.
- Expect tests double as a debugging record of state and view changes.

### P18 Stale reads and common footguns

From the docs:
- Effects close over old values. Example: `set_count` then log `doubled` logs the old value. Fix: `Bonsai.peek`, which returns `Active v | Inactive` (`effects_and_stale_values.md`).
- `Bonsai.state` setter with a record built from the old value overwrites concurrent updates. Fix: `state'` (`thinking_in_bonsai.md`).
- Storing derived values in state goes stale. Store the id, derive the rest (`organizing_state.md`).
- Side effects in `let%arr` run at undefined times, even when inactive.
- Mutable values (such as `Hash_set`) in `Bonsai.t` break change detection.
- `on_change` that copies state into other state adds frame delays and flashes of old content. `mirror` can loop forever with delayed setters.
- Physical-equality cutoff by default (P4).
- Variable-length vdom lists (filtered options, concatenations) cause DOM destruction. Use `Vdom.Node.none` as a placeholder or `Map_children` (`tips_and_tricks.md`).
- A top-level `match%sub` that is not under a `graph` function raises at startup (`upgrade/local-graph.md`, "Known Issues").
- Nested `assoc` and many `match%sub` are slow.
- Time-dependent nodes (`Clock.Expert.now`) rerun every frame.

### P19 Boilerplate and learning curve

My reading, based on the docs:
- Concepts to learn before a first stateful app: `Bonsai.t`, `graph`, `let%arr` and its `and` form, setters as `Bonsai.t`, `Effect.t`, two phases, `match%sub` versus `match%arr`.
- Every use of a `Bonsai.t` needs a `let%arr x and y in`. Every state needs a graph call and a setter.
- Tooling needs: `ppx_let`, `ppx_bonsai`, `ppx_html`, `ppx_css`, Core, Async_kernel, `incr_map`.
- The README sells it as "components that are purely functional state machines", with state, incrementality and rendering as separate parts.
- The API changed twice in about four years; code and posts in the old styles do not compile against the new API.
- The best-practices doc lists rules that are easy to break and have no compiler check: always destructure, always call the parameter `graph`, always use `@ local`.

### P20 Typing guarantees

- `graph` is `local_`: the type checker keeps graph-building code out of runtime closures (when modes are enforced).
- No `bind` and no `Bonsai.t Bonsai.t`: dynamic graph construction is not expressible.
- Effects are typed values: `unit Effect.t`, `'a Effect.t`, `'a Or_error.t Effect.t`.
- `Computation_status.t` forces you to handle `Inactive` where an input may be missing.
- Actions and models are ordinary OCaml types, including polymorphic variants.
- RPCs share types between server and client (`Rpc.Rpc.create` with `bin_query`/`bin_response`). The README calls the shared types a major gain.
- Keys for `assoc` need a comparator.

What the types do not check: equality choice (cutoff), stale closures, state ownership, order of lifecycle effects.

## Chat room

I did not compile this. It follows the shapes in `quick_start.md`, `bonsais_lifecycle.md`, `state_per_key.md`, `cont.mli` and `ui_effect_intf.ml`. Names such as `Effect.ignore_m` and `Vdom.Node.Map_children.div` come from the docs; exact signatures were not checked against a compiler.

Assumed: `Msg.t = { id : int; author : string; text : string }`, plus the four helpers from the brief.

```ocaml
open! Core
open! Bonsai_web
open Bonsai.Let_syntax

module Key = struct
  module Key_type = struct
    type t = Confirmed of int | Pending of int [@@deriving sexp, compare]
  end
  include Key_type
  include Comparator.Make (Key_type)
end

module Model = struct
  type t = { live : Msg.t Int.Map.t; pending : string Int.Map.t; next : int }
  let empty = { live = Int.Map.empty; pending = Int.Map.empty; next = 0 }
end

module Action = struct
  type t =
    | Add_pending of string
    | Confirm of { pending_id : int; msg : Msg.t }
    | Fail of int
    | Receive of Msg.t
end

let recv _ctx (m : Model.t) : Action.t -> Model.t * int = function
  | Add_pending text ->
    { m with pending = Map.set m.pending ~key:m.next ~data:text; next = m.next + 1 }, m.next
  | Confirm { pending_id; msg } ->
    { m with pending = Map.remove m.pending pending_id
           ; live = Map.set m.live ~key:msg.id ~data:msg }, -1
  | Fail id -> { m with pending = Map.remove m.pending id }, -1
  | Receive msg -> { m with live = Map.set m.live ~key:msg.id ~data:msg }, -1

let room_body ~room (graph @ local) =
  let model, inject =
    Bonsai.actor ~default_model:Model.empty ~recv graph
  in
  let socket, set_socket = Bonsai.state_opt graph in
  Bonsai.Edge.lifecycle graph
    ~on_activate:
      (let%arr room and inject and set_socket in
       let%bind.Effect s =
         open_socket room ~on_message:(fun msg ->
           Effect.ignore_m (inject (Receive msg)))
       in
       set_socket (Some s))
    ~on_deactivate:
      (let%arr socket in
       match socket with None -> Effect.Ignore | Some s -> Socket.close s);
  let history =
    Bonsai.Edge.Poll.effect_on_change
      ~equal_input:[%equal: string]
      Bonsai.Edge.Poll.Starting.empty room
      ~effect:(Bonsai.return fetch_history) graph
  in
  let rows =
    let%arr history and { Model.live; pending; _ } = model in
    let confirmed =
      List.fold (Option.value history ~default:[]) ~init:live
        ~f:(fun acc (m : Msg.t) ->
          Map.update acc m.id ~f:(Option.value ~default:m))
    in
    let sent = List.map (Map.to_alist confirmed) ~f:(fun (id, m) -> Key.Confirmed id, `Sent m) in
    let sending = List.map (Map.to_alist pending) ~f:(fun (id, t) -> Key.Pending id, `Sending t) in
    Map.of_alist_exn (module Key) (sent @ sending)
  in
  let rows_view =
    Bonsai.assoc (module Key) rows graph ~f:(fun _key row (_graph @ local) ->
      let%arr row in
      match row with
      | `Sent (m : Msg.t) -> {%html|<div>#{m.author}: #{m.text}</div>|}
      | `Sending text -> {%html|<div class="pending">#{text} (sending)</div>|})
  in
  let draft, set_draft = Bonsai.state "" graph in
  let send =
    let%arr room and inject and set_draft in
    fun text ->
      let%bind.Effect pending_id = inject (Add_pending text) in
      let%bind.Effect () = set_draft "" in
      match%bind.Effect Effect.try_with_or_error (send_message room text) with
      | Ok msg -> Effect.ignore_m (inject (Confirm { pending_id; msg }))
      | Error _ -> Effect.ignore_m (inject (Fail pending_id))
  in
  let%arr rows_view and history and draft and set_draft and send in
  let loading = if Option.is_none history then {%html|<p>Loading...</p>|} else Vdom.Node.none in
  {%html|
    <div>
      %{loading}
      %{Vdom.Node.Map_children.div rows_view}
      <input %{Vdom.Attr.(value draft @ on_input (fun _ t -> set_draft t))} />
      <button on_click=%{fun _ -> send draft}>Send</button>
    </div>
  |}

let app (graph @ local) =
  let room, set_room = Bonsai.state "general" graph in
  let body =
    Bonsai.scope_model (module String) ~on:room graph
      ~for_:(fun graph -> room_body ~room graph)
  in
  let%arr room and set_room and body in
  let tab r = {%html|<button on_click=%{fun _ -> set_room r}>#{r}</button>|} in
  {%html|<div>*{List.map [ "general"; "random" ] ~f:tab} %{body}</div>|}

let () = Bonsai_web.Start.start app
```

Server rendering: Bonsai has none (P15). The client downloads the compiled JavaScript, builds the graph, runs one stabilization and builds the DOM from nothing. The page would show an empty `<div id="app">` until the script runs. History is fetched after first display, in the `After_display` `on_change` of the poller.

Notes on the code:
- Awkward: the `rows` step merges three maps (history, live, pending) by hand into one keyed map, so that `assoc` has one key type. Bonsai gives no help here.
- `Effect.Ignore` and `Effect.ignore_m` come from the docs. Unverified.

P-items exercised:
- P1 (child gets `room` as a `Bonsai.t`, parent owns room), P2 (`actor`, `state_opt`, `state`), P3 (`room` into `Edge.Poll`, lifecycle, `send`).
- P4 and P5: `let%arr` nodes for `rows`; `assoc` with a body that creates no nodes (so it should compile down to `Incr_map.mapi`).
- P6: `send` and `fetch_history` are effects. P7: `Edge.lifecycle` for the socket. P8: `Edge.Poll.effect_on_change` for the history load.
- P9: `Poll` drops stale history responses. Nothing cancels the old fetch.
- P10: `history : Msg.t list option`, `None` shows "Loading...". The history effect has no error type in the brief, so no error branch.
- P11: `assoc` over a `Key` map. P13: optimistic message via `pending`. P14: `Effect.try_with_or_error`.
- P15: none.

Awkward or unverified:
1. `on_deactivate` closes the socket read from state. If the room changes while `open_socket` is still pending, `socket` is `None`, nothing is closed, and the late socket leaks. Bonsai has no cancel (P9). A real version would need a state machine that holds "opening" and "open" and closes on arrival.
2. `scope_model` keeps one copy of state per visited room, and keeps it when you leave. When you come back, the old `history`, `live` and `pending` are still there, so old messages show before a refetch. Whether `on_change` fires again on reactivation of the same key I did not verify (the doc comment says the callback runs the first time the node becomes active). The model is not reset on leaving; wrapping with `with_model_resetter` would do that.
3. I use the outer `room` in `on_activate`. That is the new room at activation time, which is what I want, but I did not confirm the order in which `scope_model` updates `room` and runs the effects.
4. `actor` has one return type for all actions, so the `-1` returns are dummies. Only `Add_pending` needs a response (the pending id). The `Actor` functor (`cont.mli`) gives per-action response types, but I did not use it.
5. Server confirmation can arrive on the socket (`Receive`) before `send_message` returns. The message then shows twice: once as `Pending`, once as `Confirmed`, until `Confirm` removes the pending one. The `live` map is keyed by `msg.id`, so the same message arriving twice does not duplicate.
6. If the user switches rooms before `send_message` returns, `inject` targets the old room's actor (inactive). I did not verify that actions on inactive state are applied.
7. Failed sends are removed silently (`Fail`). No error shown.
8. Event handler names (`on_click`, `on_input` inside `ppx_html`) follow `README.md` and `testing.md`. Other docs use `on_click_js_of_ocaml`. I did not check which one is current for `{%html|` attributes.

## Sources

Cloned with `git clone --depth 1` into `/tmp/claude-2020/bz` (the `$TMPDIR` of the sandbox) and read there.

| Source | Status |
|---|---|
| github.com/janestreet/bonsai: `README.md`, `CHANGES.md`, `changelog.md`, `bonsai.opam`, `src/bonsai.mli`, `src/cont.mli`, `src/cont.ml` (Poll part), `src/proc.ml` (Edge.Poll), `ppx_bonsai/readme.md` | read (partial: `cont.mli` read in ranges, not all 1768 lines) |
| github.com/janestreet/bonsai_web: `docs/quick_start.md`, `docs/bonsai_best_practices.md`, `docs/tips_and_tricks.md`, `docs/guide/{fundamentals,thinking_in_bonsai,bonsais_lifecycle}.md`, `docs/guide/structuring_bonsai_code.md` (first 120 lines), `docs/how_to/{bonsai_runtime,organizing_state,effects_and_stale_values,rpcs,testing,state_per_key,resetting_state,time,dynamic_scope,url_var}.md` (parts), `docs/advanced/how_bonsai_works.md`, `docs/upgrade/{readme,local-graph}.md`, `docs/blog/history.md` (first 80 lines), `web/bonsai_web.mli`, `web/effect.mli`, `web/rpc_effect.mli`, `web/start_experimental.mli` | read |
| `bonsai_web/docs/how_to/{partial_render_table,forms,focus,low_level_vdom,uri_parsing,benchmarking,javascript_interop,var,effects_for_browser_apis}.md`, `docs/archive/*`, `docs/blog/proc.md` | not read (not needed) |
| github.com/janestreet/bonsai_web_test: `README.md`, `proc.mli` | read |
| github.com/janestreet/bonsai_test | cloned, file list only (not read) |
| github.com/janestreet/bonsai_examples: `effect_poller/main.ml`; file list | read (one example) |
| github.com/janestreet/incremental: `src/incremental_intf.ml` (lines 95-135), file list | read |
| github.com/janestreet/virtual_dom: `README.md`, `ui_effect/src/ui_effect_intf.ml`, `ui_effect_of_deferred/*.mli`, `src/attr.mli` (greps) | read |
| github.com/janestreet/ui_effect | failed (clone asked for authentication; the code is inside `virtual_dom/ui_effect`) |
| github.com/janestreet/bonsai_term, `ppx_html`, `ppx_css`, `incr_map`, `polling_state_rpc`, `bonsai_web_components` | not read |
| https://bonsai.red and https://bonsai.red/ (WebFetch) | read, summary only: nav list (introduction, virtual_dom, dynamism, state, forms, effect, flow, css, edge triggering). The fetch did not show which API it uses. Not relied on |
| https://blog.janestreet.com/introducing-incremental/ (WebFetch) | read (summary by the tool): variables, observers, `stabilize`, `bind` |
| https://blog.janestreet.com/seven-implementations-of-incremental/ | read; no technical content on stabilization or cutoff (talk link only) |
| https://blog.janestreet.com/oxidizing-ocaml-locality/ | read (summary): `local` means a value does not escape its region; does not mention Bonsai |
| WebSearch "Jane Street blog Bonsai web UI framework incremental" | returned opam pages only; no blog post found |
| signalsandthreads.com episodes, tyoverby.com/composition-comparison | not read |
| `/home/me/workplace/davesnx/yuka/brain-dump/reactivity.md` | read (Bonsai lines only via grep) |

Claims marked "(memory)" in the text: that `virtual_dom` (JavaScript) skips same-reference subtrees (P5), and that stock OCaml does not enforce `local_` while OxCaml does (Model). Claims marked "I did not verify" are not backed by a source I read.
