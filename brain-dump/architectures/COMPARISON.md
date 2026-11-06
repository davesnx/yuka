# React, Elm and Bonsai side by side

Built only from `react.md`, `elm.md` and `bonsai.md` in this folder. No recommendation for Yuka. "(memory)" means the source document marks the claim as unverified. "unclear in source" means the document does not say.

## Models in one paragraph each

**React (19).** A component is a function from props to JSX, a description. Each update has a render phase (call functions, diff, no DOM change) and a commit phase (apply minimal DOM operations). State lives in React, not in the function. It is found by the component's position in the tree and by hook call order. A setter queues an update. React then re-calls the changed component and all components below it, unless `memo` or React Compiler skips them. Effects run after commit.

**Elm (0.19.1).** A program is `init`, `update`, `view` and `subscriptions` plus a runtime. One immutable `Model` holds all state. Every event is a `Msg` value. `update` is the only producer of a new `Model`. `Cmd` and `Sub` are values, not actions; the runtime performs them through effect managers. After each `Msg` the whole `view` runs, the virtual tree is diffed, and patches go to the DOM at most once per animation frame. Ports connect to JavaScript.

**Bonsai.** A component is an OCaml function `graph -> 'a Bonsai.t`. A `'a Bonsai.t` is a node in a static incremental graph, a value that changes over time. The graph is built once. State is created by calling primitives with `graph`; identity is the position in the static graph. There is no `bind`. Variable structure comes from `match%sub`, `Bonsai.assoc` and `scope_model`. On a change, Incremental recomputes only dependent nodes and stops where a value is unchanged (`phys_equal` by default). The view is a `Vdom.Node.t Bonsai.t`, diffed once per frame. It targets Js_of_ocaml.

## Problems

| ID | Problem | React | Elm | Bonsai |
|---|---|---|---|---|
| P1 | Unit of composition | Function from props to JSX; data down as props, callbacks up, context for far links — new callback each render; lifting state re-renders more | Not a component; function plus type. Nested TEA wraps `Model` and `Msg` — "Actively trying to make components is a recipe for disaster"; wrapping code per level | Function `graph -> Bonsai.t`; pass `Bonsai.t` down, return values up, controllable `?state`, `Dynamic_scope` — every `Bonsai.t` needs `let%arr`; no component tag in `ppx_html` |
| P2 | Local state | `useState`; identity is tree position plus hook call order — hooks in conditions break; nested component definition resets state | None. All state in one `Model`; "local" state is a field or variant the parent owns — widget state threaded through parent | `Bonsai.state`, `state'`, `state_machine`, `actor`; identity is static graph position — setter is itself a `Bonsai.t`; state kept while inactive |
| P3 | Props and inputs | Plain values; new props object each render, no subscription — anything reacting to change needs Effect or derivation | Plain arguments to view functions; child view called again on each draw — nothing says "prop X changed" | Every changing input is a `Bonsai.t`; child node recomputes when dependency changes — inactive branch has no fresh input |
| P4 | Derived state, memoization | Compute in render; `useMemo`, `memo`, `useCallback`, or Compiler; `Object.is` — new object each render defeats `memo`; `useMemo` is not a guarantee | Compute in `view` or store in `Model`; `Html.Lazy.lazy` compares arguments with `===` — only last result kept; author cannot supply `equal` | `let%arr` nodes memoized by construction; `phys_equal` default, `Bonsai.cutoff ~equal` overrides — equal but separately built values count as changes |
| P5 | Update granularity | Component and everything below re-runs; DOM diff; `memo` or Compiler skips — work scales with subtree size | Whole `view` re-runs and is diffed; `lazy` skips subtrees — no dependency tracking; nested update defeats root `lazy` | One `let%arr` or primitive; stops at unchanged values — `assoc`, `match%sub` overhead; vdom diff still starts at root (memory) |
| P6 | One-shot effects | Event handler; React 19 Actions through transitions — state updates after `await` lose transition scope; handler errors skip boundaries | `Cmd` from `update`; result returns as a `Msg`; `Http.Error` forces handling — context must travel in the `Msg` | Handler returns `unit Effect.t`; `Rpc_effect`, `Effect.of_deferred_fun` — effect closes over old values; use `Bonsai.peek` |
| P7 | Long-lived effects | `useEffect(setup, deps)` with cleanup; `useSyncExternalStore` — deps list must satisfy lint; Strict Mode double setup | `subscriptions : Model -> Sub Msg`, runtime diffs the list; ports for sockets — socket lifetime stays in JavaScript; no `WebSocket` package in 0.19 | `Edge.lifecycle` (`on_activate`, `on_deactivate`); `Clock.every`; `Poll` — no subscription primitive; handle kept in state by hand |
| P8 | "When X changes, do Y" | No on-change hook; ladder: derive, handler, `key`, set state in render, Effect — Effect cannot tell mount from change; no `(prev, next)` callback (memory) | Put the reaction in the `update` branch that changes X; old model is available there — nothing checks that a path forgot it | `Edge.on_change`, `on_change'` with previous value — runs once per frame; docs discourage it ("less declarative") |
| P9 | Cleanup and cancellation | Effect returns cleanup; `ignore` flag or `AbortController` — manual; `ignore` does not stop the request | Runtime removes dropped `Sub`s; `Http.cancel` best-effort; `Process.kill` — late results guarded by hand with a key in the `Msg` | `on_deactivate`; `Poll` drops older results; `Effect_throttling` — "`Effect` does not support cancellation in general"; old request still runs |
| P10 | Async data, loading, error | Manual `status` in state, or `use(promise)` with `Suspense` and error boundary — promise must be cached; `use` not in try/catch | Custom type in `Model` (`Loading`, `Failure`, `Success`); compiler checks all cases — no boundary that waits for a group; chains by hand | No resource type; `Poll.effect_on_change` gives `option`; `Rpc_effect.poll` response states — `None` means "no result yet"; no built-in error type |
| P11 | Keyed lists | `key` on each mapped element; state follows identity — missing key is a runtime warning; changed key remounts | `Html.Keyed.node`; diff matches by key — keeps DOM identity only; duplicate keys silently renamed | `Bonsai.assoc` over a `Map`; each row owns state; `Map_children.div` diffs by key — plain `Vdom` lists diff by index; `assoc` costly when nested |
| P12 | Batching, scheduling | Updates in a handler batched into one render; everywhere since React 18; `flushSync` — no batching across separate events | Each `Msg` runs `update` in order; draws collapse to one per animation frame — no priorities; `Cmd.batch` order not guaranteed | Everything batched per frame (`requestAnimationFrame`); one view diff per frame — lifecycle state changes wait for next frame |
| P13 | Transitions, deferred, optimistic | `useTransition`, `useDeferredValue`, `useOptimistic` — controlled input cannot be in a transition; optimistic failure only reverts | none — transitions and deferred values unavailable; optimistic by hand with a `pending` list | none — no priorities, no interruptible rendering; optimistic by hand with pending items in state |
| P14 | Error handling | Class error boundary for render errors; React 19 root handlers — does not catch handlers or async; class required | Errors are values (`Result`, `Maybe`); compiler enforces — no error boundary (memory); bad port data and flags crash | `Or_error.t Bonsai.t`, `Effect.try_with_or_error`; "never" raise — no error boundary found; behavior of exceptions in `let%arr` not verified |
| P15 | Server rendering, hydration | `renderToPipeableStream`, streaming, `hydrateRoot`, Server Components — mismatch bugs; RSC needs framework | none built in; `Browser.element` virtualizes existing DOM; `elm-pages` for pre-render — how `elm-pages` hydrates was not read | none — "Bonsai does not currently support server-side rendering"; no hydration code found |
| P16 | Testing | `act()` plus React Testing Library; tests drive DOM and events — forgetting `act` warns; effect timing needs mocks (memory) | `elm-test`; pure `update`; `Test.Html.Query`; `elm-program-test` — `Cmd` is opaque (memory); no integration solution | `Bonsai_web_test` with `ppx_expect`; `Handle.show`, `click_on`, `advance_clock_by` — runs in Node; async tests slow, unstable; RPC tools "still in their infancy" |
| P17 | Debugging | DevTools, `Profiler`, Chrome performance tracks, Strict Mode, lint — no built-in replay (memory); "why did this render" not on pages read (memory) | `elm make --debug`: message history, time travel, export and import — effects not replayed; `lazy` misses not reported (memory) | `Debug.on_change_print_s`, `debug_node`, `watch_computation`, `to_dot`; expect tests — browser debugger status unchecked |
| P18 | Stale reads, footguns | State is a snapshot per render; updater functions, deps, Effect Events, refs — long list of traps (stale timers, missing deps, nested components) | No stale closures; handlers hold `Msg` values — late results need a manual guard; `lazy` with fresh records misses | Effects close over old values; `Bonsai.peek`, `state'` — physical-equality cutoff; side effects in `let%arr`; mutable values break change detection |
| P19 | Boilerplate, learning curve | Small core, many layers (Effects, memo, Suspense, Actions, RSC) — no measured source; observation from docs structure | Small language; one architecture — nesting needs `Msg`, `Model`, `Cmd.map`, `Html.map` per child; ports need JavaScript | Many concepts before a first stateful app; `let%arr` for each use — API changed twice in about four years; unchecked style rules |
| P20 | Typing guarantees | Typed props, state, events via `@types/react` — hooks rules, deps, keys not type-checked; children cannot be constrained | Closed `Msg` type; exhaustive `case`; `Html msg` carries message type — ports and flags unchecked on JS side | `graph` is `local_` (when modes enforced); no `Bonsai.t Bonsai.t`; typed `Effect.t` — types do not check cutoff, stale closures, state ownership |

Details: react.md / elm.md / bonsai.md, section P<n>. For example, P9 is `### P9 Cleanup and cancellation` in each file.

## Chat room: what was awkward

Each document wrote its own chat room. The helpers differ (see the end of `## Gaps in the evidence`). The points below are those each document lists.

| P-item | React | Elm | Bonsai |
|---|---|---|---|
| P1, P2 | Reset on room change runs in an Effect; one commit shows old messages. `key={room}` fixes it but replaces the instance | Parent and chat share one `Model` | `scope_model` keeps one state copy per visited room; old messages show on return; reset needs `with_model_resetter` |
| P7 | Both Effects need `[room]`; socket callback may fire after `close()` | Socket lifetime is in JavaScript, not tied to the model; a `Sub` cannot express it; forgotten `joinRoom` splits room and socket | Socket closed from state; if the room changes while `open_socket` is pending, the late socket leaks |
| P8 | Reload on `room` is an Effect | `enter` helper is the only protection against a forgotten reaction | Order of `scope_model` room update and effects not confirmed |
| P9 | Strict Mode fetches twice and opens socket twice in development | `Http.cancel` is best-effort; late-data guards are manual | Nothing cancels the old fetch; `Poll` drops the stale response |
| P10 | `messages`, `status`, `sendError` are separate values; invalid combinations are possible | `History` custom type avoids this | No error branch for history (the brief had no error type) |
| P11 | Optimistic row has a temporary id; key changes, `<li>` remounts | Keyed by `clientId`; no remount | `Pending`/`Confirmed` key type; `rows` step merges three maps by hand |
| P13 | `setMessages` after `await` needs `startTransition`; optimistic row can flash | Client id counter needs a session id from `flags`; `ws.send` can throw while connecting; pending item can stay forever | `actor` has one return type, so `-1` dummies; failed sends removed silently; confirmation may arrive via socket first |
| P14 | On a caught send error the form still resets; text lost; `fetchHistory` errors by hand | Incoming port values decoded in `update` to avoid crash | Failed send gives no error shown |
| P18 | `send` closes over `room`; room switch adds message to the new list | Room tag needed on late results | `inject` after a room switch targets an inactive actor; effect on inactive state not verified |
| Merge | History and socket race; merge code written by hand; dedupe by id | Merge by `clientId` written by hand | Merge by hand; `on_change` on reactivation not verified |
| Other | none | Code not compiled | Code not compiled; `ppx_html` handler names (`on_click`) unverified |

## Where they agree, where they differ

Agree:
- P1, P3: all three pass data to children as values. Children get changes by being given new values.
- P6: in Elm and Bonsai an effect is a value that the runtime performs. In React a handler runs the work directly.
- P12: all three batch several changes before showing the result. The unit differs: one event handler (React), one animation frame (Elm, Bonsai).
- P13: none of the three offers a built-in optimistic update except React (`useOptimistic`). Elm and Bonsai do it by hand with a pending list.
- P14: Elm and Bonsai both advise errors as values (`Result`, `Or_error.t`). React uses class boundaries for render errors.
- P15: neither Elm nor Bonsai has a built-in server renderer. Elm can virtualize existing DOM; Bonsai builds the DOM from nothing.
- P16: all three can test through rendered output (DOM, `Html` query, vdom text).
- P18: React and Bonsai both have effects that read old values. Elm does not, because handlers hold `Msg` values.
- P19: all three documents report extra concepts or boilerplate as the app grows (React layers, Elm nesting, Bonsai `let%arr` and graph).

Differ:
- P2: state identity is tree position plus call order (React), position in one `Model` value (Elm), position in the static graph (Bonsai).
- P2: unmounted state is dropped in React and on an Elm variant switch. Bonsai keeps it while a node is inactive.
- P4: equality is `Object.is` (React), `===` (Elm), `phys_equal` (Bonsai). Only React (custom `arePropsEqual`) and Bonsai (`cutoff ~equal`) let the author replace it.
- P5: recompute unit is the component subtree (React), the whole view (Elm), one graph node (Bonsai).
- P7, P9: effect lifetime comes from deps (React), from the `Model` through `subscriptions` (Elm), from node activity (Bonsai).
- P8: React has no on-change hook. Elm uses the `update` branch. Bonsai has `Edge.on_change`.
- P9: Elm and Bonsai note best-effort or no cancellation of in-flight work. React uses `ignore` or `AbortController` by hand.
- P10: React has `Suspense`. Elm and Bonsai have none and use data types or `option`.
- P13: React has transitions and deferred values. Elm and Bonsai have none.
- P15: React has server rendering, streaming and hydration. Elm has `elm-pages`. Bonsai has none.
- P17: Elm has export and replay of message history. React and Bonsai have no replay in the documents.
- P20: Elm's `Msg` is a closed type. Bonsai's `graph` is `local_`. React's rules (hooks, deps) are lint-level.
- Runtime target: React and Elm target JavaScript directly. Bonsai targets Js_of_ocaml. Melange is not covered in any document.

## Gaps in the evidence

Failed or missing sources:
- react.md: no failed sources. Not fetched: `useState` and `useReducer` pages, `useLayoutEffect`, `createRoot`, Testing Library docs, DevTools profiler docs. One claim in P4 (state bail-out) is second-hand from `async-react.md`.
- elm.md: failed: `elm-program-test` package page, two `elm-pages.com` doc pages (404), the "perfect bug report" article. The `elm-pages` hydration mechanism was not read. Source pages were summarised by a small model. Chat-room code not compiled.
- bonsai.md: `ui_effect` clone failed. `bonsai.red` was read as a summary only and not relied on. `bonsai_term`, `ppx_html`, `ppx_css`, `incr_map`, `polling_state_rpc` not read. `cont.mli` read in ranges. Chat-room code not compiled.

"(memory)" claims the table relies on:
- React: P6 no automatic cancel of handler work; P8 no `(prev, next)` callback; P16 effect timing needs mocks; P17 DevTools "why did this render" and no replay; P20 TypeScript does not check hooks, deps, keys.
- Elm: P7 effect managers limited to `elm/*` packages; P13 transitions workaround; P14 no error boundary or `try`; P15 no `renderToString` in `elm/html`; P16 `Cmd` is opaque; P17 `lazy` misses not reported; P20 no runtime exceptions in normal code.
- Bonsai: P5 JavaScript virtual-dom skips same-reference subtrees; Model: only OxCaml enforces `local_` (P20 relies on "when modes are enforced").

Statements marked "I did not verify" in `bonsai.md` and used here: P9 effect in flight when a node deactivates; P14 exceptions in `let%arr`; P17 browser debugger today; chat-room points about inactive actors and `on_change` on reactivation.

Chat-room inputs differ. React and Bonsai assume helper functions (`fetchHistory`, `openSocket`/`open_socket`, `sendMessage`/`send_message`). The Elm version uses an HTTP request and ports instead, and a client id echoed by the server. Room lists also differ (`general`/`react`/`ocaml`, `general`/`ocaml`/`elm`, `general`/`random`). The awkward points are therefore not strictly like for like.
