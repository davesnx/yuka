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
- One element tree type (`Yuka.Private.node`, in `src/yuka.mli`, hidden
  from the docs with `(**/**)`; only tests and the benchmark use `Private`) in the
  shared core. The server prints it to HTML. The client creates DOM from it
  or adopts the server DOM (hydration).
- Templates with holes (melact) are not in v0.1: the client walks the tree.
  They come later as a speed step for client-only creation.
- Effects do nothing while the server renders (`Private.server_rendering`).
- Server entry points take a function that builds the tree, so component bodies run with effects off.

## Libraries

Current layout (v0.4; earlier sections use the old names, see "v0.4"):

| Library | Modes | Directory | Holds |
|---|---|---|---|
| `yuka` | native, melange | `src/` | everything users call: State, Effect, elements, Json, Codec, Async, Action, `Yuka.Server`, `Yuka.Client` (islands and browser runtime), `Yuka.Router`, `Yuka.Await`; the virtual DOM module `Web` |
| `yuka.js` | melange | `dom/js/` | the browser implementation of `Web` (a Melange entry lists it) |
| `yuka.native` | native, melange | `dom/native/` | the default implementation of `Web` (raises "browser only") |
| `yuka.ppx` | native | `ppx/` | mlx to element calls, attribute checks, holes, lints, `let%client`, `[@@deriving codec]`, `<Yuka.Client>`, `<Yuka.Await>`, templates, `Yuka.mount ()` |

Platform functions (event fields, window listeners, navigation) are a record
of functions in the core (`Private.platform`). Their defaults call `Web`, so
in the browser they work without a boot step, and on native they raise; they
are only called inside effects and handlers, which never run on the server.
`Yuka.mount` with navigation replaces `navigate`.

## HTML and hydration markers

The server output and the client hydration must agree on this format.

The browser hydrates only `<yuka-island>` elements, so the page printer
(`Yuka.Server.to_string`, `document`, `respond`, `stream`, `render_settled`)
writes the markers below only inside an island. Outside an island it writes
no `<!---->`, `<!--[-->` or `<!--]-->`. The one exception is a pending
streamed `Await`, which keeps `<!--[sN-->` and `<!--]-->` because the fill
finds them. `Private.to_html` and `Private.render_html` write the
markers everywhere: the client hydrates their output.

- Text: escaped (`&`, `<`, `>`). Attribute values: escaped (`&`, `"`, `<`).
- Two `Text` siblings in a row: the server writes `<!---->` between them, so
  the browser keeps them as two text nodes.
- `Text ""`: the server writes nothing. Hydration creates an empty text node.
- `Hole`: `<!--[-->` content `<!--]-->`.
- `Each`: `<!--[-->`, then each item as `<!--[-->` item `<!--]-->`, then
  `<!--]-->`.
- A `Hole` or `Each` that is the only child of an element has no `<!--[-->`
  and `<!--]-->` of its own: it owns all the content of the element.
- An `Each` item that renders one element (`Element` or `Template`) has no
  item markers: the element is the item.
- `Template`: printed as the tree that `Private.expand` gives, so it has the
  same HTML as the same tree made with `lower`.
- `Fragment`: no marker; the children are inline.
- `Catch`: as a `Hole`. When the children raised on the server, the hole
  holds the fallback and its start marker is `<!--[!-->`.
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
- Streaming (the request cycle sends it; tests call `Yuka.Private.stream`):
  1. One chunk: the document head (title, the inline script below when
     the shell has a pending `Await`, styles, module scripts) and `<body>`. Then one chunk: the shell (the tree with
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
  - Decoding `{"$async":"aN"}` calls `Private.async_source "aN"`, which
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
- Wire format of the action call `POST /_yuka/action/:name` (the request
  cycle answers it; `Yuka.Private.handle_action` in tests): the body
  is the JSON input. The answer is JSON: `{"ok": output}` with 200, or
  `{"error": message}` with:
  - 403: an `Origin` whose authority is not the request `Host` (scheme
    ignored), or no `Origin` and no `Sec-Fetch-Site: same-origin`.
    `Origin` without `Host` is refused. Form posts and `Action` routes use
    the same rule (`Server.trusted_origin`).
  - 404: unknown action.
  - 415: `Content-Type` is not `application/json` (parameters such as
    `charset` are allowed).
  - 400: the body is not JSON, or the input does not decode. The message
    says which.
  - 500: the implementation raised or its promise failed. The message is
    always `action failed`; the failure goes to `Yuka.Server.log_error`.
  - 413: the body is over 1 MiB (`ADAPTER.body`: `Content-Length` first,
    then while reading). The message is `request too large`.
  Checks run in this order: origin, action name, content type (all from
  the headers, no body read), body size, body.
- A ppx form (`let%action`) can come later; this form needs no target
  switch in the ppx.

## Router

- Pages are server routes (a multi-page app). Since 2026-11-10 they come
  from `Routes.mlx` through `yuka-routes` and the request cycle; see
  "Routes.mlx generator", "Request cycle" and "yuka-dream". The typed
  path GADT of `Yuka.Router` is gone.

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
  html_of_jsx: `Yuka.array`.
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
- A `State.set` updates holes synchronously when no `Yuka.batch` is
  running, so code right after it (for example `Browser.focus`) sees the new
  DOM.

## v0.2: the rest of Yuka (decided 2026-11-06)

Goal: everything left in `.workplace/plans/yuka-v0.1_PLAN.md` "Remaining
work", except the items listed as out of scope there.

### Slots

- A slot is a server element passed as `children` into a client
  component. The server renders it; the client adopts its DOM nodes and can
  place and move them, never inspect or re-render them (Leptos's rule).
- Core: `type slot`, `val slot : slot -> client element` (the user writes
  `(Yuka.slot children)` where the content goes), `Slot.make : server element
  -> slot`, `Codec.slot : slot Codec.t`, node `Private.Slot of slot`.
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

- Default equality of `State.make`, `memo` and `on_change`: replaced on
  2026-11-10 by identity; see "Equality and batch".
- `State.set` and `State.update` on a `memo` raised
  `Invalid_argument "Yuka: State.set on a memo"`: replaced on 2026-11-10 by
  a type; see "Read-only memo".
- `Private.owned` removes itself from its parent when disposed.
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

Replaced by "Compiled templates and fewer markers (2026-11-10)" below.

- The ppx wraps a lowercase JSX tree whose shape is fixed per call site in
  `Yuka.template "<id>" e`. Fixed shape: every child is a string literal, a
  fixed-shape lowercase tag, or a hole; every attribute value is a literal,
  a hole attribute or a handler. Only trees with at least 2 elements are
  wrapped. `<id>` is unique per call site (file, line, column).
- Core: node `Private.Template of { id : string; node : node }`; the server
  prints `node` as usual (no marker). `Private.skeleton_html : node ->
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
  - `Yuka.Server.to_string`, `document` (a full HTML string; named `page`
    before the request cycle) and `render_settled` stay pure.
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
- 2026-11-10: replaced by the request cycle (`Yuka.Server.handle`, `Make`)
  and the `yuka-dream` package. `stream`, `render_settled`, `respond`,
  `handle_action`, `preload_urls` and `import_map` left the public
  `Yuka.Server`; tests reach the first ones through `Yuka.Private`.

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
   repeat) scans the `.mlx` files under each `DIR` (`.ml` before "Only
   `.mlx`" below) and prints a
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
  `Private.platform`, so it needs no other path. On native or without
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
- Per-mode code in `yuka` already has a mechanism: the virtual modules `web`,
  `dev` and `client` (`yuka.native` default, `yuka.js` in a Melange entry).
  `mount` does not need more, because `Router` compiles on both targets and
  calls `Web`, and `Client` has a native stub. Melange-only code stays in
  `dom/js/`. This is why `mount` lives in `src/yuka.ml`.

### Lazy islands (replaced by "v1: lazy as a value of `loading`")

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

### As built (v0.5, 2026-11-06)

Changes from the design above, found in implementation and review:

- The generator scans subdirectories only when the `dune` file in DIR has
  `(include_subdirs unqualified)`, as dune does. A `(modules ...)` field is
  an error (not supported).
- It skips comments and strings. (The lazy attribute it read is gone: see
  "v1: lazy as a value of `loading`".)
- A lazy path that does not start with `.` gets `./`, so the dynamic import
  is relative and not a bare package name.
- The ppx adds `~islands` to any `Yuka.mount ... ()` without an `islands`
  argument, so `Yuka.mount ~navigation:false ()` works.
- `Yuka.mount` checks `Web.in_browser` (`false` in `yuka.native`, `true` in
  `yuka.js`).

## v1: lazy as a value of `loading` (decided by the user, 2026-11-06)

Replaces "Lazy islands" above and `let%client[@yuka.lazy]`. Source:
`.workplace/plans/lazy-islands_PLAN.md` (measurement: all six demo islands
together are about 3.4 KB gzip, 8% of the client; the runtime is the rest).

```ocaml
type trigger = [ `Idle | `Visible | `Interaction ]
type loading = [ `Load | trigger | `Lazy of trigger ]
```

- `` `Load `` (default): download and start at page open.
- A trigger: download at page open (through the `modulepreload` link; without
  `?preload` the island downloads when it starts), start at the trigger.
- `` `Lazy t ``: download and start at trigger `t`. Events before the start
  are recorded and replayed (as today for lazy entries).
- Lazy is decided where the island is used, not per island module. The
  bundler cannot see use sites, so every island is its own file: the
  generator makes every island a lazy entry (dynamic `import`), and the
  client entry names no island module. Islands that are not on the page are
  never downloaded.
- The server prints `<link rel="modulepreload" href="URL">` before the first
  `<yuka-island>` of each island name whose `loading` is not `` `Lazy _ ``
  (`modulepreload` is allowed in `<body>`, so it works for streamed parts).
  `data-start` is printed as before, from the trigger; the client needs no
  other attribute: it always imports the island at its start, and the
  preload makes that a cache hit.
- The server needs the island URL (since 2026-11-10, `Yuka.Server.modules`
  and `bundle` build the function from the manifest). `Yuka.Server.respond ?preload` took a
  function from island name to URL; without it, no preload links. The app
  builds it: `yuka-islands --manifest` prints JSON
  `{ "<island name>": "<path relative to the emit directory>" }`, and
  `Yuka.Server.preload_urls ~manifest ~base ?metafile ()` makes the function.
  Without `metafile` the URL is `base ^ path` (dev, emitted modules). With an
  esbuild metafile (`--metafile`), the URL is `base ^` the output file whose
  `entryPoint` is that path (production, hashed chunk names).
- Removed: `let%client[@yuka.lazy]` (the ppx rejects every `yuka.*`
  attribute on `let%client` again), the eager list in the generated module.
- Not now: prefetch triggers, `` `Media ``, a `data-lazy` attribute.

## Only `.mlx` (2026-11-10)

- Components and islands are written in `.mlx`. Plain logic modules
  (model, store, actions without JSX) stay `.ml`.
- `yuka-islands` scans only `.mlx` files: a `.ml` file is never an island.
- The ppx rejects `let%client` in a file whose name does not end in `.mlx`
  (`.ml`, `.re`, ...): "let%client is allowed only in .mlx files: rename
  a.ml to a.mlx". Locations with no file (`""`, `_none_`) pass. The check
  does not skip ghost locations: OCaml marks the item of `let%client` as
  ghost. The check reads the file name of the location; `mlx-pp` keeps the `.mlx` name,
  so preprocessed `.mlx` files pass. Without it, an island in a `.ml` file
  would compile but never be in the registry, and the client would log "no
  entry for island X" only at run time.
- Tests: `test/ppx/errors.t` (the compile error for a `.ml` file, and for a
  file named `.re`), `gen/test/islands.t` (a `.ml`
  file with `let%client` is skipped).

## Read-only memo (2026-11-10)

- `State` has one abstract type with a phantom access parameter:
  `('a, 'access) State.signal`. `'a State.t = ('a, [ `Write ]) signal` comes
  from `make`; `'a State.read = ('a, [ `Read ]) signal` comes from `memo`
  and `Async.watch`.
- `get` and `peek` take `('a, _) signal`, so they read both. `set` and
  `update` take `'a State.t`, so a write to a memo is a type error ("These
  two variant types have no intersection"). The run-time check and its
  `Invalid_argument` are gone.
- A component or function that only reads takes `('a, _) State.signal` and
  accepts both kinds with no conversion at the call site. `Effect.on_change`
  does so.
- The phantom costs nothing at run time: both types are `Signal.t`.
- Test: `test/memo` compiles a file that reads a State and a memo through one
  function, then writes the memo, and checks the compiler error; `update`
  likewise.

## Hydration mismatch log (2026-11-10)

- In development, hydration logs one `console.warn` per mismatch:
  `yuka: hydration mismatch in island NAME at PATH: expected X, found Y`.
  Mismatches: a node is missing (`found nothing`), an element has another
  tag, a text has another value, or nodes are left over at the end of an
  element, a hole, a list or the island (`expected nothing`). A node that
  was already reported as the found node of a missing one is not reported
  again as left over. `PATH` is the parent element, from the island (or
  `body`) down, with `:N` for the N-th element of the same tag; `root` is
  the island itself. Values: `<tag>`, a quoted text (30 characters at most),
  `<!--data-->`, `nothing`. The text inside a `textarea` is its value, not a
  child, so it is not reported.
- The app's bundler decides, not the build of `yuka`: an opam install
  builds `yuka` with `dune build -p` (the release profile), so a flag fixed
  when `yuka` compiles would be wrong for every installed app. `Dev` is a
  second virtual module of `yuka` (next to `Web`). Its browser
  implementation (`dom/js/dev.ml`) is `on = <the test below>` and
  `mismatch = <same test> ? function ... : 0`. Each check in `dom/js/client.ml` is the raw test
  `typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__` in place. With
  `--define:__YUKA_DEV__=false`, esbuild folds it to `false` when it parses
  the file, before tree shaking, so the dev branches and everything only
  they call (`Dev.mismatch`, option conversions, `Curry._3`) are not in the
  bundle. With no define (dev, no bundler, the jsdom tests), the test is
  `true`. A shared constant `Dev.on` in another file is folded only when
  esbuild prints the bundle, after tree shaking: it left 392 B of `Curry._3`
  in the keyed app; `Dev.on` stays for code in `src/` (`Form`). `yuka.native`
  implements `Dev` with `on = false` and a no-op `mismatch`.
- Checked against an installed `yuka`: built with `dune build -p yuka`,
  installed with `dune install --prefix`, used by a small app; its esbuild
  bundle has the message without the define and not with it.
- `demo/bundle.sh`, `bench/keyed/build.sh` and `bench/size/size.ts` pass the
  define. `make size` fails when a bundle contains "hydration mismatch".
- The checks only report; hydration repairs the DOM as before (creates the
  missing node, sets the text, removes extra nodes in holes and lists, keeps
  extra nodes at the end of an element).
- Tests: `test/melange/dom_cases.ml` "dom hydration mismatch log" (a match
  logs nothing; each kind logs one line), the `make size` check (no message
  in a production bundle), and e2e check 11b (no mismatch on the demo pages
  with the unbundled modules).

## Owners and event handlers (2026-11-10)

- An owner is a small record: a doubly linked list of disposers and a
  generation counter. No hash table, no sort. `Yuka.owner`'s dispose runs the
  disposers from the last created to the first (the same order as before),
  in time proportional to their number. A disposer added while the owner is
  disposed stays for the next dispose. `Private.owned` removes its disposer
  from the parent in constant time.
- Each dispose adds 1 to the owner's generation.
- Delegated handlers (every event except `focus`, `blur`, `mouseenter`,
  `mouseleave`, `load`, `error`, `scroll`) need no effect and no disposer.
  The element keeps a list of handlers per event; each handler records its
  owner and the owner's generation. The document listener calls a handler
  only while that generation is current, so a disposed owner (or a re-run
  hole) turns its handlers off. Adding a handler drops the dead ones on that
  element. The document listener is added once per event name and stays.
- The other events get a direct listener, removed by a disposer.
- An effect flush sorts pending effects by level only when they are not
  already in order; the order of effects does not change.

## Compiled templates and fewer markers (2026-11-10)

### Template format

- The ppx turns each lowercase JSX tree into a `Yuka.Template.t`, made once
  at the top of the module (`let __yuka_template_<module>_N =
  Yuka.Template.make shape ~html ~walk ~kids ~attrs ~values`), and an
  `instance` call with an array of parts at the place of the JSX. Nested lowercase tags are part of the same template. The ppx adds the
  bindings before the structure item that contains the JSX.
- A shape is `Fixed_text`, `Fixed_element { tag; attrs; children }` or
  `Part i`. An attribute is `Fixed (name, value)` or `Part_attr i`.
- Fixed: a string literal child, and an attribute whose value is a literal of
  the attribute's type (string, int in 31 bits, `true`/`false`, a
  polymorphic variant of the attribute). The ppx writes the HTML string of
  the value; `false` on a boolean attribute writes nothing.
- Parts: every other child (`Part`, an element: components, holes, lists,
  `Yuka.text e`, the empty string literal) and every other attribute
  (`Part_attr`: computed values, holes, handlers, optional attributes).
- The server and hydration use `Private.expand`, the tree as `lower` makes
  it. So the HTML and the hydration walk do not change.
- Fresh client creation: the ppx computes, at build time, the HTML of the
  shape (`~html`, parts write nothing) and the paths (`~walk`, `~kids`,
  `~attrs`, `~values`); see "Small client bundles" below. On first use, per
  template and per context (HTML or inside SVG), the client parses `html` in
  a `<template>` (inside `<svg>` for the SVG context) and imports the root.
  The walk lists, for each node the client needs, the index of a node
  already found, then "first child" or "next sibling", then a number of
  "next sibling" steps. Each instance is `cloneNode(true)` and one run of
  the walk. Then child parts are mounted at their place, then attribute
  parts are set.
- A child part is placed before the next fixed sibling (or at the end of the
  parent). Text separators: in the template, two fixed texts with only parts
  between them get `<!---->`. After the parts that follow a fixed text, the
  client removes that `<!---->` when the parts did not end with a text, or
  adds one before the next fixed text when they did. The result is the DOM
  that hydration of the server HTML gives.
- After the first parse, the client checks once that the parsed DOM has the
  shape of the template: one root, the same element names and the same
  number of children along the whole tree, and the same static texts. The
  HTML parser can change a tree (a `tbody` added in a `table`, a `p` closed
  by a block, `template` children moved to `.content`, a leading newline
  dropped in `pre` and `textarea`, `html`/`head`/`body` dropped, `\r\n`
  read as `\n`, entities kept literal in `style` and `script`). When the
  check fails, that template is not cloned: its instances are created from
  the expanded tree, element by element.
- A fixed `value` on a `select` is set as the property after the child parts
  are mounted, as `lower` does.
- The hoisted name carries the library and the file's module name
  (`__yuka_template_<library>_<module>_N`), so a local open of another
  module cannot capture it.

### Marker rules

- A `Hole` or `Each` that is the only child of an element writes no
  markers. The client uses the element as the range: a hole replaces its
  content (`textContent = ""`, then mount; a text stays one text node whose
  `data` changes); a list appends rows at the end.
- An `Each` item that renders one element has no item markers. Other items
  keep `<!--[-->` and `<!--]-->`. A row is a range from its first to its last
  node; for one element both are the element.
- Kept: markers of a hole or list next to siblings, at the root, or in a
  fragment; `Await` and `Slot` markers; `<!---->` between texts.

### Removal

- A row of one element is removed with one `remove` call.
- When no row of a list stays (clear or replace), the client disposes every
  row, then removes all rows in one call: `textContent = ""` when the list
  owns its parent, otherwise a `Range` from the start marker to the stop
  marker.

## Equality and batch (2026-11-10)

### Default equality

- `State.make`, `State.memo`, `Effect.on_change` and `Yuka.each` skip an
  update when the new value is the same as the old one. The default rule is
  JavaScript `===`, as in Solid: `==` in Melange. Native OCaml follows the
  same rule: ints, chars, bools and constant constructors are immediates;
  two strings or two floats compare by value (a float NaN is never the
  same); every other value compares with `==`. So a new record, tuple,
  list, array or constructor with arguments is a change, even with equal
  contents. Closures compare by identity and never raise.
- Known differences between native and the browser: Melange represents
  `Some x` as `x`, so a new `Some x` around the same `x` is "the same" in
  the browser and a change on native; `bytes` are compared by value on
  native and by identity in the browser; `Int32` is a JS number in the
  browser. Pass `~equal` for such values. Effects do not run on the server,
  so server HTML never depends on equality.
- `~equal` replaces the rule. An exception from `equal` counts as a change.
  The default needs no closure call: the State stores `None` and the check is
  inline.
- The demo's status groups (a list of tuples built by a memo) pass
  `~equal:( = )` to `Yuka.each`, so an unchanged group keeps its DOM.

### `Yuka.batch`

- `batch f` raises a depth counter. While it is above 0, a write marks its
  effects pending and does not flush. When the outermost `batch` returns,
  pending memos and effects run in one flush. Inside a flush (an effect that
  calls `batch`), the running flush picks the work up.
- When `f` raises, the counter goes back, the pending work still runs (its
  own errors are dropped), then the exception of `f` is raised again.
- Event handlers are not batched: the document listener calls the handler
  directly, so each `State.set` updates the DOM before the next line (the
  rule above for `Browser.focus`). A handler that sets several States can
  wrap them in `Yuka.batch`. The demo does so for the comment form.

### Function arity in the JavaScript output

- Melange calls a function through `Curry._N` when it cannot see its arity.
  It cannot for a module alias (`module State = Base.State`, or a module
  that `include Element` brought in): user code then called every
  `Yuka.State.*` and `Yuka.Template.*` function through `Curry`. `State` and
  `Template` are now their own files, and `yuka.ml` binds them with
  `module X = struct include X end`, which Melange compiles with known
  arity. The keyed benchmark entry went from 90 `Curry._` call sites to 1.
- Calls from `src/` into the virtual module `Web` go through `Curry`: they
  are compiled against `web.mli` only. Known arity there needs `external`
  or `[@u]` in `web.mli`. Both need `melange.ppx` on the shared library,
  which also runs for native: it turns a `[@u]` type into a `Js.Fn` type
  and a `[@@mel.send]` external into an encoded primitive, and native has
  neither (an external would need a C stub per DOM primitive).
- `Client`, the module with the most DOM calls, is therefore a virtual
  module: `src/client.mli`, the browser implementation in
  `dom/js/client.ml` (compiled next to `web.ml`, with `melange.ppx`) and a
  native stub in `dom/native/client.ml` (island values work; `render`,
  `hydrate` and `start` raise "browser only", as they did through the native
  `Web`). Its calls into `Web` have known arity and most are inlined, and it
  uses JavaScript `null`, arrays and `Map` instead of OCaml options and
  lists on the mount path. The rest of `src/` still calls `Web` through
  `Curry` (`Navigation`, `Platform`, `Async`).

## Small client bundles (2026-11-10)

Goal: a client bundle holds only the features the app uses. Measured with
`make size` (`bench/size/size.ts`): the keyed benchmark app and the demo
chunks, minified, raw and gzip -9. The keyed benchmark app must stay under
the budget in `bench/size/budget.json`.

### What keeps code in a bundle

- esbuild drops a top-level function or value that nothing uses, but keeps
  every top-level statement that may have a side effect, in every module
  that is imported, used or not: a call (`Hashtbl.create 16`,
  `Base.new_owner ()`), a `new`, a string built with `^`. Melange imports
  every module that `yuka.ml` names, so such a statement in any module of
  the library is in every app. The library has none now: a table that must
  exist at the top is created on first use (`ref None`), a constant
  exception is built when it is raised.
- An OCaml submodule is a JavaScript object. Using one member keeps all
  members. So a submodule of `Yuka` holds only members that are small or
  used together, and a feature that only some apps need is a top-level
  value of `Yuka` (an ES export, dropped when unused) or is reached only from
  one:
  - `Yuka.mount` (top level) is the only way to the island runtime, the
    action transport, the async-value watcher and navigation.
    `Client.start` and `Client.stop` are gone from `Yuka.Client`;
    `Yuka.mount ~navigation:false ()` starts the islands and
    `Yuka.unmount ()` stops them and navigation (listeners, a fetch in
    flight, `Browser.navigate`).
  - `Router.navigate` is gone from `Yuka.Router`, which now holds only the
    route functions. `Browser.navigate` is a client navigation after
    `mount` and `location.assign` otherwise, as `Router.navigate` was.
    The navigation code is in `navigation.ml`.
  - `Server.Action` is rebuilt in `yuka.ml` from top-level functions of
    `server.ml`, so `Yuka.Server` is an object of plain references that
    the bundler can drop.
- Some stdlib modules have side effects at load (`Sys`, `Int`, `Float`,
  `Obj`) and are imported by `String`, `Bytes` and `Buffer`. The runtime
  does not use `Float`, `Queue` or `Hashtbl`; `String` and `Buffer` stay
  (printer, JSON, router), so about 300 bytes of `Sys`/`Int` load code stay
  in every bundle.

### Templates compiled by the ppx

- `src/template_build.ml` holds the shape type, `html` (the template HTML,
  as `to_html` prints the shape) and `plan` (the paths). The ppx compiles
  the same file (`copy_files` in `ppx/dune`), so build time and run time
  share one implementation. The client does not contain the printer or the
  path code: it only parses `html` and follows the paths.
- Paths are int arrays. `walk`: pairs (source index * 2 + 0 for first child
  or 1 for next sibling, number of extra next-sibling steps). `kids`: five
  ints per child part (part, parent node, anchor node or -1, flags, finish);
  flags: 1 only child, 2 first of a run of parts, 4 a text before the run,
  8 SVG in an HTML context, 16 SVG in an SVG context; finish: 1 remove the
  `<!---->` after the run when it did not end with a text, 2 add one when it
  did. `attrs`: three ints per attribute part (node, part, flags: 1 SVG in
  an HTML context, 2 SVG in an SVG context). `values`: a fixed `select`
  value per node.
- Hand-written templates use `Private.template shape`, which computes the
  same arguments at run time. `Private.recompile` does it for a ppx
  template; the tests in `test/templates` compare the ppx output with it,
  and the ppx HTML with the server HTML of the shape.

### Smaller primitives

- `Web.table` (a JS `Map`; `Hashtbl` on native) replaces `Hashtbl` in
  `each`, the island registry and the scroll positions.
- JSON: `\u00XX` escapes are written by hand; floats use
  `Web.shortest_float` (on native the `%.{15,16,17}g` loop as before; in the
  browser the same digits from `toExponential`; an exact tie at 17 digits
  rounds to even, as C `printf` does, so both print the same text, where the
  old Melange `Printf` rounded it up; `-0.0` is written `-0.0` on native and
  `0.0` in the browser, as before);
  numbers are parsed with `Web.parse_float` and `Web.parse_int`.
  `Router` writes `%XX` by hand. `melange-tiny` is no longer a dependency.
- The scheduler checks for empty lists with a pattern (no `caml_notequal`),
  sorts by level with a small stable merge sort, and uses two lists as its
  queue.

## Routes.mlx generator (2026-11-10)

Spec: `.workplace/docs/routes-spec.md`. Built: increment 1, the generator
and the shared module. The request cycle, `yuka-dream`, the demo migration
and navigation come later. The GADT `Yuka.Router` stays until then.

- `gen/routes/yuka_routes.ml` (`yuka-routes`, package `yuka`, library
  `ppxlib`) reads the binary AST that `mlx-pp` writes, finds
  `let routes = <Router>...</Router>` and prints the module `Routes` as
  text. Copied expressions (`default` values) go through `Pprintast`.
  Only `--shared` exists; `--server` comes with the request cycle.
- Output: `type t` (one constructor per named node, file order; fields are
  params in path order, then search fields), `with_query` (only when a
  route has search fields), `href` and `find`.
- `href`: static segments are encoded when the generator runs; params with
  `Yuka.Router.segment` (`int` with `string_of_int`, a custom type through
  `M.to_string`); a catch-all with `Yuka.Router.segments` (`/` and one
  segment per element). `segment` raises `Invalid_argument` on `""`, `.`
  and `..`, and `segments` also on `[]`: the cycle drops empty segments and
  browsers resolve dot segments, even as `%2E`, so `find` could not give
  the route back. So `find (href r) = Found r` for every `r` that `href`
  accepts. Search values use `encode`; any value is allowed there. Search
  fields at their absent value
  (`None`, the default, `[]`) are left out; the others follow as
  `?k=v&...` in field order.
- `find meth path query`: one `match` on the decoded segment list. Nodes
  with the same path shape share one case and a `match meth`; `` `GET ``
  also takes `` `HEAD ``; other methods give `Wrong_method` with the
  methods of the path in file order. Cases are sorted by segment kind
  (static, param, catch-all) at the first position where they differ, so
  OCaml's first match is the most specific path. `int` params accept only
  the form `string_of_int` writes (no `01`, `-0`, `+1`), so each page has
  one URL. `int` and custom params
  decode inside the case; `None` gives `Missing`, with no fall-through to
  a less specific case. A redirect node matches every method and returns
  `Redirect` with its params substituted and encoded.
- Build errors, all with a location in `Routes.mlx`: two nodes with one
  path shape and a common method (a redirect has every method); a name used
  twice; a label used twice in a branch (params, search fields and loader
  results are one set); an unknown redirect param; an `Action` with
  `` `GET ``; a bad path (no leading `/`, empty, `.` or `..` segment,
  `% ? #` in a static segment, unknown param type, catch-all not last or in
  a `Group`); unknown node or prop; a missing prop; children on a leaf; a
  `prerender` that is not `true` or `false`; a name that is a predefined
  constructor the generated code uses (`Some`, `None`, `true`, `false`,
  `()`, `[]`, `::`). `Found`, `Missing` and the other `lookup`
  constructors are allowed: the generated code qualifies them.
- The generated code names the standard library only through `Stdlib`
  (`Stdlib.List.map`, `Stdlib.( ^ )`, `Stdlib.( = )`), so a sibling `List`
  module or `-open Base` does not change it. `test/routes/shadowed`
  compiles the fixture with `-open Shadow`, which shadows them all.
- New in `Yuka.Router`: `meth`, `lookup`, `PARAM`, `encode`, `segment`,
  `segments`, `int_param`, `search`.
- Size: `find` is a top-level function that a client which calls only
  `href` does not name, so esbuild drops it (checked by
  `test/routes/client/check.mts`). `Yuka.Router` is a JavaScript object, so
  `href` keeps all of `router.js` (about 2.5 KB minified, most of it the
  GADT) until the GADT goes. `Router.search` compares keys as strings, so it
  does not pull `caml_obj`.
- Tests: `test/routes/fixture` builds a fixture `Routes.mlx` with every
  segment, search and node kind through the dune rules; a `diff` rule
  checks the generated code; `test/routes/run.ml` checks `href`, `find`
  and the round trip `find (href r) = Found r`; `gen/routes/test/errors.t`
  has one case per build error.

## Request cycle (2026-11-10)

Spec: `.workplace/docs/routes-spec.md`, increment 2; its section 8 lists
what changed from the spec. `yuka-dream` and the demo migration are in
"yuka-dream"; the navigation protocol comes later.

- `src/cycle.ml`, included in `Yuka.Server`: the types the generated code
  names (`stop`, `page`, `layer`, `plan`, `cache`, `rules`, `response`,
  `fallback`, `target`, `'req app`), `assets`, `config`, `handle` and the
  functor `Make (A : ADAPTER)`. No server dependency: `handle` takes the
  adapter's request (passed to user code) and a neutral `request` record
  (read by the cycle), and returns `Respond response` or `File`.
- Order: `/_yuka/action/<name>` (POST, else 405), `/_yuka/<file>` and public
  prefixes (GET/HEAD, decoded segments, `.`, `..` or `/` inside a segment is
  404 `no-store`, never routed); trailing slash or empty segment 308 with
  the query; `find`; redirect node 308/307; `Missing` 404 page;
  `Wrong_method` 405 with `Allow` (`HEAD` after `GET`, `OPTIONS` last) or
  204 for `OPTIONS`; guards one after another; same-origin check for
  actions; handler (rule headers, then the handler's, then the rule
  `cache-control` unless set; `HEAD` drops the body) or loaders, headers
  (`content-type`, `vary: Yuka-Navigate`, rule headers and
  `cache-control`), then the streamed document (`HEAD` renders it too and
  drops the body; see "Server rendering speed").
- Errors: a stop or an exception before the first write gives the
  fallback page (404 or 500, root headers, `no-store`, the message only in
  `log_error`). The shell is printed before `handle` returns, and a render
  that already failed at that point (a fill or timeout that raised) also
  gives the 500 page; the adapter attaches its write function later through
  the `Stream` body. After that the status is sent: a failure is logged,
  the stream ends without `</body></html>`, and its `Async` succeeds, so the
  adapter closes the response normally. That happens only after the
  writes already queued have finished (`Server.drive` fails after its
  write chain settles), so nothing is written after the end. Before the
  adapter attaches its write function, chunks go to a buffer, which is
  sent first. If the error page itself fails, the answer is a plain-text
  500; a `log_error` that raises does not stop it. Every `HEAD` answer
  (405, 403, 404, 500 included) has an empty body.
- A stop `Redirect` must have status 301, 302, 303, 307 or 308 and a
  location without CR or LF, else it is a logged 500. It gets the root
  headers and `no-store`. A path with a literal `\` is the 404 page,
  because browsers read `/\evil.com` as `//evil.com`.
- `vary` values are joined: a rule `vary: Cookie` gives
  `vary: Cookie, Yuka-Navigate`.
- An `Action` always sends `cache-control: no-store`. An `Endpoint`
  response that is not 2xx gets `no-store` instead of the rule cache,
  unless the handler set `cache-control`.
- A fallback whose layouts have param keys is written inside the route's
  arm of `resolve`, where the params are bound; the others are top-level
  `fallback_N` values. A layer whose layout takes no loader result is
  built once: a top-level `layer_N` (N is the layout key number) when its
  key has no param, else a `let layer_N = ... in` at the top of the arm,
  shared by the fallback and the plan. Only layers that take a loader
  result are built inside `load`.
- A failed `Codec.async` value sends `{"error":"failed"}` and logs the
  message, streamed or already failed at print time, unless it is a
  rejection (`Server.Action.reject`), whose message is meant for the
  client. `log_error` lives in `Types`, so `Codec` can call it;
  `Server.log_error` is the same ref.
- Printer: the session has `entry` (the module script tag, written once,
  right before the first island; queued before the `<template>` inside a
  fill), `current` (an `<a>` whose `href` equals the request path gets
  `aria-current="page"`, but not inside an island, whose markup must match
  the client render), `id_prefix` (for increment 4) and `in_fill`.
  The head has `fill_script` only when the shell has a pending `Await`;
  pending `Codec.async` values send JSON, which needs no script. A page
  with no island and nothing to fill has no `<script>` other than the
  import map.
- `yuka-routes --server --shared-module M FILE.ast` prints
  `Routes_server`: the opens before `let routes`, one `rules_N` per
  distinct rule set, one `fallback_N` per distinct fallback, `resolve` (one
  arm per named node) and `app`. All loader calls of a route are bound
  before the first `Yuka.Server.loaded`, so they start together.
- Size: the client never names `Cycle`, so esbuild drops it, as long as
  `cycle.ml` has no top-level computation: `text`, `html` and the asset
  404 are functions, not partial applications or values (as values they
  kept 437 B of `cycle.js` in the keyed app). `make size`: keyed app
  11008 B gzip, budget 11345 B (18 B from `log_error` and `async_error` in
  `Types`, which the client `Codec.async` now names).
- Tests: `test/cycle` builds a `Routes.mlx` with every node kind through
  the three dune rules, diffs the server output against
  `routes_server.expected`, and runs 60 cases through `Make` with a test
  adapter (record request, `Async.t` as `io`, a fake file table): each
  step and status code above. Breaking a step (no 308, `HEAD` with another length, no
  `HEAD` in `Allow`, guards reversed, dot segments allowed, no log, no
  `OPTIONS` 204, no entry script, `aria-current` on every link, no
  outlets, no rule cache, no origin check, loaders started one after
  another) fails at least one case. `gen/routes/test/server.t` has the
  server-mode generation errors. `test/cycle/shadowed` compiles the same
  server output with `-open Shadow` (`List`, `String`, `Ok`, `Error`, `^`,
  `=` and others hidden), so it names the standard library only through
  `Stdlib`.

## yuka-dream, demo on Routes.mlx, prerender (2026-11-10)

Spec: `.workplace/docs/routes-spec.md`, increment 3 (tickets 09, 11 and
19); its section 8 lists what changed from the spec.

- Package `yuka-dream` (`dream/`, library `yuka_dream`): `handler`,
  `prerender`, `to_async`, `to_lwt`. `yuka` has no Dream dependency.
  `handler` sets `Yuka.Server.log_error` to `Dream.error`. A `Stream` body
  is a `Dream.stream` that flushes each chunk; a file is
  `Dream.from_filesystem` with the cycle's headers (a 404 gets
  `no-store`).
- Removed from `yuka`: the path GADT of `Yuka.Router` (`t`, `root`, `s`,
  `string`, `int`, `/`, `href`, `parse`, `query`, `case`, `dispatch`) and,
  from `Yuka.Server`, `respond`, `stream`, `render_settled`,
  `handle_action`, `preload_urls`, `import_map`. `Yuka.Private` keeps
  `stream`, `settled`, `handle_action`, `preload_urls` and `import_map`
  for tests. `Router` keeps `decode`, `split_target`, `split_path` and
  `query` inside the library for the cycle.
- Prerender. The pure parts are in `Yuka.Server`: `prerender_seeds` (the
  generated `~prerender` list: `GET` nodes with no param and
  `prerender=true`), `prerenderable` (find, then the rules of the target),
  `links`, `prerender_file`, `missing_page` (the `404.html`) and
  `served_dirs`. `Yuka_dream.prerender` runs each path through the cycle
  with a second adapter whose `exists` is always false (so it never reads
  an earlier output), writes 2xx answers, warns on stderr for others,
  follows links of HTML answers, then writes `404.html` and copies the
  served directories.
- Serving prerendered files: `config ~prerendered:dir`. For a page whose
  rules say `prerender`, a `GET` or `HEAD` with no query and no
  `Yuka-Navigate` is answered with its file after the guards, instead of
  the loaders, with the page headers. A missing file renders the page.
  `ADAPTER` has `exists ~root ~path` for this.
- Demo: `demo/Routes.mlx`; the shell layout is on a `Group path="/"`, so
  `/about` (prerender) is outside it and has no island. Generated
  `Routes` in `demo_shared` and `Routes_server` in `demo_app`;
  `Pages.not_found` shows "Issue not found" for `/issue/:id`, else "Page
  not found". `Shell` lost `~active`; the CSS styles
  `.nav-link[aria-current=page]`. `demo_server.ml` builds `config` and calls
  `Yuka_dream.handler`, or `Yuka_dream.prerender` with `--prerender DIR`;
  `--prerendered DIR` serves the files. Client files moved from
  `/static/js/` and `/static/bundle/` to `/_yuka/`.
- A tree whose functions never fix the request type gives
  `Routes_server.app` a weak type variable; the demo writes
  `(_ : Dream.request)` in `Loaders.issue` and `Handlers.issues_json`.
- Bench `bench/ssr`: `yuka-stream` is now `Yuka_dream.handler` with a
  hand-built `Yuka.Server.app` (the page has no `Await`, so no fill
  script).
- Size: `make size`: keyed app 11003 B gzip (budget 11345 B), demo chunks
  35834 B gzip (36608 B before; the GADT is gone). `make measure-pages`:
  `/about` loads 0 bytes of JavaScript.
- Tests: `dream/test` (prerender: seeds, crawled links, a 404 link
  skipped with a warning, links to another origin and to pages without
  `prerender` not followed, `404.html`, copied public files, two runs give
  the same files; `handler ~prerendered` serves files), `demo/test`
  through `Dream.test` (the requests of the spec), `test/cycle` (prerender
  helpers, prerendered files, query decoding). `test/router` (GADT) is
  removed; its client navigation tests moved to `test/navigation`.
- Review fixes (2026-11-10): each test and `runtest` rule names its
  package, so `dune build -p yuka @runtest` and `-p yuka-dream @runtest`
  each run alone. `HEAD` on a file answers from `exists`, without the file.
  `prerenderable` skips `/_yuka/` and public paths. `prerender` refuses an
  `out` inside a served directory. `not_found` and `error` pages get the
  params of their node's path (the demo shows the decoded issue id).
  `links` decodes numeric character references.

## Navigation protocol (2026-11-10)

Spec: `.workplace/docs/routes-spec.md`, section 4 and increment 4
(ticket 10); its section 8 lists what changed.

- Request: `Yuka-Navigate: L0 L2/YUK-1`, the `data-k` of every
  `<yuka-outlet>` in document order. The cycle compares them with the
  layer keys of the target (or of the fallback for a 404 or 500). A common
  prefix of `n >= 1` keys gives a partial: the settled content of outlet
  `n` with ids prefixed `KEY-`, no entry script, and the headers
  `Yuka-Outlet`, `Yuka-Title` (percent-encoded), `Yuka-Build`, the page's
  status and rule headers. Otherwise the settled full document with
  `Yuka-Build`.
- Build id (`Server.build_id config app`): two 32-bit FNV-1a hashes of the
  route digest and the asset description (entry, manifest, packages or
  metafile). `Digest` was the first choice, but it put melange
  `digest.js` and `Printf` into every client bundle (keyed app 11005 B ->
  22603 B gzip). Every full document has `<meta name="yuka-build">`.
- Client (`src/navigation.ml`): reads the keys, fetches, compares
  `Yuka-Build` with the meta (differs: `location.assign`), accepts 2xx and
  4xx/5xx as pages (1xx/3xx and non-HTML: `location.assign`), then with a
  known `Yuka-Outlet` runs `Client.stop_within` on that outlet, sets its
  `innerHTML` and the title, and sets or removes `aria-current="page"` on
  links outside the outlet and outside islands (only the value `page` is
  removed); without one, the old body swap. Then history, scroll and the
  island scan as before. `Client.stop_within` runs the cleanup stored on
  each live island inside the element (`__yuka_cleanup`).
- `Web`: `fetch_page` takes the keys and gives the callback the status and
  a header lookup; new `decode_uri`, `contains`, `set_title`.
- Size: keyed app 11001 -> 11005 B gzip; demo chunks 35833 -> 36364 B gzip
  (+531 B). `/about` still loads 0 bytes of JavaScript.
- Tests: `test/cycle` "navigation" (partial headers and body, deepest
  shared outlet, full document for unknown, empty or old keys, prefixed
  ids, 404 partial, `Yuka-Title` UTF-8, build meta, build id follows the
  assets); `test/navigation` (keys sent, partial swap keeps islands outside
  the outlet and stops those inside, title, `aria-current` outside the
  outlet and islands, build mismatch, unknown outlet, 404/500 in place);
  `e2e/demo.ts` 3c (sidebar counter and `New_issue` survive, title,
  `aria-current`, back, `Yuka-Build` mismatch through a rewritten
  response header) and 3d (no script on `/about`).
- Review fixes (2026-11-10): a layout that takes a loader result
  (`layer.data`) is never shared, so it is rendered again with fresh data;
  `Server.modules ~digest` (`Yuka_dream.tree_digest`) puts the module
  contents into the build id, computed once; the client sends `-` when the
  page has no outlet, does a full load when the answered outlet is not on
  the page, decodes the title before changing the DOM, leaves an existing
  `aria-current` alone, and `stop_within` aborts the action calls of the
  islands it stops (the event handler's owner is the acting owner).

## Remote data (2026-11-10)

Spec: `.workplace/docs/data-spec.md`, sections 1 and 2, increments R1 to
R3 (ticket 12); its "Changes during build" section lists the differences.

- `Status` (`src/status.ml`): `Idle`, `Loading last`, `Ready`, `Failed
  { error; last }`, with a typed `error` (`Rejected`, `Forbidden`,
  `Not_found`, `Server`, `Network`, `Protocol`) and a JSON codec for it.
- Queries: `Action.query` is `Action.declare` with the kind `[ `Query ]`
  (a phantom third parameter of `Action.t`); `Remote.use` accepts only that
  kind. Same registry, endpoint and wire format.
- Transport: `Remote.server_send` gives `(Json.t, Status.error) result` and
  returns an abort. The server sets it with `implement` (the
  implementation, `Server` logged); in the browser `Remote` maps the status
  of `fetch_post` itself (400 `Rejected` with the message, 403, 404, 413 and
  415, 5xx, network). `Action.call` keeps its string transport and its
  messages.
- `Remote.use` (`src/remote.ml`): an effect computes the key (query name
  and input JSON); a new key aborts the request and bumps a generation, and
  only the current generation writes the status. Retries use
  `Web.set_timeout`. The owner's disposal aborts and leaves the
  `invalidate` table (a `Web.table` from query name to mounted uses,
  created on first use).
- Answers (`src/answers.ml`): in a server render, a use inside an island
  writes `<script type="application/json" data-yuka-answer="r:NAME JSON">`
  with `{"ok":v}` or `{"error":ERROR}` after `</yuka-island>` and before the
  props script. A use that is still pending writes a `data-pending`
  element and a `Pending_answer`; `Server.drive` writes the full element
  when it settles (or a network timeout error). The client reads an answer
  on the first run only; a pending one is awaited with the DOM watch until
  the document ends, then fetched. `Server.drive`'s `on_value` now takes the
  HTML of the chunk.
- `Optimistic` (`src/optimistic.ml`): pending changes with ids, applied
  oldest first over a base kept elsewhere. `Remote.mutate` adds a change,
  runs the call, and on success removes it and writes `commit result base`
  (default `change base`); on failure removes it.
- Size: `make size` fails when the keyed app contains `remote.js`,
  `answers.js`, `optimistic.js` or `status.js`, or when any client chunk
  contains `printer.js`; keyed app 10460 -> 10462 B gzip. The demo client
  grows 35961 -> 38882 B gzip (it uses Remote).
- Review fixes: answers made in an `Await` fill go out before the fill
  chunk; a raising island rolls back its answers; embedded `Network` and
  `Server` errors are retried after hydration; `mutate` keeps the base's
  kind and asks again when it commits during a request; the typed server
  transport ref is `Remote.server_send`.

## Live data (2026-11-10)

Spec: `.workplace/docs/data-spec.md` section 3 (ticket 13).

- `Topic.declare ~name ~key ~state`; the wire key is the JSON of the key.
- Server (`src/live_server.ml`, `Yuka.Server.Live`): `serve ?allow topic
  load`, `publish topic key state`, `run` (the protocol on one socket),
  `SOCKET` and `Handle`. Entries per `(topic, key)` exist while they have a
  subscriber; the last unsubscribe removes the entry, and the next
  subscribe runs the loader again. `seq` comes from one process counter. A
  publish while the loader runs wins over the loaded state. Each socket
  sends in order; a state that waits to be sent is replaced by a newer one
  of the same subscription.
- Protocol v1 (JSON text frames): client `hello` (version and token), `sub`,
  `unsub`, `sync`, `ping`; server `hello` (with a fresh token), `state`,
  `error`, `synced`, `pong`. Close codes: 4400 bad message, 4403 token
  refused, 4426 other version, 1009 message over 64 KiB, 4408 no message
  for 60 s. At most 64 subscriptions per socket.
- Settle rule of `Live.mutate`: on `Ok` the client sends `sync` for the
  subscription; the server answers `synced` behind the latest state of the
  subscription on that socket. The action publishes before it answers, so
  that state holds the change, in whatever order the HTTP answer and the
  socket message arrive. While the socket is down, `sync` follows the next
  `sub`.
- Token: `Server.ADAPTER.csrf_token`; the first `Live.use` of a render
  writes it as the answer `l:csrf`, so a page with no live use asks no
  token. The server `hello` carries a fresh token for the next `hello`.
  Sessions and the secret must be shared by every node and survive a
  restart (`cookie_sessions` and `set_secret` in the demo).
- Client (`src/live.ml`): one socket per page, opened by the first use and
  closed 2 s after the last; reconnect after 250, 500, 1000, 2000, 4000,
  then 5000 ms (half to all of each, at random), reset by a server `hello`.
  While `navigator.onLine` is false it waits for the `online` event or
  5 s, whichever comes first (a headless Chrome in a sandbox reports
  offline with a working network). Ping every 25 s; 10 s of silence after
  a ping closes the socket. The client does not wait for the server's
  close reply when it closes the socket itself: `yuka-dream` does not
  answer a client close frame (see below), so the browser would stay in
  `CLOSING` until its own timeout.
- `yuka-dream`: `Yuka_dream.handler` answers `GET /_yuka/live` before the
  request cycle. Calling `Dream.close_websocket` after the connection is
  gone spins at 100% CPU (dream issue #467; in httpun-ws 0.2.0,
  `Wsd.report_result` on `Closed` closes the writer without draining it).
  So the socket is created with `~close:false` and `run` closes only a
  live connection: never after `receive` gave `None` (the client closed),
  and not after a timeout (4408) or a failed send or receive (1011). With
  `~close:false` and no `close_websocket` call, Dream sends no close reply
  to a client close frame (measured with a raw client against the demo,
  dream 1.0.0~alpha8; with a call while the connection is alive the reply
  `1000` is sent). Remaining risk until httpun-ws is fixed upstream (a PR
  for camlworks/dream#467): a publish written to a client that reset its
  connection just before can freeze the server at 100% CPU. README and
  `yuka_dream.mli` say so.
- Demo: the issue list on `Topics.issues` (key `All` or `Mine`) and the
  properties panel on `Topics.issue`, both with `Live.mutate`;
  `update_issue` and `create_issue` publish. The label chips above the list
  read the query `Queries.labels` (remote data), which the list and the new
  issue dialog invalidate.
- Review fixes:
  - Token renewal: each `pong` carries a fresh token; a first `Live.use`
    takes the token of its page; on 4403 the client asks
    `GET /_yuka/csrf` (request cycle, origin rule of the action call) once
    and connects again. A refusal after that is final only for the uses of
    that socket: a new use (after a navigation) connects again.
  - Bounds: at most 256 replies wait on a slow socket (else close 1008);
    `synced R` answers every `sync` up to `R`, so the server keeps one ref
    per subscription. No `hello` within 10 s, or no message for 60 to 120 s,
    closes 4408, with one timer per socket. `Server.Live.set_limits`
    (default 16 sockets per session, 10,000 per process) closes 1013 over a
    limit.
  - A failed send or receive ends the socket and its subscriptions (1011).
    The socket is closed once, by the protocol code, and never after the
    client closed it.
  - The entry key is the key decoded and encoded again
    (`Topic.wire_key`), so `{"b":2,"a":1}` and `{"a":1,"b":2}` are one
    entry.
  - `allow` runs on each subscribe of each connection; a reconnect checks
    again. `Server.Live.revoke` closes matching sockets with 4401 (logout,
    permission change); until then a subscriber gets every publish.
  - One exception guard (`Async.guard`; `Server.guarded` adds the app's
    `reject`), one failure mapping, and `Answers.record_value` for the
    token answer.
- Measured (`dune build --profile=release @bench/live/bench-live`, one
  machine under load): 25 issues 6 KB per message, publish to 100 sockets
  under 1 ms; 500 issues 122 KB, 14 ms; 5000 issues 1.2 MB (over the 1 MiB
  warning), encode 7 ms, publish to 100 sockets 142 ms.

## Error boundaries (2026-11-10)

Ticket 21; `.workplace/docs/app-spec.md` section 21, option A.

- An owner has `catch : (exn -> unit) option`. A new owner takes the catch
  of the current owner. The owner type is in `Scheduler`, so a node can
  hold its owner. `Base.fail o e` (`Scheduler.catch`) calls it, or raises `e` when there
  is none, so code outside a boundary and outside an island behaves as
  before.
- Routing: an effect's first run that raises calls the catch of the
  effect's owner. A later run that raises, and a dependency check that
  raises (a memo the effect reads), reach `Scheduler.flush`, which calls
  the catch of `node.owner` (set by `Effect.run`). The delegated listener
  wraps each handler in `try`, calls the catch of the handler's owner and
  marks the event stopped, so ancestor handlers do not run, as after an
  uncaught error; a non-bubbling handler is wrapped when it is attached.
  Memos are not routed themselves: their readers are. A cleanup that
  raises while its owner is disposed is routed only when the disposal
  runs inside an effect or a handler.
- `Catch` is a node with the server parts (`children`, `fallback`) and a
  `client` function that returns a `Hole`. The hole's body sets the catch
  of the hole's owner to a handler that writes an error State, so all
  effects and handlers made under it inherit it. On error the hole runs
  again: its owner is disposed (effects stop, cleanups run) and the
  fallback is rendered with the catch of the owner above, so an error in
  the fallback goes up. A synchronous error in `children ()` disposes the
  owner and shows the fallback in the same run.
- `mount_hole` writes its stop marker in its first run, also when placing
  the content raises, so a hole that runs again before `Effect.run`
  returns has its range. `Show` and `Catch` call their children untracked.
- Islands: `boot` hydrates under an owner whose catch logs
  disposes the island, then logs `yuka island ID (NAME): message` with
  `console.error` and calls `Client.on_error` (set by `mount ~on_error`);
  an exception from `on_error` is dropped. The DOM stays as it is.
- Server: the printer remembers the buffer length and a copy of the
  session (`Types.snapshot`: every mutable field, with the `select` value),
  prints the children, and on an exception restores them (`Types.restore`), calls `log_error`, and
  prints the fallback with `~error:"server error"` between `<!--[!-->`
  and `<!--]-->`. The client reads `[!` on the start comment and starts
  with the fallback.
- Size: the routing is in every client app (about 180 B gzip on the keyed
  benchmark); `Catch`, `Show` and `Status` are top-level values, dropped
  when unused.

## Forms (2026-11-10)

Spec: `.workplace/docs/app-spec.md`, section 20, option B (ticket 20); its
"20: changes during build" lists the differences.

- `[@@deriving form]` (`ppx/form_gen.ml`) on a record writes `type
  <t>_field` (one constant constructor per label), `<t>_field_name` and
  `<t>_form : (<t>, <t>_field) Yuka.Form.t`. The generated decoder calls
  `Yuka.Form.field` for each label with a kind (`string`, `int`, `float`,
  `bool`, `option`, `list`, `custom M.of_string M.to_string`), collects
  every error in field order, and builds the record with `Form.finish`.
- `Form.action ~name ~fields ~output` is an `Action.t` whose input is sent
  as the encoded fields (`[[name, value], ...]`) and whose answer is
  `{"value": o, "redirect": "/..."}` or `{"errors": [[name|null, message]]}`.
  `Action.t` has a `form` field (raw fields to input JSON or errors JSON),
  set only by `Form.action`, so the cycle can decode a raw post without
  knowing the types.
- Request cycle: a `POST` to a page path (the route has `GET`) with
  `application/x-www-form-urlencoded` and a `_yuka_action` field is a form
  post. It checks the origin (`Origin` equal to `Host`, or no `Origin` and
  `Sec-Fetch-Site: same-origin`, else 403), the 1 MiB limit (413), and the
  action (404); it decodes, runs the JSON handler of the action, and answers
  303 to `redirect` or the page URL, or renders the page as for `GET`
  (guards and loaders run) with status 422 and `no-store`. The printer
  session holds `form = (action, fields, errors)`; `<Yuka.Form>` of that
  action prints the sent values and errors, and `data-yuka-sent` on the
  `<form>` so an island hydrates with them. Any other `POST` to a page is
  405 as before.
- `<Yuka.Form>` (`src/form.ml`): `<form method="post"
  data-yuka-action="NAME">` with the hidden `_yuka_action` input. In an
  island its `submit` handler reads `FormData` (`Web.form_values`), decodes,
  and calls the action; `pending` and the errors are States. A read of
  `Form.pending` outside a hole renders the enclosing component again (the
  demo's submit button is in a hole).
- Size: keyed app 10648 -> 10664 B gzip (it has no `form.js`; `make size`
  checks it); demo client 39764 -> 41400 B gzip.
- Demo: `/new` (server-only form, works with JavaScript off) and the new
  issue dialog (`<Yuka.Form>` in the `New_issue` island) share
  `Views.Issue_form`.
- Review fixes: `ADAPTER.body` takes `~limit` and gives `None` over it
  (`yuka-dream` reads the body stream and stops), used by the form post and
  the action call. The form post checks the origin from the headers first,
  then runs the page's guards, then reads the bounded body. `Action.t.form`
  is a GADT that holds the `Form.t`, so the cycle and `<Yuka.Form>` decode
  once with the typed decoder, and field names come from the `Form.t`.
  The redirect is read from each answer (no shared ref). The posted form
  is told by `?key` (`_yuka_key`); the 422 state goes to that form only,
  and an island keeps the state of `data-yuka-sent` until a submit in the
  browser removes the attribute. The browser adds
  the submitter's `name`/`value` to the fields. With no `on_ok` and no
  redirect, an island submit navigates to the page URL. The deriver
  refuses type parameters and labels that start with `_`, and reads
  `String.t`, `Int.t`, `Float.t`, `Bool.t` as the base kinds.
- Second review fixes: the action call checks origin, name and content
  type from the headers before it reads the body. `yuka-dream` refuses a
  `Content-Length` over the limit with no read and closes the body stream
  over the limit. The form 303 goes only to a path or a URL of the request
  `Host` with no control character (below space, or DEL: browsers drop
  TAB, CR and LF from a URL, so `/\t/evil.com` is `//evil.com`); else the
  500 page and a log. One origin rule,
  `Server.trusted_origin`, for form posts, the action call and `Action`
  routes. Unknown field names in errors from the server are form errors;
  a `data-yuka-sent` that does not parse is ignored (a console message in
  a dev build). A form post with a content type other than
  `application/x-www-form-urlencoded` is 405 before the guards run.


## Prefetch, navigation cache and view transitions (2026-11-10)

Ticket 22; `.workplace/docs/app-spec.md` section 22, option A.

- One cache in `Navigation`: a `Web.table` from `absolute URL without
  fragment ^ " " ^ outlet keys` to an entry (answer or in-flight fetch,
  waiters, time, prefetched). The keys are part of the key because the
  answer depends on `Yuka-Navigate` (`Vary`). At most 30 entries; the
  oldest goes first (`Map` keeps insertion order).
- Lifetime from the answer's own `Cache-Control` (`Web.max_age`):
  `max-age=N` without `no-store` or `no-cache` keeps it N seconds, also
  for back and forward; otherwise only a prefetched answer is kept, used
  once, within 10 s. A navigation fetch is stored only when `max-age` is
  above 0 and no `clear` happened since it started (`era`).
- Dropping entries (`clear`, eviction of the oldest when a new key comes
  in) aborts an in-flight prefetch unless a navigation waits for it; that
  navigation still gets the answer. `unmount` aborts every fetch, and it
  and a `popstate` to the shown page bump the navigation counter, so a
  waiting navigation does nothing.
- A navigation finds an answer (used at once, no fetch), an in-flight
  prefetch (it waits), or nothing (it fetches as before). A counter drops
  the answer of a navigation that a newer one replaced; a prefetch is never
  aborted by a navigation, only by `unmount`.
- Prefetch: delegated `pointerover`/`focusin` start a 50 ms timer,
  `pointerout`/`focusout` and any navigation cancel it; `touchstart` and a
  `pointerdown` that would be a plain click prefetch at once. Links are the ones a click
  would navigate (`Web.link_href`), minus `data-yuka-prefetch="off"`.
  `IntersectionObserver` watches visible links after start and after each
  navigation. A prefetch sends `Yuka-Prefetch: 1` and `cache: "no-store"`:
  with the default cache mode, Chrome's HTTP cache lock made a same-URL
  page load in a new tab (ctrl-click) wait for the end of a streamed
  prefetch.
- Actions: `Platform.acted` is called by the action transport on an `ok`
  answer; navigation sets it to empty the cache. Anything that calls an
  action through the transport (later `Remote.mutate`) empties it too.
- Transitions: the history push and `loaded` change first; the DOM update
  (swap, scroll, island start) is one function. With `~transitions:true`,
  `Web.transition` runs it in `document.startViewTransition`, rethrows an
  exception from it in a task (an uncaught error, not a rejected promise),
  ignores the rejected `ready` of a skipped transition, and removes
  `data-yuka-nav` when the last started transition finishes. The direction of `popstate` compares the history keys
  (`time-counter`, made in order).
- Size: about 1.4 KB gzip in an app that mounts navigation (demo +1381 B); 0 in
  the keyed benchmark, which does not.

## CSS per module (2026-11-10)

Ticket 23; `.workplace/docs/app-spec.md` section 23, option B built
through A.

- One sheet per file, declared by `module Css = [%yuka.css "file.css"]`
  (a whole-file pass of the ppx, after `let%client`). The ppx reads the
  file next to the source (dune `preprocessor_deps`), scans the selectors
  (`ppx/css_scan.ml`: comments, strings and `url()` with a quoted or bare
  argument are skipped; a segment is a selector when it ends with `{` and
  does not start with `@`, except `@scope` (all of it) and `@supports`
  (inside `selector()`); `[...]` is skipped; class names follow the CSS
  identifier rules, with escapes and non-ASCII code points) and makes
  `Css.stylesheet` and one string per class, the unescaped name and
  `_HASH`. The OCaml name keeps letters, digits and `_`, other ASCII
  becomes `_`, a leading digit gets `_`; a non-ASCII name is an error. The hash is the first 8 hex digits of the MD5 of the
  file text, for both the class names and the file name
  `BASE-HASH.css`: the ppx and the generator see the file under different
  paths, and the same text gives the same rules.
- The ppx wraps the body (or each case of a `function`) of each `make`
  after the declaration that returns an element: a `let%client`, a body
  in JSX (also through `let`, `match`, `if`), or an `element` type on the
  binding or the result. Other functions named `make` (constructors) are
  left alone; a `make` that is not a function gets a `ppwarning`. On the server, `use_css` returns
  `Fragment [<link data-yuka-css>; body]`; in the browser it adds the link
  to `<head>` if the document has none and returns the body. The client
  tree has no new node kind, so `mount_node` and the keyed benchmark do
  not change (10,026 B gzip).
- Printer: the link is printed once per session, in document order, at
  print time (components run before printing, and list elements are
  evaluated right to left, so the order of `use_css` calls is not the page
  order). Where the output is hydrated (inside an island), it is held and
  written before the outermost island's `<yuka-island>`, after its
  `modulepreload`, by cutting the buffer at the island's start; held links
  of a fill inside an island go before its `<template>`. A link used in
  the `loading` part of a streamed `Await` goes before the region's
  start marker (or to the island), since the fill replaces the region.
  `Private.render_html` (whole-tree hydration) prints no links. `each` rows and
  the other places that look at a node's shape see the body, as the client
  does. A `Catch` that fails restores the printed set.
- Navigation: at start and before and after a swap,
  `Web.adopt_stylesheets` moves `link[data-yuka-css]` from the body to
  the head in one pass, dropping one whose `href` is there, so a swap
  never deletes a sheet that content outside the outlet needs. Sheets are
  never removed. `add_stylesheet` keeps the known `href`s in a `Set` on
  the document, filled from the DOM once.
- Cycle: `config ~css` holds the generated `(file, text)` list from
  `yuka-css` (which finds the `[%yuka.css]` declarations in the sources,
  so a sheet cannot be missed by a glob; a missing file fails the build).
  Names must be one path segment (`Invalid_argument`). Served at
  `/_yuka/css/FILE` (decoded) with `Immutable` for `GET` and `HEAD`, 405
  otherwise; any other path there is a 404 `no-store`. `Server.css_files` gives them to a
  prerender. The text lives only in the server executable; a client bundle
  has the URL and the class names.
- `Yuka.stylesheet` is a top-level value: the generated code first used
  `Yuka.Private.stylesheet`, and the `Private` record kept the server
  printer in the demo client chunk (`make size` caught it).

## Dev server (2026-11-10)

Ticket 24; `.workplace/docs/app-spec.md` section 24, option A, level 1.

- `yuka dev` is the native executable `yuka` (package `yuka`, library
  `unix`, no Dream): the spec puts it in `yuka`, and it talks only to dune
  and a child process, so `yuka-dream` users and other adapters get it.
- It runs `dune build --watch TARGETS` with stdout and stderr in one pipe,
  echoes every line, and reads the status lines: `Success, waiting for
  filesystem changes...` and `Had N errors, waiting...` (the lines in
  between, after `NEW BUILD`, are the error text). No dune RPC: the line
  is enough, and RPC needs the `dune-rpc` library.
- State: a file (`--state`, default `_build/.yuka-dev`), one JSON line
  `{"build":B,"page":P,"error":E}`, written by rename. `build` counts the
  builds that changed something, `page` is the last that needs a reload.
  On success: the server executable's stamp (mtime and size) changed, the
  server exited, or the first build: stop and start the server,
  `page = build`; else files under `--assets` changed: `build + 1`, and
  `page = build` unless all are `.css`. On failure: the same numbers with
  the error. The server is started with `YUKA_DEV=1` and
  `YUKA_DEV_FILE=<state>`; the spec's `YUKA_DEV_BUILD` is not needed,
  since the server reads the file.
- Server: `config` reads `YUKA_DEV` (so nothing changes in the app).
  `/_yuka/dev` is a `Stream` that sends the file's line (newlines joined)
  when it differs from the last one, checking every 0.25 s with the
  adapter's `sleep`; a closed connection ends it through the failed
  write. Full pages (not navigation answers) get the script in the head,
  with the state at render time, `<` escaped.
- Browser script (inline, about 1.2 KB, only in dev pages): an
  `EventSource`; `page` above the page's: save `scrollY` in
  `sessionStorage` and reload (restored on `load`); `build` above: add
  `?v=build` to each `link rel=stylesheet` that is not a `[%yuka.css]`
  sheet (those change their class names, so they come with a page build);
  `error`: a fixed `<pre id="yuka-dev-error">`, removed by the next state
  without one. A restarted server makes `EventSource` reconnect; the first
  event then carries the new numbers.
- Production: no route, no script, no client module; `make size` and
  `make measure-pages` do not change.
- Review fixes:
  - A change under `--assets` restarts the server, unless only `.css`
    files changed; the server reads the manifest, the metafile and the
    build id at start.
  - `/_yuka/dev` is a callback loop with no growing chain. It sends
    `: ping` after 15 s without a change, ends on the first failed
    write, and answers `HEAD` with headers only.
  - The state has a random `session` per `yuka dev` run; a page that sees
    another session reloads.
  - The CSS swap keeps other origins as they are and writes `u.href`.
  - The watched executable is looked up in `PATH`, or named with
    `--watch-exe`.
  - Any exception in the loop stops the server and dune. The state
    directory is made with all its parents.
  - `stop` keeps the pid until the process is reaped and retries
    `waitpid` on `EINTR`. A signal during a restart then stops the old
    server (also after `SIGKILL`) and starts no second one.
  - Deleted asset files count as changes.
  - `json_string` is shared in `gen/source_text.ml`.
  - The state file is read through `Web.read_file`, which is native only,
    so the cycle has no channel primitives for Melange.
  - A prerender uses `Server.prerender_config` (`YUKA_DEV` ignored), and
    with `YUKA_DEV` prerendered routes render live.


## Server rendering speed (2026-11-10)

Ticket 31. The printer and the request cycle changed; the HTML is byte for
byte the same (`bench/ssr/ocaml/golden.expected`, `demo/test/pages.expected`).

- Text and attribute values are escaped straight into the output buffer;
  a value with nothing to escape is copied once.
- An element prints its attributes from its attribute list. Only `a`
  (`aria-current`), `option` (`selected`), `select` and `textarea`
  (`value`) build the resolved list.
- The output buffer is reused between renders: `Web.take_buffer` and
  `Web.give_buffer`, behind a `Mutex` on the server (system threads of one
  domain, and several domains, share the pool; `test/threads` renders on 16
  threads) and a plain list in the browser. A buffer that grew past
  256 KB during a render (even if truncated later) is not kept.
  `printer.ml` uses no `Mutex` or `Domain` itself: a module with a
  top-level side effect reached from `yuka.js` would pull them and
  `Printf` into every client bundle.
- A template has an `ops` field: on the server, the first instance compiles
  the shape into static HTML chunks (tags with fixed attributes, escaped
  fixed text) and slots for its parts; later instances print the chunks
  and the parts with no `Element` tree. Parts that need state stay
  dynamic: a fixed text (the `<!---->` rule between texts), an element
  with a part attribute, `a`, and the whole subtree of `select`, `option`
  and `textarea`. A part that is the only child of its element is printed
  as `contents` prints it (a hole there has no markers).
- The cycle keeps the head and the shell as a list of strings. When
  nothing is pending after the shell, the page is answered as one string
  (with `Content-Length`); otherwise it streams as before. A `HEAD` renders
  the page like `GET` and sends the same headers with no body: the length
  of the string, or a stream with no content. Before, a `HEAD` did not
  call the page body and sent `Content-Length: 0`.
- One escape (`Template_build.add_escaped`, and `escape` built on it), one
  expansion of a shape (`Template.expand_shape`, used by `expand` and by
  the printer for `select`, `option` and `textarea`), one test of the tags
  that need the resolved attributes (`needs_special`).

## Unsafe URLs and raw-text elements (2026-11-10)

Ticket 33 and its security review.

- Rule (`src/url.ml`, shared with the ppx; names and tags lowercased by the
  caller): a URL attribute is `href`, `src`, `action`, `formaction`,
  `xlink:href`/`xlinkhref`, `poster`, `cite`, `data`, `background`,
  `longdesc`, `manifest`, `codebase`, `icon`, and `values`, `to`, `from`,
  `by` on `animate`, `set`, `animateMotion`, `animateTransform` (each
  `;`-separated item of `values`). The value is read as the URL parser
  does: leading characters up to space dropped, tab, newline and CR dropped
  anywhere, any case. `javascript:` and `vbscript:` are blocked on every
  URL attribute. `data:` is blocked only where it opens or loads a
  document: `href` of `a`, `area`, `use`; `action`; `formaction`;
  `xlink:href`; `src` of `iframe`, `frame`, `embed`, `object`; `data` of
  `object`. With no known element (`Yuka.attr` in the browser), `href` and
  `data` count as such and `src` does not. A blocked value becomes
  `about:blank#blocked` (React's rule; React blocks only `javascript:` and
  has no escape hatch, Angular checks `data:` and has one, Svelte, Solid and
  Vue do not check). `srcdoc` is an HTML sink and is not checked (React
  neither).
- Sinks (`Url.check ~tag ~log`): the server printer, for every attribute
  it prints, with the element (one check per print; `log_error` once per
  process); in the browser, `Yuka.attr` and each value of `Yuka.hole_attr`
  (no element), and the ppx's `Yuka.url_attr tag` and `url_hole_attr tag`
  (with the element). Constructors do not check on the server.
- The ppx emits `url_attr`/`url_hole_attr` for checked names and
  `attr_unchecked`/`hole_attr_unchecked` for the others. The unchecked ones
  refuse a URL name at run time (`Web.refuse_url_name`, a regular
  expression in the browser), so they cannot set an unchecked URL. That
  guard and the client guard below cost the keyed app 228 B gzip
  (10,034 -> 10,262; budget raised to 10,262).
- Raw text: in HTML (not under `svg` or `math`; `foreignObject` is HTML
  again), `script` and `style` take no child, one `Text` or one `Hole`
  that gives a `Text`; anything else raises `Invalid_argument` before
  anything of the element is printed (server) or built (client). The ppx
  joins the strings and `(Yuka.text e)` children into one text (a hole if
  one reads a State) and refuses other children with a located error. The
  text is printed by `add_raw`: in a JavaScript script (no `type`,
  `module`, or a JavaScript MIME type) `</script` and `<!--` get `\` after
  `<`; in a style, `</style`; in a script of another type every `<` becomes
  `\u003c`. Foreign context is a stack in the printer, also pushed and
  popped by template ops (`Push_context`, `Pop_context`) around the
  children of `svg`, `math` and `foreignObject`, since a template prints
  their tags as static chunks. A dev client does not log a text mismatch
  inside `script` or `style` (the server text has the escapes).
