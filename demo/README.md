# Mini Linear demo

An issue tracker built with Yuka: a Dream server renders and streams the
pages, and islands hydrate in the browser.

## Run

From the repository root:

    opam exec --switch=/home/me/workplace/davesnx/utopia -- dune build --build-dir _build_demo @demo/all
    _build_demo/default/demo/server/demo_server.exe --port 8080

Flags: `--port`, `--js-dir` (Melange output), `--static-dir` (`style.css`),
`--manifest`, `--metafile`, `--bundle`, `--prerender DIR` (write the
prerendered pages to `DIR` and exit), `--prerendered DIR` (serve them).
Defaults are relative to the executable, so any build directory works.

## URLs

- `http://localhost:8080/`: all issues, grouped by status.
- `http://localhost:8080/my`: issues assigned to the current user.
- `http://localhost:8080/issue/YUK-1`: an issue; comments and related
  issues stream in after a delay.
- `http://localhost:8080/about`: a page with no island, outside the shell
  layout, for the 0 bytes of JavaScript check of `make measure-pages`. It
  is the one `~prerender:true` page.
- `http://localhost:8080/issues.json`: the issues as JSON (an endpoint).
- `http://localhost:8080/issues`: a permanent redirect to `/`.

Keys: `j` and `k` move, Enter opens, `c` opens the new issue dialog,
Escape closes menus and the dialog.

The data is in memory. Restart the server to reset it.

## Tests

    opam exec --switch=/home/me/workplace/davesnx/utopia -- dune test --build-dir _build_demo demo --force

## Browser check

It needs playwright-core (see `e2e/README.md`). It builds the demo, starts a
server on port 8123, runs the check and stops the server:

    BUILD_DIR=_build_demo e2e/run.sh

Use a fresh server for each run: the check creates an issue and a comment.

## Production bundle

    BUILD_DIR=_build_demo demo/bundle.sh
    _build_demo/default/demo/server/demo_server.exe --bundle

`bundle.sh` runs `scripts/bundle.ts` (esbuild with `--splitting` and
`--metafile`, then swc on each file): `main.js`, shared chunks, and one chunk
per island. The server serves them from `/_yuka/bundle/`
and writes no import map. At start it reads `yuka_islands.json` (and
`meta.json` with `--bundle`) and prints `<link rel="modulepreload">` for each
island on the page, except those used with `` `Lazy _ ``. Comments, Issue props
and Related are used with `` `Lazy `Idle ``, `` `Lazy `Interaction `` and
`` `Lazy `Visible ``.

Routes are defined once in `Routes.ml`. `yuka routes` writes the shared
`Routes` module (in `shared/`, for `Routes.href` in islands) and
`Routes_server` (in `server/`); `server/demo_server.ml` gives
`Routes_server.app` to `Yuka_dream.handler`. `client/main.ml` is
`let () = Yuka.render ~islands ~transitions:true ()`, so links navigate
without a full page load. The rules
in `client/dune` generate `yuka_islands.ml` (the list of islands) and
`yuka_islands.json` (the manifest for preload).
