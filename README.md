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

- Signals: `State.make`, `State.get`, `State.set`, `State.memo`, `Effect`.
- Render once: no virtual DOM. Only holes and keyed lists update.
- mlx syntax through a ppx (`yuka.ppx`), with attribute checks.
- Server rendering and hydration from one element tree, on native and Melange.
- Streaming with `<Yuka.Await>`: send the page shell first, fill in the rest later.
- Islands: `let%client` components with a start strategy (`Load`, `Idle`,
  `Visible`, `Interaction`) and lazy loading chosen where the island is used.
- Codecs: `[@@deriving codec]` for props and action data.
- Actions: declare once, call from the client, run on the server.
- Router: typed paths shared by server and client (`Yuka.Router`).
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
`let%client` must be at the top level of a file.

To write the manifest for `~preload`, add a second rule that runs
`yuka-islands --manifest --library demo_shared ../shared` into
`yuka_islands.json`.

To load pages with a full page load, write `Yuka.mount ~navigation:false ()`.

Every island is its own file, loaded with a dynamic `import`. Islands that
are not on a page are never downloaded. An island loads at page open (`Load`,
the default) or, with a trigger, starts later but still downloads at page
open through the `modulepreload` link that `~preload` prints (without
`~preload`, an island downloads when it starts). To download and start it
only at the trigger, write
``<Yuka.Client loading=(`Lazy `Visible)>``. Lazy is chosen where the island is
used, not in the island.

## Getting started

The demo is an issue tracker. It uses every feature above. It needs OCaml 5.4,
dune 3.16+, Melange and mlx; the demo server also uses Dream. From the
repository root:

Yuka needs [melange-tiny](https://github.com/davesnx/melange-tiny), which is
not in opam. Pin it with `make pin`, or link a checkout that is next to this
one: `mkdir -p vendor && ln -s ../../melange-tiny vendor/melange-tiny`.

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
