<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="Yuka" width="280">
  </picture>
</p>

<p align="center">Web framework for OCaml. Server-rendered, with islands.</p>

Yuka renders pages on the server with Dream and streams slow parts as they
become ready. Parts that need interaction are islands: small components that
Melange compiles to JavaScript and that hydrate in the browser. Components are
written in mlx (JSX for OCaml) and use signals, so a component runs once and
only the parts that read a signal update.

## Features

- Signals: `State.make`, `State.get`, `State.set`, `State.memo`, `Effect`.
- Render once: no virtual DOM. Only holes and keyed lists update.
- mlx syntax through a ppx (`yuka.ppx`), with attribute checks.
- Server rendering and hydration from one element tree, on native and Melange.
- Streaming with `Yuka.await`: send the page shell first, fill in the rest later.
- Islands: `let%client` components with a start strategy (`Load`, `Idle`,
  `Visible`, `Interaction`) and optional lazy loading.
- Codecs: `[@@deriving codec]` for props and action data.
- Actions: declare once, call from the client, run on the server.
- Router: typed paths shared by server and client (`yuka.router`).

## Examples

### Counter

A component that runs once. Only the text that reads `n` updates.

```ocaml
open Yuka

let%client make ~(initial : int) () =
  let n = State.make initial in
  <button onClick=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.text (string_of_int (State.get n)))
  </button>
```

### Streaming

The server sends the page with the skeleton at once. When the comments are
ready, it sends them and the browser puts them in place.

```ocaml
let comments_async id =
  Yuka_server.Async.of_lwt
    (let%lwt () = Lwt_unix.sleep 0.6 in
     Lwt.return (Store.comments id))

let issue_page (i : Issue.t) : Yuka.server Yuka.element =
  <main>
    <h1>(Yuka.text i.title)</h1>
    (Yuka.await (comments_async i.id)
       ~loading:<p>"Loading comments..."</p>
       ~failed:(fun msg -> <p>(Yuka.text ("Error: " ^ msg))</p>)
       (fun comments ->
         <ul>
           (Yuka.list
              (List.map (fun c -> <li>(Yuka.text c)</li>) comments))
         </ul>))
  </main>

let handler request =
  Yuka_server.respond ~request ~title:"Issue" (fun () -> issue_page issue)
```

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

(* client entry, compiled with Melange *)
let () = Yuka_client.start [ Greeting.register ]
```

## Getting started

The demo is an issue tracker. It uses every feature above. It needs OCaml 5.4,
dune 3.16+, Melange, mlx and Dream. From the repository root:

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

v0.1, experimental. APIs change. `DESIGN.md` describes the current design.

## Credits

The signal core in `src/` comes from
[reativa](src/LICENSE.reativa). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
