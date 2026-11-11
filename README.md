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

## Security

- Text and attribute values are HTML-escaped on the server.
- URL attributes (`href`, `src`, `action`, `formaction`, `poster`,
  `xlink:href` and the like, in any case, and `values`, `to`, `from`, `by`
  of SVG animations) are read as the browser reads them (case, leading
  spaces and control characters, tabs and newlines). A `javascript:` or
  `vbscript:` URL is printed and set as `about:blank#blocked`, like React
  does; so is a `data:` URL where it would open or load a document or a
  script (links, forms, frames, `object`, `embed`, `script`, SVG `use`). A
  `data:` image or media URL is kept. A dev build logs the first block; a
  literal one in `.mlx` does not build. There is no way around it: use an
  event handler. In the browser the check runs where the attribute is set,
  with the real element, so it gives what the server prints.
- `srcdoc` of `iframe` is HTML, and `href` of `base` changes where every
  relative URL of the page points: a value that is not a literal in `.mlx`
  is printed and set as the empty string. Write them in `.mlx`, or point
  `src` at a page.
- `src` of `script` loads code: Yuka checks its scheme only. Never build it
  from user input. The same goes for the `content` of
  `<meta http-equiv="refresh">`: browsers do not follow a script URL there,
  but it can send the page to any other site.
- A tag name must be a letter followed by letters, digits and `-`;
  anything else raises an exception (in the browser, the DOM refuses it).
- An attribute name that is empty, starts with `on` (any case), or has a
  space, a control character, `"`, `'`, `<`, `>`, `/` or `=` raises an
  exception. Event handlers are functions: `on_click=(fun event -> ...)`
  in `.mlx` or `Yuka.on`; a string handler in `.mlx` does not build.
- `Yuka.Browser.navigate` does nothing with a `javascript:`, `vbscript:`
  or `data:` URL (a dev build logs it once). A form follows only a
  `redirect` on this site: the server answers 500 and logs one that is
  not, and the browser refuses one from another origin and shows an error.
- Hand-written templates go through `Yuka.template_of_shape`, which checks
  their tags and fixed attributes as above.
- `<script>` and `<style>` take one text (the ppx joins the texts and
  values you write inside them) and nothing else, in any case and in any
  namespace. In HTML their text is printed as written, not HTML-escaped:
  every `</` gets a backslash after the `<`, and so does `<!--` in a
  JavaScript script; in a script of another type (JSON, import map), every
  `<` becomes `\u003c`. Inside `<svg>` and `<math>` (but not in an
  SVG `<foreignObject>`) they are ordinary elements and their text is
  escaped; so it is inside `<select>`, where an HTML parser can drop the
  start tag and read the text as markup.

## Learn more

- [`demo/`](demo/README.md): an issue tracker that uses most features.
- [`DESIGN.md`](DESIGN.md): how Yuka works.

## Status

Experimental. APIs change.

## Credits

The update algorithm of the signal core in `src/scheduler.ml` is adapted
from Solid's `signal.ts` ([MIT](src/LICENSE.solid)). The mlx attribute checks in `ppx/` come from
[html_of_jsx](ppx/LICENSE.html_of_jsx).
