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

## Workspaces

The demo has two workspaces, each with its own issues, labels, new issue
form and live updates:

- `yuka`: 25 issues, `YUK-1` to `YUK-25`, at the root URLs below.
- `stress`: 200 issues, `STR-1` to `STR-200`, with 30 labels and 200
  comments on each issue, under `/w/stress`. `server/stress.ml` makes them
  from the issue number, with no randomness, so each start has the same
  data. The comments are made when a page asks for them; comments that a
  visitor adds are stored after them.

The header links to each workspace (the current one is marked), to the
repository on GitHub and to `@davesnx` on X.

## Themes and the progress bar

The Theme button in the header picks one of four themes: dark, light,
gray and pale. The choice is kept in `localStorage` (`yuka-demo-theme`).
Without a choice, the theme follows `prefers-color-scheme` (light or
dark). A small script in the head of each page, before the stylesheet,
sets `data-theme` on `<html>`, so the first paint has the right theme, also
on the prerendered `/about`. A cookie read on the server cannot do this for
a prerendered page, and Yuka has no attribute for `<html>`. Each theme is a
set of CSS variables in `static/style.css`.

During a client navigation that takes more than 120 ms, a thin bar at the
top of the window grows; it fills and fades out when the new page is shown.
The `Nav_progress` island reads `Yuka.Browser.navigating`.

## URLs

- `http://localhost:8080/`: all issues of `yuka`, grouped by status.
- `http://localhost:8080/my`: issues of `yuka` assigned to the current user.
- `http://localhost:8080/new`: the new issue form of `yuka`.
- `http://localhost:8080/issue/YUK-1`: an issue; comments and related
  issues stream in after a delay.
- `http://localhost:8080/w/stress`, `/w/stress/my`, `/w/stress/new` and
  `/w/stress/issue/STR-1`: the same pages for `stress`. An unknown
  workspace, or an issue of another workspace, is a not-found page.
- `http://localhost:8080/about`: a page with no island, outside the shell
  layout, for the JavaScript check of `make measure-pages`: it loads no
  script file, and only the inline theme script runs. It is the one
  `~prerender:true` page.
- `http://localhost:8080/before-hydration`: a text input, a checkbox, a
  select and a textarea in an island, each with the value of its State. The
  server sends the script of this page 3 s late (to this page only), so you
  can change the fields before the island starts. Open the URL directly or
  reload: a client navigation has the script already.
- `http://localhost:8080/issues.json`: the issues of `yuka` as JSON (an
  endpoint).
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

The image has the server, the production bundle, `style.css` and the
prerendered pages. The server listens on `0.0.0.0`, on `$PORT` or 8080.
`YUKA_DEMO_SECRET` signs the session cookies: without it the server uses
the development secret.

## Vercel

Vercel builds `Dockerfile.vercel` at the repository root and runs the image
as a Function ([Container Runtime](https://vercel.com/docs/functions/runtimes/container)).
Set two environment variables in the project: `PORT=8080` (Vercel sends
traffic to port 80 without it) and `YUKA_DEMO_SECRET`.

The project `yuka-demo` is connected to this repository: a push to `main`
deploys to https://yuka-demo.vercel.app.

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
island on the page, except those used with `` `Lazy _ ``. With `--bundle` it
also prints one for each chunk that those islands and `main.js` import
statically. Comments, Issue props and Related are used with `` `Lazy `Idle ``,
`` `Lazy `Interaction `` and `` `Lazy `Visible ``.

Routes are defined once in `Routes.ml`. `yuka routes` writes the shared
`Routes` module (in `shared/`, for links such as `Routes.issue ~id ()` in islands) and
`Routes_server` (in `server/`); `server/demo_server.ml` gives
`Routes_server.app` to `Yuka_dream.handler`. `client/main.ml` is
`let () = Yuka.render ~islands ~transitions:true ()`, so links navigate
without a full page load. The rules
in `client/dune` generate `yuka_islands.ml` (the list of islands) and
`yuka_islands.json` (the manifest for preload).
