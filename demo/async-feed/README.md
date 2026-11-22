# Async demo

A feed of notifications from New Relic, Vercel, Figma, Reddit and GitHub,
built with Yuka: the server renders the feed, and islands run the
filters, the settings, the theme toggle and the live events.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/`, Mini Linear at `/mini-linear` and this
demo at `/async-feed`, in one process. To run this demo alone, at the root:

    make async-feed-serve PORT=8080

`server/async_server.exe` takes `--port`, `--interface`, `--base PREFIX`,
`--bundle` (serve `bundle.sh` output) and `--dir` (the directory with
`client/` and `static/`, by default the build directory of the demo).

## URLs

Under `/async-feed` with `make demo-serve`, at `/` alone:

- `/async-feed`: the 50 newest of 5000 events, newest first. The data is
  made from the event number in `server/data.ml`, with no randomness, so
  each start has the same data. The page shows 50 events and links to
  the next 50 ("Older events"); there is no virtual list.
- `/async-feed?project=Billing&team=Growth&assignee=Ana%20Ruiz`: the
  filters. Each one can repeat, and an event must match one value of each
  filter. The dropdowns in the header write them to the URL, and the
  server renders the filtered feed.
- `/async-feed?before=1793552460`: the events before this time (Unix
  seconds). "Older events" and the date picker in the settings use it.

## Header

- The filters: Project, Team and Assignee. Each dropdown opens a list with a
  search field. Keys: ArrowDown or ArrowUp on the button opens it; in the
  list, arrows, Home and End move, Enter picks or drops a value, Escape
  closes. "Clear selection" drops the values of that filter.
- Settings: the time zone, and a date and time to jump to (read in that
  zone). Each date of the feed shows in the zone, with the full time in the
  `title` and the instant in `datetime`.
- The theme toggle: light or dark.

The zone and the theme are kept in `localStorage` (`async-feed-zone`,
`async-feed-theme`). A script in the head applies them before the first
paint: it sets `data-theme` and writes each `<time data-ts>` in the zone
as the parser adds it. Without a stored zone it uses the zone of the
browser; the server writes the dates in UTC.

## Simulate events

The button at the bottom calls the `async_feed_simulate` action. The
server then adds 4 events, one every 0.7 s, and publishes the 30 newest
added events on the `async_feed_recent` topic of `Yuka.Live` after each
one. Every open page of the feed gets them over its live socket and shows
the ones that match its filters at the top, with a short animation (none
with `prefers-reduced-motion`). The events stay in memory until the
server stops.

## Tests

    make demo-test

`test/run.ml` renders the pages and checks the cards, the filters and the
dates in UTC. `e2e/async-feed.ts` (run by `make e2e`) checks the events
that arrive one by one, the keyboard of a filter, the time zone and the
theme in a browser.
