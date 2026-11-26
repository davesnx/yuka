# Demos

Each demo is its own Yuka app, in its own directory, with its own
`Routes.ml` that starts at `/`:

- [Mini Linear](mini-linear/README.md): an issue tracker with streamed
  pages, islands, live updates and a shared store.
- [Async](async-feed/README.md): a feed of notifications from many
  sources, with filters in the URL and events streamed over `Yuka.Live`.
- [Infinite scroll](infinite-scroll/README.md): an endless gallery of
  palettes; the next page loads when the end of the list comes into view.
- [Posters](posters/README.md): a generative poster playground, drawn by one
  OCaml function on the server and in an island, with its settings in the URL.
- [Genart](genart/README.md): sketch 004 of Amie Chen's genart series,
  drawn as SVG lines by an island that draws them again in the browser.
- `index`: the list of demos. It has no island and loads no JavaScript.
  The list is `demos` in `index/app/pages.mlx`.

One server runs all of them: `mini-linear/server/demo_server.exe --base
/mini-linear` serves Mini Linear with `Yuka.Server.config ~base` under
`/mini-linear`, Async with its own config under `/async-feed`, Infinite
scroll under `/infinite-scroll`, Posters under `/posters`, Genart under
`/genart`, and the index at every other path, so `/` is the list. Each app
has its own client bundle. The Async, Infinite scroll, Posters and Genart
configs are made before
the Mini Linear one, as
`Yuka.Router.url` outside a render uses the last config. From the
repository root:

    make demo-serve PORT=8080
