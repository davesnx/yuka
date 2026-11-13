---
name: yuka
description: Write or change a web app built with Yuka, the OCaml web framework with server-rendered pages and islands. Use when a project depends on the `yuka` opam package, or the task names Yuka, `Routes.ml`, `let[@client]`, `Yuka.Client` or `Yuka.State`. Not for general OCaml, Melange or mlx syntax questions.
---

# Yuka

Yuka is experimental and its API changes. Do not write Yuka code from
memory: read the reference for the task first. The references are copies
of the `docs/` directory of the Yuka repository.

## Model

- The server renders each page to HTML and streams slow parts when they
  are ready.
- An island is a component that also runs in the browser. Only islands
  ship JavaScript. A page with no island loads none.
- A component is a function that runs once. After the first render, only
  holes, memos and effects run again, when a State they read changes.
  There is no virtual DOM and no dependency list.
- Markup is mlx (JSX for OCaml) in `.mlx` files. Text children are string
  literals or `Yuka.text`, and `class` is written `class_`.
- An app has three parts: a shared library (native and Melange) for
  components and islands, a server executable for pages, and a client
  entry. `Routes.ml` holds the route tree; `yuka routes` reads it and
  writes the `Routes` and `Yuka_routes` modules.

## References

Read the one that matches the task:

- [Getting started](references/getting-started.md): install, project
  layout, every dune rule, the server and client entries, `yuka dev`, the
  production bundle. Read it to create an app or to fix a build rule.
- [Islands](references/islands.md): `let[@client] make`, `<Yuka.Client>`,
  props and codecs, start strategies, children. Read it before you write
  or use an interactive component.
- [State](references/state.md): State, holes, memos, effects, batches,
  what runs on the server. Read it before you write code that updates the
  page.
- [Router](references/router.md): `Routes.ml` nodes, path and search
  params, loaders, guards, layouts, links, client navigation. Read it
  before you add or change a route or a link.
- [Security](references/security.md): escaping, blocked URL schemes,
  `script` and `style` rules. Read it when markup takes user input, or
  when a URL or attribute does not show as written.

The references do not cover remote data (`Yuka.Remote`), server actions
(`Yuka.Action`, `Yuka.Server.Action`), forms (`Yuka.Form`), live data
(`Yuka.Live`, `Yuka.Topic`), `<Yuka.Await>`, `<Yuka.Show>`, `Yuka.each`
or `Yuka.Catch`. For these, read the doc comments of `yuka.mli`
(`find "$(opam var lib)/yuka" -name yuka.mli`) and the `demo/` directory
of <https://github.com/davesnx/yuka>.

## Rules

Each rule prevents a build error or a bug that the references explain.

- An island is `let[@client] make ~(label : type) ... () = ...` at the top
  level of an `.mlx` file in the shared library. One island per file; the
  file name is the tag (`counter.mlx` gives `<Counter />`).
- A page must wrap an island in `<Yuka.Client>`. Without it, the component
  prints HTML only and gets no code in the browser.
- An event handler or a hole outside an island does not compile ("Type
  Yuka.client is not compatible with type Yuka.server"). Move it to an
  island.
- An island cannot contain `<Yuka.Client>` in its own markup. Pass the
  inner island as children from the page.
- Each island prop needs a codec. Put `[@@deriving codec]` on your records
  and variants. A function cannot be a prop.
- The ppx makes a hole only where the expression itself contains
  `Yuka.State.get`. For a read inside another function, write
  `Yuka.hole (fun () -> ...)`.
- Create a State inside `make`, not at the top level of a module.
- Do not copy one State into another with an effect. Use `Yuka.State.memo`.
- Code that needs the browser goes in an effect or an event handler:
  effects do not run on the server.
- Build links with the generated functions (`Routes.hello ~name ()`), not
  with string paths. Every link function ends with `()`.
- An editor does not check `Routes.ml`. Run `dune build` and read the
  errors of `yuka routes`.
- In `Routes.ml`, write a custom param type with its module path
  (`:tab<Model.tab>`), and define `tab_param` in the shared library.
- The client `dune` lists `yuka.js` in `libraries`, and the shared library
  has `(modes native melange)`.

## Check

Run `dune build` after each change. The type checker reports a wrong
prop, param, link or server/client mix. Then load the changed page from
the running server and confirm the result.
