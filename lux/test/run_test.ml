open Lux_shared

let width = 1280.
let height = 800.
let frame = 1000. /. 60.

let ticks run ~from count =
  for i = 1 to count do
    ignore (Run.tick run (from +. (float_of_int i *. frame)))
  done;
  from +. (float_of_int count *. frame)

let finite run =
  List.for_all Float.is_finite [ Run.center_x run; Run.center_y run; Run.zoom run; Run.scale run ]

let close name expected actual =
  if not (Float.abs (expected -. actual) <= 1e-9 *. Float.max 1. (Float.abs expected)) then
    Alcotest.failf "%s: %.9g, expected %.9g" name actual expected

let zero_size () =
  let run = Run.create ~size:64 ~seed:1 ~width ~height in
  let now = ticks run ~from:0. 30 in
  let scale = Run.scale run in
  Run.resize run ~width:0. ~height:0.;
  close "scale after a 0 x 0 resize" scale (Run.scale run);
  let now = ticks run ~from:now 120 in
  Alcotest.(check bool) "finite while the window is 0 x 0" true (finite run);
  Run.resize run ~width ~height;
  ignore (ticks run ~from:now 30);
  Alcotest.(check bool) "finite after the window comes back" true (finite run);
  let empty = Run.create ~size:64 ~seed:1 ~width:0. ~height:0. in
  ignore (ticks empty ~from:0. 120);
  Alcotest.(check bool) "finite when created at 0 x 0" true (finite empty)

let resize_keeps_card_size () =
  let run = Run.create ~size:64 ~seed:2 ~width ~height in
  ignore (ticks run ~from:0. 30);
  let scale = Run.scale run in
  Run.resize run ~width:700. ~height:900.;
  close "pixels per card after 1280 x 800 to 700 x 900" scale (Run.scale run);
  let scale = Run.scale run in
  Run.resize run ~width:390. ~height:844.;
  close "pixels per card after 700 x 900 to 390 x 844" scale (Run.scale run)

let restart_glides () =
  let run = Run.create ~size:256 ~seed:3 ~width ~height in
  let now = ticks run ~from:0. 600 in
  let x = Run.center_x run and y = Run.center_y run and zoom = Run.zoom run in
  Alcotest.(check bool) "zoomed out before the restart" true (zoom < 0.5);
  Run.restart run ~seed:4;
  close "centre x right after restart" x (Run.center_x run);
  close "centre y right after restart" y (Run.center_y run);
  close "zoom right after restart" zoom (Run.zoom run);
  let now = ticks run ~from:now 1 in
  let first = Run.zoom run in
  Alcotest.(check bool) "no jump in the first frame" true (first < zoom *. 1.2);
  ignore (ticks run ~from:now 30);
  Alcotest.(check bool) "zooms in toward the new seeds" true (Run.zoom run > first *. 2.)

let converges_to_fit () =
  let run = Run.create ~size:8 ~seed:5 ~width ~height in
  let now = ref 0. in
  while not (Spread.finished (Run.spread run)) do
    now := ticks run ~from:!now 1
  done;
  ignore (ticks run ~from:!now 600);
  Alcotest.(check bool) "finite" true (finite run);
  let x0, y0, x1, y1 = Spread.bounds (Run.spread run) in
  let box_w = float_of_int (x1 - x0 + 1) +. 6. and box_h = float_of_int (y1 - y0 + 1) +. 6. in
  close "centre x on the lit box" (float_of_int (x0 + x1 + 1) /. 2.) (Run.center_x run);
  close "centre y on the lit box" (float_of_int (y0 + y1 + 1) /. 2.) (Run.center_y run);
  let scale = Run.scale run in
  Alcotest.(check bool) "zoom not above 1" true (Run.zoom run <= 1. +. 1e-9);
  Alcotest.(check bool) "box and a margin of 3 cards in view" true
    (box_w *. scale <= width +. 1e-6 && box_h *. scale <= height +. 1e-6);
  Alcotest.(check bool) "fit: zoom 1, or the box fills one side" true
    (Float.abs (Run.zoom run -. 1.) < 1e-6
    || Float.abs ((box_w *. scale) -. width) < 1e-6
    || Float.abs ((box_h *. scale) -. height) < 1e-6)

let () =
  Alcotest.run "run"
    [
      ( "camera",
        [
          Alcotest.test_case "zero size" `Quick zero_size;
          Alcotest.test_case "resize keeps the card size" `Quick resize_keeps_card_size;
          Alcotest.test_case "restart glides" `Quick restart_glides;
          Alcotest.test_case "converges to the fit" `Quick converges_to_fit;
        ] );
    ]
