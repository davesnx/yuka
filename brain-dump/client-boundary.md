# Client boundary: `<Yuka.Client>`

Status: proposal. Nothing here is a decision. Checks are in
`/tmp/claude-2020/-home-me-workplace-davesnx-yuka/49cf5768-41a7-44d9-9d3e-d5dbfb9b5d22/scratchpad/client-boundary`.

## Sources

- React `'use client'`: https://react.dev/reference/rsc/use-client
- server-reason-react, commit `f3ec120` (local checkout
  `/home/me/workplace/ml-in-barcelona/server-reason-react`):
  `packages/server-reason-react-ppx/server_reason_react_ppx.ml:1272-1286`,
  `:1660-1710`, `:1800-1830`; `packages/esbuild-plugin/extract_client_components.ml`;
  `demo/universal/native/shared/Counter.re`.
- Astro directives: https://docs.astro.build/en/reference/directives-reference/
- Fresh islands: https://usefresh.dev/docs/concepts/islands
- Leptos islands: https://book.leptos.dev/islands.html
- Qwik: https://qwik.dev/docs/concepts/resumable/, https://qwik.dev/docs/advanced/dollar/
- Marko 6 and Solid Start: from memory, not read for this note.

## Prior art, and what each gets wrong for Yuka

| System | How client code is marked | Props across | Problem for Yuka |
|---|---|---|---|
| React `'use client'` | A string at the top of a file. Applies to the module and everything it imports. | Serialisable values, JSX, promises, server functions. Others "throw an exception" at runtime. | The boundary is on the import graph, not the render tree. One file decides for all callers. Errors are at runtime. A directive is not OCaml. |
| server-reason-react | `[@react.client.component]` on the definition. | The ppx derives `of_rsc`/`to_rsc` from type annotations. Missing annotations and arrow types are ppx errors (`:1276`, `:1309`). | Arrow check is syntactic: `type cb = unit -> unit` is not seen as a function (inferred from the code at `:1279-1286`, not tested). Needs `--shared-folder-prefix` because native and JS sources live in two folders (`:1803`, comment refers to dune#10630). The manifest comes from `// extract-client` comments scanned in compiled JS. Code needs `switch%platform` for setters. |
| Astro | `client:load / idle / visible / media / only` at the call site. No directive: static HTML. | Not stated on the directives page. | Call-site choice is good. Astro is a separate template language, so no type check of props. |
| Fresh | A file in `islands/`. | Listed serialisable types, JSX, Preact signals. Functions not supported. | Folder convention, runtime checks. Signals as props (shared state between islands) is a good idea. |
| Leptos | `#[island]` on the definition. Feature flag `islands`. | Props are serialised with serde. Children from server components are passed in and "not hydrated". Context works across islands. | Definition-site only: a component cannot be static in one place and an island in another. |
| Qwik | No boundary. The optimizer splits each `$` closure into a chunk; listeners load on event. | Captured values must be serialisable and `const`. | Needs a whole-program optimizer and a bundler, not a per-file ppx. This is "resumability level 2" in `universal-and-resumability.md`. |

## Constraints from Yuka

- One codebase, compiled to native (server) and Melange (client).
- The ppx sees syntax only, one file at a time. It sees no types. So a call
  site cannot learn the prop types of a component in another module.
- Dune: a library with `(modes native melange)` cannot use a native-only
  library in Melange mode. Checked below: the Melange build fails with
  `Unbound module Db`. So server-only code (database, secrets) lives in a
  native-only library, and it can never reach the JS bundle.

That gives a three-library layout:

- `app_ui` (`native melange`): components, including client entries.
- `app_server` (`native`): pages, data access. Depends on `app_ui`.
- `app_client` (`melange.emit`): the JS entry. Depends on `app_ui` only.

## Options

### Option A: call-site wrapper, plus a mark on the definition

```ocaml
(* app_ui/counter.mlx *)
let%client make ~(initial : int) ~(shared : int State.t) ~children () =
  let count, set_count = State.of initial in
  <div onClick=(fun _ -> set_count (count () + 1))>
    (Yuka.text (fun () -> string_of_int (count () + shared ())))
    children
  </div>

(* app_server/page.mlx *)
let make () =
  let shared, _ = State.of 10 in
  <main>
    <Header />
    <Yuka.Client start=`Visible>
      <Counter initial=3 shared>
        <p>"Rendered on the server, never re-run on the client"</p>
      </Counter>
    </Yuka.Client>
  </main>
```

What the ppx does:

- On `let%client make`:
  - It keeps `make` as it is.
  - It derives a props codec from the type annotations.
  - It adds `Counter.client`, which returns a `Yuka.Client.entry`.
  - It emits the module path as the reference.
  - It is an error if an annotation is missing, as in server-reason-react.
- On `<Yuka.Client>`:
  - The single child must be an uppercase component call. Otherwise it is
    a ppx error.
  - The ppx rewrites it to
    `Yuka.Client.island ~key:<call-site key> ~start:`Visible (Counter.client ~initial:3 ~shared ~children:[...] ())`.
  - If the component has no `let%client`, `Counter.client` does not exist,
    and the compiler reports `Unbound value Counter.client`. The message is
    poor; the ppx cannot do better, because it cannot see other modules.

Good:
- The caller chooses where code becomes interactive and when it starts, as in
  Astro. The same component can still render as static HTML elsewhere.
- Both marks are OCaml syntax. No directive, no folder convention.

Bad:
- Two marks for one idea.
- The child of `<Yuka.Client>` must be one direct component call. A
  fragment, an `if` or a list is a ppx error.

### Option B: mark on the definition only (Leptos, server-reason-react)

```ocaml
let%island make ~(initial : int) ?(start = `Load) () = ...

<Counter initial=3 start=`Visible />
```

Good: one mark, and every call is an island.

Bad:
- A component cannot be static in one place and interactive in another.
- `start` becomes a prop of every island. This mixes the component's props
  with runtime settings.
- It is the `'use client'` model moved from the file to the definition. The
  user asked for a component, not this.

### Option C: no boundary; infer it (Qwik, Marko 6)

The server records which components created State, Effect or handlers, and
ships only those.

Good: nothing to write.

Bad:
- It needs whole-program splitting: a bundler plugin and a ppx that lifts
  closures. This is resumability level 2, which is still open in
  `DECISIONS.md`.
- The user loses control of the bundle. Debugging "why is this in my JS" is
  hard.

Keep C as a later target. Option A's runtime format can stay the same if Yuka
moves to C.

## Recommendation (proposal)

Option A, with these rules.

### 1. The boundary in mlx

`<Yuka.Client start=...>` wraps exactly one component call. The component
needs `let%client` on its definition. The ppx turns the pair into
`Yuka.Client.island`.

### 2. Props across the boundary

- **What is allowed:** a prop is allowed only if its annotated type has a
  codec. That covers:
  - int, string, bool, float, option, list, array and result;
  - records and variants with derived codecs;
  - `'a State.t`;
  - a slot (see 4).
- **How a bad prop fails:** the codec is chosen by type name, as in
  ppx_deriving. A function, or an alias of a function (`type cb = unit ->
  unit`), has no codec, so the build fails with `Unbound value cb_codec`.
  This is a compile error, not a runtime error, and it works through aliases.
  Checked (`bad_fn_prop`).
- **The cost:** the error text is about a missing codec, not about client
  props.
- **A getter is not a plain function.** A State getter must be told apart
  from any `unit -> 'a` closure. Two types for `'a State.t`:
  - `type 'a t = private unit -> 'a` makes `count ()` a type error ("This
    is not a function; it cannot be applied"). Checked. That would break the
    agreed `count ()` form.
  - `type 'a t = ?state:tag -> unit -> 'a`, where `tag` is an empty type.
    Here `count ()` still works, and a plain `fun () -> 10` passed as
    `int State.t` is a type error. Checked (`ok`, `bad_getter_prop`).
- **What a State prop does:** it crosses as a shared cell with an id. Two
  islands that get the same State share it after resume, as Preact signals
  do in Fresh. Not checked at runtime: only the encoding was checked.
- **Server functions** are the one kind of function allowed as a prop. Not
  designed here: see the server-actions note.

### 3. Reference and loading

- **What the server emits:**
  `<yuka-island data-ref="Counter" data-key="..." data-start="visible" data-props="...">`
  followed by the server HTML of the island.
- **`data-ref`** is the module path. It says which code to load.
- **`data-key`** is the typed call-site key from the ppx, plus the position
  in a list when there is one. It says which instance this is. It is also the
  root of the ids for the island's State when the client resumes.
- **Registry:** the build makes a map
  `{ "Counter": () => import("./app_ui/counter.js") }` from the
  `let%client` marks. The bundler splits one chunk per island module.
- **How the build finds the marks:** server-reason-react scans compiled JS
  for comments. A dune rule that runs a small Yuka tool over the sources is
  the alternative. Not decided, not checked.
- **What the bundle holds:** the island modules and what they import from
  `app_ui`. `app_server` is never compiled to JS.
- **One source path:** a single `(modes native melange)` library has one
  source path for both targets. So server-reason-react's
  `--shared-folder-prefix` work-around should not be needed. Inferred, not
  checked.

### 4. Server-rendered children (slots)

- **What crosses:** the island's `children`, or any prop typed as an
  element, is rendered on the server and sent as HTML inside the island. It
  is not in the island's JS, and the client adopts its DOM nodes.
- **What the island can do with it:** place it, and move it. It cannot
  inspect it or re-render it. This is Leptos's rule and React's "children as
  slots".
- **Nesting:** a slot can hold another `<Yuka.Client>`. That nested island
  starts on its own.

### 5. State, Effect, Async on each side

- **Element type:** elements carry a phantom type, `'a Yuka.element`, with two
  values:
  - `client`: an element with an event handler or a dynamic hole such as
    `Yuka.text (fun () -> ...)`.
  - `'a`: a static element, usable in both kinds.
- **How the types connect:**
  - A page must be `Yuka.server Yuka.element`.
  - The body of a client entry is `Yuka.client Yuka.element`.
  - `Yuka.Client.island` returns `Yuka.server Yuka.element` (first `'a`, changed 2026-11-05 so that an island inside client code is a type error).
- **Handlers and holes are compile errors outside an island.** An `onClick`
  or a dynamic hole outside any island fails to compile on both targets
  ("Type Yuka.client is not compatible with type Yuka.server"). Checked
  (`bad_handler`, `bad_hole`).
- **Static elements stay usable on both sides.** The phantom is covariant
  (`type +'a t`), so a static element bound with `let` stays polymorphic.
  The same `header` value is used in a server page and in a client slot.
  Checked (`ok`).
- **Effect outside an island cannot be a compile error.** Effects are calls
  in the component body, not elements, and there is no context argument to
  carry a phantom: the user rejected the `graph` argument. Proposal: the
  server renderer reports, in development, an Effect created outside every
  island. Not checked.
- **State outside an island:** allowed, but nothing can set it after the
  page is sent. So it is a render-time value, unless it is passed into an
  island as a prop (see 2).
- **Async outside an island:** allowed. It resolves on the server and
  streams. Inside an island, a result already resolved on the server needs a
  codec, so it can be sent instead of fetched again. Touches the open resume
  decision.

### 6. Start strategy

- **The values:** `start` takes `` `Load ``, `` `Idle ``, `` `Visible `` or
  `` `Interaction ``. `` `Media of string `` can come later.
- **The default:** `` `Load ``. It is the least surprising.
- **`` `Interaction ``:** the delegated `document` listener from melact's DOM
  layer catches the first event, loads the chunk, then replays the event.
  The replay is not checked.

### 7. Nesting and server content

- **An island in a slot of another island:** allowed (see 4).
- **`<Yuka.Client>` inside a client body:** allowed by the types. It means a
  separate chunk with its own start strategy. The same prop rules apply, so
  there is one rule to learn.
- **Server-only content in a client component:** the client can show it only
  through slots, or by calling a server function. It cannot import server
  code: `app_ui` fails to build in Melange mode if it uses a native-only
  library.

## Where this touches server actions

- A server function is the one function type allowed as an island prop.
  `let%client` codec derivation needs to recognise it, as server-reason-react
  does with `Runtime.server_function`.
- The call-site key and the module path could also identify an action. The
  actions design should decide whether it shares this scheme.

## Checks

The setup (dune 3.21.1, Melange 6.0.1):

```
eval "$(opam env --switch=5.2.0 --set-switch)"
cd /tmp/claude-2020/-home-me-workplace-davesnx-yuka/49cf5768-41a7-44d9-9d3e-d5dbfb9b5d22/scratchpad/client-boundary
```

Each library is `(modes native melange)`. Each error below appeared twice,
once for each target. The code is a hand-written stand-in for what the ppx
would generate: there is no ppx yet.

- **Good case (`ok`):** `dune build ./ok ./okbin/run.exe ./okjs` exits 0.
  The native run and `node` print the same line:
  ```
  <div><div>static</div><yuka-island data-ref="Counter" data-key="page.ml:7:10" data-start=visible data-props='3,{"cell":10}'><div data-on><!--hole-->13<div><div>static</div></div></div></yuka-island></div>
  ```
- **`bad_handler`:** an `on_click` in a page outside an island gives
  "Type Yuka.client is not compatible with type Yuka.server". Exit 1.
- **`bad_hole`:** a dynamic hole outside an island gives the same error.
  Exit 1.
- **`bad_getter_prop`:** `~shared:(fun () -> 10)` for an `int State.t` prop
  gives "This function should have type ?state:Core.State.tag -> unit -> int
  but its first argument is unlabeled". Exit 1.
- **`bad_fn_prop`:** a prop of type `cb = unit -> unit` gives
  `Unbound value cb_codec`. Exit 1.
- **Private getter type:** `type 'a t = private unit -> 'a` makes `count ()`
  fail with "This is not a function; it cannot be applied".
- **`bad_dep`:** a dual-mode library that uses a native-only library. The
  native build passes. The Melange build fails with `Unbound module Db`.
  Exit 1.

Not checked:
- the ppx itself;
- the registry build step;
- code splitting;
- the start strategies and event replay;
- shared State cells at runtime;
- the claim that server-reason-react's arrow check misses aliases;
- Marko and Solid Start.

## Open questions

- Two marks (`let%client` and `<Yuka.Client>`), or accept Option B's single
  mark?
- The `?state:tag` trick changes the type of every getter. Does it hurt type
  errors, or Melange output size, in normal use? This bears on the agreed
  `(count, set)` shape.
- Shared State across islands: wanted, or should only values cross?
- Effect outside an island: a development warning, or a design where effects
  are elements, so the phantom type can catch them?
- Phantom types on every element show up in user signatures and error
  messages. Is that cost acceptable?
- The default start strategy.
- How the build collects `let%client` marks.

## Nested `<Yuka.Client>` is a type error (checked 2026-11-05)

Change in the scratch project: `Client.island` returns `Yuka.server Yuka.element` (was
`'a Yuka.element`). A slot is typed `Yuka.server Yuka.element` and enters a client body through
`Yuka.slot : server element -> client element`.

- `dune build ./ok ./okbin/run.exe ./okjs ./ok_slot`: exit 0. Native and node
  print the same HTML. `ok_slot` puts an island inside the slot of another
  island.
- `dune build ./bad_nested` (an island inside a client body): exit 1 on
  native and Melange, "This expression has type Yuka.server Yuka.element but an
  expression was expected of type Yuka.client Yuka.element".
- The earlier failure cases still fail (exit 1).

Hole: `Yuka.slot` turns any server element into a client element, so a user
call `Yuka.slot (Client.island ...)` inside a client body type-checks. Only the
ppx may insert `Yuka.slot`, for the `children` slot; it must not be in the
public API.

Rename (2026-11-05): the scratch library is now one flat module, `Yuka`
(`yuka/yuka.ml`), with `type 'kind element`, `type server`, `type client`,
and the submodules `State`, `Codec` and `Client`. All cases rebuilt with the
same exit codes; errors now read "This expression has type
Yuka.client Yuka.element but an expression was expected of type
Yuka.server Yuka.element".

Lowercase tags (2026-11-05): `Yuka.div` is replaced by
`Yuka.lower : string -> 'k attribute list -> 'k element list -> 'k element`,
the call the ppx will generate. `Yuka.on_click : ... -> client attribute`,
`Yuka.attr : string -> string -> 'k attribute`. All valid cases build (exit 0,
same HTML on native and node); all five failure cases still fail (exit 1) with
the same messages.

State API change (2026-11-06): State is now abstract, `'a Yuka.State.t`, with
`Yuka.State.make`, `Yuka.State.get` and `Yuka.State.set`. The `?state:tag`
getter type above (sections 5 and the open questions) is superseded. `dyn` is
renamed `Yuka.hole`. Rebuilt: valid cases exit 0 with the same HTML on native
and node; the five failure cases exit 1. `bad_getter_prop` now fails with
"This expression should not be a function, the expected type is
int Yuka.State.t".
