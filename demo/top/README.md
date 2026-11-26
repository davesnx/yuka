# top demo

A fake `top` in a Zed window. Each host of the panel is a machine made up
in OCaml: a laptop that runs Zed and `dune build -w`, a build machine full
of `ocamlopt.opt`, and a Postgres server. Nothing reads `/proc`: the
numbers come from `Machine.step`.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/` and this demo at `/top`, with the other
demos, in one process. To run this demo alone, at the root:

    make top-serve PORT=8080

`server/top_demo_server.exe` takes `--port`, `--interface`, `--base
PREFIX`, `--bundle` and `--dir`.

## How it works

- `Routes.ml` has one route, `/?host=NAME`. The page is the Zed window:
  the title bar, the panel with a link for each host, the tabs and the
  status bar are server HTML.
- `shared/machine.ml` holds the hosts and the simulation. `Machine.start`
  makes the first screen of a host and `Machine.step` the screen one
  second later: the %CPU of each process moves around its usual value
  with a burst now and then, short-lived programs (compilers, `git
  status`, autovacuum) start and end, and the CPU split, the memory and
  the load averages follow. The numbers are integers (tenths of a
  percent, KiB, hundredths of a second) and the random numbers come from
  a 31-bit generator, so the server and the browser compute the same
  first screen. Each random draw has its own `let`: native OCaml
  evaluates the parts of a tuple or a record right to left, Melange left
  to right.
- `shared/monitor.mlx` is the one island: the summary lines, the message
  line and the processes, a `Yuka.each` keyed by PID. The server renders
  the first screen; in the browser, a `Yuka.Browser.on_frame` handler
  calls `Machine.step` once a second, and a `keydown` listener on the
  window takes the keys of top: `P`, `M`, `T`, `N` sort by %CPU, %MEM,
  TIME+ and PID, `R` reverses the order, `t` switches between graphs and
  text, `1` shows a line per core, the arrows select a process and `k`
  kills it, `Space` pauses, `Enter` makes a new screen at once and `q`
  quits. A click on a column title sorts by it, and the bar under the
  screen has a button for each key. `k` kills only the processes of the
  user that runs top; for the others it answers as top does, `Operation
  not permitted`. Killing `top` itself quits.

## Design

The page and the window come from [`../zed`](../zed/README.md), the design
system of the utop and top demos: the fonts, the colours and the icons of
Zed. `static/style.css` styles only the content of the window.

## Tests

    make demo-test

`test/run.ml` renders two hosts and checks the processes, the island and
the selected host, runs each host for a minute and checks the CPU split,
the memory and the PIDs, and checks the text of the clock, the uptime,
TIME+ and the memory sizes. `e2e/top.ts` drives the page in the browser;
see `e2e/README.md`.
