<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="Yuka" width="140">
  </picture>
</p>

<p align="center">Yuka is a web framework for OCaml.</p>

Yuka renders pages on the server and streams the slow parts as they become
ready. The parts that need interaction are islands: small components that
Melange compiles to JavaScript. A page with no island loads no JavaScript.

> [!WARNING]
> Yuka is experimental. APIs change.

## Features

- **Type-safe.** The compiler checks it all: data, props, routes and links.
- **Light.** JavaScript is opt-in. A page ships none until you add an island, and each island downloads only when it is needed.
- **Fast.** A component runs once, and a change updates only the DOM nodes that depend on it.
- **Complete.** Router, remote data, server actions and live data are built in.
- **Streaming.** The page arrives immediately and the slow or async components fill in when they are ready.
- **Familiar.** Components are functions and markup is JSX.

## Example

An island, in `counter.mlx`. It runs on the server and in the browser:

```ocaml
let[@client] make ~(initial : int) () =
  let count = Yuka.State.make initial in
  <button on_click=(fun _ -> Yuka.State.update count succ)>
    "Clicks: "
    (Yuka.int (Yuka.State.get count))
  </button>
```

Two pages, in `pages.mlx`. They run on the server only. A path param is an
argument of the page, and `Routes.hello` builds a link to the route `Hello`:

```ocaml
let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      <main>
        <a href=(Routes.hello ~name:"Yuka" ())>"Say hello"</a>
        <Yuka.Client><Counter initial=0 /></Yuka.Client>
      </main>)

let hello ~name () =
  Yuka.Server.page ~title:"Hello" (fun () ->
      <h1>(Yuka.text ("Hello, " ^ name))</h1>)
```

The routes, in `Routes.ml`. A link to a route that does not exist, or with
a wrong param, does not compile:

```ocaml
Router.make ~not_found:Pages.not_found
  [
    Router.route Home ~path:"/" ~page:Pages.home;
    Router.route Hello ~path:"/hello/:name<string>" ~page:Pages.hello;
  ]
```

## Get started

- [`docs/getting-started.md`](docs/getting-started.md): install Yuka and set up an app.
- [`docs/islands.md`](docs/islands.md): components that run in the browser.
- [`docs/state.md`](docs/state.md): state, memos and effects.
- [`docs/router.md`](docs/router.md): routes, params and links.
- [`docs/security.md`](docs/security.md): what Yuka escapes and blocks.

## For coding agents

[`skills/yuka`](skills/yuka) is a skill that teaches Yuka to a coding agent.
Its references are copies of `docs/`: `make docs` updates them, and
`make test` fails when they differ.
