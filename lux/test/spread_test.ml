open Lux_shared

let size = 64

let run_to_end t =
  let rec go steps = if Spread.step t then go (steps + 1) else steps in
  go 0

let fresh_cells t = List.init (Spread.fresh_count t) (Spread.fresh t)

let seeds () =
  let t = Spread.create ~size ~seed:7 ~cols:17 ~rows:12 () in
  let cells = fresh_cells t in
  Alcotest.(check int) "five seeds" 5 (List.length cells);
  Alcotest.(check int) "five lit" 5 (Spread.lit_count t);
  Alcotest.(check (list int)) "one of each style" [ 0; 1; 2; 3; 4 ]
    (List.sort compare (List.filter_map (Spread.style t) cells));
  Alcotest.(check int) "level 1" 1 (Spread.level t);
  let x0 = (size - 17) / 2 and y0 = (size - 12) / 2 in
  List.iter
    (fun cell ->
      let x = cell mod size and y = cell / size in
      Alcotest.(check bool) "inside the view, 3 cards from its edge" true
        (x >= x0 + 3 && x < x0 + 17 - 3 && y >= y0 + 3 && y < y0 + 12 - 3))
    cells

let same_seed_same_run () =
  let lit seed =
    let t = Spread.create ~size ~seed ~cols:17 ~rows:12 () in
    ignore (run_to_end t);
    List.init (size * size) (Spread.style t)
  in
  Alcotest.(check bool) "repeatable" true (lit 3 = lit 3);
  Alcotest.(check bool) "another seed differs" true (lit 3 <> lit 4)

let monotonic_and_once () =
  let t = Spread.create ~size ~seed:11 ~cols:17 ~rows:12 () in
  let seen = Hashtbl.create 1024 in
  List.iter (fun cell -> Hashtbl.add seen cell ()) (fresh_cells t);
  let rec go level =
    let lit = Spread.lit_count t in
    if Spread.step t then begin
      Alcotest.(check int) "one level per step" (level + 1) (Spread.level t);
      Alcotest.(check int) "lit count grows by the fresh cards" (lit + Spread.fresh_count t) (Spread.lit_count t);
      List.iter
        (fun cell ->
          Alcotest.(check bool) "no card lit twice" false (Hashtbl.mem seen cell);
          Hashtbl.add seen cell ())
        (fresh_cells t);
      go (level + 1)
    end
    else begin
      Alcotest.(check int) "the level stays when nothing lights" level (Spread.level t);
      Alcotest.(check bool) "finished" true (Spread.finished t);
      Alcotest.(check bool) "a finished run stays finished" false (Spread.step t)
    end
  in
  go 1;
  Alcotest.(check int) "every lit card is counted once" (Hashtbl.length seen) (Spread.lit_count t)

let bounds_hold_all () =
  let t = Spread.create ~size ~seed:5 ~cols:17 ~rows:12 () in
  let check () =
    let x0, y0, x1, y1 = Spread.bounds t in
    for cell = 0 to (size * size) - 1 do
      if Spread.style t cell <> None then begin
        let x = cell mod size and y = cell / size in
        if x < x0 || x > x1 || y < y0 || y > y1 then Alcotest.failf "card (%d, %d) outside the bounds" x y
      end
    done
  in
  check ();
  while Spread.step t do
    check ()
  done

let stops_at_edges () =
  let t = Spread.create ~size:16 ~seed:2 ~cols:16 ~rows:16 () in
  ignore (run_to_end t);
  let x0, y0, x1, y1 = Spread.bounds t in
  Alcotest.(check bool) "inside the grid" true (x0 >= 0 && y0 >= 0 && x1 < 16 && y1 < 16);
  Alcotest.(check bool) "most of the grid lit" true (Spread.lit_count t > 16 * 16 / 2)

let corner_seed () =
  let spread_from_corner = ref false in
  for seed = 1 to 200 do
    match Spread.of_seeds ~size:8 ~seed [ (0, 0, 0) ] with
    | Error message -> Alcotest.fail message
    | Ok t ->
        if Spread.step t then spread_from_corner := true;
        List.iter
          (fun cell ->
            Alcotest.(check bool) "inside the grid" true (cell >= 0 && cell < 64);
            let x = cell mod 8 and y = cell / 8 in
            if x = 7 || y = 7 then Alcotest.failf "seed %d: card (%d, %d) on the opposite edge after one step" seed x y)
          (fresh_cells t);
        let x0, y0, x1, y1 = Spread.bounds t in
        Alcotest.(check bool) "bounds inside the grid" true (x0 >= 0 && y0 >= 0 && x1 <= 1 && y1 <= 1)
  done;
  Alcotest.(check bool) "the corner lights cards beyond itself" true !spread_from_corner

let rejects () =
  let error = function Ok _ -> false | Error _ -> true in
  Alcotest.(check bool) "outside" true (error (Spread.of_seeds ~size:8 ~seed:1 [ (8, 0, 0) ]));
  Alcotest.(check bool) "bad style" true (error (Spread.of_seeds ~size:8 ~seed:1 [ (1, 1, 5) ]));
  Alcotest.(check bool) "same cell" true (error (Spread.of_seeds ~size:8 ~seed:1 [ (1, 1, 0); (1, 1, 2) ]));
  Alcotest.(check bool) "none" true (error (Spread.of_seeds ~size:8 ~seed:1 []));
  Alcotest.(check bool) "level 0" true (error (Spread.of_seeds ~size:8 ~level:0 ~seed:1 [ (1, 1, 0) ]))

let inherits_style () =
  match Spread.of_seeds ~size:32 ~seed:9 [ (16, 16, 3) ] with
  | Error message -> Alcotest.fail message
  | Ok t ->
      ignore (run_to_end t);
      for cell = 0 to (32 * 32) - 1 do
        match Spread.style t cell with Some style -> Alcotest.(check int) "style of the seed" 3 style | None -> ()
      done

let mean_new ~level =
  let trials = 4000 in
  let total = ref 0 in
  for seed = 1 to trials do
    match Spread.of_seeds ~size:9 ~level ~seed [ (4, 4, 0) ] with
    | Error message -> Alcotest.fail message
    | Ok t ->
        ignore (Spread.step t);
        total := !total + Spread.fresh_count t
  done;
  float_of_int !total /. float_of_int trials

let probabilities () =
  let near name expected actual =
    if Float.abs (actual -. expected) > 0.25 then Alcotest.failf "%s: %.3f new cards, expected about %.3f" name actual expected
  in
  near "level 1" (8. *. 3. /. 5.) (mean_new ~level:1);
  near "level 2" (8. *. 3. /. 5.) (mean_new ~level:2);
  near "level 3" (8. *. 5. /. 6.) (mean_new ~level:3);
  near "level 9" (8. *. 5. /. 6.) (mean_new ~level:9)

let () =
  Alcotest.run "spread"
    [
      ( "spread",
        [
          Alcotest.test_case "seeds" `Quick seeds;
          Alcotest.test_case "same seed, same run" `Quick same_seed_same_run;
          Alcotest.test_case "levels and cards" `Quick monotonic_and_once;
          Alcotest.test_case "bounds" `Quick bounds_hold_all;
          Alcotest.test_case "grid edges" `Quick stops_at_edges;
          Alcotest.test_case "corner seeds" `Quick corner_seed;
          Alcotest.test_case "invalid seeds" `Quick rejects;
          Alcotest.test_case "style" `Quick inherits_style;
          Alcotest.test_case "probabilities" `Quick probabilities;
        ] );
    ]
