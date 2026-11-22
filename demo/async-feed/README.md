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
- `/async-feed/item/4999`: the panel of one notification, with a link to
  its source, the fields of its source and its comments. It is an overlay
  route: the comment icon of a card opens it over the feed with a client
  navigation, and Back, Escape, a click beside it or Close remove it. A
  direct load or a reload shows it over the newest events; Close then goes
  to the feed.

## Header

- The filters: Project, Team and Assignee. Each dropdown opens a list with a
  search field. Keys: ArrowDown or ArrowUp on the button opens it; in the
  list, arrows, Home and End move, Enter picks or drops a value, Escape
  closes. "Clear selection" drops the values of that filter.
- Settings: the time zone, and a date and time to jump to (read in that
  zone). Each date of the feed shows in the zone, with the full time in the
  `title` and the instant in `datetime`.
- The theme toggle: light or dark. Without a choice the page follows the
  color scheme of the system.

The zone and the theme are kept in cookies (`async-feed-zone`,
`async-feed-theme`), which `Loaders.settings`, the loader of the layout,
reads. The layout prints the theme on the toggle button (`data-theme`,
`aria-pressed`), and the CSS picks the colors from it with
`:root:has(#theme[data-theme=...])`, so the first paint is right with no
script. The layout gives the zone to the islands with a `Yuka.Context` that
has a codec. Each time is a `Local_time` island: the server prints the
UTC time, and the browser writes it in the zone with `Intl.DateTimeFormat`
(`shared/env.melange.ml`). Without a saved zone it uses the zone of the
browser. A zone chosen in Settings is a module-level State that only the
browser writes, so every time island shows it at once.

## Simulate events

The button at the bottom calls the `async_feed_simulate` action. The
server then adds 4 events, one every 0.7 s, and publishes the 500 newest
added events on the `async_feed_recent` topic of `Yuka.Live` after each
one. Every open page of the feed gets them over its live socket and shows
the ones that match its filters at the top (a page of older events has no
live part and opens no socket), with a short animation (none
with `prefers-reduced-motion`). The events stay in memory until the
server stops.

## Comments

The comments are in memory: generated ones for most of the 5000 events,
and the ones that the form adds with the `async_feed_comment` action. The
server refuses an empty comment and one longer than 1000 characters. After
a comment is added, the count on the card of that event changes with no
request. The panel slides in from the right (0.5 s,
`cubic-bezier(0.32, 0.72, 0, 1)`, the curve of the Vaul drawer); with
`prefers-reduced-motion` it fades in.

## Tests

    make demo-test

`test/run.ml` renders the pages and checks the cards, the filters, the
dates in UTC, the panel of an item and the comment action.
`e2e/async-feed.ts` (run by `make e2e`) checks the events that arrive one
by one, the keyboard of a filter, the time zone, the theme and the
comments panel in a browser.
