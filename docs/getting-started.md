# Getting started

## Install

Yuka is not on opam yet. Pin it from GitHub:

```sh
opam pin add yuka git+https://github.com/davesnx/yuka.git
opam pin add yuka-dream git+https://github.com/davesnx/yuka.git
```

`yuka` brings Melange, mlx and the `yuka` command. `yuka-dream` runs an
app on [Dream](https://github.com/camlworks/dream). Another server needs
one small adapter (`Yuka.Server.Adapter`). `yuka-live-pg` (pin it the same
way; it needs libpq) carries live data between server nodes over Postgres
`LISTEN`/`NOTIFY`.

## Setup

An app has three parts: shared code that compiles to native and to
JavaScript (components and islands), the server, and the client entry.

```
dune-project
Routes.ml
shared/   dune, counter.mlx, counter.css
server/   dune, pages.mlx, routes_server.mli, main.ml
client/   dune, main.ml
```

`dune-project` turns on Melange and the mlx dialect:

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

`Routes.ml` is the route tree. It is not compiled: `yuka routes` reads it.
`Router.make`, `Router.group`, `Router.route`, `Router.endpoint`,
`Router.action` and `Router.redirect` are the nodes of this file, and
`~page`, `~layout`, `~loader`, `~guard`, `~handler`, `~not_found` and
`~error` name functions of the server:

```ocaml
Router.make ~not_found:Pages.not_found
  [ Router.route Home ~path:"/" ~page:Pages.home ]
```

`shared/dune` builds the shared library in both modes with the ppx, and
writes the shared `Routes` module (the route type, `Routes.href` and
`Routes.find`). `preprocessor_deps` lists the CSS files of `[%yuka.css]`:

```
(library
 (name app_shared)
 (modes native melange)
 (libraries yuka)
 (preprocess
  (pps yuka.ppx))
 (preprocessor_deps
  (glob_files *.css)))

(rule
 (targets routes.ml)
 (action
  (with-stdout-to
   routes.ml
   (run %{bin:yuka} routes --shared --source %{dep:../Routes.ml}))))
```

`shared/counter.css` is a stylesheet of scoped classes:

```css
.button { font-weight: bold; }
```

`shared/counter.mlx` is an island that uses it:

```ocaml
open Yuka

module Css = [%yuka.css "counter.css"]

let[@client] make ~(initial : int) () =
  let n = State.make initial in
  <button class_=Css.button on_click=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.int (State.get n))
  </button>
```

`server/dune` writes the server routes (`Routes_server.app`) and the
sheets of every `[%yuka.css]` (`Yuka_css.sheets`):

```
(executable
 (name main)
 (libraries app_shared yuka yuka-dream dream)
 (preprocess
  (pps yuka.ppx)))

(rule
 (targets routes_server.ml)
 (action
  (with-stdout-to
   routes_server.ml
   (run %{bin:yuka} routes --server --shared-module App_shared.Routes
    --source %{dep:../Routes.ml}))))

(rule
 (targets yuka_css.ml)
 (deps
  (source_tree ../shared))
 (action
  (with-stdout-to
   yuka_css.ml
   (run %{bin:yuka} css --dir ../shared))))
```

`server/pages.mlx` has the pages that `Routes.ml` names:

```ocaml
open App_shared

let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      <main>
        <a href=(Routes.href Home)>"Home"</a>
        <Yuka.Client><Counter initial=0 /></Yuka.Client>
      </main>)

let not_found ~path () =
  Yuka.Server.page ~title:"Not found" (fun () ->
      <p>(Yuka.text ("No page at " ^ path))</p>)
```

`Routes_server.app` takes the request type of the adapter from a loader,
guard or handler. When none of them names it, give it in
`server/routes_server.mli`:

```ocaml
val app : Dream.request Yuka.Server.app
```

`server/main.ml` runs the app on Dream:

```ocaml
let read file = In_channel.with_open_bin file In_channel.input_all

let () =
  let dir = "_build/default/client/out" in
  let assets =
    Yuka.Server.modules ~dir ~entry:"client/main.js"
      ~manifest:(read "_build/default/client/yuka_islands.json")
      ~packages:(Array.to_list (Sys.readdir (Filename.concat dir "node_modules")))
      ~digest:(Yuka_dream.tree_digest dir)
  in
  let config =
    Yuka.Server.config ~assets ~css:Yuka_css.sheets
      ~dev:(Sys.getenv_opt "YUKA_DEV" = Some "1")
      ~log_error:(fun m -> Dream.error (fun log -> log "%s" m))
      ()
  in
  Dream.run @@ Dream.logger @@ Dream.set_secret "change-me"
  @@ Dream.cookie_sessions
  @@ Yuka_dream.handler config Routes_server.app
```

`client/dune` builds the browser entry and writes the island registry
(`Yuka_islands`) and its manifest. The client lists `yuka.js`, the browser
implementation of `yuka`; without it the build fails ("The library
yuka.native ... not compatible with melange"):

```
(melange.emit
 (target out)
 (libraries app_shared yuka yuka.js)
 (preprocess
  (pps yuka.ppx melange.ppx))
 (module_systems
  (es6 js)))

(rule
 (targets yuka_islands.ml)
 (deps
  (source_tree ../shared))
 (action
  (with-stdout-to
   yuka_islands.ml
   (run %{bin:yuka} islands --dir ../shared))))

(rule
 (targets yuka_islands.json)
 (deps
  (source_tree ../shared))
 (action
  (with-stdout-to
   yuka_islands.json
   (run %{bin:yuka} islands --manifest --dir ../shared))))
```

`client/main.ml` starts the islands and client navigation:

```ocaml
let () = Yuka.render ~islands ()
```

Build, then run the server from the project root and open
`http://localhost:8080`:

```sh
dune build
./_build/default/server/main.exe
```

`yuka dev` rebuilds on change, restarts the server and reloads the
browser. It starts the server with `YUKA_DEV=1`, so `main.ml` passes
`~dev:true` to the config:

```sh
yuka dev --build 'dune build --watch' --assets _build/default/client/out \
  -- ./_build/default/server/main.exe
```

For production, bundle the client and define `__YUKA_DEV__` as `false`.
Without the define, the bundle keeps the dev checks. The bundle goes in
the build directory, so make it after the last `dune build` (a build
deletes it). With esbuild:

```sh
cd _build/default/client/out/client
esbuild main.js --bundle --format=esm --splitting --outdir=bundle \
  --metafile=../../meta.json --define:__YUKA_DEV__=false
```

To serve the bundle instead of the module tree, `main.ml` gives these
assets (build it before you bundle):

```ocaml
let assets =
  Yuka.Server.bundle ~dir:"_build/default/client/out/client"
    ~entry:"bundle/main.js"
    ~manifest:(read "_build/default/client/yuka_islands.json")
    ~metafile:(read "_build/default/client/meta.json")
```
