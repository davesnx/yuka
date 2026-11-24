# Posters demo

A generator for a magazine poster series: lines, blocks, clouds or
lightning on a dark or light card, with a title block. One island
(`shared/playground.mlx`) holds the preview and the controls: the text on
the left, the poster in the middle, the other settings on the right. Below
1100 px the text goes under the settings, and below 860 px everything is
in one column.

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

`shared/pattern.ml` holds the settings and the generators. The art is a
variant with one parameter record per kind:

- Lines: smooth curves of `C` and `S` segments. The anchors and control
  points of a line go strictly from left to right, so a line cannot touch
  or cross itself. Each line is a blend of two random wave profiles, so
  the lines of a poster run in a stack.
- Blocks: the art area cut again and again in two (a guillotine cut), some
  rectangles filled, the others outlined.
- Clouds: outlines of `A` arcs from point to point over a dome, and a
  flat arc for the bottom. A cloud that would overlap another is not
  drawn.
- Lightning: bolts from the top of the art area, made jagged by midpoint
  displacement, with branches.

The random numbers come from a 31-bit linear congruential generator, and
all the math is on integers: native code and JavaScript give the same SVG
for the same settings. The padding is the space between the edge of the
poster and the art area. `Pattern.shapes` gives one SVG path per shape,
keyed by its index, filled or stroked.

`shared/poster.mlx` is the `<Poster />` component: the card, the art and
the text. It takes the colours and the text lines as functions, and the
art as an element, so one component serves three places:

- the island (`shared/playground.mlx`) gives functions that read its
  States, and the art as `Yuka.each` keyed by the shape index, with an
  `equal` on the path and its paint. A shape renders again only when it
  changes; a colour change sets the fill and stroke attributes only.
- `/poster.svg` (`server/handlers.ml`, a `Router.get`) prints
  `Poster.still` with `Yuka.Server.to_string` and answers
  `image/svg+xml`, cached for an hour.
- `/gallery` prints `Poster.still` for each preset of `Pattern.presets`,
  two for each kind. The page has no island and is marked
  `~prerender:true`.

The island keeps one State per group of settings (layout, art, colours,
text), and each control reads only its group. The sliders of the kind
are in a hole that reads only the kind, so a slider change does not draw
the sliders again. A click on another kind starts that kind from its
defaults. The URL is a memo over the four groups, written with
`Routes.replace`. "Download SVG" is an `<a download>` link to
`/poster.svg` with the same query. "Download PNG" draws that URL on a
canvas at twice the size, in `client/main.ml`: the shared library also
builds for native code, so the canvas code stays in the client entry and
reaches the island through `Download.png`.

## URLs

Each setting that differs from its default is a search param, so a reload
or a shared link shows the same poster, rendered by the server. The seed
has no field in the playground ("Shuffle" changes it), but it is in the
URL. `/poster.svg` reads the same params: `Router.get` takes no
`~search`, so its handler decodes the query with the generated
`Routes.find` of the playground route.

- `/posters/gallery`: eight presets, each a link to the playground with
  its settings.
- `/posters/poster.svg?kind=clouds&seed=42`: the poster as an SVG file.
- `kind`: `lines` (the default), `blocks`, `clouds` or `lightning`. An
  unknown value gives the default kind.
- `seed` (0 to 999999) and `padding` (0 to 200, default 80).
- The params of the kind. The params of the other kinds are ignored.

  | Kind | Param | Range | Default |
  | --- | --- | --- | --- |
  | lines | `lines` | 2 to 60 | 22 |
  | | `amplitude` (curviness) | 0 to 100 | 60 |
  | | `waves` | 1 to 10 | 3 |
  | | `stroke` | 1 to 24 | 6 |
  | blocks | `blocks` | 1 to 80 | 14 |
  | | `gap` | 0 to 60 | 16 |
  | | `filled` (percent) | 0 to 100 | 45 |
  | | `squareness` | 0 to 100 | 50 |
  | clouds | `clouds` | 1 to 20 | 6 |
  | | `puffs` | 3 to 14 | 6 |
  | | `size` (percent of the width) | 10 to 100 | 45 |
  | | `solid` (filled percent) | 0 to 100 | 50 |
  | lightning | `bolts` | 1 to 8 | 2 |
  | | `branches` (per bolt) | 0 to 12 | 4 |
  | | `jaggedness` | 0 to 100 | 55 |
  | | `thickness` | 1 to 24 | 7 |

- `bg=f4f4f4&fg=333333`: the colours, as six hex digits.
- `title`, `subtitle`, `year`, `day`, `weekday`: the text. The three date
  lines default to the date of the server, in UTC.

For example `/posters?kind=blocks&seed=7&gap=30&filled=80`. Values out of
range are clamped, and a colour that is not six hex digits falls back to
its default.

## Tests

    make demo-test

`test/run.ml` checks the generators (for each kind, the same settings
give the same SVG and another seed another poster; the keys and the shape
counts; the lines never go back to the left; the shapes stay inside the
padding; clamping; escaping), the links (the param scheme and a round
trip for each preset and kind), the playground, `/poster.svg` and the
gallery. `e2e/posters.ts` (run by `make e2e`) switches the kinds and
checks that the browser draws what the server draws, shuffles, changes a
slider of the kind, the padding, the colours and the title, checks which
shape nodes stay and the place of the text column, reloads, checks both
downloads and the gallery, and times a slider change with 60 lines.
