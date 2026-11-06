# Yuka v0.1 design

Status: decided by the agent on 2026-11-06, as the user asked. Earlier
decisions: `brain-dump/DECISIONS.md`. Each item here can change; a change is
recorded here first.

## Toolchain

- OCaml 5.4.1, dune 3.24.2, Melange, mlx, Dream, ppxlib, Alcotest: the opam
  switch at `/home/me/workplace/davesnx/utopia`. Every command runs as
  `opam exec --switch=/home/me/workplace/davesnx/utopia -- <command>`.
  A local switch for yuka comes later.
- No bundler in v0.1. `melange.emit` writes ES modules, and the browser loads
  them as native modules from the server. esbuild comes later, for
  production builds.
- DOM tests run on Melange under node with jsdom, installed with npm into
  `node_modules/` at the yuka root.

## Render model

- Signals, render once (this answers Decision 1 in `SYNTHESIS.md`). A
  component is a function that runs one time. Only holes and keyed lists
  run again. There is no virtual DOM diff, except the keyed list reconcile.
- One element tree type (`Yuka.Internal.node`, in `src/yuka.mli`) in the
  shared core. The server prints it to HTML. The client creates DOM from it
  or adopts the server DOM (hydration).
- Templates with holes (melact) are not in v0.1: the client walks the tree.
  They come later as a speed step for client-only creation.
- Effects do nothing while the server renders (`Internal.server_rendering`).
- Server entry points take a function that builds the tree, so component bodies run with effects off.

## Libraries

Current layout (v0.4; earlier sections use the old names, see "v0.4"):

| Library | Modes | Directory | Holds |
|---|---|---|---|
| `yuka` | native, melange | `src/` | everything users call: State, Effect, elements, Json, Codec, Async, Action, `Yuka.Server`, `Yuka.Client` (islands and browser runtime), `Yuka.Router`, `Yuka.Await`; the virtual DOM module `Web` |
| `yuka.js` | melange | `dom/js/` | the browser implementation of `Web` (a Melange entry lists it) |
| `yuka.native` | native, melange | `dom/native/` | the default implementation of `Web` (raises "browser only") |
| `yuka.ppx` | native | `ppx/` | mlx to element calls, attribute checks, holes, lints, `let%client`, `[@@deriving codec]`, `<Yuka.Client>`, `<Yuka.Await>`, templates, `[%yuka.lazy]` |

Platform functions (event fields, window listeners, fetch) are a record of
functions in the core (`Internal.platform`). The client library installs
them at boot. On native they raise; they are only called inside effects and
handlers, which never run on the server.

## HTML and hydration markers

The server output and the client hydration must agree on this format.

- Text: escaped (`&`, `<`, `>`). Attribute values: escaped (`&`, `"`, `<`).
- Two `Text` siblings in a row: the server writes `<!---->` between them, so
  the browser keeps them as two text nodes.
- `Text ""`: the server writes nothing. Hydration creates an empty text node.
- `Hole`: `<!--[-->` content `<!--]-->`.
- `Each`: `<!--[-->`, then each item as `<!--[-->` item `<!--]-->`, then
  `<!--]-->`.
- `Fragment`: no marker; the children are inline.
- `Static` attribute: written. `Dynamic`: written with its current value;
  `None` is not written. `Handler`: not written.
- Void tags (`area base br col embed hr img input link meta source track
  wbr`): no closing tag, no children.

## ppx

- mlx gives `[@JSX] tag ~a:1 ~children:[...] ()`. The ppx turns a lowercase
  tag into `Yuka.lower "tag" [attributes] [children]`, with html_of_jsx's
  attribute checks as the baseline (valid attributes for the tag, plus
  `data-*` and `aria-*`), and `onClick` style props into `Yuka.on "click"`.
- An uppercase tag `<M.Name a=1 />` becomes `M.Name.make ~a:1 ()`, with
  `~children` only when children are given.
- A string literal child becomes `Yuka.text`. A child or an attribute value
  that contains `State.get` (or `Yuka.State.get`) becomes a hole:
  `Yuka.hole (fun () -> e)` or `Yuka.hole_attr name (fun () -> Some e)`.
- Lint: `open Yuka.State`, `Yuka.State.( ... )` and a module alias of
  `Yuka.State` are errors.

## Islands

- `let%client make ~(a : int) ~(b : Issue.t) () = ...` in a module `M`
  declares a client component. Every labelled argument has a type. The ppx
  adds `M.island` (server side: encodes the props, returns a
  `server element`) and `M.register` (client side: decodes the props and
  mounts).
- `<Yuka.Client><M a=1 b /></Yuka.Client>` becomes `M.island ~a:1 ~b ()`.
- Codecs: Yuka's own JSON type and printer/parser in pure OCaml, the same on
  both targets. `[@@deriving codec]` writes `codec` for records and
  variants. The codec of a type expression: `int`, `string`, `bool`,
  `float` and `list`, `option` map to `Yuka.Codec.*`; `M.t` maps to
  `M.codec`; `M.foo` maps to `M.foo_codec`.
- The server writes `<yuka-island data-name="M" data-id="i1" style="display:contents">html</yuka-island>`
  (with ` data-start="idle"`, `"visible"` or `"interaction"` after the style
  for `Client.island ~loading`; nothing for `Load`)
  and the props as `<script type="application/json" data-yuka-props="i1">`.
  The client entry lists the islands it knows:
  `Yuka_client.start [ M.register; ... ]`.
- Ids made inside an island carry the island's id as prefix.

- Island name: `<Library>.<Module path>` (library name from dune's
  `library-name` cookie), the same in native and Melange builds.
- Codec shapes: a record is an object keyed by field name; an `option`
  field is always written (`null` for `None`) and a missing key decodes as
  `None`. A constant constructor is `"A"`, one with arguments is
  `["B", arg1, ...]`, an inline record is `["C", {...}]`. A tuple is a list.
- Not supported yet (compile errors): recursive types, type parameters,
  `~children` on a client component (slots), `loading` on `Yuka.Client`.

## Async and streaming

- `'a Yuka.Async.t` is a pure OCaml promise (pending, resolved, failed, with
  callbacks), the same on both targets. The app bridges it to its own I/O (Lwt in the demo), the
  client to JS promises.
- `Yuka.Await.make ~async ~loading ?failed ~children ()` (the component
  `<Yuka.Await>`; `children` is the function from the value to the element) makes the node
  `Await { async; loading; failed; render }`. `failed` gets the error
  message; default: nothing.
- Markers (the client hydrates `Await` as a hole over `Async.watch async`):
  - Settled at print time: `<!--[-->` content `<!--]-->`, where content is
    `render v` or `failed message`.
  - Pending, not streaming (`to_string`, `page`): `<!--[-->` `loading`
    `<!--]-->`. Nothing fills it later.
  - Pending, streaming: `<!--[sN-->` `loading` `<!--]-->`. N counts from 1
    in one response. A comment whose text starts with `[` is a hole start
    for hydration, so `[s1` is one too.
- Streaming (`Yuka.Server.respond`, and `Yuka.Server.stream ~sleep ~write build`):
  1. One chunk: the document head (title, the inline script below, styles,
     module scripts) and `<body>`. Then one chunk: the shell (the tree with
     loading elements).
  2. Each pending `Await`, when its value settles, one chunk:
     `<template data-yuka-fill="sN">HTML</template><script>__yukaFill("sN")</script>`.
     HTML is the settled content printed as in a hole, without the markers
     around it. Chunks come in settle order. An `Await` inside that HTML
     that is still pending gets the next free id and its own later chunk.
  3. Each pending async prop, when it settles, one chunk:
     `<script type="application/json" data-yuka-async="aN">JSON</script>`,
     with JSON `{"ok": value}` or `{"error": message}`.
  4. `</body></html>` when everything has settled. `Yuka.Server.fill_script`
     defines `window.__yukaFill(id)` in the head. It finds the comment
     `[id`, removes the nodes up to the matching `]` comment (nesting of
     `[...` and `]` comments is counted), inserts the template content
     there, and removes the template and its own script.
  A render that raises after the shell was written closes the stream.
- Async props: `Codec.async c` encodes `'a Async.t`.
  - Settled at encode time: `{"$async":"aN","ok":v}` or
    `{"$async":"aN","error":message}`. This also holds in streaming.
  - Pending, streaming: `{"$async":"aN"}`, and chunk 3 above comes later.
  - Pending, not streaming: `{"$async":"aN","error":"pending at render"}`.
  - Ids `aN` count from 1 in one response. Encoding must run inside the
    function given to `to_string`, `page`, `stream` or `respond`; outside
    a render the id is `a0` and a pending value is an error.
  - Decoding `{"$async":"aN"}` calls `Internal.async_source "aN"`, which
    the browser runtime installs: it returns an `Async.t` of the JSON from
    the script `data-yuka-async="aN"` (already in the page, or on arrival).
- Module scripts run after the document is parsed. With streaming, they run
  after the stream ends, so all fills and async values are in the DOM when
  islands hydrate.
- Limits: `Await` is not a client re-render source on the server; the
  server never runs it twice. A pending `Async` that never settles keeps the
  response open.

## Server actions

- Shared code declares an action:
  `let create_issue = Yuka.Action.declare ~name:"create_issue" ~input:Issue.input_codec ~output:Issue.codec`.
- Server code implements it: `Yuka.Server.Action.implement create_issue (fun input -> ...)`
  (returns `Async.t`). Implementing a name twice raises `Invalid_argument`.
- `Yuka.Action.call create_issue input : Issue.t Async.t`. On the client it
  is a `POST /_yuka/action/create_issue` with JSON. On the server it calls
  the implementation directly (installed by the first `implement`).
- Wire format of `Yuka.Server.handle_action` for `POST /_yuka/action/:name`: the body
  is the JSON input. The answer is JSON: `{"ok": output}` with 200, or
  `{"error": message}` with:
  - 403: an `Origin` header that does not match the request `Host`
    (scheme ignored). No `Origin` is allowed; `Origin` without `Host` is
    refused.
  - 404: unknown action.
  - 415: `Content-Type` is not `application/json` (parameters such as
    `charset` are allowed).
  - 400: the body is not JSON, or the input does not decode. The message
    says which.
  - 500: the implementation raised or its promise failed. The message is
    always `action failed`; the failure goes to `Yuka.Server.log_error`.
  - 413: the body is over 1 MiB (checked by `Content-Length` first, then
    while reading). The message is `request too large`.
  Checks run in this order: origin, action name, content type, body size,
  body.
- A ppx form (`let%action`) can come later; this form needs no target
  switch in the ppx.

## Router

- Pages are server routes in Dream (a multi-page app). `yuka.router` stays
  out of v0.1 (decided 2026-11-05).

## Demo: mini Linear

- Server: Dream, data in memory, seeded.
- Pages: issue list (`/`), grouped by status; issue page (`/issue/:id`) with
  comments that stream in after a delay.
- Islands: the issue list (filter, keyboard `j`/`k`, status and priority
  change with an optimistic update through a server action), "new issue"
  dialog (`c` opens it), comment box.
- Style: one CSS file, dark, compact, Linear-like.

## Answers to the demo's friction list (2026-11-06)

- Text children stay explicit, as `React.string` in reason-react: the ppx
  cannot know the type of a child. The core adds `Yuka.int`, `Yuka.float`
  and `Yuka.list` (same as `fragment`) to make it shorter. Later, as in
  html_of_jsx: `Yuka.format` (printf to text) and `Yuka.array`.
- A component body runs once. A `State.get` in a `let` before the JSX reads
  the value once and is not tracked; only reads inside JSX children and
  attributes (holes), `memo`, effects and `each` lists are tracked.
- `Event` adds `stop_propagation`, `target_tag` (lowercase tag name),
  `shift_key`, `alt_key`. Delegated handlers respect `stop_propagation`.
- `Browser` adds `navigate : string -> unit`, `focus : string -> unit` and
  `scroll_into_view : string -> unit` (both by element id). Element refs come
  later.
- `Yuka_server.page` takes `?head` (extra HTML for the head) and writes an
  import map for the Melange output, so the bare imports Melange emits
  (`yuka/yuka.js`, `melange.js/curry.js`) load with no bundler.
- A component with no children does not declare `~children`; the ppx passes
  `~children` only when the tag has children.
- `open Yuka` is allowed; the lint message says so.
- `Async.on_result : 'a t -> (('a, string) result -> unit) -> unit` for
  handlers (no `Pending` case to write).
- An action rejects bad input with `Yuka_server.Action.reject "message"`:
  the response is 400 `{"error":"message"}` and the client's `Async` fails
  with that message. Any other exception stays 500 "action failed".
- A module-level `State.make` in shared code is one value for the whole
  process on the server. Rule: only client code paths (handlers, effects)
  may write it, and server rendering must not read a value that a request
  changed. A lint for this comes later.
- A `State.set` updates holes synchronously when no batch is running, so
  code right after it (for example `Browser.focus`) sees the new DOM.

## v0.2: the rest of Yuka (decided 2026-11-06)

Goal: everything left in `.workplace/plans/yuka-v0.1_PLAN.md` "Remaining
work", except the items listed as out of scope there.

### Slots

- A slot is a server element passed as `children` into a client
  component. The server renders it; the client adopts its DOM nodes and can
  place and move them, never inspect or re-render them (Leptos's rule).
- Core: `type slot`, `val slot : slot -> client element` (the user writes
  `(Yuka.slot children)` where the content goes), `Slot.make : server element
  -> slot`, `Codec.slot : slot Codec.t`, node `Internal.Slot of slot`.
- `let%client make ~(children : Yuka.slot) () = ...` is allowed. 
  `<Yuka.Client><M a=1><p>"x"</p></M></Yuka.Client>` becomes
  `M.island ~a:1 ~children:(Yuka.Slot.make (Yuka.fragment [...])) ()`.
- Server print of a `Slot` inside a client tree: `<!--[$-->` HTML `<!--]-->`.
  `Codec.slot` encodes as `null`; the position in the tree finds the nodes.
- Client: hydrating a `Slot` captures the DOM nodes between `[$` and its
  matching `]` into the slot without walking inside them. Rendering the slot
  again (a hole re-runs) moves the captured nodes to the new place. A slot
  that was never captured renders nothing.
- A `<Yuka.Client>` inside a slot is its own island: `Yuka_client.start`
  starts it, and the outer island never walks into it.

### `loading` on `<Yuka.Client>`

- `loading` is the start strategy (the proposal called it `start`):
  `` `Load `` (default: at `Yuka_client.start`), `` `Idle ``
  (`requestIdleCallback`, else a 200 ms timeout), `` `Visible `` (an
  `IntersectionObserver` on the island's first element child; no child:
  start at once), `` `Interaction `` (the first `pointerover`, `focusin`
  or `touchstart` inside the island; these come before a click or a key, so
  no event replay is needed).
- `Client.island ?loading ...`; the server writes `data-start="idle"` etc.
  (nothing for `` `Load ``) and `style="display:contents"` on
  `<yuka-island>`.

### Other decisions

- Default equality of `State.make`, `memo` and `on_change`: physical `==`
  first, then structural `=`; when `=` raises (a functional value), the
  values count as different. Reason: `==` alone gives different results on
  native and Melange for strings and floats. Known difference: a new record
  that holds the same closure is "different" on native and "equal" on
  Melange (Melange `=` compares closures by identity). Pass `~equal` for
  such values.
- `State.set` and `State.update` on a `memo` raise
  `Invalid_argument "Yuka: State.set on a memo"`. The user decided that
  `memo` returns `'a State.t`, so the check is at run time. A type-level
  split (a phantom permission) stays possible if wanted.
- `Internal.owned` removes itself from its parent when disposed.
- `Yuka_server.render_settled : (unit -> server element) -> string Lwt.t`
  prints after every pending value settled (for tests).
- Codecs: recursive types and type parameters are supported
  (`'a t` gets `codec : 'a Codec.t -> 'a t Codec.t`).
- Lint: a structure-level `let x = State.make ...` (or `State.memo`) is a
  compile error unless marked `[@@yuka.shared]`, which states that only
  client code paths write it.
- Production bundle: esbuild bundles the Melange output of the client entry
  into one ES module (`--bundle --format=esm --minify`); the server serves it
  instead of the module tree when started with `--bundle`.

### Out of scope for v0.2

- Reversed by the user (2026-11-06): all five items are in scope. See v0.3.

## v0.3: router, early islands, chunks, templates, typed errors (decided 2026-11-06)

The user put these in scope: "all of this is on scope!".

### Typed action errors

- An action with typed errors has a `result` output:
  `Action.declare ~output:(Codec.result Issue.codec create_error_codec)`.
  The implementation returns `(Issue.t, create_error) result Lwt.t`; the
  client gets `(Issue.t, create_error) result Async.t`. A transport failure
  or `Action.reject` stays a failed `Async`.
- Core: `Codec.result : 'a Codec.t -> 'e Codec.t -> ('a, 'e) result Codec.t`
  (`{"ok": a}` or `{"error": e}`). The ppx maps the type `('a, 'e) result`
  to it.

### Templates (melact)

- The ppx wraps a lowercase JSX tree whose shape is fixed per call site in
  `Yuka.template "<id>" e`. Fixed shape: every child is a string literal, a
  fixed-shape lowercase tag, or a hole; every attribute value is a literal,
  a hole attribute or a handler. Only trees with at least 2 elements are
  wrapped. `<id>` is unique per call site (file, line, column).
- Core: node `Internal.Template of { id : string; node : node }`; the server
  prints `node` as usual (no marker). `Internal.skeleton_html : node ->
  string` prints the fixed shape: holes as empty `<!--[--><!--]-->`, no
  dynamic attributes, no handlers.
- Client: hydration walks `node` as before. Fresh creation clones a cached
  `<template>` of the skeleton (one per id) and hydrates the clone with
  `node`, so creation reuses the hydration code.

### Islands that start before the stream ends

- `Yuka_server.respond ~early:true` writes the client entry as
  `<script type="module" async>`, so it runs as soon as it loads, while the
  stream continues.
- An island is complete when its props script is in the DOM (the script
  comes right after `</yuka-island>`). `Yuka_client.start` starts the
  islands that are complete, then watches the document (a
  `MutationObserver`, also covering `__yukaFill`) and starts each new
  island when its props script arrives. Async props already wait for
  their value script.

### One chunk per island

- `Yuka_client.start` also takes lazy entries:
  `Yuka_client.lazy_entry ~name (fun () -> <dynamic import of M.register>)`.
  The module is loaded only when the island's start strategy fires (so
  `` `Visible `` and `` `Interaction `` islands load their code late).
- The ppx exposes `M.name` from `let%client`.
- Melange 7 has no dynamic-import helper. A plain
  `external import : string -> 'a Js.Promise.t = "import"` emits
  `import("...")` as written; the path is the emitted JS file of the
  island's module, relative to the emitted file of the caller. esbuild
  resolves it at bundle time and makes the chunk.
- API: `Yuka_client.lazy_entry ~name load` and
  `Yuka_client.start ?lazy_entries eager_entries`. A lazy island loads its
  code once, only when its start strategy fires; a failed load logs, keeps
  the server HTML and can retry.
- The production bundle uses esbuild `--splitting --format=esm`: one chunk
  per lazy island, shared code in common chunks.

### `yuka.router`

- Since v0.4 the router is `Yuka.Router` in `src/router.ml`, part of the one
  library `yuka` (no separate `yuka.router*` libraries, no Dream). The
  client part uses the router functions of the virtual `Web` module.
- Route type: a GADT path `('a, 'r) Yuka.Router.t`, in the style of a
  Format string. `'a` is the function that takes the parameters, `'r` its
  result. One value serves both ways, so server and client cannot differ.

  ```ocaml
  val root : ('r, 'r) t
  val s : string -> ('r, 'r) t              (* fixed segment *)
  val string : (string -> 'r, 'r) t         (* parameter *)
  val int : (int -> 'r, 'r) t               (* parameter *)
  val ( / ) : ('a, 'b) t -> ('b, 'c) t -> ('a, 'c) t
  val href : ?query:(string * string) list -> ('a, string) t -> 'a
  val parse : ('a, 'r) t -> 'a -> string -> 'r option
  val query : string -> (string * string) list
  type 'r case
  val case : ('a, 'r) t -> 'a -> 'r case
  val dispatch : 'r case list -> string -> 'r option
  val start : ?lazy_entries:Client.lazy_entry list -> Client.entry list -> unit
  val navigate : string -> unit
  ```

  `let issue = Yuka.Router.(s "issue" / int)` has type
  `(int -> 'r, 'r) t`. `href issue 12` is `"/issue/12"`. `parse issue f
  "/issue/12?x=1"` is `Some (f 12)`.
- Rules: parameters and fixed segments are percent-encoded by `href` and decoded by `parse`
  (a fixed segment is compared after decoding; segments are split before decoding, so `%2F` stays in one segment). `int`
  accepts an optional `-` and digits only. A trailing slash, an empty
  segment, the query and the fragment do not change the match. `dispatch`
  returns the result of the first case that matches. A wrong type, a
  missing segment or an extra segment is a type error (for `href`) or `None`
  (for `parse`). `s` raises `Invalid_argument` on an empty text or a `/`.
  Query values are read with `query target` and are not part of the route
  type (the simplest design: the query stays untyped).
- Server: `dispatch cases target` returns the result of the first case that
  matches `target` (a request target: path, query allowed), here the
  handler, as `'r` is chosen by the app. The app maps that handler onto its
  HTTP library and answers its own 404 when the result is `None`. With
  Dream: `Dream.get "/**" (fun req -> match Yuka.Router.dispatch cases
  (Dream.target req) with Some h -> h req | None -> Dream.empty `Not_Found)`.
  Each page handler passes the request to the server render (the
  `Yuka-Navigate: 1` rule is in `Yuka.Server`), so the client gets the
  settled page in one go.
- Client: `Yuka.Router.start ?lazy_entries entries` calls
  `Yuka.Client.start` and then intercepts clicks on same-origin `<a>`
  links. A link is not intercepted when the event is already prevented, the
  button is not the left one, a modifier key is down, `target` is set (other
  than `_self`), `download` or `data-yuka-reload` is set, the origin differs,
  or only the fragment differs from the current URL. Otherwise the client
  fetches the URL with `Yuka-Navigate: 1`, then (in this order) calls
  `Yuka.Client.stop ()`, replaces `document.title` and the content of
  `<body>` with those of the response (`DOMParser`), pushes the history
  entry (the URL after redirects), scrolls to the fragment or to the top,
  and calls `Yuka.Client.start` again. Only title and body change; `<head>`
  (styles, scripts) stays. History is pushed only after the page loaded.
  `popstate` loads the entry's URL without pushing, and restores the scroll
  saved when the user left that entry (kept in memory, by an entry key in
  `history.state`; `history.scrollRestoration` is set to `manual`). A
  navigation started while another is loading aborts the first
  (`AbortController`); a late response of an aborted request is dropped.
  A network failure, or a redirect to another origin, ends with
  `location.assign url` (full page load). After each `start`, `Yuka.Browser.navigate`
  is `navigate` (the platform function is set again after every
  `Client.start`). A response that is not 2xx, or whose
  `Content-Type` is not `text/html`, also ends with a full page load, so the
  browser shows it itself. `Yuka.Router.navigate
  url` does the same as a click; before `start` it is `location.assign`.
- Cancel on navigation: stopping an island disposes its effects; action
  requests still in flight are aborted and their `Async` fails with
  "cancelled".
- Client API needed from `Yuka.Client`: `Yuka.Client.stop : unit -> unit`
  (dispose every started island and forget them) and `start` working again
  on a new body.

### v0.3 answers to the demo's friction list

- Event replay: an island that starts on `` `Interaction `` or loads its code
  lazily records `click`, `input`, `change`, `submit` and `keydown` events
  inside it while it is not started yet, and re-dispatches them to the same
  targets right after it starts (in order). Nothing is lost while the code
  loads.
- `Yuka.Browser.navigate` goes through the client router once
  `Yuka_router_client.start` ran (it sets the platform function), so shared
  code needs no ref.
- `[%yuka.lazy Lib.M "path/to/m.js"]` (client entry only) makes the lazy entry:
  the name comes from the module path, the path stays a literal for esbuild,
  and the ppx checks that the file name matches the module name.
- Routes that take no parameters are written as functions (`let my () =
  Yuka_router.(s "my")`): the route type is a GADT, so a value made by
  applying a combinator is not generalised (OCaml's value restriction).
- `Codec.result` inside a successful call reads `{"ok":{"error":...}}` on the
  wire. This is correct: the outer object is the transport, the inner one
  the action's own result.
- Templates stay on (decided 2026-11-06, measured in headless Chromium 151,
  `bench/`, best of 10): a fully static row is about 35% faster to create
  (5000 rows: 25.4 ms plain, 16.9 ms template); a demo-like row (2 holes, a
  handler, a dynamic attribute) is within noise (5000 rows: about 40-54 ms
  both), because its cost is mostly the effects, not the DOM. Creation
  jumps to each dynamic part by a path computed once per template id; a
  tree with a slot, an island or an empty text uses plain creation.

## v0.4: one library, no Dream (decided by the user, 2026-11-06)

The user: "Yuka as a single library. Yuka_server shouldn't depend on dream."
And: "Yuka.Await should be a component not a function".

### Old names in earlier sections

`Yuka_server.x` is now `Yuka.Server.x`; `Yuka_client.x` is now
`Yuka.Client.x`; `Yuka_router.x`, `Yuka_router_server.x` and
`Yuka_router_client.x` are now `Yuka.Router.x` (the Dream handler and the
Lwt bridges live in the app). `Yuka.await` is now `<Yuka.Await>`.

### Layout

- One library `yuka` (modes native melange) holds everything users call:
  `Yuka.State`, `Effect`, elements, `Codec`, `Async`, `Action`,
  `Yuka.Server` (was `Yuka_server`), `Yuka.Client` (island API plus the
  browser runtime that was `Yuka_client`: `start`, `stop`, `lazy_entry`,
  `render`, `hydrate`), `Yuka.Router` (was `Yuka_router`,
  `Yuka_router_server`, `Yuka_router_client`), `Yuka.Await`.
- The only target-specific part is the DOM bindings: a virtual module of
  `yuka` (checked with dune 3.24 in a scratch project: a virtual library in
  modes native and melange, a native default implementation, and a melange
  implementation chosen by the `melange.emit`). Implementations:
  `yuka.native` (default; each function raises "browser only") and
  `yuka.js` (Melange externals). A Melange entry lists `yuka.js` in its
  `libraries`; native code lists nothing extra.
- Directories `server/`, `client/`, `router/` go away; their code moves
  into `src/`. Each part is its own file in `src/`, and `yuka.ml(i)`
  re-exports them, so parts can change without editing one big file.

### Server without Dream

- No Dream, no Lwt in Yuka. Server functions take plain callbacks and
  return `Yuka.Async.t`:
  - `Yuka.Server.stream ~write page` writes chunks through
    `write : string -> unit Async.t`; the stream timeout uses a
    `~sleep : float -> unit Async.t` given by the app.
  - `Yuka.Server.to_string`, `page`, `render_settled` stay pure.
  - Actions: `Yuka.Server.Action.implement` (implementation returns
    `'o Async.t`), `reject`, and
    `Yuka.Server.handle_action : name:string -> content_type:string option
    -> origin:string option -> host:string option -> body:string ->
    (int * string) Async.t` (status and JSON body, same rules and statuses
    as before). The body size limit is checked from the body length.
  - Navigation requests: the app tells `Yuka.Server` whether the request
    had `Yuka-Navigate: 1`.
- The demo holds the Dream glue (a few lines): the action route, the page
  response, and Lwt <-> `Async` bridges.

### `<Yuka.Await>`

- `Yuka.Await` is a component: `<Yuka.Await async=comments loading=(<p>"…"</p>)
  failed=(fun msg -> ...)>(fun comments -> <Comments comments />)</Yuka.Await>`.
  `Yuka.Await.make ~async ~loading ?failed ~children ()` where `children`
  is the function from the value to the element. The ppx passes the single
  function child as `~children` (not wrapped in a fragment). The function
  `Yuka.await` is removed.
- mlx: an element used as a prop value always needs parentheses:
  `loading=(<p>"…"</p>)` (without them it is a syntax error, checked with
  mlx-pp).

## v0.3 addendum: generated island registry and `Yuka.mount ()` (decided by the user, 2026-11-06)

The user: users never write `M.register` or an island list, and the client
entry is `Yuka.mount ()`, the whole client start. This section uses the v0.4
names (one library `yuka`).

```ocaml
let () = Yuka.mount ()
```

### Why the islands need a reference

Checked with dune 3.24.2 in a scratch project (melange.emit, one library of
island modules, one entry):

- `melange.emit` writes JS for every module of every library in `libraries`.
  The entry JS imports only the modules its OCaml code names. An island module
  that nothing names is emitted and never loaded. A top-level
  self-registration in the island does not help: nothing imports the module,
  and esbuild `--bundle` of the entry contained 0 islands.
- A library that implements a virtual library chosen by the app (a registry
  as a virtual module) fails: dune does not build private implementations of
  public virtual libraries in `(modes melange)`. An app would need a public
  package per library.
- `(select)` only picks between whole libraries; it cannot list modules.
- A generated module in the `melange.emit` directory works. When it names
  `Demo_shared.Counter.register`, the emitted JS imports `../shared/counter.js`
  and esbuild bundles it. A call of a plain
  `external import : string -> m Js.Promise.t = "import"` with a string
  literal emits `import("../shared/related.js")`, and esbuild makes a chunk.
  Emitted paths are `<dir>/<file stem>.js` (a wrapped library has no prefix in
  the file name), so the path from the generated module is the relative path
  of the source directory.
- `(deps (source_tree DIR))` puts only the source files of `DIR` in
  `%{deps}` (no `.pp.ml` copies).

### Design

1. Generator `yuka-islands` (new executable, installed with package `yuka`,
   directory `gen/`). `yuka-islands --library NAME DIR ...` (the pair can
   repeat) scans the `.ml` and `.mlx` files under each `DIR` and prints a
   module. A file has an island when a line starts with `let%client` (with an
   optional `[@yuka.lazy]` after it). The module name is `Name` plus the
   capitalised file stem, which is the island name of DESIGN "Islands".
   Output:

   ```ocaml
   type m
   type entry = Yuka.Client.entry
   external import : string -> m Yuka.Client.promise = "import"
   external register : m -> entry = "register" [@@mel.get]

   let registry =
     Yuka.Client.registry
       ~lazy_entries:
         [ Yuka.Client.lazy_entry ~name:"Demo_shared.Related" (fun () ->
               Yuka.Client.promise_map register (import "../shared/related.js")) ]
       [ Demo_shared.Counter.register; Demo_shared.Issue_list.register ]
   ```

   The app adds one rule next to its `melange.emit`:

   ```
   (rule
    (targets yuka_islands.ml)
    (deps (source_tree ../shared))
    (action
     (with-stdout-to yuka_islands.ml
      (run %{bin:yuka-islands} --library demo_shared ../shared))))
   ```

   The `melange.emit` needs `melange.ppx` for `[@@mel.get]` (it has it
   already, with `yuka.ppx`).
2. The ppx rewrites `Yuka.mount ()` (the identifier applied to `()`, nothing
   else) into `Yuka.mount ~islands:Yuka_islands.registry ()`. That reference
   makes the linker keep the registry and, through it, every island. A
   missing rule gives `Unbound module Yuka_islands`; the README says so.
3. `let%client` is allowed only at the top level of a file (nested ones are a
   compile error), so the module path equals the file. One `make` per file
   already holds. A scan that misses an island is not silent: the client logs
   "no entry for island X" (existing behaviour) and keeps the server HTML.
   A scan that finds a file without an island is a compile error
   (`Unbound value register`).

### `Yuka.mount`

```ocaml
val mount : ?islands:Client.registry -> ?navigation:bool -> unit -> unit
```

- It lives in `src/yuka.ml(i)`. `Client` and `Router` are core parts, built
  for native and Melange, and the browser functions come from `Web` and
  `Internal.platform`, so it needs no other path. On native or without
  `~islands` (the ppx did not run) it raises `Failure` with a message that
  names `yuka.ppx`.
- The old top-level `Yuka.mount : (unit -> 'a) -> 'a * (unit -> unit)` (the
  owner root) has another type under the same name. It becomes
  `Yuka.owner` (user choice, 2026-11-06). Its only user is
  `test/cases/cases.ml`.
- `Client.registry : ?lazy_entries:lazy_entry list -> entry list -> registry`
  (abstract). `Client.start` keeps its two lists as the low-level function
  (tests call it); `mount` calls it with the registry. User docs show only
  `Yuka.mount ()`.

### Dune version and one context

The user asked whether the latest dune gives one library, built for native
and Melange in one context, per-mode code, so `mount` could be Melange-only
inside `yuka`.

- The newest dune in the opam repository is 3.24.2 (released 2026-08-03),
  which the switch already has (`opam show dune`). Its `CHANGES.md` has no
  unreleased section. Nothing from 3.8 to 3.24.2 adds per-mode modules or a
  per-mode `(modules)` field: Melange entries there are about virtual
  libraries (3.15.0, 3.15.1, 3.17.2), several contexts for `melange.emit`
  (3.15.0) and sandboxing. Dune issue 10362 (a project-wide setting that
  separates native and Melange contexts) is a proposal, not released.
- So no upgrade or `(lang dune X)` bump helps; `(lang dune 3.16)` stays. The
  single context already works: `yuka` has `(modes native melange)` and
  builds in the default context (`dune build` in the repository).
- Per-mode code in `yuka` already has a mechanism: the virtual module `web`
  (`yuka.native` default, `yuka.js` in a Melange entry). `mount` does not need
  more, because `Client` and `Router` compile on both targets and call
  `Web`. Melange-only code stays in `dom/js/`. This is why `mount` lives in
  `src/yuka.ml`.

### Lazy islands

- `let%client[@yuka.lazy] make ...` marks an island lazy: the generator
  emits a lazy entry (dynamic import, the path above) and does not name the
  module statically. Default: eager.
- Why per island: loading code late is a choice about the island's module
  (its own chunk), not about one use. The same island can appear with
  `Load` and `Visible`; the start strategy at the use site (`loading`)
  stays separate and decides when the entry runs. A lazy island used with
  `Load` loads right after `mount`. Eager by default keeps `Load` islands
  free of an extra round trip and the dev server (no bundler) simple.
- Trade-off: the generator finds the attribute by text. The ppx accepts it
  and rejects an unknown `yuka.*` attribute on the binding.

### Router

- `Yuka.mount ()` does what `Router.start` did: it starts the islands and
  takes over same-origin link clicks (rules in "yuka.router", unchanged).
  `Yuka.mount ~navigation:false ()` starts only the islands (full page
  loads). A link with `data-yuka-reload` still opts out one by one.
- Default is on because it is the whole client start and the demo needs it;
  the server side (`Yuka.Server`) already answers `Yuka-Navigate: 1`.
- `Router.start` leaves `yuka.mli`. `Router.navigate`, the route type and
  `dispatch` stay.

### Several libraries and names

- One `--library NAME DIR` pair per library, and one `source_tree` per
  directory in the rule. Names stay `<Library>.<Module path>`; the library
  prefix keeps modules of the same name apart.
- `include_subdirs unqualified` works (the scan is recursive).
  `include_subdirs qualified` and libraries installed without sources are not
  supported: the generator exits with an error for the first.

### Removed

- `[%yuka.lazy]`, `ppx/lazy_entry.ml` and its test `test/ppx/melange`.
- `Router.start` from `yuka.mli`; `M.register` from README and demo.
  `M.register` stays a value of the island module, because the generated
  module reaches it across libraries; its doc says "for generated code".
  `Client.lazy_entry` stays for the same reason.
- No compatibility layer: demo, README, tests and e2e change in the same
  step.

### Tests

- ppx expect test (`test/ppx/rewrite.mlx`): `Yuka.mount ()` expands; other
  uses of `mount` do not; `[@yuka.lazy]` accepted.
- `test/ppx/errors.t`: nested `let%client`; unknown attribute.
- Cram test for `yuka-islands`: eager, lazy, nested directory, two
  libraries, a file with no island, `include_subdirs qualified` error.
- Melange jsdom test (`test/melange`, with a generated registry): a document
  with an island whose module no test code names; `Yuka.mount ()` hydrates
  it (eager) and, for a lazy one, loads and hydrates it after its start
  strategy fires.
- Demo e2e (`e2e/run.sh`, also `BUNDLE=1`): all islands hydrate with
  `demo/client/main.ml` equal to `let () = Yuka.mount ()`; the bundle has a
  chunk for each lazy island.
- README example "Island" and `demo/client/main.ml` become
  `let () = Yuka.mount ()`.
