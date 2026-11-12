# Yuka v0.1 design

Status: decided by the agent on 2026-11-06, as the user asked. Earlier
decisions: `brain-dump/DECISIONS.md`. Each item here can change; a change is
recorded here first.

This file is a log. The sections up to "Demo: mini Linear" describe the
model and are kept current. The dated sections after them record a
decision with the names of its date; a later section can change an earlier
one, and a note under a dated heading gives the current name of what it
calls by an old one. "API for 1.0 (2026-11-11)", the last section,
describes the current API and lists the names that changed.

## Toolchain

- OCaml 5.4.1, dune 3.24.2, Melange, mlx, Dream, ppxlib, Alcotest: a local
  opam switch (`_opam`) at the root of the checkout. The `Makefile` finds it
  and runs every command as `opam exec --switch=<root> -- <command>`
  (`SWITCH=` overrides it).
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

Current layout:

| Library | Modes | Directory | Holds |
|---|---|---|---|
| `yuka` | native, melange | `src/` | everything users call: State, Effect, elements, Json, Codec, Async, Action, `Yuka.Server`, `Yuka.Client` (islands and browser runtime), `Yuka.Router`, `Yuka.Await`; the virtual DOM module `Web` |
| `yuka.js` | melange | `dom/js/` | the browser implementation of `Web` (a Melange entry lists it) |
| `yuka.native` | native | `dom/native/` | the default implementation of `Web` (raises "browser only"); a Melange build that does not list `yuka.js` fails to build |
| `yuka.ppx` | native | `ppx/` | mlx to element calls, attribute checks, holes, lints, `let[@client]`, `[@@deriving codec]`, `<Yuka.Client>`, `<Yuka.Await>`, templates, `Yuka.render ~islands` |

The executable `yuka` (`gen/`, package `yuka`) has the commands `routes`,
`islands`, `css` and `dev`.

Platform functions (event fields, window listeners, navigation) are a record
of functions in the core (`Private.platform`). Their defaults call `Web`, so
in the browser they work without a boot step, and on native they raise; they
are only called inside effects and handlers, which never run on the server.
`Yuka.render ~islands` with navigation replaces `navigate`.

## HTML and hydration markers

The server output and the client hydration must agree on this format.

The browser hydrates only `<yuka-island>` elements, so the page printer
(`Yuka.Server.to_string` and the request cycle)
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
  same HTML as the same tree made with `Yuka.element`.
- `Fragment`: no marker; the children are inline.
- `Catch`: as a `Hole`. When the children raised on the server, the hole
  holds the fallback and its start marker is `<!--[!-->`.
- `Static` attribute: written. `Dynamic`: written with its current value;
  `None` is not written. `Handler`: not written.
- Void tags (`area base br col embed hr img input link meta source track
  wbr`): no closing tag, no children.

## ppx

- mlx gives `[@JSX] tag ~a:1 ~children:[...] ()`. The ppx turns a lowercase
  tag into `Yuka.element "tag" [attributes] [children]` (since 2026-11-10 a
  compiled template; see "Compiled templates and fewer markers"), with html_of_jsx's
  attribute checks as the baseline (valid attributes for the tag, plus
  `data-*` and `aria-*`), and `on_click` style props into `Yuka.on "click"`.
  Props on a lowercase tag are snake_case: `on_` and the DOM event name
  (`on_mousedown`), and the snake form of other names (`view_box`,
  `stroke_width`, `accept_charset`). A prop with an uppercase letter is an
  error that gives the snake name.
- An uppercase tag `<Issue.Row a=1 />` becomes `Issue.Row.make ~a:1 ()`, with
  `~children` only when children are given.
- A string literal child becomes `Yuka.text`. A child or an attribute value
  that contains `State.get` (or `Yuka.State.get`) becomes a hole:
  `Yuka.hole (fun () -> e)` or `Yuka.hole_attr name (fun () -> Some e)`.
- Lint: `open Yuka.State`, `Yuka.State.( ... )` and a module alias of
  `Yuka.State` are errors.

## Islands

- `let[@client] make ~(a : int) ~(b : Issue.t) () = ...` in a module `Counter`
  declares a client component (`[@yuka.client]` is the long name). Every labelled argument has a type. The ppx
  adds `Counter.island` (server side: encodes the props, returns a
  `server element`) and `Counter.register` (client side: decodes the props and
  mounts).
- `<Yuka.Client><Counter a=1 b /></Yuka.Client>` becomes `Counter.island ~a:1 ~b ()`.
- Codecs: Yuka's own JSON type and printer/parser in pure OCaml, the same on
  both targets. `[@@deriving codec]` writes `codec` for records and
  variants. The codec of a type expression: `int`, `string`, `bool`,
  `float` and `list`, `option` map to `Yuka.Codec.*`; `Issue.t` maps to
  `Issue.codec`; `Issue.foo` maps to `Issue.foo_codec`.
- The server writes `<yuka-island data-name="Counter" data-id="i1" style="display:contents">html</yuka-island>`
  (with ` data-start="idle"`, `"visible"` or `"interaction"` after the style
  for the `start` prop of `<Yuka.Client>`; nothing for `` `Load ``)
  and the props as `<script type="application/json" data-yuka-props="i1">`.
  The client entry starts the islands it knows: `Yuka.render ~islands ()`,
  where `yuka islands` writes the registry of every `Counter.register`.
- Ids made inside an island carry the island's id as prefix.

- Island name: `<Library>.<Module path>` (library name from dune's
  `library-name` cookie), the same in native and Melange builds.
- Codec shapes: a record is an object keyed by field name; an `option`
  field is always written (`null` for `None`) and a missing key decodes as
  `None`. A constant constructor is `"A"`, one with arguments is
  `["B", arg1, ...]`, an inline record is `["C", {...}]`. A tuple is a list.
- Not supported yet (compile errors): recursive types, type parameters,
  `~children` on a client component (slots), a start strategy on
  `Yuka.Client` (added in v0.2; now the `start` prop).

## Async and streaming

- `'a Yuka.Async.t` is a pure OCaml promise (pending, resolved, failed, with
  callbacks), the same on both targets. The app bridges it to its own I/O (Lwt in the demo), the
  client to JS promises.
- `Yuka.Await.make ~async ~loading ?failed ~children ()` (the component
  `<Yuka.Await>`; `children` is the function from the value to the element) makes the node
  `Await { async; loading; failed; render }`. `failed` gets the error
  message; default: nothing. In a server render the message is the one of
  a `Server.Action.reject`, else `"server error"`, and the detail goes to
  the `log_error` of `Server.config`.
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
     with JSON `{"ok": value}` or `{"error": message}` (the message as for
     `failed`).
  4. `</body></html>` when everything has settled. The fill script
     (`Yuka.Private.fill_script`) defines `window.__yukaFill(id)` in the head. It finds the comment
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
    function given to `to_string`, `page` or `Private.stream`; outside
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
  `let create_issue = Yuka.Action.mutation ~name:"create_issue" ~input:Issue.input_codec ~output:Issue.codec`.
- Server code implements it: `Yuka.Server.Action.implement create_issue (fun ctx input -> ...)`
  (returns `Async.t`; `ctx` is the request, a `Server.context`). Any page
  can call any action, so the action checks permissions itself.
  Implementing a name twice raises `Invalid_argument`.
- `Yuka.Action.call create_issue input : (Issue.t, Status.error) result Async.t`. On the client it
  is a `POST /_yuka/action/create_issue` with JSON. On the server it calls
  the implementation directly (installed by the first `implement`).
- Wire format of the action call `POST /_yuka/action/:name` (the request
  cycle answers it; `Yuka.Private.handle_action` in tests): the body
  is the JSON input. The answer is JSON: `{"ok": output}` with 200, or
  `{"error": message}` with:
  - 403: an `Origin` whose authority is not the request `Host` (scheme
    ignored) or, with `Server.config ~origins`, not one of those origins;
    or no `Origin` and no `Sec-Fetch-Site: same-origin`. `Origin` without
    `Host` is refused. Form posts, `Action` routes, endpoints with an unsafe
    method (unless `~cross_origin:true`), `/_yuka/csrf` and `/_yuka/live`
    use the same rule.
  - 404: unknown action.
  - 415: `Content-Type` is not `application/json` (parameters such as
    `charset` are allowed).
  - 400: the body is not JSON, or the input does not decode, or the
    implementation gave `Server.Action.reject message`. The message says
    which.
  - 500: the implementation raised or its promise failed. The message is
    always `action failed`; the failure goes to the `log_error` of
    `Server.config`.
  - 413: the body is over 1 MiB (`Server.Adapter.Backend.body ~limit`: `Content-Length` first,
    then while reading). The message is `request too large`.
  Checks run in this order: origin, action name, content type (all from
  the headers, no body read), body size, body.
- A ppx form (`let%action`) can come later; this form needs no target
  switch in the ppx.

## Router

- Pages are server routes (a multi-page app). Since 2026-11-10 they come
  from `Routes.ml` through `yuka routes` and the request cycle; see
  "Routes.mlx generator", "Request cycle", "yuka-dream" and "Routes.ml:
  one OCaml expression". The typed
  path GADT of `Yuka.Router` is gone. A link is
  `Routes.issue ~id ()`; see "Route helpers".

## Demo: mini Linear

- Server: Dream, data in memory, seeded.
- Pages: issue list (`/`), grouped by status; issue page (`/issue/:id`) with
  comments that stream in after a delay.
- Islands: the issue list (filter, keyboard `j`/`k`, status and priority
  change with an optimistic update through a server action), "new issue"
  dialog (`c` opens it), comment box.
- Style: one CSS file, dark, compact, Linear-like.

## Answers to the demo's friction list (2026-11-06)

Current names: `Yuka_server` is now `Yuka.Server`; `Yuka.list` and `Yuka.array` are removed (use `fragment`); `Server.Action.reject` returns a failed `Async` instead of raising; event handlers now run in a batch (see "Equality and batch").

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
  changed. A lint for this comes later: replaced on 2026-11-12 by a check
  at run time; see "Module-level State".
- A `State.set` updates holes synchronously when no `Yuka.batch` is
  running, so code right after it (for example `Browser.focus`) sees the new
  DOM.

## v0.2: the rest of Yuka (decided 2026-11-06)

Current names: `Yuka_server` and `Yuka_client` are now `Yuka.Server` and `Yuka.Client`; the island strategy `loading` is now the `start` prop of `<Yuka.Client>` (`type start`); `Client.island` is now `runtime_island`, which only the ppx calls; `Yuka_client.start` is now `Yuka.render ~islands ()`; `let%client` is now `let[@client]` (see "`[@client]` attribute").

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
  `<Yuka.Client><Counter a=1><p>"x"</p></Counter></Yuka.Client>` becomes
  `Counter.island ~a:1 ~children:(Yuka.Slot.make (Yuka.fragment [...])) ()`.
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
  client code paths write it: replaced on 2026-11-12 by a check at run
  time; see "Module-level State".
- Production bundle: esbuild bundles the Melange output of the client entry
  into one ES module (`--bundle --format=esm --minify`); the server serves it
  instead of the module tree when started with `--bundle`.

### Out of scope for v0.2

- Reversed by the user (2026-11-06): all five items are in scope. See v0.3.

## v0.3: router, early islands, chunks, templates, typed errors (decided 2026-11-06)

Current names: `Action.declare` is now `Action.mutation`; `Router.start` is now `Yuka.render ~islands ()` and `Router.navigate` is `Browser.navigate`; `Client.entry` and `Client.lazy_entry` are now `runtime_entry` and `runtime_lazy_entry`, which `yuka islands` writes; `Yuka_server` and `Yuka_client` are `Yuka.Server` and `Yuka.Client`; `let%client` is now `let[@client]` (see "`[@client]` attribute").

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
  `Yuka_client.lazy_entry ~name (fun () -> <dynamic import of Counter.register>)`.
  The module is loaded only when the island's start strategy fires (so
  `` `Visible `` and `` `Interaction `` islands load their code late).
- The ppx exposes `Counter.name` from `let%client`.
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
- `[%yuka.lazy Lib.Counter "path/to/counter.js"]` (client entry only) makes the lazy entry:
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

Current names: `Yuka.Server.stream` and `handle` are gone: `Server.Adapter.Make(Backend).handler` runs the request cycle (see "Request cycle"); `Client.lazy_entry` is now `runtime_lazy_entry`.

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

Current names: `yuka-islands --library NAME DIR` is now `yuka islands --dir DIR` (the library name comes from `DIR/dune`); `Client.entry`, `Client.lazy_entry`, `Client.promise`, `Client.promise_map` and the value `Client.registry` are now `runtime_entry`, `runtime_lazy_entry`, `runtime_promise`, `runtime_promise_map` and `runtime_registry` (the type `Client.registry` stays); `Router.start` and `Router.navigate` are `Yuka.render ~islands ()` and `Browser.navigate`; `let%client` is now `let[@client]` (see "`[@client]` attribute").

`Yuka.mount` is now `Yuka.render ~islands`: see "`Yuka.render`, one client
start".

The user: users never write `Counter.register` or an island list, and the client
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
- `Router.start` from `yuka.mli`; `Counter.register` from README and demo.
  `Counter.register` stays a value of the island module, because the generated
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

Current names: The island prop `loading` and `type loading` are now `start` and `type start`; an island may have its own prop named `loading`. `yuka-islands` is now `yuka islands`; `let%client` is now `let[@client]` (see "`[@client]` attribute").

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

Current names: `yuka-islands` is now `yuka islands`; `let%client` is now `let[@client]` (see "`[@client]` attribute").

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

Current names: `Yuka.Template.t` and `template_coded` are now `runtime_template`, `template_instance` is `runtime_instance`, and `url_attr`, `url_hole_attr`, `attr_unchecked` and `hole_attr_unchecked` are `runtime_url_attr`, `runtime_url_hole_attr`, `runtime_attr` and `runtime_hole_attr`: names for the ppx only. `Template.make` and `template_of_shape` are now `Private.Template.make` and `Private.template`, and `Client.hydrate` is `Private.hydrate`, for tests. `lower` is now `Yuka.element`.

### Template format

- The ppx turns each lowercase JSX tree into a `Yuka.Template.t`, made once
  at the top of the module (`let __yuka_template_<module>_N =
  Yuka.template_coded code ~html ~walk ~kids ~attrs ~values`), and a
  `Yuka.template_instance` call with an array of parts at the place of the
  JSX. `code` is the shape in one string (`Template_build.encode`): an
  element is `\x01` tag, `\x03` name `\x04` value per fixed attribute,
  `\x05` per attribute part, `\x02`, the children, `\x06`; a text is `\x08`
  and the text; a child part is `\x07`; a byte below `\x10` in a name, value
  or text is `\x0f` and the byte plus `0x40`. Part numbers are the order of
  the markers. The `Yuka.template_*` functions are top-level values, so an
  app does not keep the `Yuka.Template` module object. Nested lowercase tags are part of the same template. The ppx adds the
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
  it. So the HTML and the hydration walk do not change. They decode `code`
  on first use (`Template.shape`). Fresh client creation does not need the
  shape, so only the code that installs them links the decoder and
  `expand`: `Client.hydrate` sets `Template.expander` and the adopt steps
  (`drop_rest`, `adopt_slot` in `client.ml`), and `Template.make` sets the
  expander and the run-time check below. A render-only app links none of
  them (keyed app, A and C of the 2026-11-11 council: 10,846 -> 10,158 B
  gzip).
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
- The HTML parser can change a tree (a `tbody` added in a `table`, a `p`
  closed by a block, `template` children moved to `.content`, a leading
  newline dropped in `pre` and `textarea`, `html`/`head`/`body` dropped,
  `\r\n` read as `\n`, entities kept literal in `style` and `script`). The
  ppx checks the shape at build time (`Template_build.parser_changes`) and
  lowers a template that the parser could change with `Yuka.lower`, the
  tree that the client used to build element by element after a failed
  check. The check reads the shape as the tree construction stage of the
  HTML standard does (section 13.2.6), in two contexts: in a `<template>`
  (the "in template" mode lets a `tr`, `td`, `col`, `caption` or table
  section be the root) and inside an `<svg>` in a `<template>`, where the
  client parses a template that is mounted in SVG content. The ppx lowers
  the template when the parse fails in its own context (inside `<svg>` for
  a root that is an SVG element and not an HTML element, else in the
  `<template>`), and gives the result of both to `template_coded` as
  `~clones` (bit 1 HTML context, bit 2 SVG context). It changes the tree
  on: a start tag that closes a `p` in button scope
  (`div`, `table`, headings, lists, `form`, `hr`, ...); `li` in an open `li`
  and `dd`/`dt` in an open `dd`/`dt` (the "in body" loop); a heading in a
  heading; `a` in an `a` with no marker between (adoption agency); `nobr`
  and `button` in scope; `form` in a `form`; a table element out of its
  place, and anything but its own children in `table`, a table section,
  `tr` or `colgroup` ("in table" foster parenting), non-space text there;
  in `select` anything but `option`, `optgroup`, `hr`, in `optgroup`
  anything but `option`, any element in `option`; `rb`/`rtc` out of
  `ruby`, `rt`/`rp` out of `ruby` or `rtc`; children of `template`; a
  leading newline in `pre`, `listing`, `textarea`; an element or two texts
  in `title`/`textarea` (RCDATA), and also an entity in `xmp`, `iframe`,
  `noembed`, `noframes`, `noscript`, `style`, `script` (RAWTEXT);
  `html`, `head`, `body`, `frameset`, `frame`, `image`, `plaintext`,
  `math`; a child element or text in `param`, `keygen`, `basefont`,
  `bgsound` (the parser closes them at once, and the printer writes their
  end tag); a tag name that the parser would write in another case (HTML
  lowercases; SVG uses its camelCase table); `\r` or NUL in a text; in
  SVG, a tag that breaks out of foreign content (`div`, `p`, `span`, `b`,
  `font`, ...) and an HTML void name (no end tag is printed). Elements the
  "in body" mode closes at once were checked against the standard: `area`,
  `br`, `embed`, `img`, `wbr`, `input`, `source`, `track`, `hr`, `base`,
  `link`, `meta` are void for the printer (no children, no end tag, as
  before); `keygen`, `param`, `basefont`, `bgsound` are the rule above;
  `col` and `frame` are table placement and always lowered. The check may
  refuse a tree that would parse the same (about 19% of the refused checks
  in the test); it must not accept one that would not:
  `test/templates/nesting` compares it with jsdom's parser in both
  contexts on 4,500 random trees with a fixed seed. Two jsdom departures
  from the standard are left out there and named in its output: `search`
  is not special in jsdom, and an SVG `select` resets jsdom's insertion
  mode by its tag name.
- The client clones a ppx template only in a context whose bit is set in
  `clones`. In the other context (HTML content inside `<svg>`, such as
  `<a><span>` or a `wbr`, or SVG content outside it) it takes the expanded
  tree, element by element, as it did when the run-time check failed. An
  app that hydrates links that path; an app that only renders does not
  (it would cost the keyed app 1,059 B gzip: 10,108 -> 11,167), so there
  `Template.expander` raises `Failure` with the template's HTML. Such
  trees are not valid SVG content, so a render-only app does not need
  them. `test/templates/render_only` mounts the coded templates in a
  process that never hydrates nor makes a template at run time.
- A literal `srcdoc` of `iframe` or `href` of `base` in a tree that the
  ppx lowers stays a template of its own (that element and its children,
  with its parts renumbered) when that subtree parses as it is, so it
  prints and mounts as given, as in any template; otherwise it goes
  through `url_attr` and becomes `""`.
- Dev build: after the first parse of a ppx template, the client compares
  the parsed tree with the decoded shape, in the context it parsed it in,
  and logs a difference with `Dev.mismatch` and the template's HTML. The
  check is behind `__YUKA_DEV__`, so a production bundle does not contain
  it (the keyed bundle is the same file with and without it).
- A hand-written template (`Template.make`, `template_of_shape`) is
  still checked at run time after its first parse (`Template.check`, the
  same element names, numbers of children and static texts); when the check
  fails, its instances are created from the expanded tree.
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
- Event handlers run in a batch (since 2026-11-11): each delegated or
  direct handler and each `Browser.on_window` handler runs in `batch`, so
  the DOM updates and effects run once after it returns. `Browser.focus`
  and `Browser.scroll_into_view` called in a batch run after it, so they
  find an element that the handler's write creates. When a handler raises,
  its writes still apply, and its exception and an error of the update go
  to the boundary.

### Function arity in the JavaScript output

- Melange calls a function through `Curry._N` when it cannot see its arity.
  It cannot for a module alias (`module State = Base.State`, or a module
  that `include Element` brought in): user code then called every
  `Yuka.State.*` and `Yuka.Template.*` function through `Curry`. `State` and
  `Template` are now their own files, and `yuka.ml` binds them with
  `module State = struct include State end`, which Melange compiles with known
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

Current names: The template and attribute names are the `runtime_` names of "Compiled templates and fewer markers"; `Template.make`, `template_of_shape` and `Client.hydrate` are in `Private`; `lower` is `Yuka.element`; `Yuka.unmount` is `Yuka.stop`; `Router.navigate` is `Browser.navigate`.

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
  used together, a feature submodule is a module alias (see "Pages pay for
  the features of their islands" below), and a feature that only some apps
  need is a top-level value of `Yuka` (an ES export, dropped when unused) or
  is reached only from one:
  - The registry given as `Yuka.render ~islands` is the only way to the
    island runtime, the action transport, the async-value watcher and
    navigation.
    `Client.start` and `Client.stop` are gone from `Yuka.Client`;
    `Yuka.render ~islands ~navigation:false ()` starts the islands and
    `Yuka.unmount ()` stops them and navigation (listeners, a fetch in
    flight, `Browser.navigate`).
  - `Router.navigate` is gone from `Yuka.Router`, which now holds only the
    route functions. `Browser.navigate` is a client navigation after
    `render ~islands` and `location.assign` otherwise, as `Router.navigate` was.
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

### Minify with swc after esbuild (2026-11-11)

- A production bundle is two steps: esbuild bundles and minifies, then swc
  minifies each output file again. `scripts/bundle.ts` does both;
  `demo/bundle.sh`, `bench/keyed/build.sh` and `make size` use it, so they
  measure and serve the same bytes. An app can copy the script; it needs
  the npm packages `esbuild` and `@swc/core`:

      node scripts/bundle.ts --entry main.js --outdir dist
      node scripts/bundle.ts --entry main.js --outdir bundle \
        --format esm --splitting --metafile meta.json

  It passes `--define:__YUKA_DEV__=false`. Dev builds do not change.
- Why: esbuild does not inline functions or remove aliases, and Melange
  output has many (`let make = State.make`, wrappers of externals). swc
  (`compress.passes = 3`) removes them. The keyed app goes from 30,688 B,
  10,846 B gzip to 27,852 B, 9,675 B gzip; the demo, all chunks, from
  48,393 B to 44,553 B gzip. The e2e check of the demo in bundle mode
  passes.
- Like for like: `make bench-keyed` builds the Solid app with rollup and
  babel, without terser, and then with the same script: its JavaScript is
  4,715 B gzip, where rollup and terser gave 4,812 B.

### Mount code per node kind (2026-11-11)

- `mount_node` matches every node kind, so before this change every app
  kept the mount code of every kind. Four kinds that an app may not make
  are now reached through a reference in `client.ml`, and the code is
  linked only when the app calls the function that sets it:
  - `element_hook` (an `Element` made with `createElement`): set by
    `Client.use_element`, which `Yuka.lower` calls (and `use_css` and
    `Form`, which build their nodes with `lower`), `Client.hydrate` (its
    expander builds `Element` nodes from the shape), and, in `yuka.ml`,
    `template_of_shape`, `Template.make`, `Private.template`,
    `Private.recompile` and `Private.expand`.
  - `await_hook`: set by `Client.use_await`, which `Await.make` calls
    (`suspend` too). It is a record with a polymorphic field, because the
    value type of an `Await` is existential.
  - `slot_hook`: `Client.use_slot`, from `Yuka.slot`.
  - `catch_hook`: `Client.use_catch`, from `Catch.make`.
  On the server the four `use_*` functions do nothing.
- Rule: every place that builds one of these nodes for the client calls its
  `use_*` function before it returns the node. Nothing resets a hook, so a
  node never reaches `mount_node` before its hook is set. The only other
  constructors are `Cycle.heading` (an `Element` for server error pages)
  and `Cycle.outlet` (the `yuka-outlet` element around a nested layout),
  both server-only. A default can therefore only run after a broken rule,
  and it raises `Failure "Yuka: no mount code for a node of Yuka.lower"`
  (or `Yuka.Await.make`, `Yuka.slot`, `Yuka.Catch.make`) instead of doing
  nothing.
- `Private.node` is `private` in `yuka.mli`: tests can match on it but not
  build a node kind without its constructor. `Private.hole` builds a
  `Hole` for the tests that need one.
- Checks: `test/mount_hooks` has one process per installer (`lower`,
  `Await.make`, `slot`, `Catch.make`, `template_of_shape`, `Template.make`,
  `Private.expand`) that makes its node only that way and never hydrates;
  without that `use_*` call, it fails with the error above.
  `test/constructors` parses `src/*.ml`, `dom/js/*.ml` and `dom/native/*.ml`
  with the OCaml parser and fails when `Element`, `Await`, `Slot` or
  `Catch` is built as an expression outside `src/element.ml`,
  `src/template.ml` and `src/cycle.ml`.
- `log` moved from `element.ml` to `types.ml` (`Element.log` is an alias),
  so `Element` can call `Client` without a cycle through `Platform`.
- Internal functions of `client.ml` take uncurried arguments (`[@u]`), so
  their calls are direct and need no `Curry`: `take`'s and
  `comment_where`'s tests, `walk_region`'s visitor, the four hooks and the
  list of mounted roots. Calls of functions that the app gives (`on`,
  `hole`, `hole_attr`, `each`, the `Await` children, the root of `render`)
  and of the dispose functions of `Base.mount` still go through `Curry`;
  removing them would change public types or the reactive core. Shared
  modules in `src/` cannot use `[@u]`: the library is compiled for native
  too and has no Melange ppx.
- The client's cache of a parsed template is a plain variant (`Empty`, or
  `Compiled` with the document and the cloned root) in `types.ml`, in place
  of an extensible type, so the bundle no longer needs
  `Caml_exceptions.create`.
- Size: the keyed app goes from 25,569 B, 9,104 B gzip to 24,482 B,
  8,698 B gzip (hooks 8,838 B, `[@u]` 8,769 B, cache 8,698 B). The demo,
  all chunks, goes from 44,109 B to 44,228 B gzip (+119 B): it makes nodes
  of every kind, so it keeps all the mount code and also pays for the four
  references, their default errors and the `use_*` calls.

### URL check per app (2026-11-11)

- `Client.set_attr` calls `url_hook` in place of `Url.check`.
  `Client.use_url_check` sets it to `Url.check ~tag ~log:Types.log`, the
  same call as before. Installers: `Element.valid`, which `attr`,
  `url_attr`, `hole_attr` and `url_hole_attr` call, and `use_element`
  (so `lower`, `hydrate`, `Template.make`, `template_of_shape` and
  `Private.expand`). The unchecked constructors do not call it.
- The default is not a pass-through: when `Url.checked ~tag name` is true
  (every name and tag that `Url.check` can change), it raises
  `Failure "Yuka: no URL check for <name> of <tag>: ..."`; otherwise it
  returns the value, which is what `Url.check` returns for such a name.
  So a broken installer rule can make an app raise, never set an unchecked
  URL.
- Why every URL attribute meets an installer: a `Static` or `Dynamic`
  attribute comes from a constructor or from `Template.expand` (fixed
  attributes), from `Form` (through `lower`), or from server-only code
  (`use_css` on the server, `Cycle`). The checked constructors install.
  `Template.expand` runs only after `hydrate`, `Template.make`,
  `template_of_shape` or `Private.expand` set the expander, and all of them
  call `use_element`. The unchecked constructors refuse every URL name and
  `srcdoc` (`Web.refuse_url_name`, unchanged, in all builds); the
  remaining names (`values`, `to`, `from`, `by`) are URLs only on SVG
  animation elements, which the ppx gives the checked constructors. A
  hand-written `attr_unchecked "to"` on an `animate` made with `lower` is
  checked (`lower` installs); in a template clone with no other
  installer, it raises.
- Fixed attributes in cloned template HTML never go through `set_attr`:
  the ppx checks them at build time and `template_of_shape` with
  `Url.check` directly, as before. The server printer still calls
  `Url.check` directly.
- Checks: `test/mount_hooks` has one process per installer
  (`url_attr_only`, `url_hole_attr_only`, `url_lower_only`,
  `url_hydrate_only`, `url_expand_only`, `url_make_only`,
  `url_shape_only`) that blocks the ticket 33 cases with only that
  installer, and `url_unset`, where a URL attribute with no installer
  raises and a non-URL one is set.
- Size, measured before `each` over arrays: the keyed app goes from
  8,698 B to 8,373 B gzip (-325 B). With both changes it is 7,961 B gzip.
  The demo, all chunks, goes from 46,605 B to 46,670 B gzip (+65 B), and each one-island page about +65 B: they keep
  the check and also pay for the hook, its default and the calls.

### `each` over arrays (2026-11-11)

- `Yuka.each` takes `unit -> 'a array` (it took `unit -> 'a list`). The
  reconcile works on arrays: with a list, an app that changes rows by
  index (the keyed benchmark: swap, append, remove) converts between list
  and array and links `Stdlib.List` code for it.
- No list form: `Array.of_list` at the call site does the same, and only
  apps that call it pay for it.
- The reconcile copies the items and their keys into its own arrays, then
  renders. The previous state is the rows it rendered (key, value, nodes),
  never the caller's array. So a write into an array after `each` read it
  changes nothing; a new array shows the change. `State.set` with the same
  array is no change (default equality is identity).
- The first render does not check keys; an update with two equal keys
  raises `Failure "Yuka.each: duplicate key K"` (unchanged).
- Size: the keyed app goes from 24,482 B, 8,698 B gzip to 23,171 B,
  8,287 B gzip (library and app: -359 B; the app's append and copy through
  `Js.Array` in place of `Stdlib.Array`: -52 B). The demo keeps its lists
  and calls `Array.of_list`: all chunks 46,605 -> 46,660 B gzip, start set
  23,806 -> 23,864 B.

## Pages pay for the features of their islands (2026-11-11)

Current names: `Optimistic` is no longer public; `lower` is now `Yuka.element`; `yuka-islands` is `yuka islands`.

Goal: the JavaScript that a page with islands loads at start holds only
the features that its islands use.

### Measure

`make size` also prints the JavaScript loaded at start, each file gzip -9
on its own, summed:

- three apps with one island each, built through the ppx and
  `yuka-islands`: `main.js`, the island chunk and their static imports.
  `bench/size/page`: a counter (one State, one button);
  `bench/size/codec_page`: an island whose props are a `string option`, a
  `string list` and a `float`; `bench/size/remote_page`: an island with
  one `Remote.use`;
- the demo start set: `main.js` and its static imports;
- each demo page: `make size` starts the demo server, reads the module
  script and the `<link rel="modulepreload">` links of the page (the
  server's preload logic: a non-lazy island gets one), and adds the static
  imports of each from the bundle metafile. A page with no island loads
  nothing. The server gets a port that the OS gave as free and a
  `--static-dir` with one file that holds a random nonce; the script
  measures only after `/static/<nonce>.txt` answers the nonce, so another
  process on the port fails the command (no answer within 20 s) instead of
  being measured. Each page request times out after 10 s, a missing
  `demo_server.exe` is an error that names it, and the server is stopped
  on every exit path.

There is no budget for these numbers.

### What puts a module in the start chunk

- esbuild splits by file, not by statement. A file goes to the chunk of
  the set of entry points that reach it through static imports, whether
  or not the importing code is used; the code of the file that any entry
  point uses goes there. `yuka.js` imports every module that `yuka.ml`
  names, and `main.js` imports `yuka.js`, so before this change `live.js`,
  `form.js`, `remote.js` and `codec.js` were in the chunk of every page.
- Melange compiles `module Live : sig ... end` (a module with a signature in
  `yuka.mli`) to an object in `yuka.js`, and a use of `Yuka.Live.f` to a read
  of that object, so the module is reached through `yuka.js`. A module
  alias in the interface, `module Live = Live`, has no field in `yuka.js` and no
  import from it: a use of `Yuka.Live.f` compiles to an import of `live.js` by
  the module that uses it. A `struct include Live end` and an alias in
  `yuka.ml` behind a signature in `yuka.mli` both keep the import (checked
  with a scratch library: the island chunk got `a.js` only for the alias
  in the interface).

### Changes

- `Codec`, `Status`, `Remote`, `Live` and `Form` are module aliases in
  `yuka.mli`. Their interfaces and documentation moved to `codec.mli`,
  `status.mli`, `remote.mli`, `live.mli` and `form.mli`, with the same
  names and types. A type of an aliased module must be the type of
  `Yuka`, so the abstract types they share are abstract types of lower
  modules, and `yuka.mli` gives the equation:
  - `'kind element = 'kind Kind.element`. `kind.mli` keeps it abstract
    and gives `%identity` conversions to and from `Types.node`; the
    modules that build or take elements (`element.ml`, `template.ml`,
    `island.ml`, `form.ml`, `client.mli`, `cycle.ml`) convert at their
    edges, so the JavaScript does not change. Conversions of a function
    use a type abbreviation for the result, so the external has one
    argument.
  - `slot = Slot_value.t`, the same way. `Private.node` has
    `Slot of slot_data`.
  - `'a Async.t`, `('i, 'o, 'kind) Action.t` and `('k, 's) Topic.t` are
    abstract in `async.mli`, `action.mli` and `topic.mli`; the library
    reads an action and a topic through functions (`Action.input`,
    `Topic.key`, ...). `Async`, `Action`, `Topic` and `Optimistic` stay
    objects in `yuka.mli`: they are small, and the core uses them.
  - `Codec.t` and `Status` types were already public; `Codec.t` is
    re-exported with its fields.
  - `Codec.mismatch` moved to `Json.mismatch`, so `codec.mli` is the
    public interface only.
- `Bridge` holds the references that the server sets for code that runs
  on both sides: the action sender of `Remote` on the server, the live
  state loader of `Live` in a server render, and the reset of the live
  socket manager (`Private.reset_live`, set by `live.ml` when it creates
  the manager; before that there is nothing to reset). Before, `server.ml`
  and `live_server.ml` wrote into `remote.ml` and `live.ml`, and
  `yuka.ml` into `live.ml`, so those files were reached from `main.js`.
- `scripts/bundle.ts` marks the files of `node_modules/yuka/` and
  `node_modules/yuka.js/` as free of side effects (an esbuild plugin that
  returns `sideEffects: false`). esbuild then drops an import of such a
  file when none of its names are used, also for chunk assignment, so the
  server modules (`server.js`, `cycle.js`, `live_server.js`, `printer.js`)
  no longer bring `form_core.js`, `codec.js` and `status.js` into the
  start chunk. The rule of "What keeps code in a bundle" makes this true:
  no module of the library has a top-level side effect. The Melange
  standard library has some (the `MelangeError` setup, `Sys`), so it is
  not marked; marking it saved nothing in the counter page.
- The action transport and the reader of streamed async values are
  installed on first use, as the mount code of a node kind is:
  `Action.send` (used by `Action.call` and the island submit of `Form`)
  calls `Client.use_actions`, and the decoder of a `Codec.async`
  reference calls `Client.use_async`. `Client.start` installs a gate into
  `Private.call_action` and `Private.async_source` that calls the
  installed function, so before `render ~islands` the default failed
  `Async` stays. After the start, a gate that runs with nothing installed
  raises `Failure "Yuka: no action transport for NAME: ..."` or
  `"Yuka: no reader for async value ID: ..."`. The transport moved from
  `Action.transport` to `Types.transport`, so `action.ml` can call
  `Client`. `yuka.mli` documents this for `Private.call_action` and
  `Private.async_source`, and `test/mount_hooks` has one process for each
  (`call_action_only`, `async_source_only`): it reads the reference before
  `render ~islands` (the failed `Async`), after it (the `Failure`), then
  calls `Action.call` or decodes a `Codec.async` reference and reads it
  again; without the install, the process fails. Other checks: without the `use_actions` call, 6 cases of
  `test/navigation` fail; without the `use_async` call, 5 cases of
  `test/melange` fail (the "async value watcher" case now decodes through
  `Codec.async` instead of reading `Private.async_source`); without the
  reset in `live.ml`, the live cases of `test/melange` fail. In the split
  bundle the gate and the hook are in the start chunk and the chunks that
  call `use_async` import it from there: one instance.
- No polymorphic compare on the boot path: `navigation.ml` compares
  `string option` values with a match, and the island and record decoders
  of the ppx look up a field with one local `_yuka_field` function
  (`List.find_map` and `String.equal`) instead of `List.assoc_opt`. The
  counter page no longer has `caml_obj.js`.

### Size

`make size`, gzip bytes; "/" is also "/my", "/new" is also
"/issue/YUK-1"; "/about" loads nothing at every step.

| step | counter page | demo start | / | /new | all demo chunks | keyed app |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| main 000ab12 | 20,936 | 29,880 | 40,211 | 36,997 | 44,244 | 8,698 |
| aliases `Status`, `Remote`, `Live`; `Bridge` | 20,936 | 26,951 | 42,133 | 36,183 | 46,157 | 8,698 |
| yuka files free of side effects | 20,935 | 26,526 | 42,140 | 36,180 | 46,155 | 8,698 |
| alias `Codec` | 19,836 | 25,712 | 42,384 | 36,414 | 46,426 | 8,698 |
| transport and async reader on first use | 19,054 | 25,833 | 42,512 | 36,545 | | 8,698 |
| no polymorphic compare | 18,729 | 25,851 | 42,654 | 36,662 | 46,755 | 8,698 |
| alias `Form` | 18,728 | 23,806 | 42,493 | 36,494 | 46,606 | 8,698 |

The steps were measured in one build directory, the table below in another;
chunk names hold a hash of the paths, so the gzip size moves by a few bytes
between directories. `make size` on the final tree, and main 000ab12 with the
same fixtures and script:

| page | main 000ab12 | final |
| --- | ---: | ---: |
| counter island | 20,935 | 18,726 |
| island with `Codec` props | 20,913 | 19,010 |
| island with `Remote` | 22,880 | 22,677 |
| demo start set | 29,880 | 23,805 |
| demo `/`, `/my` | 40,201 | 42,489 |
| demo `/new`, `/issue/YUK-1` | 36,990 | 36,489 |
| demo `/about` | 0 | 0 |
| all demo chunks | 44,231 | 46,597 |
| keyed app | 8,698 | 8,698 |

- A page that uses every feature pays more: "/" loads `live.js`,
  `remote.js`, `form.js` and `codec.js` as before, but in more files. Each
  file is compressed on its own and the chunks import each other by name,
  so "/" grew by 2,288 B and all chunks by 2,366 B.
- Grouping does not recover it. In the static import graph no two
  feature modules need each other: `answers` always comes with `status`
  (it imports it, and only `live` and `remote` import `answers`), but
  `status` comes without `answers` (an island that reads a `Status.t`),
  `codec` without `status` (the counter), `remote` without `live` and
  the reverse. esbuild already puts files with the same entry set in one
  chunk (`status` and `answers` share one in the demo). Any further group
  makes a page load code it does not use. Two were measured, with a dead
  reference that makes one module reach another, and dropped:

  | group | counter | `Codec` props | `Remote` | demo start | / | /new | all chunks |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
  | none (final) | 18,726 | 19,010 | 22,677 | 23,805 | 42,489 | 36,489 | 46,597 |
  | `live` with `status` and `answers` | 18,731 | 19,010 | 22,673 | 23,805 | 42,245 | 39,010 | 46,360 |
  | `codec` in the start chunk | 18,763 | 18,946 | 22,719 | 24,399 | 42,029 | 36,049 | 46,109 |

  The first makes "/new" load `live.js` (+2,521 B); the second makes the
  counter, the `Remote` page and the demo start larger. In the one-island
  apps a dead reference adds nothing, because the island and its features
  are in one chunk anyway; a real dependency would add the code of the
  other module.
- What is left in the counter page (minified): `client.js` 14.7 KB,
  `web.js` 9.2 KB, `navigation.js` 6.0 KB, `json.js` 5.4 KB, the
  scheduler 4.0 KB, `Curry` 2.1 KB, `template.js` 2.0 KB, `url.js` 1.7 KB,
  and `String`, `Bytes`, `Buffer` (about 4.5 KB with `caml_bytes`).
  Navigation is the largest part that a page may not need: the counter
  page without it is 14,535 B and the demo start set 20,441 B. Navigation
  is on by default and `~navigation:false` is a run-time flag; making it a
  link-time choice needs a second registry builder that does not name
  `Navigation`, which is a new entry point. Loading it on the first
  click, hover or `popstate` makes the first navigation asynchronous.
  The second is done: see "Navigation code on first use".

## Routes.mlx generator (2026-11-10)

Current names: `yuka-routes` is now `yuka routes --source FILE`.

The input format and the reader changed later; see "Routes.ml: one OCaml
expression". The shared module also has a link function per named node;
see "Route helpers".

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
  `Yuka.Router.Param.encode` of its value, see "Param values"); a catch-all with `Yuka.Router.segments` (`/` and one
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
- New in `Yuka.Router`: `meth`, `lookup`, `Param`, `encode`, `segment`,
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

Current names: `ADAPTER` and `Make` are now `Server.Adapter.Backend` and `Server.Adapter.Make`, all in `Async.t`, and the `handler` of `Make` answers `/_yuka/live` too; `handle` and the `request` record are internal. Client files are served under `/_yuka/app/`. `Server.log_error` is now the `log_error` of `Server.config`. `fill_script` is `Private.fill_script`. A failed `Codec.async` value sends the message of a rejection, else `"server error"`. A stop `Redirect` is `Redirect { location; kind }` and must stay on the site; `Redirect_off_site` leaves it; `Forbidden` is a 403. Every handler with an unsafe method checks the origin. `yuka-routes` is `yuka routes`.

Spec: `.workplace/docs/routes-spec.md`, increment 2; its section 8 lists
what changed from the spec. `yuka-dream` and the demo migration are in
"yuka-dream"; the navigation protocol comes later.

- `src/cycle.ml`, included in `Yuka.Server`: the types the generated code
  names (`stop`, `page`, `layer`, `plan`, `cache`, `rules`, `response`,
  `fallback`, `target`, `'req app`), `assets`, `config`, `handle` and the
  functor `Make (Backend : ADAPTER)`. No server dependency: `handle` takes the
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
- `yuka-routes --server --shared-module Routes FILE.ast` prints
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

Current names: `handler` sends the server log to `Dream.sub_log "yuka"` when the config has no `~log` (see "`Yuka.Console` and the server log"). The prerender values are in `Server.Prerender`: `seeds`, `prerenderable`, `links`, `file`, `missing_page`, `served_dirs`. `ADAPTER.exists` is `Server.Adapter.Backend.exists`. Client files are under `/_yuka/app/`.

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

Current names: `Server.build_id` is now `Server.Adapter.build_id config app`.

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

Current names: `Action.declare` is now `Action.mutation`; `Optimistic` is internal; `Remote.mutate` and `Live.mutate` take `?commit` and a function that gives `('r, Status.error) result Async.t`, and an `Error` rolls back; `Action.call` gives `('o, Status.error) result Async.t`.

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

Current names: `SOCKET` and `Handle` are gone: the adapter's `upgrade` gives a `Server.Live.connection` and `Server.Adapter.Make(Backend).handler` answers `/_yuka/live`. `ADAPTER.csrf_token` is `Server.Adapter.Backend.csrf_token`. `Live.set_limits` is now `Server.Live.node ?per_session ?total`. `allow` and `revoke` take a `Server.context`. A server render of `Live.use` runs `allow` with the page request.

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

Current names: `Effect.run` is now `Effect.before`; the client's holes, attributes and lists call `Base.run_effect Scheduler.queue` (see "`Effect.after` and `Effect.before`").

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
  `console.error` and calls `Client.on_error` (set by `render ~on_error`);
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

Current names: `ADAPTER.body` is now `Server.Adapter.Backend.body`. `Form.form_errors` and `Form.form_error_view` are now `Form.errors` and `Form.errors_view`; `Form.action` makes an action of the kind `` [ `Form ] ``. Form fields are polymorphic variants (`` `Title ``).

Spec: `.workplace/docs/app-spec.md`, section 20, option B (ticket 20); its
"20: changes during build" lists the differences.

- `[@@deriving form]` (`ppx/form_gen.ml`) on a record writes `type
  <t>_field` (one constant constructor per label), `<t>_field_name` and
  `<t>_form : (<t>, <t>_field) Yuka.Form.t`. The generated decoder calls
  `Yuka.Form.field` for each label with a kind (`string`, `int`, `float`,
  `bool`, `option`, `list`, `custom Email.of_string Email.to_string`), collects
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
  over the limit. The form 303 (and the island answer's `redirect`) goes only
  to a path or an `http:`/`https:` URL of the request `Host` (scheme read as
  `Url` reads it, so `javascript://HOST/` is refused) with no control character (below space, or DEL: browsers drop
  TAB, CR and LF from a URL, so `/\t/evil.com` is `//evil.com`); else the
  500 page and a log. One origin rule,
  `Server.trusted_origin`, for form posts, the action call and `Action`
  routes. Unknown field names in errors from the server are form errors;
  a `data-yuka-sent` that does not parse is ignored (a console message in
  a dev build). A form post with a content type other than
  `application/x-www-form-urlencoded` is 405 before the guards run.


## Prefetch, navigation cache and view transitions (2026-11-10)

Current names: `Yuka.unmount` is now `Yuka.stop`.

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

Current names: `yuka-css DIR` is now `yuka css --dir DIR`; `Server.css_files` is `Server.Prerender.css_files`; `Immutable` is `Server.immutable` (`Server.cache` is abstract); `Yuka.stylesheet` is `runtime_stylesheet`; `let%client` is now `let[@client]` (see "`[@client]` attribute").

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

## Routes.ml: one OCaml expression (2026-11-10)

Current names: `yuka routes --source FILE` now reads FILE, not stdin; dune rules use `--source %{dep:../Routes.ml}`.

Plan: `.workplace/plans/routes-async_PLAN.md`. As server-reason-react
router-gen: the manifest is a plain OCaml file, not mlx.

- `Routes.ml` holds exactly one top-level item, the expression
  `Router.make ...`. An `open`, a `let`, a second expression or an empty
  file is an error with a location. The file is never compiled.
- Nodes: `Router.make`, `Router.group`, `Router.route Name`,
  `Router.endpoint Name`, `Router.action Name` and
  `Router.redirect ~path ~to_:(Permanent "/")`. The name is the one
  unlabelled argument of a route, endpoint or action; the child nodes are
  the one unlabelled list of `Router.make` and `Router.group`. Each former
  prop is a labelled argument with the same name and meaning; a redirect
  is its own node with `~to_` instead of a `Route` with `redirect`.
- Attachments (`page`, `layout`, `loader`, `guard`, `handler`,
  `not_found`, `error`) must be value paths (`Pexp_ident`). They are
  called as before.
- `yuka-routes --shared --source FILE` and `yuka-routes --server
  --shared-module Routes --source FILE` read the source text from stdin and
  parse it with `Parse.implementation`; `--source` names the file in
  locations. Dune rules use `with-stdin-from %{dep:../Routes.ml}`. The
  `mlx-pp` step and `routes.ast` are gone; syntax errors are reported by
  the OCaml parser.
- The prelude is dropped: the server output no longer starts with the
  `open`s written before `let routes`. Paths in `Routes.ml` must resolve
  in the server library as written (`test/cycle` writes `App.Pages.home`).
- The build id (`~build` of `Routes_server.app`) is a digest of the
  printed expression, so it changes with the format.

## Dev server (2026-11-10)

Current names: `yuka dev --build COMMAND` runs the full build command through `/bin/sh` (default `dune build --watch`); `--dune` is gone; the default state file is `$DUNE_BUILD_DIR/.yuka-dev`. The library no longer reads `YUKA_DEV`: `yuka dev` sets it, and the app passes `Server.config ~dev:true`. `prerender_config` is now `Server.Prerender.config`.

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

Current names: `template_coded` is now `runtime_template`; `url_attr`, `url_hole_attr`, `attr_unchecked` and `hole_attr_unchecked` are the `runtime_` names; `Template.make` and `template_of_shape` are `Private.Template.make` and `Private.template`, for tests.

Ticket 33 and its four security reviews.

- Rule (`src/url.ml`, shared with the ppx; names and tags lowercased by the
  caller): a URL attribute is `href`, `src`, `action`, `formaction`,
  `xlink:href`/`xlinkhref`, `poster`, `cite`, `data`, `background`,
  `longdesc`, `manifest`, `codebase`, `icon`, and `values`, `to`, `from`,
  `by` on `animate`, `set`, `animateMotion`, `animateTransform` (each `;`-separated item of `values`; on other elements,
  such as `feColorMatrix`, they are not URLs). The value is read as the URL parser
  does: leading characters up to space dropped, tab, newline and CR dropped
  anywhere, any case. `javascript:` and `vbscript:` are blocked on every
  URL attribute. `data:` is blocked only where it opens or loads a
  document: `href` of `a`, `area`, `use`; `action`; `formaction`;
  `xlink:href`; `src` of `iframe`, `frame`, `embed`, `object`, `script`;
  `href` of `script`; `data` of `object`. Every sink knows the element.
  A blocked value becomes
  `about:blank#blocked` (React's rule; React blocks only `javascript:` and
  has no escape hatch, Angular checks `data:` and has one, Svelte, Solid and
  Vue do not check). `srcdoc` of `iframe` is
  an HTML sink: `check` gives `""` and logs, as for a script URL. Only a
  literal `srcdoc` in `.mlx` is kept (`add_attr ~literal:true` for template
  fixed attributes); React does not check it. `href` of `base` is handled
  the same way (it moves every relative URL of the page). Only
  `template_coded` (hidden, for the ppx) and `Template.make` (hidden, for
  tests) reach `literal`. A template that the ppx lowers keeps a literal
  `srcdoc` or `base` `href` only in a nested `template_coded` made from
  the literal; see "Template format".
  A hand-written template goes through `template_of_shape`, which runs
  `Url.check` on its fixed attributes first. `src` of `script` and `content` of a refresh `meta` are left to
  the developer (README).
- Attribute names (`Url.valid_name`): empty, or with a character up to
  space, DEL, `"`, `'`, `>`, `/`, `=` or `<`, is refused by the server
  printer, the browser constructors, the unchecked constructors,
  `template_of_shape` and the ppx (a located error). Such a name would end
  the attribute or the tag early. A name that starts with `on` (any case)
  is refused too: it is an inline event handler. Handlers are `Yuka.on`
  only; the ppx turns `on_click=f` into it and refuses a string literal.
- Tag names (`Url.valid_tag`: a letter, then letters, digits and `-`):
  the printer refuses another tag before it writes `<` (also in template
  compilation), and so does `template_of_shape`. The browser's
  `createElement` and `createElementNS` already throw on such a name, so
  the client adds no check. The ppx takes only tags it knows.
- Sinks (`Url.check ~tag ~log`): the server printer, for every attribute
  it prints, with the element (one check per print; `log_error` once per
  process); in the browser, `Client.set_attr`, for every attribute value it
  sets (static, each hole value, template parts), with the element's
  `localName`. So both sides apply the same rule with the real element;
  constructors check only names. That costs the keyed app 595 B gzip
  (10,303 -> 10,898): `Url` was not in it before, because its
  constructors with no URL name never called the check. Since "URL check
  per app" (2026-11-11), `set_attr` reaches the check through a hook that
  the checked constructors and `use_element` set; the rule is the same.
- Navigation: `Browser.navigate` drops a URL that `Url.unsafe ~tag:"a"
  "href"` blocks (a dev build logs it), with navigation on or off. A form
  answer's `redirect` goes through `Server.local_location` with the
  request `Host` in `answer_action` (as the 303 does; `Redirect` answer
  case), and the browser follows it only when `new URL(r, location)` has
  the page's origin.
- The ppx emits `url_attr`/`url_hole_attr` for checked names and
  `attr_unchecked`/`hole_attr_unchecked` for the others. The unchecked ones
  refuse a URL name, `srcdoc` and a bad name at run time
  (`Web.refuse_url_name`, a regular expression in the browser), so they
  cannot set an unchecked URL. That guard and the client guard below cost
  the keyed app 228 B gzip (10,034 -> 10,262); the second review added 42 B
  (bad names in the regular expression +29 B, the case-insensitive client
  guard +25 B, less the namespace test it dropped; 10,304, the budget).
- Hand-written templates: the browser puts `Template.make`'s `html` in the
  page as given, so `Yuka.template_of_shape` checks the fixed attributes
  (with the element) before it computes the HTML. It is a top-level value
  so that the keyed app, which uses `Yuka.Template`, does not keep the
  template builder (0 B).
- Raw text: `script` and `style` (any case, any namespace, on both sides)
  take no child, one `Text` or one `Hole` that gives a `Text`; anything
  else raises `Invalid_argument` before anything of the element is printed
  (server) or built (client). The ppx
  joins the strings and `(Yuka.text e)` children into one text (a hole if
  one reads a State) and refuses other children with a located error. The
  text is printed by `add_raw` only in the HTML namespace: every `</` gets
  `\` after `<` (an end tag of any element, so a `noscript`, `textarea`,
  `title` or `iframe` around it cannot be closed), and `<!--` too in a
  JavaScript script (no `type`, `module`, or a JavaScript MIME type); in a
  script of another type every `<` becomes `\u003c`. In `svg` and `math`
  the text is escaped, and so inside `select` (a `Select` entry on the
  same stack): a classic parser ignores a `style` start tag there and reads
  its text as markup. The namespace is a stack in the printer (`Html`,
  `Svg`, `Math`, `Select`; tags compared in lowercase): `svg` and `math` enter their
  namespace from HTML, `foreignObject` in SVG goes back to HTML, and
  anything inside `math` stays MathML (also `math > svg` and
  `math > foreignObject`). MathML text integration points (`mi`, `mtext`,
  `annotation-xml` and the like) are treated as MathML: their raw text is
  escaped, which is safe. Template ops `Enter tag` and `Leave` move the
  stack around the children of `svg`, `math` and `foreignObject`, since a
  template prints their tags as static chunks. Tag names are printed as
  written: `createElementNS` is case-sensitive for SVG camelCase tags. A dev client does not log a text mismatch
  inside `script` or `style` (the server text has the escapes).

## suspend: a server element that arrives later (2026-11-11)

```ocaml
val suspend :
  loading:server element ->
  ?failed:(string -> server element) ->
  server element Async.t ->
  server element
```

- `suspend ~loading ?failed el` is
  `Await.make ~async:el ~loading ?failed ~children:(fun e -> e) ()`: the same
  node, markers, fills, timeout and navigation behaviour. The usual
  argument is `Async.map (fun data -> <View data />) fetch`.
- Server only: `Async.map` runs its function in the settle callback, so in
  the browser a component built there would run with no owner. In an
  island, `<Yuka.Await>` builds the element in the island's owner.
- `Await` is unchanged.

## Live data on more than one node (2026-11-10)

Current names: `Server.Live.instance` and `?instance` are now `Server.Live.node` and `?node`; `use_bus ~node` is `use_bus ~name`; `Yuka_dream.handler ?live` is `?node`; `Server.live_mark` is internal.

Ticket 25; `.workplace/docs/app-spec.md` section 25, option B; settle rule
in `.workplace/docs/data-spec.md` section 8 ("More nodes").

- The live server state is a value, `Server.Live.instance` (entries,
  sockets, `seq`, bus, the notes sent, the notes heard per node, a local
  event counter, the subscriptions waiting for a `synced`). The process has
  one; every function takes `?instance` for tests with two nodes in one
  process. Topics (loaders) stay global: they are the app's code.
- The bus record (`send`, `listen`, `on_restart`) has no Dream or Lwt type.
  A note is `{"n","t","k","p"}`, at most 7,900 bytes (Postgres `NOTIFY`:
  8,000); sends go through one chain per node, so `p` is in send order.
- A note for a key with subscribers starts a load unless one runs; then it
  marks the entry `again`, and one more load runs after it. A local publish
  during a load marks `again` and keeps its state (the load result is not
  stored when `seq` changed during the load). A failed reload keeps the
  last state and logs.
- Settle rule: the action answer gets `"live":[NODE,P]` through
  `Server.live_mark` (set by `use_bus` on the process instance); the client
  transport hands it to `Live` through `Platform.live_mark`, and the next
  `Live.mutate` puts it in its `sync` as `after`. The node holds `synced`
  until it heard note `P` of `NODE` and no load started before that point
  is still running (the entry keeps the event numbers of notes that no
  finished load started after). At most 5 s.
- `yuka-live-pg` (its own opam package, so `yuka` and `yuka-dream` keep
  no database dependency): two libpq connections from `postgresql`
  (postgresql-ocaml, the client with `notifies`). One sends with
  `SELECT pg_notify($1, $2)` (a query sent with `send_query`, the result
  read when the socket is readable, under a mutex). The other runs
  `LISTEN` and waits with `Lwt_unix.wait_read` on its socket, then
  `consume_input` and `notifies`. A failed listener connects again every
  `retry` seconds, runs `LISTEN` again and calls the `on_restart`
  functions; a failed sender connects again on the next note. Tested
  against Postgres 17 in docker over a unix socket (the test reads
  `YUKA_LIVE_PG`, and skips without it).
- The demo serves a second node on another port in the same process
  (`--second-node PORT`, `--bus memory|pg:CONNINFO`): the store is in
  memory, so two processes would load different data. The e2e opens a
  page on each node.
- `revoke` is per node. The client protocol and bundle sizes do not change
  for apps without a bus; the keyed app does not use `Live`.

## `Yuka.render`, one client start (decided by the user, 2026-11-11)

```ocaml
val render :
  ?islands:Client.registry ->
  ?navigation:bool ->
  ?prefetch:[ `Hover | `Visible | `Off ] ->
  ?transitions:bool ->
  ?on_error:(string -> unit) ->
  ?root:Client.container * (unit -> 'k element) ->
  unit ->
  unit
```

- `Yuka.render ~islands ()` is what `Yuka.mount ()` was.
  `Yuka.render ~root:(container, app) ()` is what `Client.render` was, and
  `Yuka.stop ()` (first named `Yuka.unmount`) stops it (and every other `~root` tree) as well as the
  islands. Both labels can be in one call; the root is built first.
  `Yuka.mount` and `Yuka.Client.render` are removed; tests that need the
  dispose function of one tree use `Yuka.Private.render`.
- Without `~islands`, `~navigation`, `~prefetch`, `~transitions` and
  `~on_error` do nothing; a check would cost bytes in every app. A call
  with neither `~islands` nor `~root` raises `Invalid_argument`, because
  `Yuka.render ()` is the likely mistake when moving from `Yuka.mount ()`.
- The ppx rewrites an argument `~islands` whose value is the identifier
  `islands` (so the punned `~islands`, and also `~islands:islands`) in any
  application of `Yuka.render`, partial or not, into
  `~islands:Yuka_islands.registry`, unless a binding of `islands` is in
  scope there. After a top-level `open Yuka`, a bare `render` counts too.
  Other values, `?islands` and calls without `~islands` stay as they are. Without the ppx, a punned
  `~islands` is `Unbound value islands`, so the old runtime check that named
  `yuka.ppx` is gone.
- The registry carries the start function: `Yuka.runtime_registry` (in
  `yuka.ml`; first named `Yuka.Client.registry`) builds a record whose one field is a closure over the entries
  that calls `Navigation.start` (now `Navigation_stub.start`, see
  "Navigation code on first use") or `Client.start`. `Yuka.render` reaches
  the island, action and navigation code only through that field, so an
  app that never builds a registry does not contain it. The closure takes
  its options as one tuple: a call of a closure of unknown arity goes
  through `Curry`, and `Curry._1` is in every app already.
- `Client.render_root` and `Client.stop_roots` keep the dispose functions
  in `dom/js/client.ml`, so `yuka.ml` calls `Client` with one argument.
- Size (`make size`, keyed app, which now calls `Yuka.render ~root`): from
  30,767 B, 10,886 B gzip to 30,688 B, 10,846 B gzip. Not the 1.5 KB of
  roadmap 30: `Yuka.Client` (which held `hydrate`) and `island.js` leave
  the bundle, but the code that adopts server DOM is in the same functions
  that render uses (`mount_node`, `take`, `mount_slot`, `drop_to_end` test
  `pos.adopt` at run time), so esbuild keeps it.

## API for 1.0 (2026-11-11)

Source: the API reviews of 2026-11-11 (server, client, and the surface:
`Private`, ppx, packages, command line). Each change below is breaking
unless it says otherwise; `CHANGES.md` lists them one by one.

### Server

- Actions, form actions and the live `allow` and `revoke` get a
  `Server.context` (`Context.header`, `session`, `meth`, `path`). Any page
  can call any action, so an action checks permissions itself. The live
  loader gets no context: its state is shared by every subscriber of a key
  on a node, so `allow` decides who reads it. A server render of
  `Live.use` runs `allow` with the page request and reads the state of the
  handler's node.
- One adapter signature, `Server.Adapter.Backend`, all in `Async.t`; its answer
  type is `reply`. `Server.Adapter.Make(Backend).handler ?node config app`
  answers every path, `/_yuka/live` included. Reserved paths:
  `/_yuka/action/NAME`, `/_yuka/csrf`, `/_yuka/css/FILE`, `/_yuka/dev`,
  `/_yuka/live`, and `/_yuka/app/FILE` for the client files; any other
  path under `/_yuka/` is a 404. There is no base path.
- A handler with a method other than `GET`, `HEAD` and `OPTIONS` checks the
  origin before its guards; `Router.endpoint ~cross_origin:true` turns
  this off for webhooks. `Server.config ~origins` lists the accepted
  origins behind a proxy that rewrites `Host`.
- `Server.stop`: `Not_found`, `Forbidden` (a plain 403), `Redirect`
  (must stay on the site, else a logged 500), `Redirect_off_site` and
  `Fail`.
- No global configuration: `Server.config ~log ~dev ~origins` and
  `Server.Live.node ~log ~per_session ~total`. The library does not
  read `YUKA_DEV`; `yuka dev` sets it and the app passes `~dev`.
- `Server.response`, `Server.Live.bus` are private records with builder
  functions; `Server.Live.connection` and `Server.cache` are abstract
  (`no_store`, `no_cache`, `private_ ~max_age`, `public ?s_max_age
  ~max_age ()`, `immutable`).
- Values for generated code are in `Server.Generated`, prerender values in
  `Server.Prerender`, test values in `Server.Testing`; these are outside
  semantic versioning.
- `Server.Action.reject message` fails the `Async` with a prefix that holds
  a per-process secret (`Web.nonce`), so user text cannot pass for a
  rejection.
- Headers: a name can repeat inside one list; a later layer replaces a
  name of an earlier one; CR, LF or NUL in an outgoing header is a 500.

### Client

- `Action.call` gives `('o, Status.error) result Async.t`, in the browser
  and on the server. `Action.declare` is `Action.mutation`. `Form.action`
  makes an action of the kind `` [ `Form ] ``, the only kind that
  `Form.make ~action` takes.
- `Yuka.stop` stops what `Yuka.render` started; calls in flight give
  `Error (Network "cancelled")`.
- The island start strategy is the `start` prop of `<Yuka.Client>`.
- `Yuka.element` builds an element; `Yuka.list` and `Yuka.array` are
  removed (use `fragment`).
- Event handlers run in a batch (see "Equality and batch").
- `Effect.run` is replaced by `Effect.after` and `Effect.before`;
  `Effect.on_change` has the timing of `after` (see "`Effect.after` and
  `Effect.before`").
- An `Async.map` or `Async.bind` function that raises gives `Failed`.
- A failed `<Yuka.Await>`, `suspend` or `Async` prop shows the message of
  a `Server.Action.reject`, else `"server error"`; the detail goes to
  the `log` of `Server.config`.
- `Codec.t` is private (`Codec.make`, `Codec.map`), `Remote.retry` is
  abstract, `Remote.mutate` and `Live.mutate` have one shape, and
  `Optimistic` is internal.
- The values and types that the ppx, the derivers and `yuka islands`
  write are top-level `Yuka.runtime_*` names, outside semantic versioning.
  `Private` is for the tests of Yuka.
- A production bundle must define `__YUKA_DEV__` as `false`; when it is
  not defined, the dev checks are on.

### Build and ppx

- One executable `yuka` with the commands `routes`, `islands`, `css` and
  `dev`; flags in any order, `--help` on each command, exit 2 on a usage
  error. `yuka routes --source FILE` reads the file; `yuka islands --dir
  DIR` reads the library name from `DIR/dune`; `yuka dev --build COMMAND`
  runs a full command.
- `yuka.native` is native only, so a Melange build without `yuka.js` fails
  at build time.
- `[@@deriving form]` field types are polymorphic variants.
- `let%yuka.client` is the same as `let%client` (now `let[@yuka.client]`
  and `let[@client]`, see "`[@client]` attribute"). After a top-level
  `open Yuka`, `<Await>`, `<Show>`, `<Catch>` and `<Client>` work
  unqualified.

### Names that changed

| Old name | Current name |
|---|---|
| `Yuka_server`, `Yuka_client`, `Yuka_router` | `Yuka.Server`, `Yuka.Client`, `Yuka.Router` |
| `Yuka.mount ()`, `Router.start`, `Client.render` | `Yuka.render ~islands ()`, `Yuka.render ~root ()` |
| `Yuka.unmount` | `Yuka.stop` |
| `Router.navigate` | `Browser.navigate` |
| `Yuka.lower` | `Yuka.element` |
| `Yuka.list`, `Yuka.array` | `Yuka.fragment` |
| `Action.declare` | `Action.mutation` |
| `<Yuka.Client loading=...>`, `type loading` | `<Yuka.Client start=...>`, `type start` |
| `Client.entry`, `Client.lazy_entry`, `Client.promise`, `Client.promise_map`, `Client.island`, the value `Client.registry` | `runtime_entry`, `runtime_lazy_entry`, `runtime_promise`, `runtime_promise_map`, `runtime_island`, `runtime_registry` |
| `Yuka.Template.t`, `template_coded`, `template_instance` | `runtime_template`, `runtime_instance` |
| `url_attr`, `url_hole_attr`, `attr_unchecked`, `hole_attr_unchecked` | `runtime_url_attr`, `runtime_url_hole_attr`, `runtime_attr`, `runtime_hole_attr` |
| `Yuka.stylesheet` | `runtime_stylesheet` |
| `Template.make`, `template_of_shape`, `Client.hydrate` | `Private.Template.make`, `Private.template`, `Private.hydrate` |
| `Form.form_errors`, `Form.form_error_view` | `Form.errors`, `Form.errors_view` |
| `Effect.run` | `Effect.after` (DOM up to date) or `Effect.before` (the old timing) |
| `Optimistic` | internal |
| `Server.ADAPTER`, `Server.Make`, `Server.handle` | `Server.Adapter.Backend`, `Server.Adapter.Make`, internal |
| `Server.Live.SOCKET`, `Server.Live.Handle` | the adapter's `upgrade` and `Server.Live.connection` |
| `Server.log_error` | `Server.config ~log`, `Server.Live.node ~log` |
| `YUKA_DEV` read by `Server.config` | `Server.config ~dev:true` |
| `Server.prerender_config` | `Server.Prerender.config` |
| `Server.prerender_seeds`, `prerenderable`, `prerender_file`, `missing_page`, `served_dirs`, `css_files` | `Server.Prerender.seeds`, `prerenderable`, `file`, `missing_page`, `served_dirs`, `css_files` |
| `Server.build_id app` | `Server.Adapter.build_id config app` |
| `Server.Live.instance`, `?instance` | `Server.Live.node`, `?node` |
| `Server.Live.set_limits` | `Server.Live.node ?per_session ?total` |
| `Server.Live.peer` | `Server.context` |
| `Server.document`, `Server.fill_script` | removed (`Private.fill_script` for tests) |
| `Immutable` and the other `cache` constructors | `Server.immutable`, `no_store`, `no_cache`, `private_`, `public` |
| `/_yuka/<file>` | `/_yuka/app/<file>` |
| `yuka-routes`, `yuka-islands`, `yuka-css`, `yuka dev --dune` | `yuka routes`, `yuka islands`, `yuka css`, `yuka dev --build` |
| `let%client`, `let%yuka.client` | `let[@client]`, `let[@yuka.client]` |

## Navigation code on first use (2026-11-11)

Goal: a page with islands does not load the client router (fetch, swap,
cache, prefetch, history) at start. It loads it with a dynamic `import()`
when it first needs it.

### Design

- `src/navigation_stub.ml` is what `Yuka.render ~islands` starts when
  navigation is on. At start it does what must happen at page open: it
  sets `history.scrollRestoration`, gives the history entry a key if it has
  none, keeps the URL of the page, adds the `click`, `popstate` and
  prefetch listeners (`pointerover`, `focusin`, `pointerout`, `focusout`,
  `pointerdown`, `touchstart`), starts the islands and sets
  `Platform.client_navigate`, which the default `navigate` of the platform
  calls. A test that sets `Private.platform` keeps its own `navigate`.
- The click listener decides as before (`Web.plain_click` and
  `Web.link_href`) and calls `preventDefault` at once. `popstate` and
  `Browser.navigate` go to the router. Before the router is loaded,
  `pointerover`, `focusin`, `pointerdown` and `touchstart` go to it only
  when their target is in a link that it would prefetch
  (`Web.link_href true`), and `pointerout` and `focusout` only while the
  router loads; after it is loaded, all of them go to it, as before. So
  a pointer, focus or touch elsewhere on the page loads nothing (Chromium
  sends a `pointerover` after layout with no user action). If the router
  is not loaded, the stub keeps the events in order, starts the load, and
  gives them to the router when it arrives. A hover, a focus or a pointer
  down on a link starts the load, so the code is usually there before the
  click. With `` `Visible `` prefetch, or a link with
  `data-yuka-prefetch="visible"` on the page, the load starts at once.
- Failure: if the `import()` rejects, or a navigation (a click, a
  `popstate`, `Browser.navigate`) waits more than 3 s for it, the stub
  logs `yuka: cannot load navigation: ...` once and stops until the next
  `render`: a kept click does `location.assign` of its URL, a kept
  `popstate` does `location.assign` of the new URL when it is not the
  page shown, later clicks are not prevented (the browser loads the
  page), later `popstate` and `Browser.navigate` do `location.assign`, and
  there is no new `import()`. A retry in the same page would not help:
  Chromium keeps a failed module fetch in its module map, so the same
  `import()` rejects again with no request. 3 s: the router chunk is one
  request of about 3.6 KB gzip from the same origin, well under 1 s on a
  slow 3G link (400 ms round trip); a load that takes longer is stalled,
  and a user should not wait longer than that for a link to work. A
  module that arrives after the give-up is not used.
- The 3 s count from the first navigation that waits, not from the
  start of the load: a load started at page open (`` `Visible ``
  prefetch) or by a hover can take longer without turning navigation
  off.
- While a navigation waits, the stub listens to `beforeunload`: if the
  page starts to leave by other means (a link that the router does not
  take, a form, the address bar), the waiting navigations are dropped,
  so a late `location.assign` does not replace the page the user chose.
- `Yuka.stop` cancels the timer and the load in progress (a counter of
  attempts: a result of an earlier attempt is ignored), so a stop during
  a slow load and a new `render` start again with a new attempt.
- An exception in the router's `boot` stops the router (its `stop`) and
  is a failure as above. An exception while one kept event runs is
  logged (`yuka: navigation: ...`) and that event takes its fallback (a
  click does `location.assign`); the other kept events still run. The
  stub does not rely on `Web.promise_then`, which sends an exception of
  its success function to its failure function.
- `src/navigation.ml` is the router. It exports one value, `router`, of
  type `Types.router` (`boot`, `navigate`, `handle`, `stop`), and keeps
  `current_key` and `loaded` in the stub, so that a `popstate` before the
  load knows the entry of the page.
- `Navigation_web` is a virtual module with the browser functions that
  only the router uses (`fetch_page`, `swap_page`, `transition`,
  `observe`, ...), moved out of `web.js`: esbuild assigns a file to a
  chunk as a whole, so a router-only function in `web.js` stayed in the
  start chunk. For the same reason the router reads URL parts and outlet
  keys with small JavaScript functions there instead of `String` and
  `List`.
- Where the `import()` is: no file that `yuka.js` imports may contain
  it. Without code splitting (the keyed app, IIFE), esbuild wraps every
  module that a dynamic import reaches in a lazy `__esm` init function,
  also when the `import()` is dead code; that cost the keyed app 771 B
  gzip. So the code that `yuka islands` writes has it:
  `Yuka.runtime_registry ~navigation:(fun () -> Yuka.runtime_promise_map
  router (import "yuka/navigation.js"))`, with
  `external router : m -> Yuka.runtime_router = "router" [@@mel.get]`.
  `yuka/navigation.js` is the same bare path as Melange's own imports, so
  the import map and esbuild resolve it. `Yuka.runtime_registry` gives the
  loader to `Navigation_stub.start`, which keeps it in a reference, so
  `Yuka.stop`, which calls `Navigation_stub.stop`, does not reach it.
  Without `~navigation`, `runtime_registry` starts the islands only, as
  with `~navigation:false`. `runtime_registry` gets the new optional
  argument and `runtime_router` is a new abstract type; both are
  `runtime_*` names, outside semantic versioning. The first version of
  this change made `Yuka.Client` a module alias of a new `Client_api`
  module that held the loader; main's API for 1.0 keeps `Yuka.Client`
  small, so the loader moved to the generated code.
- `~navigation:false` calls `Client.start` only: no listener, and the
  router module is never requested. With code splitting the navigation
  chunk exists but is not loaded; the flag is still a run-time choice.

### Behaviour that changes

- The first client navigation after a page load waits for the router
  module (one request) unless a hover, focus or pointer down on a link
  loaded it before.
- The default prefetch of the first link that the pointer enters is sent
  after the module arrives (50 ms after the event, as before, when the
  module is already there).
- A hover or focus on a link loads the router code also with
  `~prefetch:`Off` (it fetches no page).
- After a failed or stalled load, the page does full page loads until the
  next `render`.
- In an app built without code splitting, the router is in the one bundle
  as before, and the modules it shares with the app are wrapped in lazy
  init functions.

### Size

`make size`, gzip bytes, main 543478d (built from `git archive
origin/main` with the same script) against this change:

| page | main 543478d | after |
| --- | ---: | ---: |
| counter island | 19,157 | 17,185 |
| island with `Codec` props | 19,317 | 17,259 |
| island with `Remote` | 22,981 | 20,917 |
| demo start set | 25,083 | 24,163 |
| demo `/`, `/my` | 43,375 | 42,530 |
| demo `/new`, `/issue/YUK-1` | 37,373 | 36,510 |
| all demo chunks | 47,467 | 50,262 |
| keyed app | 7,967 | 7,967 |

- The router chunk is 3,622 B gzip.
- On main b865218, before main's API for 1.0, the first version measured
  18,729 to 16,450 B on the counter page, against 14,490 B for the same
  tree with no navigation at all. What the start set still pays for
  navigation: the stub (about 2 KB minified), the `web.js` functions it
  needs (`link_href`, the history key functions), the code of shared
  files that the router uses (`Curry`, `Array`, `Option`,
  `Client.stop_within`), and one more chunk per page: esbuild puts the
  files that the start and the islands share, but the router does not,
  in their own chunk, and each file is compressed on its own.
- All demo chunks grow by 2,795 B: one more chunk, and code that is now
  compressed in more files.

### Tests

`test/navigation` (jsdom, Node `require.cache` shows whether
`yuka/navigation.js` was loaded; its `runtime_registry` passes the same
loader as the generated code):

- "navigation off loads no navigation code": with `~navigation:false`, a
  hover, a pointer down, a click and a `popstate` load no router code and
  fetch nothing.
- "the first click loads the navigation code and is not lost": no router
  code at start; the click is prevented at once, the fetch starts when
  the code arrives, the page is swapped and pushed, and there is no
  `location.assign`.
- `run.js back` (its own process, so the router is not loaded yet): a
  `popstate` to an earlier entry and then forward, before the code
  loads: each fetches its URL, swaps, restores the scroll and pushes no
  entry.
- "pointer, focus and touch off links load no navigation code": events
  on a button and an input load nothing. `run.js hover`: a `pointerover`
  on a link loads the router, which then prefetches the link.
- `run.js stall` and `run.js fail` block `yuka/navigation.js` with a Node
  resolve hook (`module.register`) that never answers or throws.
  - Stall: a `Yuka.stop` 1 s after a waiting click and a new `render`
    give no give-up and no error, and a click is still taken; a
    `beforeunload` while a click waits drops it (no late
    `location.assign`); with `` `Visible `` prefetch the load starts at
    page open, a click 1 s later is prevented, nothing happens 2.5 s
    after the click, a full load and one error 3.2 s after it, and a
    later click is not prevented.
  - Fail: one import and one error, then a click is not prevented and a
    hover, a pointer down and `Browser.navigate` start no import and log
    nothing more.
- `run.js replay`: `window.scrollY` throws, so each kept click throws in
  the router; both clicks do `location.assign` and both errors are
  logged as replay errors, not as a load failure.

On main b865218 the first three fail at "no navigation code" (the router
is linked at start). With the stub but without the replay of kept
events, the click and the back cases fail. The first version of the stub
(any pointer or focus event loaded the router, no timeout, retries after
a failure, `Web.promise_then` for the replay) fails the "off links",
`fail` and `replay` cases; the second (timer from the start of the load,
no reset on `stop`, no `beforeunload`) fails the three `stall` cases.
`e2e/demo.ts` 3b.0 checks in Chromium, in module and bundle mode, that
hovering and focusing the filter input requests no router module and
that the first click requests it once; with the first stub it fails
(`at start=1`).

No test makes `boot` throw: the stub's handling of it was checked by
reading only.

## `[@client]` attribute (2026-11-12)

Decided by the user: the island mark is the attribute `let[@client] make
... = ...` instead of the extension `let%client make ... = ...`. Reason: an
attribute can carry options later, for example `let[@client { x = 1 }]`.

- `[@yuka.client]` is the long name. `let make ... = ... [@@client]` is the
  same attribute on the same binding; the docs show only `let[@client]`.
- The payload must be empty: no option exists yet, and any payload is a
  ppx error.
- `let%client` and `let%yuka.client` are removed, with no compatibility
  path. The ppx refuses them with "let%client is now let[@client]".
- The ppx expands the attribute in its whole-file pass before the other
  rules, with the same checks and errors as before. OCaml does not report an
  attribute that no ppx reads, so the ppx refuses `[@client]` on a binding
  nested in a module or a function, in a file that is not `.mlx`, on a
  binding not named `make`, on `let rec` and on more than one binding.
  ppxlib declares the attribute for value bindings, so its `-check` mode
  reports one in another place.
- `yuka islands` finds an island by text: a line that starts with
  `let[@client]` or `let[@yuka.client]`. A `make` marked only with
  `[@@client]` is not found.

## Route helpers (2026-11-12)

Decided by the user: the shared `Routes` module has one link function per
named node (route, endpoint, action), so a link is
`Routes.hello ~name:"Yuka" ()` instead of
`Routes.href (Hello { name = "Yuka" })`. Reason: shorter links that read
as a call, with the same checks.

- `yuka routes --shared` writes, after `href`,
  `let hello ~name () = href (Hello { name })`. The name is the node name
  with its first letter in lowercase (`My_issues` is `my_issues`).
- Arguments, in the order of the constructor fields: each path param
  (also of a group, and a catch-all) is a required labelled argument; each
  search field (also of a group) is optional: `optional T` is `?tag`,
  `default T d` is `?(page = d)`, `many T` is `?(label = [])`. The default
  is the absent value that `href` leaves out, so `Routes.blog ()` is
  `/blog`.
- Each function ends with `()`, also with no param (`Routes.issues ()`):
  one form for all, as component `make`, and a search field added later
  does not break callers.
- `type t`, `href`, `find` and `with_query` do not change. `href` turns a
  `Routes.t` (for example from `find`) into a URL; the server code and
  `find` use the constructors.
- Build errors with a location in `Routes.ml`: a node name whose function
  is an OCaml keyword (the ppxlib list, plus `effect`, a keyword since
  OCaml 5.3) or a value the module defines (`href`, `find`,
  `with_query`). `href` is also a reserved label, since each function
  calls it. Constructors start with a capital letter, so two node names
  cannot give the same function name.
- Each function is a plain top-level function, so esbuild drops the ones
  a client does not call (`test/routes/client/check.mts`). It names no
  standard library value: its defaults are `[]` or the copied `default`
  values.
- `test/cycle/Routes.ml` renames its route `Find` to `Search`.

## Module-level State (2026-11-12)

Decided by the user: the server checks a module-level State at run time,
in place of the ppx. Reason: the ppx check went by spelling, so it did not
see a State in a tuple or a record, a State that a function returns, or
`State` under a module alias; and `[@@yuka.shared]` was a statement that
nothing checked.

- Removed: `[@@yuka.shared]`, `[@@shared]` and the ppx error on a
  structure-level `State.make` or `State.memo`. No compatibility path:
  ppxlib reports an unused attribute only in its `-check` mode, which dune
  does not use, so a leftover `[@@yuka.shared]` compiles with no message.
- The seal is the first server render (`Printer.print`) or the first
  request (`Cycle.handle`, which serves pages, actions, endpoints and the
  live socket) of the process. A State made before the seal is
  module-level. A State made after it never is, so the set does not grow
  per request.
- After the seal, `State.set` and `State.update` on a module-level State
  raise `Invalid_argument "Yuka.State: a write to a State made at module
  level, before the first server render or request. The server process has
  one copy for every request. Create the State inside a component."`. A
  read is allowed. A write before the seal is allowed.
- Native only: `State.set` calls `Web.check_state_write`, and the seal
  calls `Web.seal_states`. Both are in the virtual module `Web`; the
  browser versions do nothing.
- The native check is one compare: `Scheduler.make` gives each node the
  next id, so the seal keeps the last id, and a State with an id at most
  that one was made before the seal. If node ids become per domain, this
  needs a table of the States made before the seal, found by id and
  compared with `==`.
- The States of Yuka itself (`Async.watch`, `Remote`, `Live`, `Form`,
  `Catch`) go through the same check. A `Remote.use`, `Live.use` or form
  made at module level is also one copy for every request, so a server
  write to it raises.
- Size: the check added 8 B gzip to the keyed benchmark app (7,967 to
  7,975 before the merge with `Effect.after`; 7,965 after it, budget
  7,981). A table filled by `State.make` added 23 B: `make` had to call
  `Web` through `Curry`.

## `Yuka.Console` and the server log (2026-11-12)

Plan: `.workplace/plans/console_PLAN.md`. A prototype, decided by the
user: it will be improved later, and the API can change.

- `Yuka.Console` has `log`, `info`, `warn`, `error` and `debug`, each
  `string -> unit`, so shared code (an island that the server also
  renders) can log. In the browser each calls the `console` method of its
  name (`Web.console_*`). On the server each sends a level and the
  message to the server log; `log` and `info` are `` `Info ``, as in the
  browser. `Console` tests `Web.in_browser`; the server branch calls
  `Types.log_message`.
- One sink type, `Server.log_level -> string -> unit`, with
  `` Server.log_level = [ `Error | `Warn | `Info | `Debug ] ``. It replaces
  `string -> unit` in `Server.config ?log` (was `?log_error`),
  `Server.Live.node ?log` and `Server.Testing.set_log`. Breaking.
- The request context carries the sink of its config. A `Console` call
  during a server render of a request goes there; any other call (no
  render, or after the render returned, as in an action or a loader that
  resumes later) goes to the default sink, `Types.default_log`. The
  current request is the session of the running print, so an `Async`
  callback does not know it.
- Yuka's own messages use the same sink: `` `Warn `` for a blocked URL in
  a server render, a live message over 1 MiB, a live key too long for the
  bus and a `Live.use` under a shared cache rule; `` `Error `` for the
  rest.
- Default sink: one line on stderr, `yuka: LEVEL MESSAGE`; it drops
  `` `Debug ``. No logging library in `yuka`. The blocked URL message lost
  its `yuka: ` prefix and the live message its `warning: ` prefix, which
  the line now carries.
- The config keeps `log` as an option, so an adapter can fill it:
  `Server.Adapter.default_log sink config` sets it only when the user gave
  none. `Yuka_dream.handler` does this once, when it is applied to the
  config and the app, with `Dream.sub_log "yuka"` (`` `Warn `` is
  `` `Warning ``). Dream then adds the time, the level, the request id
  (from `Dream.logger`) and its threshold. A field in `Backend` would make
  every adapter, the test ones too, give a log, and would send the
  messages of `Yuka_dream.prerender` to Dream; `prerender` keeps the
  default sink.
- Not in the prototype: lazy messages, a threshold in the core, named
  sub-logs, values other than a string, and the request of an `Async`
  callback.
- Tests: `test/cycle` (the levels in a request and outside one),
  `test/native/default_log` (the stderr line, no debug), `test/melange`
  (the `console` methods), `dream/test` (a warning in the Dream log with
  the request id; a config `log` is kept).

## Param values (2026-11-12)

Decided by the user: a param type is a value, as a codec is.
`Yuka.Router.Param` has an abstract `'a t`, `make ~decode ~encode`,
`int`, `string`, `bool`, `decode` and `encode`. The module type `PARAM`
(`of_string`, `to_string`) is gone, with no compatibility path: 1.0 is
not released. Reason: one shape for codecs and params, and a user can
build a param on `Param.int` and the others.

- `Routes.ml` names the type of a param, with its module path:
  `:id<Model.issue_id>`, `optional Tab.t`,
  `default Model.sort Model.Newest`. The value comes from the rule of
  `[@@deriving codec]`: `Issue_id.t` uses `Issue_id.param`,
  `Model.issue_id` uses `Model.issue_id_param`.
  Reason: the generator reads only `Routes.ml` and sees no types, but it
  must write each field type in `type t` of `Routes`; a type path gives
  it that name, and the value follows by the codec rule.
- Build errors with a location in `Routes.ml`: a capitalised last name
  (`:id<Issue_id>`) gives what to write (`:id<Issue_id.t>`); a type
  without a module (`issue_id`) and a type with a parameter (`int list`)
  are bad types. A bare type could resolve only through an `-open` flag
  on the shared library, since the generated module opens nothing.
- The generated `type t` writes the type path as given. The generated
  code calls `Yuka.Router.Param.decode Model.issue_id_param s` and
  `Yuka.Router.Param.encode Model.issue_id_param v` where it called
  `Issue_id.of_string s` and `Issue_id.to_string v`. Percent-encoding
  does not change.
- The built-in `int`, `string`, `string...` and `bool` keep their inline
  code: `Yuka.Router.int_param p` is shorter than
  `Yuka.Router.Param.decode Yuka.Router.Param.int p`, which also goes
  through `Curry._2` in JavaScript. `int_param` stays for the generated
  code.
- `Param` is its own compilation unit, `src/router_param.ml`, and
  `yuka.mli` declares it as the alias `module Param = Router_param` inside
  `Router`. `Yuka.Router` is one JavaScript object that a client keeps
  whole when it uses the router; a member there cost the demo start
  about 120 B gzip. An alias has no field in that object, and code that
  names `Yuka.Router.Param` imports `router_param.js` itself, so a client
  with no custom param type does not grow.
- `int`, `string` and `bool` are record literals, so they are free of
  side effects. A module that calls `Param.make` at its top level is not:
  esbuild keeps it when the bundle imports it. A missing value fails with
  `Unbound value Model.issue_id_param` in the generated `routes.ml`.

## `Effect.after` and `Effect.before` (2026-11-12)

Decided by the user. Before, the DOM bindings (holes, reactive attributes,
keyed lists) and the bodies of `Effect.run` were in one queue, ordered by
depth, level and id. After a write, a user effect could run before the DOM
update of the same change and read the old DOM: an effect that reads
`count` has level 1, a hole that reads `memo (count * 2)` has level 2. The
first run of `Effect.run` was in the component body, before the nodes of
the component existed. Ticket 35.

- `Effect.run` is removed, with no alias. Two functions with its type
  replace it: `Effect.after` and `Effect.before`. There is no timing
  parameter and no `Effect.sync`.
- `Effect.before` is the old `Effect.run`: first run at creation, later
  runs in the queue of the DOM bindings, parents first.
- `Effect.after` is the common case. A later run comes after the DOM
  bindings and `before` effects of the same change. First run: when the
  effect is created inside a batch or a flush (`Scheduler.depth > 0`), it
  is put in the second queue and runs in the flush that ends that batch;
  else it runs at once, as `before` does. `render` and hydration (the
  client's `start`) now run in a `batch`, and the creation of a list row
  or of a component in a hole that runs again is inside a flush, so a
  component's `after` effect finds its elements. At the top level of
  `Yuka.owner` (not a batch) the first run is at once; in an event
  handler it is at the end of the handler's batch.
- `Effect.on_change` has the timing of `after`. Its previous value is the
  value at creation, so a change between the creation and a deferred first
  run calls it.
- Scheduler: a node's `eff` is the queue it goes to (`Some queue`,
  `Some late`, `None` for a State or a memo). `flush` takes the `queue`
  while it is not empty; when it is empty it takes `late`. So each round
  runs either `before`-kind nodes or `after` effects, in the old order
  (depth, level, id), and the `after` effects run only when no
  `before`-kind node is pending. A write in an `after` effect starts new
  rounds. Each round counts toward the limit of 100; at the limit both
  queues are dropped. Errors, cleanups and disposal do not change: a
  deferred first run that raises goes to the catch of the effect's owner
  through `flush`, as a later run does; outside a boundary it is raised at
  the end of the batch, and the effect is not stopped. An `after` effect
  whose owner is disposed before its first run has state 3 and never runs.
- `flush` lost its empty-queue check: it is only called at depth 0, and
  an empty flush does nothing.
- Internal callers keep the old timing through `Base.run_effect
  Scheduler.queue`: the holes, reactive attributes and keyed lists in
  `dom/js/client.ml`, and the effects of `Remote.use` and `Live.use`.
  Their first run reads the answer that the server embedded and sets the
  status State before the markup reads it; deferred, hydration would see
  `Loading` where the server printed the data. The keyed list no longer uses `on_change`: an effect
  calls `reconcile` on each run, as `on_change ~equal:(fun _ _ -> false)`
  did. The client does not reference `Base.Effect`, so an app that does
  not use effects does not bundle it.
- Demo: the two `on_window "keydown"` effects are `after`.
- Size (`make size`, gzip): the keyed benchmark app goes from 7,967 to
  7,962 B. A page that bundles `Base.Effect` pays for the two wrappers,
  the deferral and a second copy of the `on_change` logic in the keyed
  list: a one-island page +90 to +102 B, the demo start +108 B, the demo
  pages +118 to +124 B.
