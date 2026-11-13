# Mini Linear demo

An issue tracker built with Yuka: a Dream server renders and streams the
pages, and islands hydrate in the browser.

## Run

From the repository root (`SWITCH=` names the opam switch, `BUILD_DIR=`
the build directory):

    make demo-serve PORT=8080

`make demo-dev` runs it under `yuka dev`: it rebuilds, restarts the server
and reloads the browser on change.

Flags: `--port` (default `$PORT`, or 8080), `--interface` (default
`localhost`), `--js-dir` (Melange output), `--static-dir` (`style.css`),
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
- `http://localhost:8080/before-hydration`: a text input, a checkbox, a
  select and a textarea in an island, each with the value of its State. The
  server sends the script of this page 3 s late (to this page only), so you
  can change the fields before the island starts. Open the URL directly or
  reload: a client navigation has the script already.
- `http://localhost:8080/issues.json`: the issues as JSON (an endpoint).
- `http://localhost:8080/issues`: a permanent redirect to `/`.

Keys: `j` and `k` move, Enter opens, `c` opens the new issue dialog,
Escape closes menus and the dialog.

The data is in memory. Restart the server to reset it.

## Tests

    make demo-test

## Browser check

It needs playwright-core (see `e2e/README.md`). It builds the demo, starts a
server on `PORT` (default 8123), runs the check and stops the server:

    make e2e

Use a fresh server for each run: the check creates an issue and a comment.

## Docker

From the repository root:

    docker build -f Dockerfile.vercel -t yuka-demo .
    docker run --rm -p 8080:8080 -e YUKA_DEMO_SECRET=<secret> yuka-demo

The image has the server, the production bundle and `style.css`. The server
listens on `0.0.0.0`, on `$PORT` or 8080. `YUKA_DEMO_SECRET` signs the
session cookies: without it the server uses the development secret.

## Vercel

Vercel builds `Dockerfile.vercel` at the repository root and runs the image
as a Function ([Container Runtime](https://vercel.com/docs/functions/runtimes/container)).
Set two environment variables in the project: `PORT=8080` (Vercel sends
traffic to port 80 without it) and `YUKA_DEMO_SECRET`.

An instance stops after 5 minutes with no traffic, and its data goes with
it. Vercel can run more than one instance, each with its own data.

## Production bundle

    make demo-bundle
    _build/default/demo/server/demo_server.exe --bundle

`bundle.sh` runs `scripts/bundle.ts` (esbuild with `--splitting` and
`--metafile`, then swc on each file): `main.js`, shared chunks, and one chunk
per island. The server serves them from `/_yuka/app/bundle/`
and writes no import map. At start it reads `yuka_islands.json` (and
`meta.json` with `--bundle`) and prints `<link rel="modulepreload">` for each
island on the page, except those used with `` `Lazy _ ``. Comments, Issue props
and Related are used with `` `Lazy `Idle ``, `` `Lazy `Interaction `` and
`` `Lazy `Visible ``.

Routes are defined once in `Routes.ml`. `yuka routes` writes the shared
`Routes` module (in `shared/`, for links such as `Routes.issue ~id ()` in islands) and
`Routes_server` (in `server/`); `server/demo_server.ml` gives
`Routes_server.app` to `Yuka_dream.handler`. `client/main.ml` is
`let () = Yuka.render ~islands ~transitions:true ()`, so links navigate
without a full page load. The rules
in `client/dune` generate `yuka_islands.ml` (the list of islands) and
`yuka_islands.json` (the manifest for preload).
