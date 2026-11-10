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
- **Typed routes.** One route tree gives typed links, loaders and guards on the server and the client.
- **Actions and forms.** Declare once, run on the server, call from the browser. Forms work without JavaScript.
- **Remote and live data.** Queries with retry and optimistic updates; server state pushed over a WebSocket.
- **Scoped CSS.** One stylesheet per module, with a compile error for a class that does not exist.
- **Client navigation.** Prefetch, cache and view transitions.
- **Prerender** pages to static files, and **`yuka dev`** to rebuild and reload on change.

## Example

```ocaml
open Yuka

let%client make ~(initial : int) () =
  let n = State.make initial in
  <button onClick=(fun _ -> State.update n succ)>
    "Clicks: "
    (Yuka.int (State.get n))
  </button>
```

## Install

```sh
opam install yuka yuka-dream mlx
```

`yuka-dream` runs an app on [Dream](https://github.com/camlworks/dream).
Another server needs one small adapter.

## Security

- Text and attribute values are HTML-escaped on the server.
- URL attributes (`href`, `src`, `action`, `formaction`, `poster`,
  `xlink:href` and the like, in any case, and `values`, `to`, `from`, `by`
  of SVG animations) are read as the browser reads them (case, leading
  spaces and control characters, tabs and newlines). A `javascript:` or
  `vbscript:` URL is printed and set as `about:blank#blocked`, like React
  does; so is a `data:` URL where it would open or load a document (links,
  forms, frames, `object`, `embed`, SVG `use`). A `data:` image or media URL
  is kept. A dev build logs the first block; a literal one in `.mlx` does
  not build. There is no way around it: use an event handler.
- `srcdoc` of `iframe` is HTML and is not checked, like in React: never
  put user input in it.
- `<script>` and `<style>` take one text (the ppx joins the texts and
  values you write inside them) and nothing else. In HTML their text is
  printed as written, not HTML-escaped: in a JavaScript script `</script`
  and `<!--` get a backslash after the `<`; in a style, `</style`; in a
  script of another type (JSON, import map), every `<` becomes `\u003c`.
  Inside `<svg>` and `<math>` they are ordinary elements and their text is
  escaped.

## Learn more

- [`demo/`](demo/README.md): an issue tracker that uses every feature.
- [`DESIGN.md`](DESIGN.md): how Yuka works.

## Status

Experimental. APIs change.

## Credits

The update algorithm of the signal core in `src/scheduler.ml` is adapted
from Solid's `signal.ts` ([MIT](src/LICENSE.solid)). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
