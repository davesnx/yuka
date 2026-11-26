# Genart demo

A port of [sketch-004](https://github.com/amiechen/genart/blob/master/sketch-004.js)
of Amie Chen's genart series: a grid of dots on black, each joined by a
round line to itself (a dot), or to its right, lower right or lower
neighbour, in a colour from a palette, with an opacity of its own. The
original draws on a canvas with canvas-sketch; this port draws one SVG
`<line>` per dot in a Yuka island (`shared/studio.mlx`).

## Run

From the repository root:

    make demo-serve PORT=8080

serves this demo at `/genart`, with the other demos. To run it alone, at
the root:

    make genart-serve PORT=8080

`server/genart_server.exe` takes `--port`, `--interface`, `--base PREFIX`,
`--bundle` (serve `bundle.sh` output) and `--dir` (the directory with
`client/` and `static/`, by default the build directory of the demo).

## The drawing

`shared/sketch.ml` holds the settings and the generator. The original
calls `Math.random`; here each random number is a hash of the seed, the
cell and what it picks (the direction, the palette, the colour, the
opacity), so the server prints the lines that the island hydrates. The
math is on integers below 2^31, which native code and JavaScript compute
the same way.

- The server renders the page with the lines of the seed in the URL.
- In the browser, the island draws them again with `Yuka.each`, keyed by
  the cell, with `~equal:( = )`: a row renders again only when its line
  changed. The line width is one attribute on the `<g>` around the lines,
  so a width change touches one node.
- "Shuffle" picks another seed. "Drift" draws about one line in 60 again
  every 90 ms with `Yuka.Browser.on_frame`, in an effect that stops when
  the drift is turned off. The opacity of a line stays, as in the
  original, which picks it once.
- A larger grid keeps the direction and the colour of each line: a cell
  draws from its column and row, not from its index in the grid.
- "Download PNG" draws the SVG on a canvas of 2048 px, the size of the
  original, in `client/main.ml`.

The palettes are written for this demo; the original picks from
`nice-color-palettes`. "Mixed" picks a palette for each line, as the
original does.

## URLs

Each setting that differs from its default is a search param, written
back with `Routes.replace`, so a reload or a shared link shows the same
drawing, rendered by the server. Values out of range are clamped.

| Param | Range | Default |
| --- | --- | --- |
| `seed` | 0 to 999999 | 4 |
| `grid` (dots per side) | 2 to 40 | 20 |
| `stroke` (line width, of 2048) | 1 to 40 | 10 |
| `palette` (index of a palette) | 0 to 11 | none: mixed |

## Tests

    make demo-test

`test/run.ml` checks the page (one line per dot, the search params and
their clamping) and the generator (the same seed gives the same lines,
each line goes to the dot or a neighbour, all four directions occur, a
palette keeps its colours, a larger grid keeps the lines, the drift
changes few lines and keeps the opacity). `e2e/genart.ts` (run by
`make e2e`) checks that the browser keeps and then draws what the server
draws, the URL, the palette, a reload after a shuffle, the drift and the
PNG download.
