# sketch

A whiteboard built with Yuka: one island draws the board as SVG. The
geometry, the pen outline, hit tests, transforms and undo history are plain
OCaml in `shared/`, tested natively in `test/`. The board stays in the
browser (localStorage); the server only serves the page.

```sh
make sketch-serve PORT=8080   # http://localhost:8080
make sketch-test              # geometry and editor tests
make sketch-e2e               # every feature in Chrome, with screenshots
node e2e/sketch_perf.ts URL   # frame times with 500 shapes
```

## Features

- Canvas: pan with space+drag, middle drag or the wheel; zoom to the cursor
  with ctrl+wheel or a pinch; a dot grid that follows the zoom.
- Pen: a variable-width stroke, thinner when fast, with tapered ends and
  smoothed input; pen pressure when the device gives it.
- Rectangle and ellipse: shift draws a square or circle, alt draws from
  the centre; a click makes a 100 x 100 shape.
- Arrow and line: shift snaps to 15 degrees; drag an end to move it.
- Text: click to place, type, double click to edit; the box grows with the
  text and an empty text goes away.
- Selection: click, shift+click, marquee, hover outline, select all,
  escape.
- Transform: move, nudge with the arrow keys, resize with 8 handles (shift
  keeps the ratio, alt resizes from the centre, dragging past an edge
  flips), rotate (shift snaps to 15 degrees), also for several shapes.
- Style: 8 colours, 3 sizes, no fill, light fill or solid fill, for the
  selection and the next shape.
- Undo and redo: a whole drag is one step.
- Edit: delete, eraser, duplicate, copy and paste at the cursor, bring to
  front, send to back, export the board as SVG.

## Shortcuts

| Key | Action |
|---|---|
| V, H, D or P, R, O, A, L, T, E | Select, hand, pen, rectangle, ellipse, arrow, line, text, eraser |
| Space + drag, middle drag, wheel | Pan |
| Ctrl + wheel, pinch | Zoom to the cursor |
| + and - | Zoom in and out |
| Shift+1, Shift+0 | Zoom to fit, zoom to 100% |
| Ctrl+A, Escape | Select all, clear the selection |
| Arrow keys, Shift+arrow keys | Move the selection by 1 or 10 |
| Delete, Backspace | Delete the selection |
| Ctrl+D | Duplicate |
| Ctrl+C, Ctrl+X, Ctrl+V | Copy, cut, paste at the cursor |
| ], [ | Bring to front, send to back |
| Ctrl+Z, Ctrl+Shift+Z or Ctrl+Y | Undo, redo |
| Escape or Ctrl+Enter while typing | End the text edit |

Cmd works in the place of Ctrl.

The pen outline follows the method of
[perfect-freehand](https://github.com/steveruizok/perfect-freehand) (MIT),
written again in OCaml.
