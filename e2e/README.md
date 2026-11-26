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
also on a second page), a filter used with the keyboard, the time zone,
the theme, and the comments panel (open from a card, its URL, Back, Escape,
a direct load, a new comment and the card count).
`ASYNC_FEED_SCREENSHOTS=DIR` saves light and dark screenshots of the feed
and of the panel to `DIR`:

    node e2e/async-feed.ts http://127.0.0.1:8125/async-feed

Last, `posters.ts` runs under `/posters`: each of the four kinds, Shuffle,
the sliders of a kind, the padding, the light preset and the title change
the preview and the URL, and the browser draws the same shapes as the
server. A colour or text change keeps every shape node, the text column is
left of the poster and goes under it on a narrow screen, a reload keeps the
poster, the Download SVG link points to `/poster.svg` with the same query,
Download PNG gives a PNG, the gallery opens a preset in the playground, and
it prints the time of a slider change with 60 lines of 10 waves. `POSTERS_SCREENSHOTS=DIR` saves the playground (dark and light) and
the gallery to `DIR`:

    node e2e/posters.ts http://127.0.0.1:8125/posters

Then `utop.ts` runs under `/utop`: the first session, `let` and integer
arithmetic at the prompt, an unbound name, a phrase on two lines, the
history with the arrow keys, completion with Tab, Ctrl+L, a click on
another file of the project panel, `#quit;;` and "Start again", and the
One Light colours with a light colour scheme. `UTOP_SCREENSHOTS=DIR` saves
a dark and a light screenshot to `DIR`:

    node e2e/utop.ts http://127.0.0.1:8125/utop

Then `top.ts` runs under `/top`: the first screen of the laptop and the
same screen after the island starts, a new screen a second later, sorting
by key and by a click on a column, graphs and one line per core, Space to
pause, selecting and killing a process (and the refusal for a process of
root), another host from the panel, `q` and "Start again", and the One
Light colours with a light colour scheme. `TOP_SCREENSHOTS=DIR` saves a
dark and a light screenshot to `DIR`:

    node e2e/top.ts http://127.0.0.1:8125/top

`BUNDLE=1 e2e/run.sh` runs `demo/mini-linear/bundle.sh`,
`demo/async-feed/bundle.sh`, `demo/posters/bundle.sh`,
`demo/infinite-scroll/bundle.sh`, `demo/utop/bundle.sh` and
`demo/top/bundle.sh` and starts the
server with `--bundle`. The check then expects one script and no import map.
