# lux

"Let there be light": an endless canvas of small dark cards. Five lights
start at random cards in the first view and spread from card to card, one
level per step (every 120 ms). Each lit card takes the colour and shape of
light of the card that lit it. The camera zooms out to keep every lit card
in view.

A Yuka app with two pages, each with one island:

- `/` draws with WebGL2: the cost of a frame does not depend on the number
  of lit cards. The light spreads on a grid of 1024 x 1024 cards and stops
  at its edge.
- `/dom` makes each card an element that Yuka renders, to find how many
  cards the DOM can animate. `?n=` sets the side of the grid, from 8 to 512
  (default 64, so 4096 cards): `/dom?n=128`. The flicker and the flash are
  CSS animations; the camera is one `transform` on the grid. The readout
  shows the number of cards.

## Run

From the repository root:

    make lux-serve PORT=8080

Then open http://localhost:8080. Scroll or pinch to zoom, drag to pan;
"Follow" gives the camera back, "Restart" starts again with new lights,
and the third button goes to the other page.

`make lux-test` runs the tests of the spread.
