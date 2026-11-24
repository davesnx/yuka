# Infinite scroll

An endless gallery of colour palettes: the server renders the first page,
and the next one loads when the first skeleton card after the list comes
into view.

    make infinite-scroll-serve PORT=8080

- `Routes.ml` has one route, `/?pages=N`. The page shows the first
  `N × 24` palettes, so a reload or Back shows every page that was loaded.
  The server makes the palettes from their number, and waits 1 s before it
  answers a later page, as a slow database would.
- While there is a next page, the grid ends with skeleton cards.
  `shared/load_more.mlx` watches the first one (an `IntersectionObserver`
  that `client/main.ml` gives through `shared/browser.ml`) and then calls
  `Yuka.Browser.navigate ~replace:true ~keep_scroll:true` with the URL of
  the next page. The navigation replaces the history entry, and the page
  stays where the user scrolled while it loaded.
- The island also shows a status while `Yuka.Browser.navigating` is
  `true`, and a line at the end of the gallery.
