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

`shared/poster.ml` draws the poster from its settings, on the server and in
the browser: `Poster.svg` gives the SVG file, and the island renders the
same grid path (`Poster.grid`) and text lines (`Poster.labels`). Each cell
is a half disc on one of its four edges, empty, a full block or a half-cell
bar, picked with the weights of the shape mix. The random numbers come from
a 31-bit linear congruential generator in integer math, so native code and
JavaScript give the same poster for a seed.

## URLs

Each setting that differs from its default is a search param, written with
`Routes.replace` as the controls change, so a reload or a shared link shows
the same poster, rendered by the server:

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
cell count, the shape mix, escaping) and the server page.
`e2e/posters.ts` (run by `make e2e`) changes the seed, a slider, the
colours and the title in a browser, reloads, and checks both downloads.
