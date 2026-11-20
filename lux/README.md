# lux

"Let there be light": an endless canvas of small dark cards. Five lights
start at random cards in the first view and spread from card to card, one
level per step (every 120 ms). Each lit card takes the colour and shape of
light of the card that lit it. The camera zooms out to keep every lit card
in view.

A Yuka app with one page and one island. The island draws with WebGL2: the
cost of a frame does not depend on the number of lit cards. The light
spreads on a grid of 1024 x 1024 cards and stops at its edge.

## Run

From the repository root:

    make lux-serve PORT=8080

Then open http://localhost:8080. Scroll or pinch to zoom, drag to pan;
"Follow" gives the camera back, "Restart" starts again with new lights.

`make lux-test` runs the tests of the spread.
