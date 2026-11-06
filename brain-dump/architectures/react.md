# React

This document describes React 19 as it is. It makes no recommendation for Yuka.

Notes on evidence. Every URL in `## Sources` was fetched with a tool that returns a summary of the page, not the raw page. Quotes below are as that tool returned them. A claim marked "(memory)" is not backed by a page I read.

## Model

**A component is a function from props to a description.** It returns JSX. JSX creates elements: plain objects that name a type (a tag or a component) and props (memory). An element is a description, not a live thing.

**Two phases.** React splits every update into render and commit.

- Render: React calls component functions. It compares the result with the previous result. It does not touch the DOM. Rendering must be pure: same inputs, same JSX, no change to outside objects. (render-and-commit)
- Commit: React applies the minimal DOM operations computed during render. Only now does the DOM change. (render-and-commit)
- After commit, the browser paints. Effects run after commit. Usually they run after paint. For a discrete event such as a click, they may run before paint. (useEffect, performance-tracks)

**State lives in React, not in the function.** The function runs from scratch each render. Local variables do not survive. React keeps state per component instance, and an instance is identified by its position in the tree: "React preserves a component's state for as long as it's being rendered at its position in the UI tree." A different component type at the same position, or removal, discards the state. A `key` becomes part of the position. (preserving-and-resetting-state)

**Hooks find their state by call order.** `useState` takes no name. The docs give this mental model: React holds an array of state pairs per component and an index that is reset to 0 before each render; each hook call takes the next pair. The docs say this is an illustration, not the real code. Hence the rule: call hooks at the top level, not in conditions or loops. (state-a-components-memory, rules-of-hooks) In the real implementation, hook state hangs off the fiber as a linked list (memory).

**Fibers.** A fiber is an object per component instance holding type, key, props, links to child, sibling and parent, and the work state. It is a unit of work, so React can pause, prioritize, reuse or abort work. A component has at most two fibers: the current one and the work-in-progress one, each the `alternate` of the other. (react-fiber-architecture; this is an unofficial 2016 note and says it may be outdated)

**How an update flows.**

1. An event handler or Effect calls a setter. The setter does not change the variable in running code. It queues an update and asks for a render. (state-as-a-snapshot)
2. Updates made before the handler ends are batched. React processes them after all handler code has run. (queueing-a-series-of-state-updates)
3. In the next render, React walks the queue in order: a value replaces, an updater function `n => n + 1` transforms. (queueing-a-series-of-state-updates)
4. React calls the component whose state changed, then every component below it. A child is skipped only if wrapped in `memo`, or compiled by React Compiler, and its props are equal. (render-and-commit, memo)
5. Commit changes only the DOM nodes that differ. Then effects run: cleanup of the old effect first, then setup of the new one. (render-and-commit, useEffect)

**Concurrent rendering.** Render can be interrupted and restarted. The UI stays consistent because DOM changes wait until the whole tree is evaluated. It is on only where a concurrent feature is used: transition, deferred value, Suspense. (react-v18) Internally, updates carry a priority ("lane") (memory). The Performance tracks show four: Blocking, Transition, Suspense, Idle. (react-performance-tracks)

**One more layer.** React Compiler is a build-time tool. It memoizes components and hooks so you write fewer `useMemo`, `useCallback` and `memo`. It depends on the Rules of React. It is optional. (react-compiler/introduction)

## Problems

### P1 Unit of composition (what a component is; parent/child communication)

**How React solves it.** A component is a function taking props and returning JSX. Data goes down as props. A child changes the parent by calling a function the parent passed as a prop. Nested JSX arrives as the `children` prop. Shared state is lifted to the closest common parent. Context gives data to any descendant without passing it through each level. Components are first-class values, so they can be passed as props.

```tsx
function Panel({ isActive, onShow }: { isActive: boolean; onShow(): void }) { /* ... */ }
<Panel isActive={i === 0} onShow={() => setActive(0)} />
```

The docs call a component with its own state "uncontrolled" and one driven by props "controlled". (sharing-state-between-components, passing-props-to-a-component)

**Cost.** Callbacks are plain functions, so the parent creates a new function each render. That matters for memoization (P4). Lifting state can force many components to re-render (P5). A child cannot read or change a parent's state except through what the parent passes. (sharing-state-between-components)

**Source.** sharing-state-between-components, passing-props-to-a-component.

### P2 Local state (where it lives, how it is created, how it gets identity)

**How React solves it.** `useState(initial)` returns `[value, setValue]`. React stores the value. Identity has two parts: the component's position in the render tree, and the hook's call order inside that component. Two copies of one component have isolated state. `useReducer` is the same mechanism with a reducer.

```tsx
const [count, setCount] = useState(0);
<Chat key={contact.id} contact={contact} /> // new key: new instance, fresh state
```

(state-a-components-memory, preserving-and-resetting-state)

**Cost.**
- Hooks in conditions or loops break the call order: "Rendered fewer hooks than expected." (state-a-components-memory)
- A component defined inside another component is a new type each render, so its state resets each render. (preserving-and-resetting-state)
- Moving a component to a different place in the tree can reset or keep state unexpectedly. The position, not the JSX, decides. (preserving-and-resetting-state)
- Updater functions must be pure. Strict Mode calls them twice in development. (queueing-a-series-of-state-updates)

**Source.** state-a-components-memory, preserving-and-resetting-state, queueing-a-series-of-state-updates.

### P3 Props and inputs (values or reactive; how a change reaches the child)

**How React solves it.** Props are plain values. Each render receives a new props object: "Props are read-only snapshots in time: every render receives a new version of props." There is no subscription. A child sees a change only because the parent re-rendered and called the child again with new props. A child cannot change its props. It asks the parent through a callback. (passing-props-to-a-component, render-and-commit)

```tsx
function ChatRoom({ room }: { room: string }) { /* runs again with the new room */ }
```

**Cost.**
- Because props are snapshots, anything that must react to a change needs an Effect (P8) or must be derived in render (P4).
- The default is that a child re-renders whenever its parent re-renders, even with equal props. `memo` opts out. (memo)
- `key` is not a prop. The child cannot read it. (rendering-lists)
- `ref` became an ordinary prop for function components in React 19. (react-19)

**Source.** passing-props-to-a-component, render-and-commit, memo, rendering-lists, react-19.

### P4 Derived state and memoization (who decides equality)

**How React solves it.** Derived values are computed in render: "When something can be calculated from the existing props or state, don't put it in state." For costly work, `useMemo(fn, deps)` caches the result. `memo(Component)` skips a re-render if props are equal. `useCallback` caches a function. (you-might-not-need-an-effect, useMemo, memo, useCallback)

Equality is decided in these places:
- Dependency arrays: `Object.is` per item. (useMemo, useEffect)
- `memo`: `Object.is` per prop by default. A custom `arePropsEqual(old, new)` can replace it. It must compare every prop, including functions. (memo)
- State bail-out: same value by `Object.is` means no re-render of the component or children. (useState, from async-react.md; see Sources)
- With React Compiler: the compiler inserts the caching. You do not choose. (react-compiler/introduction)

```tsx
const visible = useMemo(() => filterTodos(todos, filter), [todos, filter]);
```

**Cost.**
- `Object.is` on objects, arrays and functions says "different" for equal contents. `Object.is({}, {})` is false. One always-new prop defeats `memo` for the whole component. (memo)
- `useMemo` is "a performance optimization, not a semantic guarantee". React may discard the cache. (useMemo)
- Deep equality is discouraged because it can freeze the app. (memo)
- The deps list is written by hand. The linter requires every reactive value. (useEffect)
- The compiler memoizes only components and hooks, not every function, and needs code that follows the Rules of React. (react-compiler/introduction)

**Source.** useMemo, memo, useCallback, you-might-not-need-an-effect, react-compiler/introduction.

### P5 Update granularity (what recomputes after a change)

**How React solves it.** The unit is the component. A setter marks one component. React re-runs that component and all components below it. It then diffs the output and changes only the DOM nodes that differ. (render-and-commit) A component that reads a context re-renders when the context value changes, even inside `memo`. (memo) To cut work: move state down, pass JSX as `children`, use `memo`, or enable the compiler. (useMemo, memo, react-compiler/introduction)

**Cost.** Work scales with subtree size, not with the number of changed values. Most skipping is opt-in or compiler-made. The compiler targets update performance and does not share memoization across components. (react-compiler/introduction) A render is cheap to trigger but not free to measure: see P17.

**Source.** render-and-commit, memo, useMemo, react-compiler/introduction.

### P6 One-shot effects (e.g. fetch on click)

**How React solves it.** Put the work in an event handler. "You don't want to buy the product when the user visits a page; you want to buy it when the user clicks." For async work with pending, error and ordering handled, React 19 offers Actions: async functions run inside a transition, used through `<form action>`, `useActionState` or `useTransition`. (synchronizing-with-effects, react-19, useActionState)

```tsx
async function handleClick() { await fetch("/api/buy", { method: "POST" }); }
```

**Cost.**
- A handler is not part of render. React does not cancel it if the component unmounts (memory).
- Errors in event handlers are not caught by error boundaries. (Component)
- In a transition, state updates after `await` are not marked as transitions. Each needs its own `startTransition`. "This is a JavaScript limitation due to React losing the scope of the async context." (useTransition)
- Several overlapping Actions in a transition have no guaranteed order. (useTransition)
- `useActionState` queues calls and runs them one after another. A throw cancels the queued calls. (useActionState)

**Source.** synchronizing-with-effects, useTransition, useActionState, react-19, Component.

### P7 Long-lived effects (subscriptions, sockets, timers) and their lifetime

**How React solves it.** `useEffect(setup, deps)`. Setup returns a cleanup. React runs setup after commit. When a dep changes, React runs the old cleanup, then the new setup. On unmount it runs the cleanup. The docs say to think of one start/stop cycle, not mount/update/unmount: "An Effect can only do two things: to start synchronizing something, and later to stop synchronizing it." (synchronizing-with-effects, lifecycle-of-reactive-effects)

```tsx
useEffect(() => {
  const c = createConnection(serverUrl, roomId); c.connect();
  return () => c.disconnect();
}, [roomId]);
```

The lifetime is set by the deps. Values the Effect reads that should not restart it can go in an Effect Event (`useEffectEvent`), which always sees the latest props and state and is left out of the deps. It is listed as a React 19.2 feature. (separating-events-from-effects, react-19-2) `useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot?)` handles subscriptions to external stores. (useSyncExternalStore)

**Cost.**
- "You can't choose your dependencies." The lint rule must be satisfied. A function or object created in render is a new value each render, so the Effect restarts each time. (lifecycle-of-reactive-effects, useEffect)
- Strict Mode runs an extra setup, cleanup, setup in development. Missing cleanup shows up as a duplicate connection. (StrictMode)
- `useEffectEvent` has rules: call only inside Effects, never pass to other components or hooks. (separating-events-from-effects)
- `useSyncExternalStore` needs a cached snapshot, or it loops. A `subscribe` function created inline resubscribes each render. (useSyncExternalStore)
- Content hidden by `<Activity>` has its effects cleaned up. Hidden Suspense content has its layout effects cleaned up and restarted. (react-19-2, Suspense)

**Source.** synchronizing-with-effects, lifecycle-of-reactive-effects, useEffect, separating-events-from-effects, react-19-2, useSyncExternalStore, StrictMode.

### P8 "When X changes, do Y" (reacting to a prop or state change)

**How React solves it.** There is no "on change" hook. The docs give a ladder of answers:
1. Compute Y in render if Y is derived from X.
2. If Y is a reaction to a user event, put it in the event handler.
3. To reset state when a prop changes, change the `key`. `<Profile userId={userId} key={userId} />`.
4. To adjust some state during a prop change, store an ID and derive the rest, or set state during render (the docs say most components should not need it).
5. If Y syncs with an outside system, use an Effect with X in the deps.

(you-might-not-need-an-effect)

```tsx
useEffect(() => { fetchHistory(room).then(setMessages); }, [room]);
```

**Cost.**
- An Effect does not run "on change". It runs on mount and again on each dep change, so it cannot tell the two apart. The docs steer you to think "sync", not "react". (lifecycle-of-reactive-effects)
- Chains of Effects that set state to trigger each other are listed as an anti-pattern. (you-might-not-need-an-effect)
- Setting state in an Effect causes an extra render. (useEffect)
- To compare old and new values you must keep the old one yourself, in state or a ref. React has no `(prev, next)` callback (memory).

**Source.** you-might-not-need-an-effect, lifecycle-of-reactive-effects, useEffect.

### P9 Cleanup and cancellation

**How React solves it.** The Effect returns a cleanup function. For fetches, the pattern is a local flag, or an `AbortController`. Each Effect run has its own `ignore` variable, so stale responses are dropped. The cleanup should "ensure that the fetch that's not relevant anymore does not keep affecting your application."

```tsx
useEffect(() => {
  let ignore = false;
  fetchBio(person).then(r => { if (!ignore) setBio(r); });
  return () => { ignore = true; };
}, [person]);
```

(synchronizing-with-effects, you-might-not-need-an-effect)

**Cost.**
- Cleanup is by hand. Forget it and you get leaks or out-of-order results. Strict Mode exists to expose this. (StrictMode)
- The `ignore` flag drops the result but does not stop the request. The request still goes out; in development you may see two. (synchronizing-with-effects)
- Cancelling an Action is not always safe: aborting a request does not undo a server-side change. (useActionState)
- Handler-started async work has no cleanup hook (memory).
- Cleanup order: old cleanup before new setup, for every changed Effect. (useEffect)

**Source.** synchronizing-with-effects, you-might-not-need-an-effect, useEffect, useActionState, StrictMode.

### P10 Async data, loading and error states (Suspense and equivalents)

**How React solves it.** Two styles.

1. Manual: an Effect fetches, and the component keeps `status`, `data` and `error` in state (see Chat room).
2. Suspense: a component reads a promise with `use(promise)` during render. It suspends. The nearest `<Suspense fallback>` shows the fallback. A rejected promise goes to the nearest error boundary. The promise must be created outside render or cached, so the same instance is reused.

```tsx
<ErrorBoundary fallback={<p>Could not fetch.</p>}>
  <Suspense fallback={<Loading />}><Albums albumsPromise={p} /></Suspense>
</ErrorBoundary>
```

Triggers for Suspense: `lazy`, `use(promise)`, stylesheets with `precedence`, streaming SSR. "Suspense does not detect when data is fetched inside an Effect or event handler." A transition keeps already-revealed content on screen instead of showing the fallback again. Reveal is throttled to once per 300 ms. A suspended first render keeps no state. (use, Suspense)

**Cost.**
- The promise-must-be-cached rule is a footgun. `use(fetch(...))` in render makes a new promise each render. (use)
- `use` cannot be used in try/catch. Errors need a class boundary. (use)
- Without a framework or library you build the cache yourself. The docs say Suspense-enabled frameworks handle it. (Suspense)
- Manual style has race conditions (P9), waterfalls, no cache, and does not run on the server. (synchronizing-with-effects)
- How components suspend internally (a thrown promise) is not documented on the pages I read (memory).

**Source.** use, Suspense, synchronizing-with-effects.

### P11 Keyed lists and dynamic collections

**How React solves it.** Each element from `map()` gets a `key`. "Keys tell React which array item each component corresponds to." With a key, React matches items by identity, so moving, inserting and deleting keep each item's state. Without a key, React uses the index.

```tsx
people.map(p => <li key={p.id}>{p.name}</li>)
```

Rules: unique among siblings, stable, taken from data, not generated in render. (rendering-lists)

**Cost.**
- A missing key is a console warning at runtime, not a type error. (rendering-lists)
- Index keys cause "subtle and confusing bugs" when order changes. `Math.random()` keys rebuild everything and lose input. (rendering-lists)
- `key` is not passed to the child as a prop. (rendering-lists)
- A key is also the reset switch (P2). Changing it destroys the subtree's state. (preserving-and-resetting-state)
- Optimistic items need a temporary key. When the real ID arrives the key changes and the item remounts (see Chat room).

**Source.** rendering-lists, preserving-and-resetting-state.

### P12 Batching and scheduling of updates

**How React solves it.** React waits until all code in an event handler has run, then processes all queued updates in one render. Since React 18 this holds everywhere: timeouts, promises, native handlers. It does not batch across separate events such as two clicks. `flushSync` forces a synchronous update when code outside React needs the DOM now. Priority: updates are urgent by default. Transitions and deferred values are marked lower. (queueing-a-series-of-state-updates, react-v18, flushSync, react-performance-tracks)

```tsx
setCount(c => c + 1); setFlag(f => !f); // one render
```

**Cost.**
- Reading state right after the setter gives the old value (P18).
- `flushSync` can hurt performance, force Suspense fallbacks, and flush pending Effects. It does nothing inside render or Effects. (flushSync)
- Before React 18, batching covered only React handlers. Older code and articles describe that. (react-v18)
- A render scheduled during a render pass can make React discard finished work and restart ("cascading update"). (react-performance-tracks)

**Source.** queueing-a-series-of-state-updates, react-v18, flushSync, react-performance-tracks.

### P13 Concurrency: transitions, deferred values, optimistic updates

**How React solves it.**
- `startTransition` / `useTransition`: updates made in the call become non-urgent. They can be interrupted by urgent ones. `isPending` reports progress. (useTransition)
- `useDeferredValue(value)`: React renders first with the old value, then re-renders in the background with the new one. The background render is interruptible and restarts when the value changes. If it suspends, the old value stays. Compared by `Object.is`. (useDeferredValue)
- `useOptimistic(value, reducer?)`: shows a temporary value while an Action runs. When the Action ends, success or error, React renders the real `value`. With a reducer, React re-runs it if the base value changes while pending. (useOptimistic)

```tsx
const [rows, addPending] = useOptimistic(messages, (cur, m) => [...cur, m]);
```

**Cost.**
- A controlled text input cannot be in a transition. Use two state values or `useDeferredValue`. (useTransition)
- `useDeferredValue` helps a slow child only if the child is wrapped in `memo`. It does not stop network requests. (useDeferredValue)
- The `useOptimistic` setter must run inside an Action, or React warns and the value flashes. (useOptimistic)
- Optimistic failure only reverts. To tell the user why, catch the error and set state yourself. (useOptimistic)
- Transition markers are lost after `await` (P6).
- `<Activity>` (19.2) hides parts of the UI, defers their updates and unmounts their effects. (react-19-2)
- Concurrent features require pure render, since render can run more than once or be thrown away. (react-v18)

**Source.** useTransition, useDeferredValue, useOptimistic, react-19-2, react-v18.

### P14 Error handling (error boundaries)

**How React solves it.** An error boundary is a class component with `static getDerivedStateFromError` (choose the fallback state) and/or `componentDidCatch` (log). It catches errors thrown while rendering its descendants. "There is currently no way to write an Error Boundary as a function component." Most apps write one class once, or use the `react-error-boundary` package. React 19 adds root options `onCaughtError`, `onUncaughtError`, `onRecoverableError`. Errors thrown in a function passed to `startTransition`, and rejected `use` promises, reach the nearest boundary. Unknown errors from a `useActionState` action also do. (Component, react-19, useTransition, use, useActionState)

```tsx
<ErrorBoundary fallback={<p>Something went wrong</p>}><Profile /></ErrorBoundary>
```

**Cost.**
- Not caught: event handlers, async code such as `setTimeout`, server rendering, errors in the boundary itself. (Component)
- A class is required, in a library that otherwise uses functions. (Component)
- Expected failures (validation) should be returned as data, not thrown. The docs say so for `useActionState`. (useActionState)
- A boundary shows a fallback. It does not retry by itself. (memory)

**Source.** Component, react-19, useTransition, use, useActionState.

### P15 Server rendering and hydration (including streaming, RSC)

**How React solves it.**
- Render to HTML on the server: `renderToPipeableStream` (Node) or `renderToReadableStream` (edge). `renderToString` still works but is discouraged. (react-v18)
- Streaming: React sends the shell first, with Suspense fallbacks. When a boundary's data is ready it sends the HTML plus an inline script that swaps in the content. Streaming does not wait for React to load in the browser. `onShellReady` starts streaming. `onAllReady` waits for everything (for crawlers). (renderToPipeableStream)
- Hydration: `hydrateRoot(domNode, <App />)` attaches to the existing HTML and takes over the DOM. The client tree must produce the same output as the server. (hydrateRoot)
- Effects do not run on the server. "Effects only run on the client." (useEffect)
- Server error in a boundary: React emits the fallback and the client retries. (Suspense, renderToPipeableStream)
- `useSyncExternalStore` needs `getServerSnapshot` for server rendering. (useSyncExternalStore)
- Server Components render ahead of time, in a separate environment (build or per request). They can be `async` and read data directly. No state, hooks or effects. A `'use client'` module marks a client boundary. Props that cross it must be transferable. A Server Component can pass an unawaited promise to a client component that reads it with `use`. (server-components)
- 19.2 adds partial pre-rendering: pre-render the static shell, then `resume` rendering later. (react-19-2)

**Cost.**
- Mismatch causes: `typeof window` branches, `Date`, `Math.random`, browser-only APIs, extra whitespace. "You must fix them like other bugs." In the worst case, handlers attach to the wrong elements. (hydrateRoot, react-19)
- `suppressHydrationWarning` works one level deep and does not patch text. Two-pass render (state set in an Effect) makes hydration slower. (hydrateRoot)
- Effect-fetched data is not in the server HTML. (renderToPipeableStream)
- RSC needs a bundler or framework. Its implementation APIs do not follow semver. (server-components, react-19)
- A framework is needed for routing, caching and the RSC build; React alone gives the primitives. (server-components)
- The RSC wire format and selective hydration internals are not described on the pages I read (memory).

**Source.** renderToPipeableStream, hydrateRoot, Suspense, server-components, react-19-2, react-v18, useEffect.

### P16 Testing

**How React solves it.** `act()` applies pending updates and effects before assertions. Wrap render calls and event dispatch in `await act(async () => ...)`. The test environment needs `global.IS_REACT_ACT_ENVIRONMENT = true`. The docs recommend React Testing Library, whose helpers already use `act` and set the flag. Tests drive components through rendered DOM and events. (act)

```tsx
await act(async () => { button.dispatchEvent(new MouseEvent("click", { bubbles: true })); });
```

**Cost.**
- Forgetting `act` gives a warning and assertions on stale DOM. (act)
- The container must be attached to the document for DOM events. (act)
- The sync form of `act` is planned for deprecation. (act)
- Hooks and state have no public handle outside a component. Tests go through the DOM or a wrapper component (memory).
- Effects with timing (sockets, fetch) need mocks and manual flushing (memory).

**Source.** act.

### P17 Debugging: why did this render or effect run; devtools; replay

**How React solves it.**
- React Developer Tools: Components panel to inspect and edit props and state; Profiler panel for performance. (react-developer-tools)
- `<Profiler id onRender>`: reports `actualDuration` vs `baseDuration` per commit. Off in production builds by default. (Profiler)
- Performance tracks in Chrome (19.2): Scheduler track by priority and phase (Update, Render, Commit, Remaining Effects); Components track with render and effect durations. In development, clicking a render entry shows changed props. Cascading updates are flagged. (react-performance-tracks)
- Strict Mode: double render and double Effect setup in development, to expose impure render and missing cleanup. DevTools dims the second render's logs. (StrictMode)
- `eslint-plugin-react-hooks`: rules of hooks and exhaustive deps. (rules-of-hooks, react-19-2)

**Cost.**
- The pages I read do not mention "why did this render" or highlight-updates features. DevTools has them (memory).
- No built-in replay or time-travel. Redux DevTools-style replay comes from external libraries (memory).
- The cause of a re-run Effect is the changed dep. You find it by comparing deps by hand, or in DevTools (memory).
- Production profiling needs a special build. (Profiler, react-performance-tracks)
- Strict Mode doubled logs confuse some readers (memory).

**Source.** react-developer-tools, Profiler, react-performance-tracks, StrictMode.

### P18 Stale reads and common footguns

**How React solves it.** State is a snapshot per render: "Every render (and functions inside it) will always 'see' the snapshot of the state that React gave to that render." Handlers and Effects close over their render's values. The tools: updater functions to read the latest queued value, deps arrays and the linter, Effect Events for non-reactive reads, refs for mutable values that do not trigger renders. (state-as-a-snapshot, queueing-a-series-of-state-updates, useRef)

```tsx
setNumber(number + 5);
setTimeout(() => alert(number), 3000); // alerts the old value
```

**Cost.** The list of known traps from the docs:
- Setter does not change the variable; three `set(n + 1)` calls give +1. (queueing-a-series-of-state-updates)
- Timers and async code read old state. (state-as-a-snapshot)
- Missing deps give stale values. Suppressing the linter "lies" to React. (useEffect)
- Objects and functions made in render restart Effects. (useEffect)
- Effects run twice in development. Fix the cleanup. Do not add a run-once flag. (synchronizing-with-effects)
- Nested component definitions reset state. (preserving-and-resetting-state)
- Index or random keys. (rendering-lists)
- Do not read or write `ref.current` in render. (useRef)
- `useMemo` can drop its cache. (useMemo)
- Promise created in render passed to `use`. (use)
- `getSnapshot` returning a new object each call loops forever. (useSyncExternalStore)
- Hydration mismatches. (hydrateRoot)
- A custom `arePropsEqual` that skips a function prop leaves stale handlers. (memo)

**Source.** state-as-a-snapshot, queueing-a-series-of-state-updates, useEffect, synchronizing-with-effects, memo, useRef.

### P19 Boilerplate and learning curve

**How React solves it.** A small core: components, props, state, handlers. Extra concepts layer on: hooks and their rules, Effects, memoization, Suspense, transitions, Actions, Server Components. React Compiler removes most manual memoization. React 19 removes `forwardRef` need for new function components (`ref` is a prop) and adds Actions to cut form boilerplate (pending, error, reset). (react-19, react-compiler/introduction)

**Cost.** I did not find a primary source that measures learning cost. These are observations from the docs' own structure, not measured facts:
- The Learn section has separate pages just for Effects: synchronizing, lifecycle, separating events, removing dependencies, and "you might not need an effect".
- `memo`, `useMemo`, `useCallback` each carry caveats and "only if profiling shows" advice.
- Error boundaries need a class.
- Server Components need a framework and two directives with different meanings: `'use client'` marks a boundary, `'use server'` marks Server Functions, and "there is no directive for Server Components". (server-components)
- Several APIs have changed names or shape recently: `useFormState` became `useActionState`; `forwardRef` is going away. (react-19)

**Source.** react-19, react-compiler/introduction, server-components; the rest is from the shape of the Learn section (react.dev, observation).

### P20 Typing guarantees (React with TypeScript)

**How React solves it.** Types come from `@types/react` and `@types/react-dom`. Props are typed with an object type. `useState` infers from the initial value; give a union explicitly for state machines. `useReducer` types state and a discriminated action. `createContext` infers from the default. Event handlers have types like `React.ChangeEvent<HTMLInputElement>`. Children are `React.ReactNode` or `React.ReactElement`. (learn/typescript)

```tsx
type Status = "idle" | "loading" | "error";
const [status, setStatus] = useState<Status>("idle");
```

**Cost.**
- "You cannot use TypeScript to describe that the children are a certain type of JSX elements." (learn/typescript)
- A context with no default needs `| null` and a runtime check in a custom hook. (learn/typescript)
- The types do not check the rules of hooks, dependency arrays, or key presence. A lint plugin checks hooks and deps. A missing key is a runtime warning. (rules-of-hooks, rendering-lists; that TypeScript itself does not check them is (memory))
- Effect Event rules (call only in Effects) are lint-level, not type-level. (separating-events-from-effects)
- Suspense, boundaries, and the purity of render are not visible in types (memory).
- Values that cross the Server/Client boundary must be serializable. The docs do not say that types enforce it. (server-components)

**Source.** learn/typescript, rules-of-hooks, rendering-lists, server-components.

## Chat room

```tsx
import { startTransition, useEffect, useOptimistic, useState } from "react";

type Msg = { id: string; text: string };
type Row = Msg & { pending?: boolean };
type Status = "loading" | "ready" | "error";

declare function fetchHistory(room: string): Promise<Msg[]>;
declare function openSocket(room: string, onMessage: (m: Msg) => void): { close(): void };
declare function sendMessage(room: string, text: string): Promise<Msg>;

const ROOMS = ["general", "react", "ocaml"];
const upsert = (list: Msg[], m: Msg): Msg[] =>
  list.some((x) => x.id === m.id) ? list : [...list, m];

export function App() {
  const [room, setRoom] = useState(ROOMS[0]);
  return (
    <>
      <select value={room} onChange={(e) => setRoom(e.target.value)}>
        {ROOMS.map((r) => <option key={r}>{r}</option>)}
      </select>
      <ChatRoom room={room} />
    </>
  );
}

function ChatRoom({ room }: { room: string }) {
  const [messages, setMessages] = useState<Msg[]>([]);
  const [status, setStatus] = useState<Status>("loading");
  const [sendError, setSendError] = useState<string | null>(null);
  const [rows, addPending] = useOptimistic<Row[], Row>(messages, (cur, m) => [...cur, m]);

  useEffect(() => {
    let ignore = false;
    setMessages([]);
    setStatus("loading");
    fetchHistory(room).then(
      (history) => {
        if (ignore) return;
        setMessages((live) => live.reduce(upsert, history));
        setStatus("ready");
      },
      () => { if (!ignore) setStatus("error"); },
    );
    return () => { ignore = true; };
  }, [room]);

  useEffect(() => {
    const socket = openSocket(room, (m) => setMessages((cur) => upsert(cur, m)));
    return () => socket.close();
  }, [room]);

  async function send(form: FormData) {
    const text = String(form.get("text") ?? "").trim();
    if (!text) return;
    setSendError(null);
    addPending({ id: `pending-${crypto.randomUUID()}`, text, pending: true });
    try {
      const saved = await sendMessage(room, text);
      startTransition(() => setMessages((cur) => upsert(cur, saved)));
    } catch {
      setSendError("Could not send. Try again.");
    }
  }

  return (
    <section>
      <h2>#{room}</h2>
      {status === "loading" && <p>Loading history...</p>}
      {status === "error" && <p>Could not load history.</p>}
      <ul>
        {rows.map((m) => (
          <li key={m.id} style={{ opacity: m.pending ? 0.5 : 1 }}>{m.text}</li>
        ))}
      </ul>
      <form action={send}>
        <input name="text" />
        <button>Send</button>
      </form>
      {sendError && <p role="alert">{sendError}</p>}
    </section>
  );
}
```

**Server rendering and hydration.** The server renders `App` with `renderToPipeableStream`. Effects do not run there, so the HTML holds the room picker, the title, "Loading history..." and an empty list. No history, no socket. The client calls `hydrateRoot`. After hydration the two Effects run: history loads and the socket opens. To put history in the HTML, load it in a Server Component, or read a cached promise with `use` inside `<Suspense>`, and pass it to `ChatRoom` as initial data.

**P-items exercised.** P1 (parent passes `room`), P2 (three `useState`, one `useOptimistic`), P3 (`room` as snapshot prop), P6 (send action), P7 (socket Effect), P8 (reload on `room`), P9 (`ignore` flag, `socket.close`), P10 (manual loading and error), P11 (keyed list), P12 (batched `setMessages` and `setStatus`), P13 (`useOptimistic`, `startTransition`), P15 (server and client render differ by Effects), P18 (closure over `room`), P20 (types for state and props).

**Awkward points.**
- Both Effects need `[room]`. The reset (`setMessages([])`) runs in an Effect, so for one commit the new room's title shows the old room's messages. `<ChatRoom key={room} />` fixes this and drops the reset, but then the instance is replaced, not updated.
- History and socket race. A live message can arrive before history. The merge `live.reduce(upsert, history)` is code the user must remember to write.
- The socket callback can fire after `close()` if the helper does not guarantee otherwise. Then the old room's message enters the new room's list. A guard flag is needed if the helper does not promise silence after `close`.
- `send` closes over `room` from its render. If the user switches room before `sendMessage` resolves, `upsert` adds the saved message to the new room's list. A fix needs a ref updated in an Effect, or a room tag on `Msg`.
- The optimistic row has a temporary id. When the saved message arrives, the key changes and the `<li>` remounts. The helper API takes no client id, so the key cannot stay the same.
- The socket may deliver the saved message before `sendMessage` resolves. `upsert` by id prevents a duplicate, but only because the code dedupes.
- The setter after `await` needs `startTransition`, or the optimistic row can flash away before the real row is in state. This is the "scope lost after await" rule.
- On a caught send error the form still resets, because the action did not throw. The typed text is lost.
- Strict Mode in development fetches history twice and opens the socket twice. Cleanup makes this correct. It is still visible in logs.
- Status is three separate values (`messages`, `status`, `sendError`). Nothing prevents states like "error" with a full list. A reducer or a discriminated union is possible but not required by React.
- Errors from `fetchHistory` are handled by hand. Using `use` with Suspense would move them to an error boundary, a class component, and require a promise cache.

## Sources

Status "read" means the page was fetched and a summary came back. Where a page lacked a topic, the entry says so.

- https://react.dev/learn/render-and-commit: read.
- https://react.dev/learn/state-a-components-memory: read. The array-of-pairs model is described as an illustration.
- https://react.dev/learn/preserving-and-resetting-state: read.
- https://react.dev/learn/queueing-a-series-of-state-updates: read.
- https://react.dev/learn/state-as-a-snapshot: read.
- https://react.dev/learn/synchronizing-with-effects: read.
- https://react.dev/learn/lifecycle-of-reactive-effects: read.
- https://react.dev/learn/you-might-not-need-an-effect: read.
- https://react.dev/learn/separating-events-from-effects: read. It does not state whether `useEffectEvent` is stable.
- https://react.dev/learn/rendering-lists: read.
- https://react.dev/learn/sharing-state-between-components: read.
- https://react.dev/learn/passing-props-to-a-component: read.
- https://react.dev/learn/typescript: read.
- https://react.dev/learn/react-developer-tools: read, partial. No "why did this render" or highlight-updates content.
- https://react.dev/learn/react-compiler/introduction: read. It gives no version number.
- https://react.dev/reference/react/memo: read.
- https://react.dev/reference/react/useMemo: read.
- https://react.dev/reference/react/useCallback: read.
- https://react.dev/reference/react/useEffect: read.
- https://react.dev/reference/react/useRef: read.
- https://react.dev/reference/react/use: read.
- https://react.dev/reference/react/Suspense: read.
- https://react.dev/reference/react/useTransition: read.
- https://react.dev/reference/react/useDeferredValue: read.
- https://react.dev/reference/react/useOptimistic: read. Its message example is adapted by the fetch tool from the docs' `<form action>` example, not quoted from the page.
- https://react.dev/reference/react/useActionState: read.
- https://react.dev/reference/react/useSyncExternalStore: read.
- https://react.dev/reference/react/Component: read (error boundaries). `onCaughtError` and `onUncaughtError` are not on this page; they come from the React 19 post.
- https://react.dev/reference/react/StrictMode: read.
- https://react.dev/reference/react/Profiler: read.
- https://react.dev/reference/react/act: read.
- https://react.dev/reference/rules/rules-of-hooks: read. It does not state the call-order reason; the reason comes from state-a-components-memory.
- https://react.dev/reference/react-dom/flushSync: read.
- https://react.dev/reference/react-dom/client/hydrateRoot: read. It does not cover selective hydration or event replay.
- https://react.dev/reference/react-dom/server/renderToPipeableStream: read. It does not say outright that Effects do not run on the server; the useEffect page does.
- https://react.dev/reference/rsc/server-components: read. It has no serialization rules.
- https://react.dev/reference/dev-tools/react-performance-tracks: read.
- https://react.dev/blog/2022/03/29/react-v18: read. Selective hydration is only named.
- https://react.dev/blog/2024/12/05/react-19: read.
- https://react.dev/blog/2025/10/01/react-19-2: read. It lists `useEffectEvent` as a new feature but does not use the word "stable".
- https://github.com/acdlite/react-fiber-architecture: read. Unofficial, 2016, work in progress. It does not cover `memoizedState` or the render/commit phases.
- https://github.com/facebook/react/tree/main/packages/react-devtools: read, partial. No Profiler, "why did this render" or time-travel content.
- /home/me/workplace/davesnx/yuka/brain-dump/async-react.md: read as background only. One claim is taken from it: a state setter given the same value (`Object.is`) causes no re-render of the component or children (useState and useReducer pages, which I did not fetch myself). Treat that claim as second-hand.
- /home/me/workplace/davesnx/yuka/brain-dump/react-internals.md: read as background. Nothing taken from it that is not also from a source above.

Failed sources: none. Not fetched: the `useState` and `useReducer` reference pages, `useLayoutEffect`, `createRoot`, React Testing Library docs, the React DevTools profiler docs.

Claims marked "(memory)" in the body: element as plain object; hook state as a linked list on the fiber; lanes; no automatic cancel of handler-started work; no `(prev, next)` change callback; boundary does not retry itself; hook testing needs a wrapper; effect testing needs mocks; DevTools has "why did this render" and highlight updates; no built-in replay; how components suspend internally; RSC wire format; TypeScript does not check hook rules, deps or keys; Suspense and render purity are not visible in types.
