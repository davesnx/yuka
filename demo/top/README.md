# top demo

A fake `top` in the layout of [btop](https://github.com/aristocratos/btop),
in a Zed window that fills the browser. Each host of the panel is a machine
made up in OCaml: a laptop that runs Zed and `dune build -w`, a build
machine full of `ocamlopt.opt`, and a Postgres server. Nothing reads
`/proc`: the numbers come from `Machine.step`.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/` and this demo at `/top`, with the other
demos, in one process. To run this demo alone, at the root:

    make top-serve PORT=8080

`server/top_demo_server.exe` takes `--port`, `--interface`, `--base
PREFIX`, `--bundle` and `--dir`.

## How it works

- `Routes.ml` has one route, `/?host=NAME`. The page is the Zed window,
  in full screen: the title bar, the panel with a link for each host, the
  tabs and the status bar are server HTML.
- `shared/machine.ml` holds the hosts and the simulation. `Machine.step`
  makes the screen one second later: the %CPU of each process moves
  around its usual value with a burst now and then, short-lived programs
  (compilers, `git status`, autovacuum) start and end as children of
  `dune`, `zed` or `postgres`, and the CPU split, the memory, the network and the
  load averages follow. Each screen keeps the CPU use and the network of
  the last `Machine.samples` screens, and each process its %CPU of the
  last minute. `Machine.start` runs `samples` screens from the first one,
  so the graphs of the page are full, and ends at the clock of the host.
  The numbers are integers (tenths of a percent, KiB, hundredths of a
  second) and the random numbers come from a 31-bit generator, so the
  server and the browser compute the same screens. Each random draw has
  its own `let`: native OCaml evaluates the parts of a tuple or a record
  right to left, Melange left to right.
- `shared/graph.ml` draws the graphs in braille, as btop does: a
  character holds two values of four dots each. The upload graph hangs
  from the top.
- `shared/monitor.mlx` is the one island: four boxes, as btop has. `cpu`
  is the graph of the CPU use and a meter per core; `mem` the used,
  available, cached and free memory and the swap; `net` the download and
  upload graphs; `proc` the processes, a `Yuka.each` keyed by PID, with a
  filter on the border. A bar of keys runs under the boxes. A click on a
  process, or Enter on the selected one, opens its detail over the boxes:
  the command, a graph of its %CPU, the memory, the parent, the threads,
  and buttons to terminate or kill it. The numbers of the detail change
  each second and its frame stays, so the focus stays on its buttons.
- In the browser, a `Yuka.Browser.on_frame` handler calls `Machine.step`
  once a second, and a `keydown` listener on the window takes the keys:
  `P`, `M`, `T`, `N` and `C` sort by %CPU, memory, CPU time, PID and
  program, `R` reverses the order, `f` or `/` goes to the filter, the
  arrows select a process, Enter opens its detail and Escape closes it,
  `k` kills the selected process (`t` terminates it from the detail),
  `Space` pauses and `q` quits. A click on a column title sorts by it, and
  each key of the bar is a button. Killing works only for the processes of
  the user that runs top; for the others the answer is `Operation not
  permitted`. Killing `top` itself quits.

## Design

The page and the window come from [`../zed`](../zed/README.md), the design
system of the utop and top demos: the fonts, the colours and the icons of
Zed. `static/style.css` makes the window fill the browser and styles its
content: the boxes take a colour of the One theme each, the meters and the
CPU graph go from green to red as btop's do, and the detail of a process is
a modal of Zed. Lilex has no braille, so the font after it in `--mono`
draws the graphs.

## Tests

    make demo-test

`test/run.ml` renders two hosts and checks the boxes, the processes, the
island and the selected host; runs each host for a minute and for an hour
and checks the CPU split, the memory, the PIDs, the graphs, the history of
each process and the parent of the compilers; checks the braille of
`Graph.lines`; and checks the text of the clock, the uptime, TIME+, the
sizes, the rates, the program names and the filter. `e2e/top.ts` drives
the page in the browser; see `e2e/README.md`.
