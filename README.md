<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo-light.svg" alt="Yuka" width="140">
  </picture>
</p>

<p align="center">Web framework for OCaml. Server-rendered, with islands.</p>

Yuka renders pages on the server and streams the slow parts as they become
ready. The parts that need interaction are islands: small components that
Melange compiles to JavaScript. A page with no island loads no JavaScript.

## Features

- **Signals, no virtual DOM.** A component runs once; only the parts that read a signal update.
- **mlx syntax.** JSX for OCaml, checked at compile time.
- **Streaming.** Send the page shell first and fill in the rest when it is ready.
- **Islands.** Start on load, when idle, when visible or on interaction, and download only when needed.
- **Typed routes.** One route tree gives typed links on the server and the client, and loaders and guards on the server.
- **Actions and forms.** Declare once, run on the server, call from the browser. Forms work without JavaScript.
- **Remote and live data.** Queries with retry and optimistic updates; server state pushed over a WebSocket, also across server nodes through a bus (`yuka-live-pg` for Postgres).
- **Scoped CSS.** One stylesheet per module, with a compile error for a class that does not exist.
- **Client navigation.** Prefetch, cache and view transitions.
- **Prerender** pages to static files, and **`yuka dev`** to rebuild and reload on change.

## Example

```ocaml
open Yuka

let%client make ~(initial : int) () =
  let n = State.make initial in
  <button on_click=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.int (State.get n))
  </button>
```

## Install

Yuka is not on opam yet. Pin it from GitHub:

```sh
opam pin add yuka git+https://github.com/davesnx/yuka.git
opam pin add yuka-dream git+https://github.com/davesnx/yuka.git
opam install mlx
```

`yuka-dream` runs an app on [Dream](https://github.com/camlworks/dream).
Another server needs one small adapter. `yuka-live-pg` (pin it the same
way; it needs libpq) carries live data between server nodes over Postgres
`LISTEN`/`NOTIFY`.

## Learn more

- [`demo/`](demo/README.md): an issue tracker that uses most features.
- [`DESIGN.md`](DESIGN.md): how Yuka works.
- [`docs/security.md`](docs/security.md): what Yuka escapes, blocks and refuses.

## Status

Experimental. APIs change.

## Credits

The update algorithm of the signal core in `src/scheduler.ml` is adapted
from Solid's `signal.ts` ([MIT](src/LICENSE.solid)). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
