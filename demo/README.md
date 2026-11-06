# Mini Linear demo

An issue tracker built with Yuka: a Dream server renders and streams the
pages, and islands hydrate in the browser.

## Run

From the repository root:

    opam exec --switch=/home/me/workplace/davesnx/utopia -- dune build --build-dir _build_demo @demo/all
    _build_demo/default/demo/server/demo_server.exe --port 8080

Flags: `--port`, `--js-dir` (Melange output), `--static-dir` (`style.css`).
Defaults are relative to the executable, so any build directory works.

## URLs

- `http://localhost:8080/`: all issues, grouped by status.
- `http://localhost:8080/my`: issues assigned to the current user.
- `http://localhost:8080/issue/YUK-1`: an issue; comments and related
  issues stream in after a delay.

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

`bundle.sh` runs esbuild with `--splitting`: `main.js`, a shared chunk, and
one chunk per lazy island (`Issue_props`, `Related`, `Comments`). The server
serves them from `/static/bundle/` and writes no import map.

Routes are defined once in `shared/routes.ml` with `Yuka.Router`. The server
maps `Yuka.Router.dispatch` onto Dream, and `client/main.ml` calls
`Yuka.Router.start`, so links navigate without a full page load.
