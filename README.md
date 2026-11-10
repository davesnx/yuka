<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="Yuka" width="140">
  </picture>
</p>

<p align="center">Web framework for OCaml. Server-rendered, with islands.</p>

Yuka renders pages on the server and streams slow parts as they become ready.
The `yuka` library does not depend on a web server; the `yuka-dream` package
runs an app on Dream, and another server needs one small adapter. Parts that need interaction are islands: small components that
Melange compiles to JavaScript and that hydrate in the browser. Components are
written in mlx (JSX for OCaml) and use signals, so a component runs once and
only the parts that read a signal update.

## Features

- Signals: `State.make`, `State.get`, `State.set`, `State.memo`, `Effect`,
  `Yuka.batch`. A memo is read-only: `State.set` on it does not compile. A write is a change unless the new value is the same as the
  old one (identity, as JavaScript `===`); pass `~equal:( = )` for structural
  equality.
- Render once: no virtual DOM. Only holes and keyed lists update.
- mlx syntax through a ppx (`yuka.ppx`), with attribute checks.
- Compiled templates: the ppx turns each JSX tree into one HTML template that
  the browser parses once and clones for each use.
- Server rendering and hydration from one element tree, on native and Melange.
- Streaming with `<Yuka.Await>`: send the page shell first, fill in the rest later.
- Error boundaries with `<Yuka.Catch>` and loading states with `<Yuka.Show>`.
- Client navigation with prefetch on hover, a cache that follows each page's
  `Cache-Control`, and optional view transitions.
- Islands: `let%client` components with a start strategy (`Load`, `Idle`,
  `Visible`, `Interaction`) and lazy loading chosen where the island is used.
- Codecs: `[@@deriving codec]` for props and action data.
- Actions: declare once, call from the client, run on the server.
- Remote data: `Remote.use` reads a query as a `Status.t` signal, with
  retry, abort and `Remote.mutate` for optimistic changes. The server render
  embeds the answers, so hydration sends no request.
- Routes: one `Routes.ml` tree. The `yuka-routes` generator turns it into a
  `Routes` module shared by server and client (the route type, a typed
  `href` and the matcher), and a server module that the request cycle runs:
  assets, redirects, 405 and `OPTIONS`, guards, loaders, route headers and
  the streamed page.
- Prerender: pages marked `~prerender:true` are written to a directory,
  following links.
- Two packages: `yuka` (a Melange entry also lists `yuka.js`, the browser
  implementation of the DOM bindings) and `yuka-dream`, the Dream adapter.

## Examples

### Counter

A component that runs once. Only the text that reads `n` updates.

```ocaml
open Yuka

let%client make ~(initial : int) () =
  let n = State.make initial in
  <button onClick=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.int (State.get n))
  </button>
```

### Streaming

The server sends the page with the skeleton at once. When the comments are
ready, it sends them and the browser puts them in place.

```ocaml
let issue_page (i : Issue.t) : Yuka.server Yuka.element =
  <main>
    <h1>(Yuka.text i.title)</h1>
    <Yuka.Await async=(Store.comments_async i.id)
      loading=(<p>"Loading comments..."</p>)
      failed=(fun msg -> <p>(Yuka.text ("Error: " ^ msg))</p>)>
      (fun comments ->
        <ul>
          (Yuka.list (List.map (fun c -> <li>(Yuka.text c)</li>) comments))
        </ul>)
    </Yuka.Await>
  </main>
```

The request cycle streams the page (see "Routes"). A page with no
`Await` still pending after the shell and no island loads no JavaScript.

### Island

`let%client` declares a component that runs in the browser. Its props need a
codec, so the server can send them. `<Yuka.Client>` mounts it in a server page.

```ocaml
(* greeting.mlx, shared by server and client *)
module Item = struct
  type t = { name : string; count : int } [@@deriving codec]
end

let%client make ~(item : Item.t) () =
  let n = State.make item.count in
  <button onClick=(fun _ -> State.update n succ)>
    (Yuka.text (item.name ^ ": " ^ string_of_int (State.get n)))
  </button>

(* server page *)
let page () =
  <Yuka.Client loading=`Visible>
    <Greeting item=({ name = "Hello"; count = 0 }) />
  </Yuka.Client>

(* client entry, main.ml, compiled with Melange *)
let () = Yuka.mount ()
```

`Yuka.mount ()` starts the islands and makes links navigate without a full
page load. It finds the islands through a module that `yuka-islands`
generates. Add this rule next to the `melange.emit` of the client (here the
islands are in the library `demo_shared`, in `../shared`):

```
(melange.emit
 (target out)
 (libraries demo_shared yuka yuka.js)
 (preprocess
  (pps yuka.ppx melange.ppx))
 (module_systems es6))

(rule
 (targets yuka_islands.ml)
 (deps
  (source_tree ../shared))
 (action
  (with-stdout-to
   yuka_islands.ml
   (run %{bin:yuka-islands} --library demo_shared ../shared))))
```

Without the rule, the build fails with `Unbound module Yuka_islands`.
`let%client` must be at the top level of a `.mlx` file: in any other file
(`.ml`, `.re`) it is a compile error, and `yuka-islands` scans only `.mlx` files.

To write the manifest that `Yuka.Server.modules` and `Yuka.Server.bundle`
take, add a second rule that runs
`yuka-islands --manifest --library demo_shared ../shared` into
`yuka_islands.json`.

To load pages with a full page load, write `Yuka.mount ~navigation:false ()`.

When the server HTML of an island does not match what the client renders,
the browser console shows one warning per mismatch, for example
`yuka: hydration mismatch in island Demo_shared.Counter at div > span:
expected "1", found "0"`. Your bundler decides: for production, pass
`--define:__YUKA_DEV__=false` to esbuild (or the same define to another
bundler), and the log code is not in the bundle. Without the define, for
example when the browser loads the Melange output with no bundler, the
warnings are on.

Every island is its own file, loaded with a dynamic `import`. Islands that
are not on a page are never downloaded. An island loads at page open (`Load`,
the default) or, with a trigger, starts later but still downloads at page
open through the `modulepreload` link that the server prints from the
manifest (without a manifest entry, an island downloads when it starts). To download and start it
only at the trigger, write
``<Yuka.Client loading=(`Lazy `Visible)>``. Lazy is chosen where the island is
used, not in the island.

### Remote data

A query is an action that only reads (`Action.query`). An island reads it
with `Remote.use`:

```ocaml
let issues =
  Yuka.Action.query ~name:"issues" ~input:view_codec ~output:(Yuka.Codec.list Issue.codec)

let%client make ~(view : view) () =
  let source = Remote.use Queries.issues (fun () -> view) in
  match Remote.status source with
  | Status.Ready { data; _ } -> Yuka.int (List.length data)
  | Status.Loading _ -> Yuka.text "Loading"
  | Status.Failed { error; _ } -> Yuka.text (Status.error_to_string error)
  | Status.Idle -> Yuka.empty
```

The query runs again when a State read by the input function changes; the
request in flight is aborted. `Network` and `Server` errors are tried two
more times. The server render runs the implementation and writes its answer
after the island (`<script data-yuka-answer>`), so the browser starts with
the same data and sends no request; a slow answer is streamed. After a
change on the server, `Remote.invalidate query` fetches every mounted use
again. `Remote.mutate source change run` shows `change` at once, calls
`run`, keeps the change on success (or applies `~commit` with the result)
and removes it on failure. An app that does not call `Remote` gets none of
its code.

### Prefetch, cache and transitions

With navigation on, a link is prefetched 50 ms after the pointer or the
focus enters it, or at once on pointer down; the click then uses that
answer. A page whose rule gives `max-age=N` is kept for N seconds (also for
back and forward); a `no-store` page is used once, from a prefetch less than
10 s old. A successful action call empties the cache.

```ocaml
let () = Yuka.mount ~prefetch:`Hover ~transitions:true ()
```

```ocaml
<a href=(Routes.href (Issue { id })) data_yuka_prefetch="visible">...</a>
<a href="/export.csv" data_yuka_prefetch="off">...</a>
```

`~prefetch:`Visible` prefetches every link when it becomes visible, and
`~prefetch:`Off` turns prefetch off. With `~transitions:true` each client
navigation runs in a view transition, and `<html>` has
`data-yuka-nav="push"`, `"back"` or `"forward"` for CSS. A page with no
island has no client navigation; this CSS rule gives it cross-document
transitions with no JavaScript:

```css
@view-transition { navigation: auto; }
```

### Errors and loading states

`<Yuka.Catch>` shows a fallback when its children raise: while they render,
in an effect, a memo or a hole that runs again, or in an event handler.
`reset ()` renders the children again from their first state.

```ocaml
<Yuka.Catch fallback=(fun ~error ~reset ->
    <div class_="crash">
      <p>(Yuka.text error)</p>
      <button onClick=(fun _ -> reset ())>"Try again"</button>
    </div>)>
  <Issue_props issue />
</Yuka.Catch>
```

On the server, an exception in the children prints the fallback with the
error `"server error"`, and the detail goes to `Server.log_error`. In an
island, the client hydrates that fallback. An island with no `Catch` stops
at its first exception and keeps its DOM; `Yuka.mount ~on_error ()` gets the
message. A failed `Async` or `Status.Failed` is data, not an exception.

`<Yuka.Show>` shows a `Status.t`: data while it loads again, `loading` only
when there is no data yet.

```ocaml
<Yuka.Show status=(fun () -> State.get labels) loading=(<p>"Loading"</p>)
  failed=(fun e -> <p>(Yuka.text (Status.error_to_string e))</p>)>
  (fun labels -> <Chips labels />)
</Yuka.Show>
```

### CSS per module

A module brings its own stylesheet. `[%yuka.css]` reads the file at build
time and gives one `string` per class, with a name scoped to the file:

```css
/* related.css */
.related { margin-top: 20px; }
.related-list li { display: flex; }
```

```ocaml
(* related.mlx *)
module Css = [%yuka.css "related.css"]

let%client make ~related () =
  <div class_=Css.related><ul class_=Css.related_list>...</ul></div>
```

`Css.related` is `"related_1084c5c6"`; a class that the file does not have
is a compile error. Classes are found in selectors, also in `@scope` and
`@supports selector()` (not in comments, strings, `url()` or attribute
values), with CSS escapes (`.md\:flex` is `Css.md_flex`, `"md:flex_HASH"`);
other characters become `_` in the OCaml name, and a non-ASCII class name
is an error. After `[%yuka.css]`, each function named `make` that returns
an element (JSX, an `element` type annotation, or a `let%client`) calls
`Yuka.use_css Css.stylesheet`; a `make` that is not a function gets a
warning. Call `use_css` yourself in other functions. The
server prints `<link rel="stylesheet" data-yuka-css>` once per page, before
the first element that uses it; the sheets an island uses are printed
before its `<yuka-island>`, next to its `modulepreload`. In the browser, a
sheet that the page does not have yet is added to `<head>`, and after a
client navigation (and when it starts) the links move to `<head>`. A sheet is never removed.
A page with no island still loads no JavaScript.

The library needs the files at preprocessing time, and the server needs
the rewritten sheets. `yuka-css` reads the sources of the library, finds
each `[%yuka.css]` and writes the sheets as an OCaml module; a declared
file that is missing fails the build:

```dune
; shared/dune
(library (name shared) (preprocess (pps yuka.ppx))
 (preprocessor_deps (glob_files *.css)))

; server/dune
(rule (targets yuka_css.ml) (deps (source_tree ../shared))
 (action (with-stdout-to yuka_css.ml (run %{bin:yuka-css} ../shared))))
```

```ocaml
Yuka.Server.config ~css:Yuka_css.sheets ()
```

The cycle serves them at `/_yuka/css/NAME-HASH.css` with `Immutable`, and a
prerender writes them. Global CSS (resets, variables) stays in
`~styles`.

### Forms

A record with `[@@deriving form]` gets a field type and a decoder that runs
on the server and in the browser:

```ocaml
type new_issue = { title : string; priority : Priority.t } [@@deriving form]
(* type new_issue_field = Title | Priority, val new_issue_form *)

let create_issue =
  Yuka.Form.action ~name:"create_issue" ~fields:new_issue_form ~output:Issue.codec

let () =
  Yuka.Server.Form.implement create_issue
    ~redirect:(fun i -> Routes.href (Issue { id = i.id }))
    (fun input ->
      if String.trim input.title = "" then Async.return (Error [ (Some Title, "Required") ])
      else Async.return (Ok (Store.create input)))
```

```ocaml
<Yuka.Form action=create_issue>
  (fun form ->
    <div>
      <input name="title" value=(Yuka.Form.value form Title) />
      (Yuka.Form.error_view form Title (fun m -> <p class_="error">(Yuka.text m)</p>))
      <button type_=`submit>"Create"</button>
    </div>)
</Yuka.Form>
```

`<Yuka.Form>` prints `<form method="post">` with a hidden `_yuka_action`
field and no `action` attribute, so it posts to the page URL and works with
no JavaScript: the request cycle decodes the fields, runs the
implementation, and answers 303 to `redirect` (or the page URL), or renders
the page again with status 422, the sent values and the errors. The post
must come from the same origin (`Origin`, or `Sec-Fetch-Site: same-origin`; the
action call from an island and `Action` routes use the same rule);
the page's guards run before the action, and the body is read up to 1 MiB.
Two forms of one action on a page need different `key`s, so a 422 shows
the sent values in the form that was posted.
Field types are `string`, `int`, `float`, `bool` (a checkbox), `option`,
`list` and `M.t` with `M.of_string` and `M.to_string`.

Inside an island, a submit is handled in the browser: the same decoder runs
first (its errors show with no request), then `Action.call` (or `~run`, for
example with `Remote.mutate`), with `Form.pending` true until the answer;
on success `~on_ok` runs, or the page follows `redirect` (or reloads its
URL), as a post with no JavaScript would. The submit button's `name` and
`value` are part of the fields in both cases. A page whose forms
are not in an island loads no JavaScript.

### Routes

`Routes.ml` holds the route tree: one OCaml expression, `Router.make ...`,
and nothing else (no `open`, no `let`). The generator reads it as source
text; it is not compiled, so `Router` needs no definition:

```ocaml
Router.make
  [
    Router.route Home ~path:"/" ~page:Pages.home;
    Router.group ~path:"/issue/:id<Issue_id>" ~loader:Loaders.issue
      [
        Router.route Issue ~path:"/" ~page:Pages.issue
          ~search:{ tab = optional Tab };
        Router.action Close ~path:"/close" ~method_:`POST
          ~handler:Actions.close;
      ];
    Router.route Doc ~path:"/docs/:parts<string...>" ~page:Pages.doc;
    Router.redirect ~path:"/i/:id<Issue_id>" ~to_:(Permanent "/issue/:id");
  ]
```

The nodes are `Router.make` (the root), `Router.group`, `Router.route`,
`Router.endpoint`, `Router.action` and `Router.redirect`. The first
unlabelled argument of a route, endpoint or action is its name; the
unlabelled list of `Router.make` and `Router.group` holds the child nodes.
Pages, layouts, loaders, guards, handlers, `not_found` and `error` are
value paths such as `Pages.home`. The server module calls them, so each
path must resolve in the server library. A param type that is a module
(`Issue_id`) is named in both modules, so it must resolve in both libraries
(for example with `(flags (:standard -open Shared))` in the server
library).

A dune rule in the shared library (native and Melange) writes `routes.ml`:

```
(rule
 (targets routes.ml)
 (action
  (with-stdout-to routes.ml
   (with-stdin-from %{dep:../Routes.ml}
    (run %{bin:yuka-routes} --shared --source %{dep:../Routes.ml})))))
```

`--source` names the file in error locations.

The module has `type t = Home | Issue of { id : Issue_id.t; tab : Tab.t option } | ...`,
`href : t -> string` and `find : Yuka.Router.meth -> string list -> (string * string) list -> t Yuka.Router.lookup`.
`href` percent-encodes each param. It raises `Invalid_argument` when a
param segment is `""`, `"."` or `".."` (or a catch-all is `[]`): no URL
could give such a segment back, because the server drops empty segments
and browsers resolve dot segments.
A param type is `int`, `string`, `string...` (catch-all, last segment) or a
module with `of_string` and `to_string` (`Yuka.Router.PARAM`). Search fields
are `optional T`, `default T value` or `many T`. Two nodes with the same path
shape and a common method fail the build with a location in `Routes.ml`.
Otherwise the more specific path wins: a static segment before a param, a
param before a catch-all. A client that calls only `href` does not contain
`find`.

A third rule writes the server module, in the server library:

```
(rule
 (targets routes_server.ml)
 (action
  (with-stdout-to routes_server.ml
   (with-stdin-from %{dep:../Routes.ml}
    (run %{bin:yuka-routes} --server --shared-module Demo_shared.Routes
     --source %{dep:../Routes.ml})))))
```

`Routes_server.app` is a `Yuka.Server.app`. Loaders, guards and handlers take
the server's request first (`Dream.request` with Dream), then the params by
label. A page function returns `Yuka.Server.page ~title (fun () -> ...)`; it
gets the params, the search fields and the loader results (labelled with the
loader's name: `~loader:Loaders.issue` gives `~issue`). The loaders of one
route start together. A `not_found` page gets the params of the
path of its node and `~target` (the request path); an `error` page gets
them and `~status`. So no param of that path can be named `target` (with a
`not_found`) or `status` (with an `error`): the build fails.

Loaders, guards and handlers that ignore the request must still name its
type (`(_ : Dream.request)`) when no other function of the tree fixes it;
otherwise `Routes_server.app` has a weak type variable. A tree where no
function takes the request needs `routes_server.mli` with
`val app : Dream.request Yuka.Server.app` (see "Getting started").

`Yuka.Server.handle config app` answers one request in a fixed order:
`/_yuka/` (actions, client JavaScript) and public files, a 308 for a
trailing slash, the match, redirect nodes, 405 with `Allow`, `OPTIONS`,
guards, loaders, then the page. The page has no module script unless it has
an island, and no inline script unless an `Await` is still pending when the
shell is sent. Each layout's children are inside
`<yuka-outlet data-k="KEY" style="display:contents">`, and a link to the
current path gets `aria-current="page"` (not inside an island).

A client navigation sends the outlet keys of the page. When the new page
shares layouts with it, the server sends only what goes inside the deepest
shared outlet, and the client replaces only that: islands in shared layouts
keep their state. The `display:contents` element adds one level to CSS
child selectors (`.main > .x`). When the server's build id (route tree and
client files) differs from the page's, the client loads the page in full.

### With Dream

The `yuka-dream` package runs the cycle on Dream:

```ocaml
let () =
  let assets =
    Yuka.Server.modules ~dir:"client/out" ~entry:"demo/client/main.js"
      ~manifest:(read_file "client/yuka_islands.json")
      ~packages:[ "melange"; "melange.js"; "yuka"; "yuka.js" ]
      ~digest:(Yuka_dream.tree_digest "client/out")
  in
  let config =
    Yuka.Server.config ~assets ~public:[ ("/static", "static") ]
      ~styles:[ "/static/style.css" ] ()
  in
  Dream.run @@ Dream.logger @@ Yuka_dream.handler config Routes_server.app
```

`Yuka.Server.modules` serves the Melange module tree under `/_yuka/` with an
import map; `Yuka.Server.bundle` serves an esbuild bundle (with its
`--metafile`, so the `<link rel="modulepreload">` of each island points at
its hashed chunk). Actions are answered at `POST /_yuka/action/<name>`.
`Yuka_dream.to_async` and `to_lwt` convert between `Lwt.t` and
`Yuka.Async.t`.

Another server implements `Yuka.Server.ADAPTER` (request fields, `respond`,
`file`, `exists`, its promise type) and gets a handler from
`Yuka.Server.Make`.

### Prerender

`~prerender:true` on a node marks its pages for prerendering.
`Yuka_dream.prerender ~out config app` renders each such page with no param,
then follows the links of each page to other prerender pages (links to
another origin are not followed), and writes the files: `/` to
`index.html`, `/a/b` to `a/b/index.html`, `/feed.xml` to `feed.xml`, plus
`404.html` and the `/_yuka/` and public files. A page that does not answer
2xx is skipped with a warning. `Yuka.Server.config ~prerendered:dir` serves
those files for a plain `GET` (no query, no `Yuka-Navigate`) after the
guards, and renders the page when its file is missing. The demo writes its
prerendered pages with `demo_server.exe --prerender DIR`.

## Getting started

You need OCaml 5.4 and opam. Install Yuka, the Dream adapter and mlx (it
gives `mlx-pp`, which reads `.mlx` files):

```sh
opam install yuka yuka-dream mlx
```

This app has one page with one island, a counter. Create these files in an
empty directory.

`dune-project`:

```
(lang dune 3.16)

(using melange 0.1)

(dialect
 (name mlx)
 (implementation
  (extension mlx)
  (merlin_reader mlx)
  (preprocess
   (run mlx-pp %{input-file}))))
```

`Routes.ml`, the route tree:

```ocaml
Router.make [ Router.route Home ~path:"/" ~page:Pages.home ]
```

`shared/dune`, the code of both server and browser, with the shared
`Routes` module:

```
(library
 (name shared)
 (modes native melange)
 (libraries yuka)
 (preprocess (pps yuka.ppx)))

(rule
 (targets routes.ml)
 (action
  (with-stdout-to routes.ml
   (with-stdin-from %{dep:../Routes.ml}
    (run %{bin:yuka-routes} --shared --source %{dep:../Routes.ml})))))
```

`shared/counter.mlx`, the island:

```ocaml
open Yuka

let%client make ~(initial : int) () =
  let n = State.make initial in
  <button onClick=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.int (State.get n))
  </button>
```

`server/dune`:

```
(executable
 (name main)
 (libraries shared yuka yuka-dream dream)
 (preprocess (pps yuka.ppx)))

(rule
 (targets routes_server.ml)
 (action
  (with-stdout-to routes_server.ml
   (with-stdin-from %{dep:../Routes.ml}
    (run %{bin:yuka-routes} --server --shared-module Shared.Routes
     --source %{dep:../Routes.ml})))))
```

`server/routes_server.mli`. No function of this route tree takes the
request, so the interface gives its type:

```ocaml
val app : Dream.request Yuka.Server.app
```

`server/pages.mlx`, the page that `Routes.ml` names:

```ocaml
let home () =
  Yuka.Server.page ~title:"Hello" (fun () ->
      <main>
        <h1>"Hello from Yuka"</h1>
        <Yuka.Client><Shared.Counter initial=0 /></Yuka.Client>
      </main>)
```

`server/main.ml`:

```ocaml
let read_file path = In_channel.with_open_bin path In_channel.input_all

let () =
  let assets =
    Yuka.Server.modules ~dir:"_build/default/client/out" ~entry:"client/main.js"
      ~manifest:(read_file "_build/default/client/yuka_islands.json")
      ~packages:[ "melange"; "melange.js"; "yuka"; "yuka.js" ]
      ~digest:(Yuka_dream.tree_digest "_build/default/client/out")
  in
  let config = Yuka.Server.config ~assets () in
  Dream.run @@ Dream.logger @@ Yuka_dream.handler config Routes_server.app
```

`client/dune`, the browser code and the island list:

```
(melange.emit
 (target out)
 (libraries shared yuka yuka.js)
 (preprocess (pps yuka.ppx melange.ppx))
 (module_systems es6))

(rule
 (targets yuka_islands.ml)
 (deps (source_tree ../shared))
 (action
  (with-stdout-to yuka_islands.ml
   (run %{bin:yuka-islands} --library shared ../shared))))

(rule
 (targets yuka_islands.json)
 (deps (source_tree ../shared))
 (action
  (with-stdout-to yuka_islands.json
   (run %{bin:yuka-islands} --manifest --library shared ../shared))))
```

`client/main.ml`:

```ocaml
let () = Yuka.mount ()
```

Build and run it from the directory of `dune-project`:

```sh
dune build
dune exec ./server/main.exe
```

Open `http://localhost:8080/` and click the button. The sections above
describe each part.

### The demo

The demo is an issue tracker. It uses every feature above. From the
repository root:

```sh
dune build @demo/all
_build/default/demo/server/demo_server.exe --port 8080
```

Open `http://localhost:8080/`. See `demo/README.md` for the pages and flags.

Run the tests:

```sh
dune test
```

DOM tests run under node with jsdom: run `npm install` first.

## Status

Experimental. APIs change. `DESIGN.md` describes the current design.

## Credits

The update algorithm of the signal core in `src/scheduler.ml` is adapted
from Solid's `signal.ts` ([MIT](src/LICENSE.solid)). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
