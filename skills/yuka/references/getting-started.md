# Getting started

## Install

Yuka is not on opam yet. Pin it from GitHub:

```sh
opam pin add yuka git+https://github.com/davesnx/yuka.git
opam pin add yuka-dream git+https://github.com/davesnx/yuka.git
```

`yuka` brings Melange, mlx and the `yuka` command. `yuka-dream` runs an
app on [Dream](https://github.com/camlworks/dream). Pin these the same
way when you need them:

- `yuka-tapak` runs an app on [tapak](https://github.com/syaiful6/tapak),
  in direct style on Eio (`Yuka_tapak.handler`). tapak and cows are not
  on opam: pin them at the commits that `make pin-list` of the Yuka
  repository prints.
- `yuka-live-pg` carries live data between server nodes over Postgres
  `LISTEN`/`NOTIFY`. It needs libpq.

Another server needs one small adapter (`Yuka.Server.Adapter`).

For editor support, `opam install ocamlmerlin-mlx`.

## Setup

An app has three parts: shared code that compiles to native and to
JavaScript (components and islands), the server, and the client entry.

```
dune-project
Routes.ml
shared/   dune, counter.mlx, counter.css
server/   dune, pages.mlx, main.ml
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
`Router.make`, `Router.group`, `Router.route`, `Router.get`,
`Router.post`, `Router.put`, `Router.patch`, `Router.delete` and
`Router.redirect` are the nodes of this file, and
`~page`, `~layout`, `~loader`, `~guard`, `~handler`, `~not_found` and
`~error` name functions of the server:

```ocaml
Router.make ~not_found:Pages.not_found
  [ Router.route Home ~path:"/" ~page:Pages.home ]
```

`shared/dune` builds the shared library in both modes with the ppx, and
writes the shared `Routes` module (the route type, a link function for
each route such as `Routes.home ()`, `Routes.href` and `Routes.find`). `preprocessor_deps` lists the CSS files of `[%yuka.css]`:

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
module Css = [%yuka.css "counter.css"]

let[@client] make ~(initial : int) () =
  let count = Yuka.State.make initial in
  <button class_=Css.button on_click=(fun _ -> Yuka.State.update count succ)>
    "Clicks: "
    (Yuka.int (Yuka.State.get count))
  </button>
```

`server/dune` writes the server routes (`Yuka_routes.app`) and the
sheets of every `[%yuka.css]` (`Yuka_css.sheets`). A rule that runs
`yuka css` or `yuka islands` over a directory needs `(sandbox always)`:
without it, the command reads the build directory of `shared`, where
dune deletes and writes other files during the same build, and the build
can fail now and then:

```
(executable
 (name main)
 (libraries app_shared yuka yuka-dream dream)
 (preprocess
  (pps yuka.ppx)))

(rule
 (targets yuka_routes.ml)
 (action
  (with-stdout-to
   yuka_routes.ml
   (run %{bin:yuka} routes --server --shared-module App_shared.Routes
    --source %{dep:../Routes.ml}))))

(rule
 (targets yuka_css.ml)
 (deps
  (source_tree ../shared)
  (sandbox always))
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
        <a href=(Routes.home ())>"Home"</a>
        <Yuka.Client><Counter initial=0 /></Yuka.Client>
      </main>)

let not_found ~path () =
  Yuka.Server.page ~title:"Not found" (fun () ->
      <p>(Yuka.text ("No page at " ^ path))</p>)
```

`server/main.ml` runs the app on Dream:

```ocaml
let read file = In_channel.with_open_bin file In_channel.input_all

let () =
  let dir = "_build/default/client/out" in
  let assets =
    match
      Yuka.Server.modules ~dir ~entry:"client/main.js"
        ~manifest:(read "_build/default/client/yuka_islands.json")
        ~packages:(Array.to_list (Sys.readdir (Filename.concat dir "node_modules")))
        ~digest:(Yuka.Server.tree_digest dir)
    with
    | Ok assets -> assets
    | Error message ->
        prerr_endline message;
        exit 1
  in
  let config =
    Yuka.Server.config ~assets ~css:Yuka_css.sheets
      ~dev:(Sys.getenv_opt "YUKA_DEV" = Some "1")
      ()
  in
  Dream.run @@ Dream.logger @@ Dream.set_secret "change-me"
  @@ Dream.cookie_sessions
  @@ Yuka_dream.handler config Yuka_routes.app
```

The config has no `~log`, so `Yuka_dream.handler` sends the messages of
Yuka, and of `Yuka.Console` during a request, to the Dream log under the
name `yuka`.

### Live data on more than one server

With more than one server process, each process joins a bus before it
serves, so that a publish reaches the pages on every process (see
[Data](data.md#nodes-and-the-bus)). Add `yuka-live-pg` and `unix` to the
`libraries` of `server/dune`, and in `main.ml`, before `Dream.run`:

```ocaml
let name = Printf.sprintf "%s-%d" (Unix.gethostname ()) (Unix.getpid ()) in
let bus = Yuka_live_pg.bus ~conninfo:"host=db dbname=app user=app" ~channel:"app_live" () in
Lwt_main.run (Yuka_dream.to_lwt (Yuka.Server.Live.use_bus ~name bus));
```

`Yuka_dream.handler config Yuka_routes.app` then uses the default live
node, which is on the bus. The name must be unique to the process.

### Static files and prerender

`~public` serves the files of a directory under a URL prefix, and
`~prerendered` serves the pages that a prerender wrote:

```ocaml
let config =
  Yuka.Server.config ~assets ~css:Yuka_css.sheets
    ~public:[ ("/static", "static") ]
    ~prerendered:"_build/site"
    ()
```

A prerender writes each page whose rules say `~prerender:true` (see
[Router](router.md)) to a directory. It starts from the nodes with no
param, follows the links of each page to other such pages, writes
`404.html`, and copies the client JavaScript and the `public`
directories. A page that uses `Yuka.Live.make` is not written. Run it as a
build step, with the config and app of the server:

```ocaml
match Lwt_main.run (Yuka_dream.prerender ~out:"_build/site" config Yuka_routes.app) with
| Ok () -> ()
| Error message ->
    prerr_endline message;
    exit 1
```

With `~prerendered`, a `GET` of such a page, with no query, gets its
file after the guards run, and the loaders do not run. In dev mode the
server does not use the files.

`client/dune` builds the browser entry and writes the island registry
(`Yuka_islands`) and its manifest:

```
(melange.emit
 (target out)
 (libraries app_shared yuka)
 (preprocess
  (pps yuka.ppx melange.ppx))
 (module_systems
  (es6 js)))

(rule
 (targets yuka_islands.ml)
 (deps
  (source_tree ../shared)
  (sandbox always))
 (action
  (with-stdout-to
   yuka_islands.ml
   (run %{bin:yuka} islands --dir ../shared))))

(rule
 (targets yuka_islands.json)
 (deps
  (source_tree ../shared)
  (sandbox always))
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
deletes it). Yuka does not bundle; you run esbuild:

```sh
cd _build/default/client/out/client
esbuild main.js --bundle --minify --format=esm --splitting --outdir=bundle \
  --metafile=../../meta.json --define:__YUKA_DEV__=false
```

`--metafile` writes esbuild's report of the bundle as JSON. esbuild puts a
hash in the name of each chunk, and the server reads the report to find
the chunk of each island and to give the hashed files a long cache time.

A smaller bundle needs two more steps, which the command line of esbuild
cannot do: tell esbuild that the modules of Yuka have no side effects, so
it drops the ones the app does not use, and minify a second time with
[swc](https://swc.rs). On Yuka's demo, with each chunk gzipped, the
command above gives 107.2 KB in all and this script 101.3 KB. Install `esbuild` and `@swc/core` from npm,
save the script as `client/bundle.mjs` and run it in the place of the
command above (`node ../../../../../client/bundle.mjs`):

```js
import { build } from "esbuild";
import { minify } from "@swc/core";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const yuka = {
  name: "yuka",
  setup(build) {
    build.onResolve({ filter: /\.js$/ }, async (args) => {
      if (args.pluginData === yuka) return undefined;
      const found = await build.resolve(args.path, {
        kind: args.kind,
        importer: args.importer,
        resolveDir: args.resolveDir,
        pluginData: yuka,
      });
      const inYuka = /[\\/]node_modules[\\/]yuka(\.js)?[\\/]/.test(found.path);
      return inYuka ? { ...found, sideEffects: false } : found;
    });
  },
};

const result = await build({
  entryPoints: ["main.js"],
  bundle: true,
  minify: true,
  format: "esm",
  splitting: true,
  outdir: "bundle",
  define: { __YUKA_DEV__: "false" },
  metafile: true,
  write: false,
  plugins: [yuka],
});

for (const file of result.outputFiles) {
  mkdirSync(dirname(file.path), { recursive: true });
  const { code } = await minify(file.text, {
    module: true,
    compress: { passes: 3 },
    mangle: { toplevel: true },
  });
  writeFileSync(file.path, code);
}

writeFileSync("../../meta.json", JSON.stringify(result.metafile));
```

To serve the bundle instead of the module tree, `main.ml` gives these
assets (build it before you bundle):

```ocaml
let assets =
  match
    Yuka.Server.bundle ~dir:"_build/default/client/out/client"
      ~entry:"bundle/main.js"
      ~manifest:(read "_build/default/client/yuka_islands.json")
      ~metafile:(read "_build/default/client/meta.json")
  with
  | Ok assets -> assets
  | Error message ->
      prerr_endline message;
      exit 1
```

## Next

- [`router.md`](router.md): routes, params, loaders, guards and links.
- [`islands.md`](islands.md): `<Yuka.Client>`, props, start strategies and
  children.
- [`state.md`](state.md): State, memos, effects and when updates run.
- [`data.md`](data.md): actions, forms, remote data, live data, `Await`
  and `Catch`.
