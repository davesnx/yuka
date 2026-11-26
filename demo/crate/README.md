# Crate demo

A crate of records that shows view transitions: open a record and its
cover grows into the album page, with the vinyl sliding out of the
sleeve; Back puts the cover in its slot on the shelf.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/` and this demo at `/crate`, with the
other demos, in one process. To run this demo alone, at the root:

    make crate-serve PORT=8080

`server/crate_server.exe` takes the flags of the Posters server:
`--port`, `--interface`, `--base PREFIX`, `--bundle` and `--dir`.

## How it works

- `client/main.ml` turns on view transitions with `Yuka.render
  ~transitions:true`, so each client navigation runs in one where the
  browser has `document.startViewTransition`.
- Each cover has `view-transition-name:cover-N` (`server/pages.mlx`), on
  the shelf, as the large cover of its album page, and as the small cover
  of the previous or next record. The browser moves it from its place on
  the old page to its place on the new one: from the grid to the album
  page, from Next to the large cover, and to its new place when a genre
  tab filters the shelf.
- `static/style.css` slides the rest of the page with the direction:
  Yuka sets `data-yuka-nav` on `<html>` to `push`, `back` or `forward`
  while a view transition runs. The disc has its own name, so it slides
  out of the sleeve when an album page opens.
- Picking the first track runs a view transition: the cover, the disc and
  the tonearm have names, so the cover tips over into the corner, the
  record comes out and spins, and the arm swings onto it. Stop puts them
  back. Once a track plays, a click on another one has
  `data-yuka-transition="off"` (with `data-yuka-replace` and
  `data-yuka-keep-scroll`): it changes one row, and a cross-fade of the
  whole page would only flash it.
- `shared/keys.mlx` goes to the previous and next record with the arrow
  keys through `Yuka.Browser.navigate ~replace:true`, which runs in a view
  transition too. Previous and Next replace the history entry as well, so
  the entry before an album page is the shelf it was opened from:
  `shared/back.mlx`, the "All records" link, then does
  `Yuka.Browser.back ()`, which shows the shelf with its genre and scroll.
  After a direct load of an album page it is a link to the shelf.
- The root has no view transition name and `::view-transition` has
  `pointer-events: none`, so the header, the intro, the genre tabs and the
  footer, which have no name, keep working while a view transition runs. `shared/progress.mlx` shows a bar while a page loads; it is also
  the island of the shelf, as a page with no island loads no JavaScript
  and its links would load full pages.

## Tests

    make demo-test

`test/run.ml` checks the shelf and its genre filter, that no page has a
cover name twice (the browser would skip the view transition), the
tracks with no view transition, and the 404 of a record that is not in
the crate.
