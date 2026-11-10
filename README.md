<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="Yuka" width="140">
  </picture>
</p>

<p align="center">Web framework for OCaml. Server-rendered, with islands.</p>

Yuka renders pages on the server and streams slow parts as they become ready.
It does not depend on a web server: you connect it to Dream, or any other, in a
few lines. Parts that need interaction are islands: small components that
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
- Islands: `let%client` components with a start strategy (`Load`, `Idle`,
  `Visible`, `Interaction`) and lazy loading chosen where the island is used.
- Codecs: `[@@deriving codec]` for props and action data.
- Actions: declare once, call from the client, run on the server.
- Router: typed paths shared by server and client (`Yuka.Router`).
- Routes: one `Routes.mlx` tree. The `yuka-routes` generator turns it into a
  `Routes` module with the route type, a typed `href` and the matcher, and a
  server module that the request cycle (`Yuka.Server.handle`) runs: assets,
  redirects, 405 and `OPTIONS`, guards, loaders, route headers and the
  streamed page (in progress: no server adapter yet).
- One library, `yuka`. A Melange entry also lists `yuka.js`, the browser
  implementation of the DOM bindings.

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

`Yuka.Server.respond` writes the page through two functions that your web
server gives: `write` sends a chunk, `sleep` waits (for the stream timeout).
With Dream and Lwt (see `demo/server/yuka_dream.ml`):

```ocaml
let to_async p =
  let async, resolve, fail = Yuka.Async.make () in
  Lwt.on_any p resolve (fun e -> fail (Printexc.to_string e));
  async

let to_lwt async =
  let p, w = Lwt.wait () in
  Yuka.Async.on_result async (function
    | Ok v -> Lwt.wakeup w v
    | Error m -> Lwt.wakeup_exn w (Failure m));
  p

let handler request =
  let navigating = Dream.header request "Yuka-Navigate" = Some "1" in
  Dream.stream ~headers:[ ("Vary", "Yuka-Navigate") ] (fun stream ->
      let write s = to_async (Lwt.bind (Dream.write stream s) (fun () -> Dream.flush stream)) in
      let sleep d = to_async (Lwt_unix.sleep d) in
      to_lwt
        (Yuka.Server.respond ~navigating ~title:"Issue" ~preload ~sleep ~write (fun () ->
             issue_page issue)))
```

`preload` makes the server print `<link rel="modulepreload">` for each island on
the page, so the browser downloads its code early. Build it once at start from
the manifest that `yuka-islands --manifest` writes (see "Island"):

```ocaml
let preload =
  Yuka.Server.preload_urls ~manifest:(read_file "yuka_islands.json")
    ~base:"/static/js/demo/client/" ()
```

With an esbuild `--metafile`, pass it as `~metafile:(read_file "meta.json")`:
the links then point at the hashed chunks.

Actions go through `Yuka.Server.handle_action`, which returns the status and
the JSON body; mount it on `POST /_yuka/action/:name`.

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

To write the manifest for `~preload`, add a second rule that runs
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
open through the `modulepreload` link that `~preload` prints (without
`~preload`, an island downloads when it starts). To download and start it
only at the trigger, write
``<Yuka.Client loading=(`Lazy `Visible)>``. Lazy is chosen where the island is
used, not in the island.

### Routes

`Routes.mlx` holds the route tree. It is read by the generator, not compiled:

```ocaml
let routes =
  <Router>
    <Route name=Home path="/" page=Pages.home />
    <Group path="/issue/:id<Issue_id>" loader=Loaders.issue>
      <Route name=Issue path="/" page=Pages.issue search={ tab = optional Tab } />
      <Action name=Close path="/close" method_=`POST handler=Actions.close />
    </Group>
    <Route name=Doc path="/docs/:parts<string...>" page=Pages.doc />
    <Route path="/i/:id<Issue_id>" redirect=(Permanent "/issue/:id") />
  </Router>
```

Two dune rules in the shared library (native and Melange) write `routes.ml`:

```
(rule
 (targets routes.ast)
 (deps ../Routes.mlx)
 (action (with-stdout-to routes.ast (run %{bin:mlx-pp} %{deps}))))

(rule
 (targets routes.ml)
 (action
  (with-stdout-to routes.ml
   (run %{bin:yuka-routes} --shared %{dep:routes.ast}))))
```

The module has `type t = Home | Issue of { id : Issue_id.t; tab : Tab.t option } | ...`,
`href : t -> string` and `find : Yuka.Router.meth -> string list -> (string * string) list -> t Yuka.Router.lookup`.
A param type is `int`, `string`, `string...` (catch-all, last segment) or a
module with `of_string` and `to_string` (`Yuka.Router.PARAM`). Search fields
are `optional T`, `default T value` or `many T`. Two nodes with the same path
shape and a common method fail the build with a location in `Routes.mlx`.
Otherwise the more specific path wins: a static segment before a param, a
param before a catch-all. A client that calls only `href` does not contain
`find`.

A third rule writes the server module, in the server library:

```
(rule
 (targets routes_server.ml)
 (action
  (with-stdout-to routes_server.ml
   (run %{bin:yuka-routes} --server --shared-module Demo_shared.Routes
    %{dep:../shared/routes.ast}))))
```

`Routes_server.app` is a `Yuka.Server.app`. Loaders, guards and handlers take
the server's request first (`Dream.request` with Dream), then the params by
label. A page function returns `Yuka.Server.page ~title (fun () -> ...)`; it
gets the params, the search fields and the loader results (labelled with the
loader's name: `loader=Loaders.issue` gives `~issue`). The loaders of one
route start together.

`Yuka.Server.handle config app` answers one request in a fixed order:
`/_yuka/` and public files, a 308 for a trailing slash, the match, redirect
nodes, 405 with `Allow`, `OPTIONS`, guards, loaders, then the page. A server
implements `Yuka.Server.ADAPTER` (request fields, `respond`, `file`, its
promise type) and gets a handler from `Yuka.Server.Make`. The page has no
module script unless it has an island, and no inline script unless an
`Await` is still pending when the shell is sent. Each layout's children are inside
`<yuka-outlet data-k="KEY" style="display:contents">`, and a link to the
current path gets `aria-current="page"`.

## Getting started

The demo is an issue tracker. It uses every feature above. It needs OCaml 5.4,
dune 3.16+, Melange and mlx; the demo server also uses Dream. From the
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

The signal core in `src/` comes from
[reativa](src/LICENSE.reativa). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
