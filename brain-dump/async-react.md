# Async and concurrent React

## Sources

- https://react.dev/reference/react/useTransition: read.
- https://react.dev/reference/react/useDeferredValue: read.
- https://react.dev/reference/react/useOptimistic: read.
- https://react.dev/blog/2022/03/29/react-v18: read. The page does not mention `flushSync`.
- https://react.dev/blog/2024/12/05/react-19: read. No batching content.
- https://react.dev/reference/react/Suspense: read.
- https://react.dev/learn/react-compiler/introduction: read.
- https://react.dev/reference/react/useState: read.
- https://react.dev/reference/react/useReducer: read.
- Not fetched: the React Fiber architecture notes, the React Working Group threads, and the React source. Claims about React's internal queue (marked "background") come from general knowledge, not from a fetched page. Verify before relying on them.

## Key ideas

**Interruptible rendering (Fiber)**

- Concurrent React is opt-in: it is on only where a concurrent feature (transition, deferred value, Suspense) is used. Without one, an update renders "in a single, uninterrupted, synchronous transaction". (React 18 post)
- Rendering can pause and restart. The UI stays consistent because DOM mutations wait "until the end, once the entire tree has been evaluated". (React 18 post) This is the render/commit split from react-internals.md. It is why render must be pure.
- Stale work is discarded: React will "throw out the stale rendering work that wasn't finished and render only the latest update". (React 18 post)
- Suspended renders keep no state, so React retries from scratch when data is ready. (Suspense page)

**Blocking vs non-blocking updates**

- Urgent (blocking) updates: typing, clicking, pressing. They render first. Transition updates move the UI from one view to another and can be interrupted by urgent ones. (React 18 post)
- Default is urgent. Non-blocking is an opt-in marker on the update: `startTransition`, or a deferred value. Urgent updates are not delayed unless you opt in. (Suspense page)
- A controlled text input cannot be in a transition. Its value must update synchronously. Use two pieces of state, or `useDeferredValue`. (useTransition page)

**useTransition**

- Returns `[isPending, startTransition]`. The function passed is an "Action". (useTransition page)
- `startTransition` runs the callback at once. Only updates made during the synchronous call are transition updates. A `set` after `await` or inside `setTimeout` is not, unless wrapped in another `startTransition`. (useTransition page)
- Several ongoing transitions are batched together today. The docs say this may change. Action order is not guaranteed, so out-of-order async results are possible. (useTransition page)
- A transition that suspends does not show an already-revealed fallback again. The old UI stays and `isPending` is true. (useTransition, Suspense pages)
- Needs access to the setter. For props or custom hook values use `useDeferredValue`. (useTransition page)
- Errors thrown from an Action go to the nearest Error Boundary. (useTransition page)

**useDeferredValue**

- Two renders. First: urgent, with the old deferred value. Second: in the background with the new value. If the background render suspends, React abandons it and the old value stays on screen. (useDeferredValue page)
- The background render is interruptible and restarts on a newer value. No fixed delay, unlike debounce. (useDeferredValue page)
- Network requests are not deferred. Only display is. Effects in the background render run only after it commits. (useDeferredValue page)
- Inside a transition it returns the new value directly. It works only if the slow child is memoized, otherwise the child re-renders on each parent render. Pass primitives or stable objects, because comparison is `Object.is`. (useDeferredValue page)
- Show staleness with `query !== deferredQuery`. (useDeferredValue page)

**useOptimistic and Actions**

- `useOptimistic(value, reducer?)`: shows a temporary value while an Action runs. The real value comes back when the Action ends, success or failure. (useOptimistic page)
- The setter must run inside an Action, or React warns and the value flashes. (useOptimistic page)
- The optimistic value is a function of the real value plus the pending actions. If the real value changes while pending, the reducer is re-run on the new value. So the optimistic layer is derived, not stored. (useOptimistic page)
- Real and optimistic values converge in the same commit. There is no separate "clear" render. (useOptimistic page)
- React 19 Actions: async functions in transitions. React handles pending state, errors (to Error Boundaries), optimistic revert and request ordering for you. `useActionState` returns `[state, action, isPending]`. `<form action={fn}>` uses Actions and resets the form after success. (React 19 post)

**Automatic batching, and setState vs dispatch**

- Within one event, many `set` calls give one re-render. The screen updates after all handlers have run. (useState page)
- React 17: batching only inside React event handlers. Two updates in a `setTimeout` gave two renders. React 18: batched everywhere (timeouts, promises, native handlers), so one render. (React 18 post)
- `set` does not change the value in running code. The new value appears in the next render. Updater functions queue and apply in order: three `setAge(a => a + 1)` give +3. Three `setAge(age + 1)` give +1. (useState page)
- Same value (`Object.is`): no re-render of the component or its children. React may still call the component once before it bails out. (useState, useReducer pages)
- `dispatch` behaves the same: batched, same bail-out, stable identity. The docs describe `useReducer` as "very similar to `useState`". So for the question in the notes ("setState vs dispatch multiple rerenders"): by the docs, no difference in re-render count. Both batch and both bail out. The difference is where the update logic lives. (useReducer page) Background, not fetched: in React's source `useState` is implemented as a `useReducer` with a basic reducer, which is why they behave the same.
- `flushSync` opts out of batching to force an early update. (useState page: mentioned only; no detail fetched)
- Reducers, updaters and initializers must be pure. Strict Mode calls them twice in development. (useReducer page)

**Suspense**

- A boundary shows `fallback` while a child is not ready. Triggers: `lazy`, `use(promise)`, stylesheets with `precedence`, streaming SSR. Data fetched in an Effect or event handler does not trigger it. (Suspense page)
- `use` can be called conditionally, unlike hooks. The promise must be cached, not created during render. (React 19 post, Suspense page)
- Suspense plus transition: keep old content, do not hide it behind a spinner. A new boundary still shows its fallback. A `key` on the boundary forces a fresh fallback. (Suspense page)
- Reveal is throttled to once per 300 ms and boundaries that become ready together reveal together. (Suspense page)
- Server: the shell with fallbacks goes first, then each boundary streams in. Selective hydration lets parts hydrate independently. An error inside a boundary on the server emits the fallback, and the client retries. (Suspense page, React 18 post)
- Suspense is also an error-handling seam: a thrown error is retried on the client, then goes to the Error Boundary. (Suspense page)

**React Compiler**

- Build-time, a Babel plugin around a core compiler. It memoizes components, hooks and values, so `useMemo`, `useCallback` and `memo` are not needed. (Compiler page)
- Why: manual memoization is tedious and easy to get wrong. Example: an inline arrow in `onClick` defeats `memo` on the child even with `useCallback` elsewhere. (Compiler page)
- Needs code that follows the Rules of React (pure render, hook rules). (Compiler page)
- Limits: only components and hooks, not arbitrary functions. No sharing between components. Does not replace profiling. `useMemo`/`useCallback` stay as escape hatches, for example to stabilize an Effect dependency. (Compiler page)

## What this means for the library

**Must keep, if interruptible or non-blocking rendering is a goal**

- A pure render, and a commit that is one synchronous step. Without it, nothing else on this page works.
- Priority as data on the update: urgent or transition. Updates carry a lane; the scheduler picks the highest and may drop lower-priority work in progress.
- Updates as a queue with updaters (`fun old -> new`), applied at render time. This is what makes batching and optimistic layers correct. `set` as "replace with a value" is lossy.
  ```ocaml
  type 'a update = Set of 'a | Update of ('a -> 'a)
  ```
- A way to abandon and restart render, and to keep showing the old committed tree meanwhile.

**Can drop or do differently**

- *Compiler.* The need comes from "render re-runs everything and compares by reference". If components set up once and render reads tracked cells (see react-internals.md), unchanged parts are not recomputed at all. Memoization becomes the default and `memo` and `useMemo` disappear. If the library keeps the "re-run the function" model, OCaml has no JS-style cheap closure identity problem for records and variants (they are values), but Melange objects still compare by reference in dependency checks. A ppx that hoists constant subtrees and wraps handlers is a smaller tool than React Compiler. It only needs to see syntax, because OCaml types make purity visible: mutation and I/O are marked by `ref`, `<-` and effects in types and the stdlib. A ppx can also see call sites for slot ids.
- *Batching.* Choose a simple rule: updates made inside one event or one tick coalesce into one render. In Melange, flush with `queueMicrotask`. In native SSR there are no updates after render, so batching is irrelevant.
- *`useOptimistic`.* Model it as a derived layer, not a second state. It is a pure function of base state and a pending list:
  ```ocaml
  let optimistic ~base ~pending ~apply = List.fold_left apply base pending
  ```
  The pending list is dropped when the action ends, in the same commit that installs the real value. Make the "action" a real type so that calling the setter outside one is a type error, not a warning:
  ```ocaml
  Action.run (fun act ->
    Optimistic.add act (Todo.pending t);
    let%await saved = Api.save t in
    State.update todos (fun xs -> saved :: xs))
  ```
- *`useDeferredValue`.* A function from the live value to a lagging value, with a background render pass: `Deferred.make : 'a -> 'a` plus a stale test. A typed `'a Deferred.t = { live : 'a; shown : 'a }` makes staleness explicit instead of comparing two values by hand.
- *Suspense.* React uses a thrown promise (JS-only trick). In OCaml, three options:
  - exception `Suspend of unit Promise.t` caught by the boundary (works on Melange and native, but loses type information and is easy to swallow);
  - OCaml 5 effect `Await` handled by the boundary (native only; Melange has no effect handlers);
  - a typed result: `Remote.t = Loading | Failed of exn | Ready of 'a`, read through a function that forces the caller to handle each case. This is the most Elm-like and is type-safe, but not "suspending": each component handles `Loading`, or a boundary helper does it.
  Errors: the notes say "Suspense could catch errors and be type-safe". A `Boundary` component taking `~loading` and `~error:(exn -> node)` and a `Remote.t` child covers both, with no exception.
- *Actions and forms.* An Action is just an async function with a pending/error/result state machine. A type captures it: `type ('i, 'o) action = { run : 'i -> unit; state : 'o Remote.t }`. Ordering (last-wins vs queue) becomes an explicit parameter instead of a footgun.
- *Transition boundary of `await`.* React loses the transition context after `await`. In OCaml with a `let%await` ppx or an explicit `act` value (above), the context is carried by the value, so it is not lost.

**Melange vs native**

- Interruption and priority only matter on the client. Native SSR can render synchronously in one pass, or stream: render the shell, emit boundary placeholders, emit chunks when each `Remote` resolves. A streaming SSR needs the same boundary type on both sides, so make the boundary a core concept.
- JS is single-threaded, so a lane queue is simple on Melange. Native with multiple domains needs per-request render state. Keep the scheduler state in a value passed to the renderer, not in globals.
- `queueMicrotask`, `MessageChannel` and `requestIdleCallback` are host functions. The same host interface that handles DOM nodes handles time.
- Promises: Melange has JS promises. Native uses Eio, Lwt or direct-style fibers. The core should depend on an abstract `Async` signature, not either.

## Tensions

- **Interruptible render vs simple model.** Interruption needs purity, an update queue with lanes, and the ability to throw work away. That is most of Fiber. If it is not needed in v1, a plain synchronous render plus Suspense-like boundaries covers most real use.
- **Typed `Remote` vs "suspending" ergonomics.** React's thrown promise keeps component code straight-line. The typed variant is safer and more explicit but spreads `match` through the tree. A boundary helper with `~ready:(fun a -> node)` reduces that.
- **Fine-grained cells vs transitions.** Transitions rely on rendering a second, speculative tree while the first stays on screen. Signal graphs update in place. Two worlds need a version or a copy of state. This is a design cost that React pays with `alternate` trees.
- **Batching vs read-your-own-writes.** React says the new value appears next render. In a cell model, `State.get` right after `State.update` is tempting to make immediate. Pick one and say so.
- **Compiler vs ppx.** The user wants no compiler. A ppx can do syntax-level work only. It cannot know that a value is stable across renders, unless types or a `memo`-like annotation say so.
- **Optimistic revert on error.** React reverts to the real value and does nothing else. The user probably wants the error as data too, so the action type needs to expose it.

## Open questions

- Is interruptible rendering a goal for v1, or only non-blocking in the sense of "async data does not block the shell"?
- Do transitions and deferred values exist at all, or does the library offer only Suspense-like boundaries and Actions?
- Which Suspense encoding: exception, effect, or typed `Remote.t`? Can the same choice work on Melange and native?
- Is an update "urgent" by default, as in React, or must the user choose?
- Does the `Action` value carry the transition context, so that no code needs "wrap again after await"?
- How does streaming SSR hand off to client hydration: re-render, or resumability (the notes mention it)? Not covered by these sources.
- Not read: React's internal lane model and the `act` testing story. Read the source or the React Working Group notes if lanes matter.
