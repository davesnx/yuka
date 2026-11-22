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

After `demo.ts`, `run.sh` starts a second server with `--base /mini-linear`
on port `PORT + 2` and runs `base.ts`: a small proxy on `PORT + 3` forwards
the paths under the prefix to it unchanged and answers any other path itself.
It checks the page, a client navigation, an action and a live update across
two pages, all through the proxy:

    node e2e/base.ts http://127.0.0.1:8125 8126 /mini-linear

Then it runs `async-feed.ts` against the same server, under
`/async-feed`: the feed, "Simulate events" (the cards arrive one by one,
also on a second page), a filter used with the keyboard, the time zone and
the theme. `ASYNC_FEED_SCREENSHOTS=DIR` saves a light and a dark
screenshot to `DIR`:

    node e2e/async-feed.ts http://127.0.0.1:8125/async-feed

Last, `posters.ts` runs under `/posters`: a new seed, Shuffle, the columns
slider, the light preset and the title change the preview and the URL, the
browser draws the same grid as the server, a reload keeps the poster, and
Download SVG and Download PNG give the files. `POSTERS_SCREENSHOTS=DIR`
saves a dark and a light screenshot to `DIR`:

    node e2e/posters.ts http://127.0.0.1:8125/posters

`BUNDLE=1 e2e/run.sh` runs `demo/mini-linear/bundle.sh`,
`demo/async-feed/bundle.sh` and `demo/posters/bundle.sh` and starts the
server with `--bundle`. The check then expects one script and no import map.
