# Posters demo

A playground for generative posters: a grid of half discs in four
orientations on a dark or light card, with a title block. One island
(`shared/playground.mlx`) holds the preview and the controls.

## Run

From the repository root:

    make demo-serve PORT=8080

serves this demo at `/posters`, with the other demos. To run it alone, at
the root:

    make posters-serve PORT=8080

`server/posters_server.exe` takes `--port`, `--interface`, `--base PREFIX`,
`--bundle` (serve `bundle.sh` output) and `--dir` (the directory with
`client/` and `static/`, by default the build directory of the demo).

## The poster

`shared/pattern.ml` holds the settings and the generator: each cell is a
half disc on one of its four edges, empty, a full block or a half-cell bar,
picked with the weights of the shape mix. The random numbers come from a
31-bit linear congruential generator in integer math, so native code and
JavaScript give the same poster for a seed. `Pattern.cells` gives one SVG
path per drawn cell, keyed by the cell index.

`shared/poster.mlx` is the `<Poster />` component: the card, the grid and
the text. It takes the colours and the text lines as functions, and the
grid as an element, so one component serves three places:

- the island (`shared/playground.mlx`) gives functions that read its
  States, and the grid as `Yuka.each` keyed by the cell index, with an
  `equal` on the path. A cell renders again only when its shape changes;
  a colour change sets the fill and stroke attributes only.
- `/poster.svg` (`server/handlers.ml`, a `Router.get`) prints
  `Poster.still` with `Yuka.Server.to_string` and answers
  `image/svg+xml`, cached for an hour.
- `/gallery` prints `Poster.still` for each preset of `Pattern.presets`.
  The page has no island and is marked `~prerender:true`.

The island keeps one State per group of settings (pattern, shape mix,
colours, text), and each control reads only its group. The URL is a memo
over the four groups, written with `Routes.replace`. "Download SVG" is an
`<a download>` link to `/poster.svg` with the same query. "Download PNG"
draws that URL on a canvas at twice the size, in `client/main.ml`: the
shared library also builds for native code, so the canvas code stays in
the client entry and reaches the island through `Download.png`.

## URLs

Each setting that differs from its default is a search param, so a reload
or a shared link shows the same poster, rendered by the server.
`/poster.svg` reads the same params: `Router.get` takes no `~search`, so
its handler decodes the query with the generated `Routes.find` of the
playground route.

- `/posters/gallery`: eight presets, each a link to the playground with
  its settings.
- `/posters/poster.svg?seed=42`: the poster as an SVG file.
- `/posters?seed=42&columns=9&rows=12`: the seed (0 to 999999) and the grid
  (4 to 24 columns, 4 to 30 rows).
- `half`, `empty`, `block`, `bar`: the shape mix, each 0 to 100.
- `bg=f4f4f4&fg=333333`: the colours, as six hex digits.
- `title`, `subtitle`, `year`, `day`, `weekday`: the text. The three date
  lines default to the date of the server, in UTC.

Values out of range are clamped, and a colour that is not six hex digits
falls back to its default.

## Tests

    make demo-test

`test/run.ml` checks the generator (the same seed gives the same SVG, the
cell count and keys, the shape mix, escaping), the links, the playground,
`/poster.svg` and the gallery. `e2e/posters.ts` (run by `make e2e`)
changes the seed, the sliders, the colours and the title in a browser,
checks which cell nodes stay, reloads, checks both downloads and the
gallery, and times a slider change with 24 x 30 cells.
