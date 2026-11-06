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

`BUNDLE=1 e2e/run.sh` runs `demo/bundle.sh` and starts the server with
`--bundle`. The check then expects one script and no import map.
