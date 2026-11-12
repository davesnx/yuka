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

## Features

- **Type-safe.** The compiler checks it all: data, props, routes and links. A mistake is a build error, not a bug in production.
- **Light.** JavaScript is opt-in. A page ships none until you add an island, and each island downloads only when it is needed.
- **Fast.** No virtual DOM. A component runs once, and a change updates only the DOM nodes that depend on it.
- **Complete.** Router, remote data, server actions and live data are built in. You add no other library to build a full app.
- **Streaming.** The page arrives at once and the slow parts fill in when they are ready. Nobody waits for the slowest query.
- **Familiar.** Components are functions and markup is JSX. If you know React, you can read Yuka on day one, with no hook rules to learn.

## Example

An island, in `counter.mlx`. It runs on the server and in the browser:

```ocaml
open Yuka

let[@client] make ~(initial : int) () =
  let n = State.make initial in
  <button on_click=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.int (State.get n))
  </button>
```

Two pages, in `pages.mlx`. They run on the server only. A path param is an
argument of the page, and `Routes.href` builds a link from a route:

```ocaml
let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      <main>
        <a href=(Routes.href (Hello { name = "Yuka" }))>"Say hello"</a>
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

## Learn more

- [`docs/getting-started.md`](docs/getting-started.md): install Yuka and set up an app.
- [`docs/features.md`](docs/features.md): the full feature list.
- [`demo/`](demo/README.md): an issue tracker that uses most features.
- [`src/yuka.mli`](src/yuka.mli): the API, with a doc comment for each value.
- [`DESIGN.md`](DESIGN.md): how Yuka works.
- [`docs/security.md`](docs/security.md): what Yuka escapes, blocks and refuses.

## Status

Experimental. APIs change.

## Credits

The update algorithm of the signal core in `src/scheduler.ml` is adapted
from Solid's `signal.ts` ([MIT](src/LICENSE.solid)). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
