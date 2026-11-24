# Posters demo

A generator for a magazine poster series: lines, blocks, clouds,
lightning or a grid of half discs on a dark or light card, with a title block. One island
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
  the lines of a poster run in a stack. The lines are drawn on a square of
  1564 px around the centre of the art area, which covers the art area at
  any angle. The direction turns them with `transform="rotate(...)"`, so
  the path data never holds a sine or a cosine.
- Blocks: the art area cut again and again in two (a guillotine cut), some
  rectangles filled, the others outlined, with an optional corner radius
  of at most half the short side. A cut never leaves a side under 68 px.
  When a free cut would leave room for fewer than 80 blocks, the cut falls
  on a multiple of 68 px, so every count of the slider is reached. The
  gap is taken from the inner sides only, so neighbours are exactly `gap`
  apart and the outer blocks touch the art area.
- Clouds: puffs of `A` arcs, each close to a half circle, over a dome
  made from the rational parametrization of a circle. Each cloud has its
  own width, height, number of puffs and puff sizes, and every cloud is
  filled. The widest cloud is the smaller of `size` and a width that
  leaves room for the count, so more clouds make smaller clouds. A cloud
  that would overlap an earlier one tries 60 random places, then every
  place on an 8 px grid, and then the same at four fifths of its width,
  so each cloud of the count is drawn.
- Lightning: bolts from the top of the art area, made jagged by midpoint
  displacement, with branches. `length` is the share of the height that
  a bolt goes down. The direction turns the bolts like the lines, with
  `transform="rotate(...)"`; the bolts are drawn in the box of the art
  area turned by that angle, with an integer sine, so they still cover
  the art area.
- Circles: the first poster of this demo, a grid of half discs on one of
  their four edges, squares and half-cell bars, picked with the weights of
  the mix.

All the math is on integers, so native code and JavaScript give the same
SVG for the same settings. Each random number is a hash of the seed, the
kind and the place it is used: the index of the shape, and then the
anchor, the cut, the puff or the node of a bolt. A draw scales the hash to
its range, it does not take a remainder. So a setting other than the seed
moves each shape a little and does not shuffle the poster:

- More clouds, bolts or branches add shapes and keep the others; a cloud
  is placed against the earlier clouds only.
- One more block makes one more cut of the same sequence, so all blocks
  but the one cut in two stay. The cuts depend on the seed, the padding
  and the squareness only, not on the gap, the filled share or the radius.
- More columns or rows keep the shape of each cell; a cell keeps its key,
  `row * 24 + column`.
- More lines spread the stack over the same area, so each line moves a
  little. The direction and the padding do not change the lines at all,
  and a half turn of the bolts draws the same bolts.

The padding is the space between the edge of the poster and the art
area. The art is clipped to the art area with a `clipPath` (its id is
`art-` and the padding, so posters with the same padding on one page
share it). For lightning the padding also includes half the stroke
width; a padding of 0 is full bleed. `Pattern.shapes` gives one SVG path
per shape, keyed by its index, filled or stroked.

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
defaults. The direction of the lines is a dial: a `role="slider"` with
`aria-valuenow`, turned with the arrow keys (Shift for 15 degrees), Page
Up and Down, Home and End, or by a click or a drag. The angle of a pointer
comes from `client/main.ml` through `Dial.angle`, as the PNG download
does. The URL is a memo over the four groups, written with
`Routes.replace`. "Download SVG" is an `<a download>` link to
`/poster.svg` with the same query and the three date lines, always: the
server fills a missing date line with the date of the request, so a page
left open past midnight would otherwise download another date. The page
URL leaves them out when they are the defaults. "Download PNG" draws that URL on a
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

- `/posters/gallery`: ten presets, two for each kind, each a link to the playground with
  its settings.
- `/posters/poster.svg?kind=clouds&seed=42`: the poster as an SVG file.
- `kind`: `lines` (the default), `blocks`, `clouds`, `lightning` or
  `circles`. An
  unknown value gives the default kind.
- `seed` (0 to 999999) and `padding` (0 to 200, default 80).
- The params of the kind. The params of the other kinds are ignored.

  | Kind | Param | Range | Default |
  | --- | --- | --- | --- |
  | lines | `lines` | 2 to 60 | 32 |
  | | `amplitude` (curviness) | 0 to 100 | 60 |
  | | `waves` | 1 to 10 | 3 |
  | | `stroke` | 1 to 24 | 6 |
  | | `direction` (degrees, 90 is horizontal) | 0 to 359 | 90 |
  | blocks | `blocks` | 1 to 80 | 14 |
  | | `gap` | 0 to 60 | 16 |
  | | `filled` (percent) | 0 to 100 | 45 |
  | | `squareness` | 0 to 100 | 50 |
  | | `radius` (corner radius) | 0 to 60 | 0 |
  | clouds | `clouds` | 1 to 20 | 6 |
  | | `puffs` | 3 to 14 | 6 |
  | | `size` (percent of the width) | 10 to 100 | 45 |
  | lightning | `bolts` | 1 to 8 | 2 |
  | | `branches` (per bolt) | 0 to 12 | 4 |
  | | `jaggedness` | 0 to 100 | 55 |
  | | `thickness` | 1 to 24 | 7 |
  | | `length` (percent of the height) | 20 to 100 | 100 |
  | | `direction` (degrees, 180 is down) | 0 to 359 | 180 |
  | circles | `columns` | 4 to 24 | 13 |
  | | `rows` | 4 to 30 | 15 |
  | | `half`, `empty`, `block`, `bar` (weights of the mix) | 0 to 100 | 80, 12, 2, 6 |

- `bg=f4f4f4&fg=333333`: the colours, as six hex digits.
- `title`, `subtitle`, `year`, `day`, `weekday`: the text, each cut to 40
  bytes at a character boundary. The three date lines default to the date
  of the server, in UTC.

For example `/posters?kind=blocks&seed=7&gap=30&filled=80`. Values out of
range are clamped, and a colour that is not six hex digits falls back to
its default.

## Tests

    make demo-test

`test/run.ml` checks the generators (for each kind, the same settings
give the same SVG and another seed another poster; the keys and the shape
counts; the block count at the extreme settings; every cloud of the
count drawn; the turn and length of the bolts; a gap of 1; that
settings keep the number of shapes, that a larger count keeps the shapes,
and that one step of a setting moves the shapes a little; the direction;
the clip; the lines
never go back to the left; the shapes and their strokes stay inside the
padding; clamping; the cut of the text; escaping), the links (the param
scheme, a round trip for each preset and kind, and the date in the
download link), the playground, `/poster.svg` and the
gallery. `e2e/posters.ts` (run by `make e2e`) switches the kinds and
checks that the browser draws what the server draws, turns the dial with
keys, a click and a drag, turns and shortens the bolts, draws twelve
large clouds, adds clouds, bolts and a block and checks that
the other nodes stay, shuffles, changes a slider of the kind, the padding, the colours and the title, checks which
shape nodes stay and the place of the text column, reloads, checks both
downloads and the gallery, and times a slider change with 60 lines.
