# Demos

Each demo is its own Yuka app, in its own directory, with its own
`Routes.ml` that starts at `/`:

- [Mini Linear](mini-linear/README.md): an issue tracker with streamed
  pages, islands, live updates and a shared store.
- [Async](async-feed/README.md): a feed of notifications from many
  sources, with filters in the URL and events streamed over `Yuka.Live`.
- `index`: the list of demos. It has no island and loads no JavaScript.
  The list is `demos` in `index/app/pages.mlx`.

One server runs all of them: `mini-linear/server/demo_server.exe --base
/mini-linear` serves Mini Linear with `Yuka.Server.config ~base` under
`/mini-linear`, Async with its own config under `/async-feed`, and the
index at every other path, so `/` is the list. Each app has its own
client bundle. The Async config is made before the Mini Linear one, as
`Yuka.Router.url` outside a render uses the last config. From the
repository root:

    make demo-serve PORT=8080
