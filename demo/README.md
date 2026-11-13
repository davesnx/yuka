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

- `yuka` (shown as Home): 25 issues, `YUK-1` to `YUK-25`, at the root URLs below.
- `stress`: 200 issues, `STR-1` to `STR-200`, with 30 labels and 200
  comments on each issue, under `/w/stress`. `server/stress.ml` makes them
  from the issue number, with no randomness, so each start has the same
  data. The comments are made when a page asks for them; comments that a
  visitor adds are stored after them.

The header links to each workspace (the current one is marked), to the
repository on GitHub and to `@davesnx` on X.

## Themes and the progress bar

The Theme button in the header opens one menu with two groups. Theme picks
one of four themes: dark, light, gray and pale. Code picks the colours of
highlighted code: Auto, or one of six styles (Dark+, One Dark, Nord, Tokyo
Night, Gruvbox, Light+). Auto, the default, uses the style that goes with
the theme (dark: Dark+, light: Light+, gray: One Dark, pale: Light+) on the
background and text colour of the theme; a CSS rule for each theme does
this, with no script. Another style keeps its own background for every
theme until Auto is chosen again.

The choices are kept in `localStorage` (`yuka-demo-theme` and
`yuka-demo-code-theme`; Auto removes the second key). Without a choice, the
theme follows `prefers-color-scheme` (light or dark). A small script in the
head of each page, before the stylesheet, sets `data-theme` and
`data-code-theme` on `<html>`, so the first paint has the right colours,
also on the prerendered `/about`. A cookie read on the server cannot do this
for a prerendered page, and Yuka has no attribute for `<html>`. Each theme
is a set of CSS variables in `static/style.css`.

During a client navigation that takes more than 120 ms, a thin bar at the
top of the window grows; it fills and fades out when the new page is shown.
The `Nav_progress` island reads `Yuka.Browser.navigating`. It is used with
`` `Idle ``: it starts when the browser is idle after the page load, as no
bar is needed before the first navigation.

## Markdown

Issue descriptions and comments are markdown (CommonMark with tables, task
lists and strikethrough). The server renders them with `cmarkit` and
highlights fenced code with `ochre` (`server/markdown.ml`,
`server/code_style.ml`); no markdown code goes to the browser. Raw HTML is
shown as text, and a link keeps its URL only for `http`, `https`, `mailto`
and relative URLs. Code in OCaml, JavaScript, TypeScript, shell, JSON and
CSS is highlighted; another language is plain text. A new comment shows its
text at once and its rendered form when the server answers.

Each code token carries the colours of every code style, so a change of
theme or code style (in the Theme menu) needs no request. The demo needs
the opam packages `cmarkit`, `ochre` and `tm-grammars` (`make install`
installs them) and the oniguruma library (`conf-oniguruma`).

## URLs

- `http://localhost:8080/`: all issues of `yuka`, grouped by status.
- `http://localhost:8080/my`: issues of `yuka` assigned to the current user.
- `http://localhost:8080/?q=hydration&label=bug&label=client`: the list
  filtered by title and by labels (an issue must have each label). Each
  list page reads `q` and `label`, and the server renders the filtered
  list. Typing in the filter or a click on a label changes the URL with
  `Yuka.Browser.replace_url`, so a reload, back and a shared link keep it.
  The label row shows the labels that fit on one line, chosen labels
  first; the dots button opens a popover menu with all labels.
- `http://localhost:8080/new`: the new issue form of `yuka`.
- `http://localhost:8080/insights`: charts of the issues of `yuka`, drawn
  in SVG by one island (`shared/insights.mlx`). The server prints them, and
  the browser computes them again on each change of the measure, the
  filters, the date range or the live issues. The "Created" control in the
  filter row opens the From and To sliders of the date range, with a "Full
  range" reset. The stress control (1x, 10x, 100x) makes copies of the
  issues in the browser, up to 20 000 points on `stress`; Animate, at the
  right of the page header, moves the date range on each frame. A panel at
  the bottom right shows what the browser measures: frames per second, the
  time of the last update (from the change to the updated DOM), updates per
  second, the longest frame of the last second, the frames over 50 ms in
  the last 10 seconds, the SVG and DOM nodes, the points and a line of the
  last 60 frame times. It refreshes once per second, and after each change.
  Its button collapses it to the frames per second.
- `http://localhost:8080/report`: the same seven charts at 1x, drawn in SVG
  by the server only (`server/report.mlx`, with the geometry of
  `shared/insights.mlx`). The page has no island of its own and sends no
  data for the charts, so you can compare its HTML with `/insights`.
- `http://localhost:8080/canvas`: a whiteboard with a card for each issue
  and notes (`shared/canvas.mlx`). The board is in the server store, one
  per workspace, and each open page gets its changes over `Yuka.Live`. Drag
  a card to move it: the move is sent on release, and a move from another
  page glides into place. Drag the background to pan; the buttons zoom,
  shuffle the board and add a note (at most 140 characters, 100 notes per
  board). The first positions come from the issue numbers; Shuffle and
  new notes use random positions.
- `http://localhost:8080/issue/YUK-1`: an issue; comments and related
  issues stream in after a delay. An issue with more than 12 comments
  shows the first 3 and the last 5; a band between them gives the number
  of hidden comments, "Load 50 more" (the next ones after the first group)
  and "Load all". The page does not send the hidden comments: the island
  gets them with the `comment_range` query (`shared/comment.ml`).
  "Load all" is a link to `?comments=all`, which the server renders with
  the whole thread, so the link also works before the island starts, and
  can be shared.
- `http://localhost:8080/w/stress`, `/w/stress/my`, `/w/stress/insights`,
  `/w/stress/report`, `/w/stress/canvas`, `/w/stress/new` and
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

A click anywhere on a row opens the issue: the title link covers the row,
and the buttons of the row are above it. The avatar of a row opens a card
with the user and the number of their open, in-progress and done issues
(`User_popup`; the numbers come from the `user_stats` query when the card
first opens).

Keys: `j` and `k` move, Enter opens, `c` opens the new issue dialog,
Escape closes menus and the dialog. A created issue opens on its page, as
after the form at `/new`.

With no database, the data is in memory. Restart the server to reset it.

## Shared data

With a Postgres database, every server process reads and writes the same
data:

    _build/default/demo/server/demo_server.exe --database postgresql://user:password@host/db

- `--database CONNINFO`, default `$YUKA_DEMO_DATABASE`: the connection
  string (libpq syntax or a URL). Empty means memory. Use a direct
  connection, not a pooled one: Live updates between processes use
  `LISTEN`.
- `--reset-days N`, default `$YUKA_DEMO_RESET_DAYS`, or 7: the data starts
  again from the seed when it is older than N days, by the clock of the
  database. N is at least 1. A page that is open at that time shows the old
  data until the next change. To reset by hand, set `started` of the rows
  to an old date; do not delete the rows.

At start the server makes the table `yuka_demo_state` if it is not there.
The table has one row for each workspace, with all of its data as JSON and
a version. Each process keeps a copy in memory. Before each request, and
before each Live load, it reads the versions and loads the rows that
changed. An action locks the row, runs its check and its change, and writes
the row with the next version. A refused action writes nothing. The
processes tell each other about changes over `LISTEN`/`NOTIFY`
(`yuka-live-pg`, channel `yuka_demo`), so a page on one process gets the
changes made on another.

The queries block the server for the time of a round trip to the database.
This is fine for a demo, not for a busy site. So that a slow database does
not stop a process for long, the server sets `PGCONNECT_TIMEOUT=5` and
`PGOPTIONS` (a lock wait of 5 s, a statement of 10 s, an idle transaction
of 15 s) when they are not set.

The server does not start when the database does not answer. When a read
fails later, the server logs the error and shows the data it has. When a
write fails, the action is refused with a message.

## Tests

    make demo-test

With `YUKA_DEMO_DATABASE` set, the tests also check the shared data in a new
schema of that database, and remove the schema after.

## Browser check

It needs playwright-core (see `e2e/README.md`). It builds the demo, starts a
server on `PORT` (default 8123), runs the check and stops the server:

    make e2e

Use a fresh server for each run: the check creates an issue and a comment.

    YUKA_DEMO_DATABASE=<conninfo> make e2e-shared

starts two server processes on one database, on `PORT` and the next port. A
note made through the first is moved through the second, and the pages on
both get the changes. It adds one note and removes it. With no database,
each process has its own data and the check fails.

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
Set these environment variables in the project: `PORT=8080` (Vercel sends
traffic to port 80 without it) and `YUKA_DEMO_SECRET`. For the shared data,
connect a Neon database to the project: in production (`VERCEL_ENV` is
`production`) the server uses the direct URL that the integration adds,
`DATABASE_URL_UNPOOLED` or `POSTGRES_URL_NON_POOLING`. A preview deployment
keeps its data in memory. `YUKA_DEMO_DATABASE`, when set, is used in every
environment; give it a direct URL (with Neon, no `-pooler` in the host
name). `YUKA_DEMO_RESET_DAYS` is optional.

The project `yuka-demo` is connected to this repository: a push to `main`
deploys to https://yuka-demo.vercel.app.

Vercel can run more than one instance. With `YUKA_DEMO_DATABASE`, they all
share the data in the database (see [Shared data](#shared-data)). Without
it, each instance has its own data, and the data goes when the instance
stops.

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
statically. Nav_progress is used with `` `Idle ``; Comments, Issue props and
Related are used with `` `Lazy `Idle ``, `` `Lazy `Interaction `` and
`` `Lazy `Visible ``.

Routes are defined once in `Routes.ml`. `yuka routes` writes the shared
`Routes` module (in `shared/`, for links such as `Routes.issue ~id ()` in islands) and
`Yuka_routes` (in `server/`); `server/demo_server.ml` gives
`Yuka_routes.app` to `Yuka_dream.handler`. `client/main.ml` is
`let () = Yuka.render ~islands ~transitions:true ()`, so links navigate
without a full page load. The rules
in `client/dune` generate `yuka_islands.ml` (the list of islands) and
`yuka_islands.json` (the manifest for preload).
