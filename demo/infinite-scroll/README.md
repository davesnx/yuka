# Infinite scroll demo

An endless gallery of colour palettes: the server renders the first page,
and the next one loads when the first skeleton card after the list comes
into view.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/` and this demo at `/infinite-scroll`, with
the other demos, in one process. To run this demo alone, at the root:

    make infinite-scroll-serve PORT=8080

`server/infinite_scroll_server.exe` takes the flags of the Async server:
`--port`, `--interface`, `--base PREFIX`, `--bundle` and `--dir`.

## How it works

- `Routes.ml` has one route, `/?pages=N`. The page shows the first
  `N × 24` palettes, so a reload or Back shows every page that was loaded.
  The server makes the palettes from their number, and waits 1 s before it
  answers a later page, as a slow database would.
- While there is a next page, the grid ends with skeleton cards.
  `shared/load_more.mlx` watches the first one with
  `Yuka.Browser.on_visible` and then calls
  `Yuka.Browser.navigate ~replace:true ~keep_scroll:true` with the URL of
  the next page. The navigation replaces the history entry, and the page
  stays where the user scrolled while it loaded.
- The island also shows a status while `Yuka.Browser.navigating` is
  `true`, and a line at the end of the gallery.

## Tests

    make demo-test

`test/run.ml` renders the first, a later and the last page and checks the
cards, the skeleton cards and the URL of the next page.
