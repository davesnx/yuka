# Browser check of the demo

Needs the playwright-core library (path in `demo.ts`, override with
`PLAYWRIGHT_CORE`).

Run (builds the demo, starts the server on port 8123, runs the check, stops
the server):

    e2e/run.sh

`BUILD_DIR` sets the dune build directory (default `_build`). `PORT` sets the
port. The script exits 2 when the build fails.

Run against a server that is already running:

    node e2e/demo.ts http://127.0.0.1:8123

The server keeps data in memory. Use a fresh server for each run, because the
check creates an issue and a comment. Each step prints PASS or FAIL. The exit
code is 1 when any step fails. Screenshots go to `e2e/screenshots/`.

After `demo.ts`, `run.sh` starts a second server with `--base /demo/mini-linear`
on port `PORT + 2` and runs `base.ts`: a small proxy on `PORT + 3` forwards
the paths under the prefix to it unchanged and answers any other path itself.
It checks the page, a client navigation, an action and a live update across
two pages, all through the proxy:

    node e2e/base.ts http://127.0.0.1:8125 8126 /demo/mini-linear

`BUNDLE=1 e2e/run.sh` runs `demo/bundle.sh` and starts the server with
`--bundle`. The check then expects one script and no import map.

## sketch

`e2e/sketch.sh` (or `make sketch-e2e`) builds the sketch demo, starts it on
`PORT` (default 8130) under `/demo/sketch`, and runs `sketch.ts`: every
whiteboard feature, a phone with touch, and the dark theme. Screenshots go to
`SHOTS` (default `e2e/screenshots/sketch/`). Against a running server:

    node e2e/sketch.ts http://127.0.0.1:8130/demo/sketch DIR

`sketch_perf.ts` loads a board of 500 shapes and prints the frame times of a
pen stroke, a drag of 50 shapes and a pan. `CPU_THROTTLE=4` slows the CPU:

    node e2e/sketch_perf.ts http://127.0.0.1:8130/demo/sketch
