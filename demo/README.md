# Demos

Each demo is its own Yuka app, in its own directory, with its own
`Routes.ml` that starts at `/`:

- [Mini Linear](mini-linear/README.md): an issue tracker with streamed
  pages, islands, live updates and a shared store.
- `index`: the list of demos. It has no island and loads no JavaScript.
  The list is `demos` in `index/app/pages.mlx`.

One server runs both: `mini-linear/server/demo_server.exe --base
/mini-linear` serves Mini Linear with `Yuka.Server.config ~base` under
`/mini-linear`, and the index at every other path, so `/` is the list.
From the repository root:

    make demo-serve PORT=8080
