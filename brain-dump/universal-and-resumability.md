# Universal code and resumability

## Sources

Status is per URL. Items marked "background" below are my own prior knowledge, not read in this session. Verify before relying on them.

- https://brumate-docs.vercel.app/ - read. Landing page only (v0.5.2). The serialisation format is inferred from one compiled Counter example. The page does not document it.
- https://qwik.dev/docs/concepts/resumable/ - read. It does not explain `$` or the optimizer.
- https://qwik.dev/docs/advanced/optimizer/ - read. It does not state rules for captured values.
- https://github.com/ml-in-barcelona/server-reason-react - read (README via fetch, twice). Silent on `browser_only`, virtual libraries, hydration and dune setup.
- https://raw.githubusercontent.com/ml-in-barcelona/server-reason-react/main/README.md - read. Same content as above.
- https://docs.astro.build/en/concepts/islands/ - read. Does not cover prop serialisation.
- https://react.dev/reference/rsc/server-components - read. No full list of serialisable prop types. Hydration not detailed.
- https://melange.re/v5.0.0/build-system/ - failed (HTTP 404).
- https://melange.re/v5.0.0/ - read, but it has no page on native/Melange sharing. Nothing learned.
- https://markojs.com/docs/explanation/fine-grained-bundling/ - failed (HTTP 404).
- WebSearch "Marko 6 tags API resumability" - read results. Only 2021 preview material. Nothing on serialisation internals.
- Not attempted: Js_of_ocaml docs, Qwik docs on `useLexicalScope` limits, React hydration internals (selective/progressive). Those sections below are background.

## Key ideas

- Resumability means no re-execution on the client. The server serialises state, listeners and component boundaries into the HTML. The browser continues from there. (Qwik resumable page; brumate landing)
- Qwik closures cannot be serialised as values. The optimizer finds each `$` and moves the expression to a top-level exported symbol in a lazy chunk. The HTML holds a reference `chunk.js#symbol`. Variables the closure captures from outer scope are passed as an explicit array (`qrl(chunk, 'Counter_onClick', [count])`), which the handler reads with `useLexicalScope()`. Only that captured array must be serialisable. (Qwik optimizer page)
- Qwik serialises circular refs, Date, URL, Map, Set, Promise, DOM refs and QRLs. It cannot serialise class instances or Streams. Fallback: run on the client only. (Qwik resumable page)
- Qwik uses one global listener (Qwikloader). On an event it downloads the named chunk and runs the symbol. (Qwik resumable page)
- brumate does the same without closures in the payload. Handlers are exports of a client module, and the DOM names them: `b-on="click=Counter_ud6oco#h2"`. State goes in a `b-state` script as plain values (`{0:{k:1,m:"Counter_ud6oco",s:[0,0]}}`). A handler gets the state object (`($$s) => $$b.update($$s, 0, 1, false)`). A dependency map records which state slots feed which memos and text nodes. Text that can change gets a comment marker (`<!--t0:1-->`). Counter client entry: 439 B (238 B gzip). (brumate landing; inferred from one example)
- brumate's compiler knows statically which parts are interactive, so non-interactive elements ship zero JS. It exposes `brumate inspect` to report what ships. (brumate landing)
- RSC splits components into server (never shipped, can be async, no state) and client (`"use client"`, hydrated). A server component passes props and JSX children to a client component as serialised output. Promises can cross the boundary and a client `use(promise)` suspends inside a Suspense boundary. (React RSC page)
- Astro islands: the page is static HTML. Each `client:*` directive (`load`, `idle`, `visible`) opts one component into hydration, independently of the others. `server:defer` makes a server island that streams in later. (Astro islands page)
- server-reason-react shares code through per-platform implementations behind one name: `url_js` binds to `window.URL`, `url_native` uses `opam-uri`. It reimplements or stubs `js`, `belt`, `promise`, `fetch`, `webapi`, `dom` for native, so components compile on both. `ppx_platform` drops code per platform with `let%melange_only`, `switch%platform`, `[@melange_only]`, `[@native_only]`. A `melange_ppx` adds Melange attributes to native code. RSC support: a `ReactServerDOM` streaming module, an esbuild plugin mapping client components, Dream integration, a typed router. Parts are marked experimental. (server-reason-react README)
- Background, not verified here: Marko 6 compiles to fine-grained signals and serialises only the values that cross from server to client. Because the compiler traces where each value is used, it can leave out state and code the browser never needs.
- Background, not verified here: React hydrates by re-running the component tree on the client and matching it to the server DOM. A mismatch warns in dev and may fall back to client rendering of the nearest Suspense boundary. Selective hydration lets Suspense boundaries hydrate independently and in event-priority order. Streaming SSR sends HTML chunks as Suspense boundaries resolve.
- Checked (2026-11-04, dune 3.21.1, Melange 6.0.1): one library can declare `(modes native melange)` directly. With `(lang dune 3.8)` and `(using melange 0.1)`, `dune build` exits 0 and produces both `core.cmxa` and `core.cmj`. A `melange.emit` stanza is still needed to output JS. Not checked: per-platform code through `(implements ...)` virtual libraries or `(select ... from ...)`.
- Background, not verified here: Js_of_ocaml compiles OCaml bytecode to JS. The same OCaml source runs on native and in the browser with no second compiler, and closures work as normal values. It does not give a serialisation story.

## What this means for the library

The central question: what is the unit sent from server to client? Three options, from least to most ambitious.

### Option A: Hydrate (the React model), done well

The client runs the same component code, creates the same tree, and attaches to the existing DOM.

- Same code on both sides, no serialisation of closures. Closures stay on the client because they are re-created by running the component.
- Need to ship the state the server computed so the first client render matches. Only data is serialised.
- Cost: all component code ships and runs once, even for static parts.

Sketch of the state transfer. Each piece of state needs a codec, so type safety replaces the guesswork:

```ocaml
module Codec : sig
  type 'a t
  val int : int t
  val string : string t
  val list : 'a t -> 'a list t
  val record2 : ... (* or ppx deriving *)
end

val use_state : codec:'a Codec.t -> 'a -> 'a * (('a -> 'a) -> unit)
```

On native, `use_state` writes `(id, encoded)` into a `<script type="application/json">` blob. On Melange, it reads the blob by the same `id`. IDs come from the position in the tree, so the server and client must walk the tree in the same order. An alternative is a ppx that gives each call site a stable key, which also removes the "rules of hooks" problem from the notes.

Trade-off: simple and robust, but it does not reach the "nothing renders twice" goal.

### Option B: Islands with typed props

Only marked components get client code. Everything else is server-only HTML.

```ocaml
(* island marks a client boundary; props must have a codec *)
let%island counter ~initial:(int) = ...
```

A ppx generates, for the native side, a function that renders the HTML and a `data-island="Counter" data-props="..."` wrapper. On the Melange side it generates a registry entry that hydrates the wrapper. Props crossing the boundary are restricted by type to what the codec supports. A function prop is a compile error. This is the RSC rule ("props must be serialisable") enforced by OCaml types instead of runtime errors.

- Matches the existing server-reason-react split (`ppx_platform`, esbuild plugin for client mappings).
- Typed children could be handled by letting an island take server-rendered `Html.t` children as opaque pre-rendered HTML, like RSC children.
- Trade-off: the author must decide where the boundaries are. Still hydrates inside each island.

### Option C: True resumability, via defunctionalised handlers

The Qwik trick in OCaml terms: a closure is not a value, but a pair of (code pointer, captured data). A ppx can make that pair explicit:

```ocaml
let%component counter () =
  let count = State.make ~codec:Codec.int 0 in
  Html.button
    ~on_click:[%handler fun () -> State.set count (State.get count + 1)]
    ...
```

`[%handler e]` would:

1. Find free variables of `e` (here `count`).
2. Lift `e` to a top-level function `counter_on_click : State.t -> unit -> unit` in a module the client bundle exports.
3. Replace the site with `Handler.make ~id:"Counter#on_click" ~captures:[State.pack count]`.

On native, `Handler.make` serialises `(id, captures)` into an attribute. On the client, a small global listener (like Qwikloader) reads the attribute, looks up `id` in a table, unpacks the captures with their codecs, and runs the function. The table can be filled lazily per module with Melange's `import()` bindings, so the code of untouched components never loads.

What makes this feasible in OCaml:

- OCaml has a typed AST in ppx and a clear free-variable analysis. Qwik needs a custom Rust optimizer for the same step.
- Pure OCaml values (records, variants, lists, options) have simple, typed codecs that can be derived (`ppx_deriving_yojson`, `ppx_sexp_conv`, or a custom one). Closures are the only non-data value, and `[%handler]` removes them.
- Melange compiles to ES modules per OCaml module, so a lifted handler in its own module maps to its own chunk.

What makes it hard:

- A handler may capture another closure (a callback prop, a `Fun`-typed value). The ppx must reject it, or recursively lift it. Rejecting at compile time is the honest choice: "captures must be serialisable" as a type error.
- Component identity: the server must tell the client "state slot 2 of component instance X". The brumate form (`{id:{k,m,s}}` plus a dependency map) suggests a compiler pass assigns slots statically. This requires that the library knows the reactive graph at compile time, which fits a signals model better than the "re-run the whole function" model of React.
- Effects: an effect is also a closure. It should run only on the client and only after a trigger. Options: `Effect.on_client [%handler ...]`, or an effect that has no captures beyond serialisable state and can run lazily when a dependency changes.
- Re-render after resume: resuming means a handler runs, mutates state, and something must update the DOM without the component function ever running on the client. brumate does it with a dependency map and text markers. In the library this means fine-grained signals that point at DOM nodes, not a virtual DOM that re-runs the function. That is a larger design choice than it looks (see Tensions).

### Which parts must be identical, which may differ

Identical on both platforms:

- Component functions and props types.
- The HTML element and attribute types (one `Html` module, as tyxml does).
- State and effect type signatures, and the codecs.
- Event handler types (opaque on the server).
- Escaping rules and the exact DOM shape produced (otherwise hydration mismatches).
- Ordering rules for state IDs.

May differ per platform (use dune virtual library or `implements`):

- `Dom`/`Window`/`Storage` access: client only. Make these a separate library that does not exist on native, so a server-side reference is a link error, not a runtime crash. This is stronger than a `browser_only` ppx that deletes code. Cost: it needs library boundaries, not just expressions.
- `Effect` execution: native no-op for client effects, real on Melange.
- Data fetching: native can run it during render (async server components) while client uses fetch.
- Scheduler/commit phase: native is a single string-building pass with no commit phase.
- Randomness, time, locale: must be passed in from the server to avoid mismatch.

Sketch of the dune side (check against the dune docs before use; this is from background):

```
(library (name yuka_core) (modes melange native) ...)   ; shared
(library (name yuka_platform) (virtual_modules platform)) ; interface
(library (name yuka_platform_js) (implements yuka_platform) (modes melange))
(library (name yuka_platform_native) (implements yuka_platform) (modes native))
```

### Hydration mismatch handling

- Dev: the client checks the DOM against the expected tree while hydrating and reports the path and the first differing node. Cheap to do when the library controls both sides.
- Prod: the least bad default is to replace the mismatched subtree by a client render and log. A full-page fallback is simpler but slow.
- Prevention by types: values that can differ between server and client (`Date.now`, `Math.random`, `window.innerWidth`) get a distinct type such as `'a Client_only.t`. They can only be read in effects or handlers, never in render. This is something React cannot do and OCaml can.
- Under Option C there is no hydration, so no mismatch of this kind. Instead the risk is stale or lost state in the payload. A version/hash of the payload schema is needed so an old cached page does not meet new client code.

### Streaming

Both native and Melange can support async boundaries with Suspense-like nodes. The server flushes the shell and then each boundary when its promise resolves, with a small inline script that swaps the fallback. This is the same on any of options A to C and does not need new ideas. server-reason-react already streams RSC payloads. Note that native OCaml needs an async story (Lwt, Eio, or Dream's) chosen early.

## Tensions

- Resumability needs a reactive graph the compiler can see. React-style "re-run the function, diff" does not give that. The "Simplify React" notes (Elm, mobx, lwd, incremental) lean toward a graph, but Elm's model is a full re-run of `view` with a diff, which is the opposite. Pick one before picking Option C.
- Closure capture analysis in a ppx is easy for syntactic free variables, but OCaml's type-directed features (module-level values, labelled args, partial application, GADTs) make "is this value serialisable?" a type question. A ppx alone sees syntax. A full guarantee needs a type-level trick such as requiring a `Codec.t` witness per capture, which is verbose.
- "Remove need for compiler (Melange does all the work or a ppx does)" versus resumability: Option C needs a build step that splits modules into chunks and a runtime loader. A ppx can lift handlers, but chunking is the bundler's job (esbuild/rollup). So at least a bundler plugin is needed.
- Hook order removal: stable per-site keys from a ppx would solve it, but they also tie the state of a component to its source location. Hot reload and refactors then change IDs. A server-rendered page with old IDs meets new client code.
- Universal from day one costs API surface. Every browser API must be absent or stubbed on native. server-reason-react shows this is a long tail (it re-implements `js`, `belt`, `promise`, `fetch`, `webapi`, `dom`).
- Melange value representation: options, variants, lists and records compile to JS in a specific shape. A codec must go through that shape on the client and a different one on native. Keep codecs as OCaml values, not `Obj` or `JSON.stringify` on raw Melange values (see the melange-advanced skill on value identity).
- Small client versus rich OCaml stdlib: Melange already adds the OCaml runtime bits it uses. Brumate-like 238 B entries will not happen with OCaml's `Printf`, `Format`, or polymorphic compare in scope. Resumability's size win may be smaller than in JS.

## Open questions

- Is the target "no hydration cost" (Option C) or "same code both sides, simply" (A/B)? This single choice decides the reactive model, so it should be settled early.
- Signals/graph or virtual DOM? What does the Elm influence mean here: `view : model -> html` re-run every time, or lazy/memoised views?
- Which codec mechanism: ppx-derived per type, or hand-written combinators? Does `State.make` require a codec always, or only for state that must cross the boundary (a separate `State.local` that is never serialised and so cannot be read during server render)?
- Can the library tell, by type or by ppx, which state is serialised and which is client-only?
- How does server data loading work: async components, loaders per route, or effects only on the client?
- Which server runtime on native: Dream, Eio, Lwt? This decides the streaming API.
- What bundler step is acceptable: esbuild plugin like server-reason-react, or `melange.emit` alone with dynamic `import()`?
- How do effects that sync with the outside world run on a resumed page: lazily on first dependency change, or eagerly on load?
- Needed follow-up reading (not done): Qwik's `useLexicalScope` limits, Marko 6 compiler output, server-reason-react's hydration code and its `browser_only` ppx source, dune's docs on `implements` and `(modes melange native)`, React's hydration mismatch recovery.
