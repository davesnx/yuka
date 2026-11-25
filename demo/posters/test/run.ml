open Posters_app
open Posters_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:(Filename.temp_dir "posters" "js") ~entry:"demo/posters/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
    ()

let handler = Yuka_dream.handler config Yuka_routes.app

let get target =
  let response = Dream.test handler (Dream.request ~target "") in
  (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

let count html needle =
  let n = String.length needle in
  let rec go i found =
    if i + n > String.length html then found else go (i + 1) (if String.sub html i n = needle then found + 1 else found)
  in
  go 0 0

let contains html needle = count html needle > 0

let find html needle =
  let n = String.length needle in
  let rec go i = if i + n > String.length html then None else if String.sub html i n = needle then Some i else go (i + 1) in
  go 0
let check_has html name needle = Alcotest.(check bool) name true (contains html needle)
let defaults = Pattern.defaults ~year:2019 ~month:2 ~day:1 ~weekday:5
let svg (s : Pattern.settings) = Yuka.Server.to_string (fun () -> Poster.still s)
let shapes (s : Pattern.settings) = Pattern.shapes s.layout s.art
let ds s = Array.to_list (Array.map (fun (x : Pattern.shape) -> x.d) (shapes s))
let with_art art = { defaults with art }
let with_seed seed (s : Pattern.settings) = { s with layout = { s.layout with seed } }
let kinds =
  List.map (fun k -> (Pattern.Kind.name k, with_art (Pattern.fresh k))) Pattern.Kind.all
  @ [ ("fragments", with_art (Pattern.Circles Pattern.fragments_default)) ]

let commands d =
  let out = ref [] and current = ref None and number = Buffer.create 8 in
  let flush () =
    if Buffer.length number > 0 then begin
      (match !current with Some (c, ns) -> current := Some (c, int_of_string (Buffer.contents number) :: ns) | None -> ());
      Buffer.clear number
    end
  in
  let close () = match !current with Some (c, ns) -> out := (c, List.rev ns) :: !out | None -> () in
  String.iter
    (fun ch ->
      match ch with
      | '0' .. '9' | '-' -> Buffer.add_char number ch
      | ' ' -> flush ()
      | c ->
          flush ();
          close ();
          current := Some (c, []))
    d;
  flush ();
  close ();
  List.rev !out

let same_seed () =
  List.iter
    (fun (name, s) ->
      Alcotest.(check string) (name ^ ": same settings, same SVG") (svg s) (svg (Pattern.normalize ~defaults s));
      Alcotest.(check bool) (name ^ ": draws shapes") true (Array.length (shapes s) > 0);
      Alcotest.(check bool) (name ^ ": another seed, another poster") false (String.equal (svg s) (svg (with_seed 7 s))))
    kinds;
  Alcotest.(check bool) "shuffle changes the seed" true (Pattern.shuffle defaults.layout.seed <> defaults.layout.seed)

let keys () =
  List.iter
    (fun (name, s) ->
      let all = Array.to_list (Array.map (fun (x : Pattern.shape) -> x.index) (shapes s)) in
      Alcotest.(check (list int)) (name ^ ": keys grow, so they are unique") (List.sort_uniq compare all) all)
    kinds;
  Alcotest.(check int) "one shape per line" 30 (Array.length (shapes (with_art (Lines { Pattern.lines_default with lines = 30 }))));
  Alcotest.(check int) "one shape per block" 20 (Array.length (shapes (with_art (Blocks { Pattern.blocks_default with blocks = 20 }))));
  Alcotest.(check int) "one shape per bolt and branch" 15
    (Array.length (shapes (with_art (Lightning { Pattern.lightning_default with bolts = 3; branches = 4 }))));
  Alcotest.(check int) "one shape per cell" (9 * 7)
    (Array.length (shapes (with_art (Circles { Pattern.circles_default with columns = 9; rows = 7; half = 1; empty = 0; block = 0; bar = 0 }))))

let not_crossing d =
  match commands d with
  | ('M', [ x0; _ ]) :: ('C', [ c1; _; c2; _; x1; _ ]) :: rest ->
      let rec go previous_control anchor = function
        | [] -> true
        | ('S', [ c2; _; x; _ ]) :: rest ->
            let c1 = (2 * anchor) - previous_control in
            anchor < x && anchor <= c1 && c1 <= c2 && c2 <= x && go c2 x rest
        | _ -> false
      in
      x0 < x1 && x0 <= c1 && c1 <= c2 && c2 <= x1 && go c2 x1 rest
  | _ -> false

let lines_do_not_cross_themselves () =
  Alcotest.(check bool) "the check finds a curve that turns back" false (not_crossing "M10 0C40 0 5 9 30 9");
  Alcotest.(check bool) "the check finds an anchor behind the last one" false (not_crossing "M10 0C12 0 28 9 30 9S40 0 20 0");
  List.iter
    (fun (lines, amplitude, waves, padding) ->
      List.iter
        (fun seed ->
          let s = { (with_seed seed (with_art (Lines { lines; amplitude; waves; stroke = 4; direction = 90 }))) with layout = { seed; padding } } in
          List.iter
            (fun d -> Alcotest.(check bool) (Printf.sprintf "x grows along %s" (String.sub d 0 20)) true (not_crossing d))
            (ds s))
        [ 0; 1; 42; 2019; 999_999 ])
    [ (22, 60, 3, 80); (2, 100, 10, 200); (60, 100, 1, 0); (10, 0, 6, 40) ]

let in_box padding paint d =
  let w = match paint with Pattern.Stroke w -> w | Pattern.Fill | Pattern.Tint _ -> 0 in
  let in_x x = (2 * x) - w >= 2 * padding && (2 * x) + w <= 2 * (Pattern.width - padding) in
  let in_y y = (2 * y) - w >= 2 * padding && (2 * y) + w <= 2 * (Pattern.art_bottom - padding) in
  let rec pairs = function x :: y :: rest -> in_x x && in_y y && pairs rest | [] -> true | [ _ ] -> false in
  List.for_all
    (fun (c, ns) ->
      match (c, ns) with
      | 'H', _ -> List.for_all in_x ns
      | 'V', _ -> List.for_all in_y ns
      | 'z', _ -> ns = []
      | 'A', [ _; _; _; _; _; x; y ] -> in_x x && in_y y
      | 'A', _ -> false
      | _ -> pairs ns)
    (commands d)

let inside () =
  Alcotest.(check bool) "the check rejects a block below the art area" false (in_box 80 Pattern.Fill "M80 80H920V1200H80z");
  Alcotest.(check bool) "the check rejects a stroke on the padding" false (in_box 80 (Pattern.Stroke 6) "M80 80L120 120");
  Alcotest.(check bool) "the check takes a block on the padding" true (in_box 80 Pattern.Fill "M80 80H920V1120H80z");
  List.iter
    (fun padding ->
      List.iter
        (fun art ->
          let s = { (with_art art) with layout = { seed = 3; padding } } in
          Array.iter
            (fun (x : Pattern.shape) ->
              let margin = if padding = 0 then 0 else padding in
              Alcotest.(check bool)
                (Printf.sprintf "inside padding %d: %s" padding (String.sub x.d 0 12))
                true
                (in_box margin (if padding = 0 then Pattern.Fill else x.paint) x.d))
            (shapes s))
        [
          Pattern.Blocks { Pattern.blocks_default with gap = 0 };
          Pattern.Blocks { Pattern.blocks_default with radius = 60; filled = 50 };
          Pattern.Circles Pattern.circles_default;
          Pattern.Circles { Pattern.circles_default with columns = 24; rows = 4 };
          Pattern.Circles Pattern.fragments_default;
          Pattern.Circles { Pattern.fragments_default with columns = 24; rows = 30; merge = 100; round = 100; gap = 0; accent = 6 };
          Pattern.Circles { Pattern.fragments_default with columns = 2; rows = 2; gap = 40 };
          Pattern.Blocks { Pattern.blocks_default with gap = 1; filled = 0 };
          Pattern.Lightning Pattern.lightning_default;
          Pattern.Lightning { Pattern.lightning_default with thickness = 24; jaggedness = 100; branches = 12 };
        ])
    [ 0; 1; 80; 200 ];
  List.iter
    (fun padding ->
      let s = { (with_art (Pattern.Lines { Pattern.lines_default with stroke = 24 })) with layout = { seed = 3; padding } } in
      let svg = svg s in
      let clip = Printf.sprintf {|<clipPath id="art-%d"><rect x="%d" y="%d" width="%d" height="%d">|} padding padding padding
          (Pattern.width - (2 * padding)) (Pattern.art_bottom - (2 * padding)) in
      check_has svg (Printf.sprintf "lines are clipped to the art area at padding %d" padding) clip;
      check_has svg "the art uses the clip" (Printf.sprintf {|style="clip-path:url(#art-%d)"|} padding);
      Alcotest.(check (list string)) "the padding does not move the lines" (ds { s with layout = { s.layout with padding = 0 } }) (ds s))
    [ 0; 1; 80; 200 ];
  let wide = ds { (with_art (Pattern.Blocks Pattern.blocks_default)) with layout = { seed = 3; padding = 0 } } in
  let narrow = ds { (with_art (Pattern.Blocks Pattern.blocks_default)) with layout = { seed = 3; padding = 150 } } in
  Alcotest.(check bool) "padding moves the art" false (wide = narrow)

let painted (x : Pattern.shape) =
  match commands x.d with
  | [ ('M', [ left; top ]); ('H', [ right ]); ('V', [ bottom ]); ('H', _); ('z', []) ] ->
      let half = match x.paint with Pattern.Stroke w -> w / 2 | Pattern.Fill | Pattern.Tint _ -> 0 in
      (left - half, top - half, right + half, bottom + half)
  | _ -> failwith ("not a rectangle: " ^ x.d)

let block_count () =
  List.iter
    (fun (padding, gap, blocks, squareness, seed) ->
      let s = { (with_art (Pattern.Blocks { blocks; gap; filled = 50; squareness; radius = 0 })) with layout = { seed; padding } } in
      let all = Array.map painted (shapes s) in
      Alcotest.(check int) (Printf.sprintf "padding %d gap %d squareness %d seed %d" padding gap squareness seed) blocks (Array.length all);
      Alcotest.(check bool) "no empty block" true (Array.for_all (fun (l, t, r, b) -> r > l && b > t) all))
    (List.concat_map
       (fun padding ->
         List.concat_map
           (fun gap ->
             List.concat_map
               (fun blocks -> List.concat_map (fun squareness -> List.map (fun seed -> (padding, gap, blocks, squareness, seed)) [ 0; 1; 42; 2019; 999_999 ]) [ 0; 100 ])
               [ 1; 80 ])
           [ 0; 60 ])
       [ 0; 200 ])

let gap_of_one () =
  let s = { (with_art (Pattern.Blocks { Pattern.blocks_default with gap = 1 })) with layout = { seed = 3; padding = 80 } } in
  let all = Array.to_list (Array.map painted (shapes s)) in
  let apart (l1, t1, r1, b1) (l2, t2, r2, b2) =
    let dx = max (l2 - r1) (l1 - r2) and dy = max (t2 - b1) (t1 - b2) in
    max dx dy
  in
  let distances = List.concat_map (fun a -> List.filter_map (fun b -> if a == b then None else Some (apart a b)) all) all in
  Alcotest.(check int) "neighbouring blocks are 1 apart" 1 (List.fold_left min max_int distances);
  Alcotest.(check bool) "there are neighbours" true (List.mem 1 distances)

let shape_count (s : Pattern.settings) = Array.length (shapes s)
let with_padding padding (s : Pattern.settings) = { s with layout = { s.layout with padding } }
let by_key s = List.map (fun (x : Pattern.shape) -> (x.index, x.d)) (Array.to_list (shapes s))

let keeps_count () =
  List.iter
    (fun (name, base, changes) ->
      List.iter
        (fun (change, art) ->
          List.iter
            (fun seed ->
              let s = with_seed seed (with_art base) in
              let t = with_seed seed (with_art art) in
              Alcotest.(check int) (Printf.sprintf "%s: %s keeps the number of shapes (seed %d)" name change seed) (shape_count s) (shape_count t);
              Alcotest.(check int) (Printf.sprintf "%s: padding keeps the number of shapes (seed %d)" name seed) (shape_count s)
                (shape_count (with_padding 160 s)))
            [ 1; 42; 2019 ])
        changes)
    [
      ( "lines",
        Pattern.Lines Pattern.lines_default,
        [
          ("amplitude", Pattern.Lines { Pattern.lines_default with amplitude = 10 });
          ("waves", Pattern.Lines { Pattern.lines_default with waves = 8 });
          ("stroke", Pattern.Lines { Pattern.lines_default with stroke = 20 });
          ("direction", Pattern.Lines { Pattern.lines_default with direction = 10 });
        ] );
      ( "blocks",
        Pattern.Blocks Pattern.blocks_default,
        [
          ("gap", Pattern.Blocks { Pattern.blocks_default with gap = 50 });
          ("filled", Pattern.Blocks { Pattern.blocks_default with filled = 95 });
          ("squareness", Pattern.Blocks { Pattern.blocks_default with squareness = 0 });
          ("radius", Pattern.Blocks { Pattern.blocks_default with radius = 40 });
        ] );
      ("clouds", Pattern.Clouds Pattern.clouds_default, [ ("size", Pattern.Clouds { Pattern.clouds_default with size = 100 }) ]);
      ( "lightning",
        Pattern.Lightning Pattern.lightning_default,
        [
          ("jaggedness", Pattern.Lightning { Pattern.lightning_default with jaggedness = 100 });
          ("thickness", Pattern.Lightning { Pattern.lightning_default with thickness = 24 });
          ("length", Pattern.Lightning { Pattern.lightning_default with length = 30 });
          ("direction", Pattern.Lightning { Pattern.lightning_default with direction = 45 });
        ] );
      ("circles", Pattern.Circles Pattern.circles_default, [ ("nothing", Pattern.Circles Pattern.circles_default) ]);
    ]

let prefix a b = List.filteri (fun k _ -> k < List.length a) b = a

let count_keeps_shapes () =
  List.iter
    (fun seed ->
      List.iter
        (fun size ->
          let clouds n = by_key (with_seed seed (with_art (Pattern.Clouds { Pattern.clouds_default with clouds = n; size }))) in
          List.iter
            (fun n ->
              Alcotest.(check bool) (Printf.sprintf "cloud %d keeps the clouds before it (size %d, seed %d)" (n + 1) size seed) true
                (prefix (clouds n) (clouds (n + 1))))
            (List.init 19 (fun k -> k + 1)))
        [ 25; 45; 100 ];
      let bolts n b = by_key (with_seed seed (with_art (Pattern.Lightning { Pattern.lightning_default with bolts = n; branches = b }))) in
      Alcotest.(check bool) (Printf.sprintf "more bolts keep the bolts (seed %d)" seed) true (prefix (bolts 2 4) (bolts 5 4));
      Alcotest.(check bool) (Printf.sprintf "more branches keep the branches (seed %d)" seed) true
        (List.for_all (fun shape -> List.mem shape (bolts 2 7)) (bolts 2 4));
      let blocks n = ds (with_seed seed (with_art (Pattern.Blocks { Pattern.blocks_default with blocks = n }))) in
      List.iter
        (fun n ->
          let before = blocks n and after = blocks (n + 1) in
          let kept = List.length (List.filter Fun.id (List.mapi (fun k d -> List.nth after k = d) before)) in
          Alcotest.(check (pair int int)) (Printf.sprintf "block %d is cut in two, the others stay (seed %d)" n seed) (n - 1, n + 1)
            (kept, List.length after))
        (List.init 79 (fun k -> k + 1));
      let cells half bar = by_key (with_seed seed (with_art (Pattern.Circles { Pattern.circles_default with half; bar }))) in
      let before = cells 80 6 and after = cells 79 7 in
      let changed = List.length (List.filter (fun shape -> not (List.mem shape after)) before) in
      Alcotest.(check bool) (Printf.sprintf "a small mix change redraws few cells (%d of %d, seed %d)" changed (List.length before) seed) true
        (changed * 20 < List.length before);
      let grid columns = by_key (with_seed seed (with_padding 0 (with_art (Pattern.Circles { Pattern.circles_default with columns; rows = 30 })))) in
      let kinds_of cells = List.map (fun (key, d) -> (key, (commands d |> List.map fst))) cells in
      Alcotest.(check bool) (Printf.sprintf "more columns keep the shape of each cell (seed %d)" seed) true
        (List.for_all (fun cell -> List.mem cell (kinds_of (grid 24))) (kinds_of (grid 20))))
    [ 1; 42; 2019; 999_999 ]

let gradual () =
  let points d = List.concat_map snd (commands d) in
  let moved a b = List.fold_left2 (fun m x y -> max m (abs (x - y))) 0 (points a) (points b) in
  let most a b = List.fold_left2 (fun m x y -> max m (moved x y)) 0 (ds a) (ds b) in
  List.iter
    (fun seed ->
      let lines amplitude = with_seed seed (with_art (Pattern.Lines { Pattern.lines_default with amplitude })) in
      Alcotest.(check bool) (Printf.sprintf "one step of curviness moves the lines a little (seed %d)" seed) true
        (most (lines 60) (lines 61) <= 6);
      let bolts jaggedness = with_seed seed (with_art (Pattern.Lightning { Pattern.lightning_default with jaggedness })) in
      Alcotest.(check bool) (Printf.sprintf "one step of jaggedness moves the bolts a little (seed %d)" seed) true
        (most (bolts 55) (bolts 56) <= 16);
      let blocks squareness = with_seed seed (with_art (Pattern.Blocks { Pattern.blocks_default with squareness })) in
      let rects gap filled =
        Array.to_list (Array.map painted (shapes (with_seed seed (with_art (Pattern.Blocks { Pattern.blocks_default with gap; filled; radius = 0 })))))
      in
      Alcotest.(check bool) (Printf.sprintf "gap and filled share do not move the cuts (seed %d)" seed) true
        (List.for_all2
           (fun (l, t, r, b) (l', t', r', b') -> l <= l' && t <= t' && r >= r' && b >= b' && l' - l <= 30 && r - r' <= 30 && t' - t <= 30 && b - b' <= 30)
           (rects 0 100) (rects 60 100));
      Alcotest.(check int) (Printf.sprintf "squareness keeps the number of blocks (seed %d)" seed) (shape_count (blocks 0)) (shape_count (blocks 100));
      let direction d = with_seed seed (with_art (Pattern.Lines { Pattern.lines_default with direction = d })) in
      Alcotest.(check (list string)) "the direction does not change the lines" (ds (direction 90)) (ds (direction 17));
      check_has (svg (direction 135)) "the direction turns the lines" {|<g transform="rotate(45 500 600)">|};
      Alcotest.(check bool) "direction 90 has no turn" false (contains (svg (direction 90)) "rotate("))
    [ 1; 42; 2019 ]

let every_cloud () =
  List.iter
    (fun (seed, size, padding) ->
      List.iter
        (fun n ->
          let s = with_padding padding (with_seed seed (with_art (Pattern.Clouds { Pattern.clouds_default with clouds = n; size }))) in
          Alcotest.(check int) (Printf.sprintf "%d clouds drawn (size %d, padding %d, seed %d)" n size padding seed) n (shape_count s))
        (List.init 20 (fun k -> k + 1)))
    [ (2019, 45, 80); (42, 100, 80); (7, 100, 200); (314, 10, 0); (1, 70, 160) ];
  Alcotest.(check bool) "every cloud is filled" true
    (Array.for_all (fun (x : Pattern.shape) -> x.paint = Pattern.Fill) (shapes (with_art (Pattern.Clouds Pattern.clouds_default))))

let lowest d = List.fold_left (fun m (_, ns) -> List.fold_left max m (List.filteri (fun k _ -> k mod 2 = 1) ns)) min_int (commands d)

let bolt_turn () =
  let bolts ?(seed = 2019) changes = with_seed seed (with_art (Pattern.Lightning (changes Pattern.lightning_default))) in
  let same = bolts Fun.id in
  Alcotest.(check bool) "direction 180 has no turn" false (contains (svg same) "rotate(");
  check_has (svg (bolts (fun l -> { l with direction = 270 }))) "the direction turns the bolts" {|<g transform="rotate(90 500 600)">|};
  check_has (svg (bolts (fun l -> { l with direction = 0 }))) "up" {|<g transform="rotate(-180 500 600)">|};
  List.iter2
    (fun seed digest ->
      Alcotest.(check string) (Printf.sprintf "the defaults draw the bolts of before (seed %d)" seed) digest
        (Digest.to_hex (Digest.string (String.concat "\n" (ds (with_padding 80 (bolts ~seed Fun.id)))))))
    [ 1; 42; 2019 ]
    [ "afeb5c86d339645fe0535ea81756efbf"; "f87b1e1c1017ccbdbf2def9f904663b0"; "9d002cb5b41726e20977812f894c2ae5" ];
  Alcotest.(check (list string)) "a half turn draws the same bolts upside down" (ds same) (ds (bolts (fun l -> { l with direction = 0 })));
  List.iter
    (fun seed ->
      let ends length =
        List.map (fun (x : Pattern.shape) -> lowest x.d) (Array.to_list (shapes (bolts ~seed (fun d -> { d with length; branches = 0 }))))
      in
      let top = 84 and height = 1032 in
      Alcotest.(check bool) (Printf.sprintf "full length ends in the lower quarter (seed %d)" seed) true
        (List.for_all (fun y -> y >= top + (height * 3 / 4) && y <= top + height) (ends 100));
      Alcotest.(check bool) (Printf.sprintf "length 40 ends by 40%% of the height (seed %d)" seed) true
        (List.for_all (fun y -> y >= top + (height * 40 / 100 * 3 / 4) && y <= top + (height * 40 / 100)) (ends 40)))
    [ 1; 42; 2019 ];
  List.iter
    (fun direction ->
      List.iter
        (fun padding ->
          let s = with_padding padding (bolts ~seed:42 (fun l -> { l with direction; branches = 12; jaggedness = 100 })) in
          let a = Float.of_int (direction - 180) *. Float.pi /. 180. in
          let turn x y =
            let x = Float.of_int x -. 500. and y = Float.of_int y -. 600. in
            ((x *. cos a) -. (y *. sin a) +. 500., (x *. sin a) +. (y *. cos a) +. 600.)
          in
          let low = Float.of_int padding -. 1. in
          let inside (x, y) = x >= low && y >= low && x <= 1001. -. low && y <= 1201. -. low in
          Array.iter
            (fun (x : Pattern.shape) ->
              List.iter
                (fun (_, ns) ->
                  let rec pairs = function x :: y :: rest -> (x, y) :: pairs rest | _ -> [] in
                  List.iter
                    (fun (px, py) ->
                      Alcotest.(check bool)
                        (Printf.sprintf "a turned bolt stays in the art area (direction %d, padding %d)" direction padding)
                        true (inside (turn px py)))
                    (pairs ns))
                (commands x.d))
            (shapes s))
        [ 0; 80; 200 ])
    [ 0; 30; 45; 90; 135; 200; 225; 270; 315; 359 ];
  Alcotest.(check bool) "sine" true
    (List.map Pattern.sine [ 0; 30; 90; 180; 270; 360; -90 ] = [ 0; 500; 1000; 0; -1000; 0; -1000 ])

let date () =
  Alcotest.(check (list string)) "date lines" [ "2019"; "March, 1"; "Friday" ] [ defaults.text.year; defaults.text.day; defaults.text.weekday ]

let normalize () =
  let s =
    Pattern.normalize ~defaults
      { defaults with layout = { seed = -4; padding = 999 }; colours = { defaults.colours with background = "red\"/>" } }
  in
  Alcotest.(check (pair int int)) "layout" (0, 200) (s.layout.seed, s.layout.padding);
  Alcotest.(check string) "bad colour" defaults.colours.background s.colours.background;
  let art a = Pattern.normal_art a in
  Alcotest.(check bool) "lines" true
    (art (Lines { lines = 0; amplitude = 500; waves = -1; stroke = 99; direction = 360 })
    = Lines { lines = 2; amplitude = 100; waves = 1; stroke = 24; direction = 359 });
  Alcotest.(check bool) "blocks" true
    (art (Blocks { blocks = 900; gap = -5; filled = 101; squareness = -1; radius = 61 })
    = Blocks { blocks = 80; gap = 0; filled = 100; squareness = 0; radius = 60 });
  Alcotest.(check bool) "circles" true
    (art
       (Circles
          {
            Pattern.fragments_default with
            columns = 1;
            rows = 99;
            half = -1;
            empty = 101;
            block = 0;
            bar = 100;
            merge = 101;
            round = -1;
            gap = 41;
            accent = 7;
            tint = "red";
          })
    = Circles
        {
          Pattern.fragments_default with
          columns = 2;
          rows = 30;
          half = 0;
          empty = 100;
          block = 0;
          bar = 100;
          merge = 100;
          round = 0;
          gap = 40;
          accent = 6;
          tint = Pattern.accent_default;
        });
  Alcotest.(check bool) "clouds" true (art (Clouds { clouds = 0; puffs = 1; size = 1 }) = Clouds { clouds = 1; puffs = 3; size = 10 });
  Alcotest.(check bool) "lightning" true
    (art (Lightning { bolts = 50; branches = -2; jaggedness = 300; thickness = 0; direction = 400; length = 5 })
    = Lightning { bolts = 8; branches = 0; jaggedness = 100; thickness = 1; direction = 359; length = 20 })

let fragments () =
  let art c = with_seed 3 (with_art (Pattern.Circles c)) in
  let tiles c = Array.to_list (shapes (art c)) in
  let fill c = List.filter (fun (x : Pattern.shape) -> x.paint = Pattern.Fill) (tiles c) in
  let base = { Pattern.fragments_default with columns = 5; rows = 6; accent = 0 } in
  Alcotest.(check int) "no long tiles: one tile per cell" 30 (List.length (fill { base with merge = 0 }));
  let long = List.length (fill { base with merge = 100 }) in
  Alcotest.(check bool) (Printf.sprintf "all long tiles: at most one cell alone per row (%d tiles)" long) true (long >= 15 && long <= 18);
  let square = { base with merge = 0; round = 0 } and round = { base with merge = 0; round = 100 } in
  Alcotest.(check bool) "round 0 draws no arc" true (List.for_all (fun (x : Pattern.shape) -> not (String.contains x.d 'A')) (fill square));
  Alcotest.(check bool) "round 100 draws four arcs per tile" true
    (List.for_all (fun (x : Pattern.shape) -> List.length (List.filter (fun (c, _) -> c = 'A') (commands x.d)) = 4) (fill round));
  let accents c = List.filter (fun (x : Pattern.shape) -> x.paint <> Pattern.Fill) (tiles c) in
  Alcotest.(check int) "no accent" 0 (List.length (accents base));
  Alcotest.(check bool) "an accent is a tinted circle in place of a tile" true
    (match accents { base with accent = 1; tint = "#0066ff" } with
    | [ { paint = Pattern.Tint "#0066ff"; d; _ } ] -> List.map fst (commands d) = [ 'M'; 'A'; 'A'; 'z' ]
    | _ -> false);
  Alcotest.(check int) "an accent replaces its tile, it does not add one" 30
    (List.length (tiles { base with merge = 0; accent = 6 }));
  Alcotest.(check bool) "more accents keep the accents" true
    (List.for_all (fun x -> List.mem x (accents { base with accent = 6 })) (accents { base with accent = 3 }));
  let svg = svg (art { base with accent = 1; tint = "#0066ff" }) in
  check_has svg "the accent is filled with its colour" {|fill="#0066ff"|}

let cut () =
  let title t = (Pattern.normal_text { defaults.text with title = t }).title in
  Alcotest.(check string) "40 ASCII letters stay" (String.make 40 'a') (title (String.make 40 'a'));
  Alcotest.(check string) "41 ASCII letters lose one" (String.make 40 'a') (title (String.make 41 'a'));
  Alcotest.(check string) "a cut never splits a character" (String.make 39 'a') (title (String.make 39 'a' ^ "\xc3\xa9"));
  Alcotest.(check string) "a two-byte character that fits stays" (String.make 38 'a' ^ "\xc3\xa9") (title (String.make 38 'a' ^ "\xc3\xa9b"))

let escaped () =
  let svg = svg { defaults with text = { defaults.text with subtitle = "<b>&" } } in
  check_has svg "escaped text" "&lt;b&gt;&amp;";
  Alcotest.(check bool) "no raw tag" false (contains svg "<b>")

let links () =
  let href s = Routes.href (Link.route ~defaults s) in
  Alcotest.(check string) "defaults give no query" "/" (href defaults);
  Alcotest.(check string) "another kind with its defaults" "/?kind=blocks" (href (with_art (Pattern.fresh Blocks)));
  Alcotest.(check string) "a changed parameter" "/?kind=clouds&padding=20&puffs=9"
    (href { (with_art (Clouds { Pattern.clouds_default with puffs = 9 })) with layout = { defaults.layout with padding = 20 } });
  Alcotest.(check string) "the direction of the lines" "/?direction=45"
    (href (with_art (Lines { Pattern.lines_default with direction = 45 })));
  Alcotest.(check string) "circles and the corner radius" "/?kind=circles&columns=9&bar=20"
    (href (with_art (Circles { Pattern.circles_default with columns = 9; bar = 20 })));
  Alcotest.(check string) "fragments with their defaults" "/?kind=circles&style=fragments"
    (href (with_art (Circles Pattern.fragments_default)));
  Alcotest.(check string) "a fragments parameter" "/?kind=circles&gap=20&style=fragments&accent=3&tint=0066ff"
    (href (with_art (Circles { Pattern.fragments_default with gap = 20; accent = 3; tint = "#0066ff" })));
  List.iter
    (fun art ->
      let s = with_seed 5 (with_art art) in
      Alcotest.(check bool) "fragments come back from the link" true (Link.settings ~defaults (Link.route ~defaults s) = s))
    [
      Pattern.Circles Pattern.fragments_default;
      Pattern.Circles { Pattern.fragments_default with columns = 7; merge = 0; round = 100; tint = "#0066ff" };
      Pattern.Circles { Pattern.circles_default with columns = 9 };
    ];
  Alcotest.(check string) "the direction and length of the bolts" "/?kind=lightning&direction=90&length=60"
    (href (with_art (Lightning { Pattern.lightning_default with direction = 90; length = 60 })));
  Alcotest.(check string) "the corner radius" "/?kind=blocks&radius=12" (href (with_art (Blocks { Pattern.blocks_default with radius = 12 })));
  Alcotest.(check string) "a parameter of the default kind" "/?seed=42&waves=5"
    (href (with_seed 42 (with_art (Lines { Pattern.lines_default with waves = 5 }))));
  let light = { (with_seed 42 defaults) with colours = Pattern.light } in
  Alcotest.(check string) "svg link" "/poster.svg?seed=42&bg=f4f4f4&fg=333333" (Link.svg (Link.route ~defaults light));
  Alcotest.(check bool) "an unknown kind is the default kind" true
    (match Routes.find `GET [] [ ("kind", "spirals"); ("waves", "5") ] with
    | Yuka.Router.Found route -> (Link.settings ~defaults route).art = Lines { Pattern.lines_default with waves = 5 }
    | _ -> false);
  Alcotest.(check bool) "parameters of another kind are ignored" true
    (match Routes.find `GET [] [ ("kind", "blocks"); ("waves", "5"); ("gap", "30") ] with
    | Yuka.Router.Found route -> (Link.settings ~defaults route).art = Blocks { Pattern.blocks_default with gap = 30 }
    | _ -> false);
  List.iter
    (fun (name, (s : Pattern.settings)) ->
      Alcotest.(check bool) (name ^ " round trip") true (Link.settings ~defaults (Link.route s) = s);
      Alcotest.(check bool) (name ^ " round trip with defaults") true (Link.settings ~defaults (Link.route ~defaults s) = s))
    (Pattern.presets @ kinds)

let amp href = String.concat "&amp;" (String.split_on_char '&' href)

let download () =
  let link = Link.download ~defaults defaults in
  Alcotest.(check bool) "the download link names the date" true
    (String.starts_with ~prefix:"/poster.svg?year=2019&" link && contains link "day=" && contains link "weekday=Friday");
  let _, body = get link in
  check_has body "a later day draws the date of the page: year" ">2019</text>";
  check_has body "day" ">March, 1</text>";
  check_has body "weekday" ">Friday</text>";
  Alcotest.(check bool) "the page URL keeps the date out" false (contains (Routes.href (Link.route ~defaults defaults)) "year")

let page () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_has html "poster" {|class="poster"|};
  check_has html "settings panel" {|aria-label="Poster settings"|};
  check_has html "text panel" {|aria-label="Poster text"|};
  check_has html "shuffle" ">Shuffle</button>";
  Alcotest.(check bool) "Shuffle is in the section of the kind, after its settings" true
    (let at needle = Option.get (find html needle) in
     at {|<h2>Lines</h2>|} < at ">Shuffle</button>" && at {|id="padding"|} < at {|<h2>Lines</h2>|});
  Alcotest.(check int) "an icon on each kind" (List.length Pattern.Kind.all) (count html {|class="kind-icon"|});
  Alcotest.(check bool) "no gallery link in the playground" false (contains html "Browse the gallery");
  Alcotest.(check bool) "no seed input" false (contains html {|id="seed"|});
  check_has html "padding slider" {|id="padding"|};
  check_has html "lines slider" {|id="waves"|};
  check_has html "direction dial" {|id="direction" class="dial" role="slider" tabindex="0"|};
  check_has html "the dial names its value" {|aria-valuenow="90"|};
  Alcotest.(check bool) "no slider of another kind" false (contains html {|id="gap"|});
  check_has html "colour input" {|type="color"|};
  check_has html "download svg link with the date" ({|href="|} ^ amp (Link.download ~defaults:(Pages.today ()) (Pages.today ())) ^ {|"|});
  Alcotest.(check bool) "the date is in the link" true (contains html {|href="/poster.svg?year=|});
  check_has html "download png" ">Download PNG</button>"

let page_with_params () =
  let status, html = get "/?kind=blocks&seed=42&gap=30&padding=20&bg=f4f4f4&fg=333333&title=Hello" in
  Alcotest.(check int) "status" 200 status;
  let wanted = { (with_art (Blocks { Pattern.blocks_default with gap = 30 })) with layout = { seed = 42; padding = 20 } } in
  Alcotest.(check bool) "every shape of the URL poster" true (List.for_all (fun d -> contains html ({|d="|} ^ d ^ {|"|})) (ds wanted));
  check_has html "blocks sliders" {|id="squareness"|};
  Alcotest.(check bool) "no lines slider" false (contains html {|id="waves"|});
  check_has html "light background" {|fill="#f4f4f4"|};
  check_has html "title" ">HELLO</text>";
  check_has html "svg link keeps the settings"
    {|href="/poster.svg?kind=blocks&amp;seed=42&amp;padding=20&amp;gap=30&amp;bg=f4f4f4&amp;fg=333333&amp;title=Hello&amp;year=|}

let svg_route () =
  let response = Dream.test handler (Dream.request ~target:"/poster.svg?kind=lightning&seed=42&bolts=3&bg=f4f4f4" "") in
  let body = Lwt_main.run (Dream.body response) in
  Alcotest.(check int) "status" 200 (Dream.status_to_int (Dream.status response));
  Alcotest.(check (option string)) "type" (Some "image/svg+xml; charset=utf-8") (Dream.header response "content-type");
  Alcotest.(check (option string)) "cache" (Some "public, max-age=3600") (Dream.header response "cache-control");
  check_has body "an SVG file" {|<svg xmlns="http://www.w3.org/2000/svg"|};
  let wanted =
    { (with_art (Lightning { Pattern.lightning_default with bolts = 3 })) with colours = { defaults.colours with background = "#f4f4f4" } }
    |> with_seed 42
  in
  Alcotest.(check bool) "the shapes of the query" true (List.for_all (fun d -> contains body ({|d="|} ^ d ^ {|"|})) (ds wanted));
  check_has body "light" {|fill="#f4f4f4"|};
  Alcotest.(check bool) "no island markers" false (contains body "yuka")

let gallery () =
  let status, html = get "/gallery" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check int) "one poster per preset" (List.length Pattern.presets) (count html {|<svg xmlns="http://www.w3.org/2000/svg" class="poster"|});
  Alcotest.(check (list string)) "two presets per kind, and Fragments"
    (List.concat_map (fun k -> [ Pattern.Kind.name k; Pattern.Kind.name k ]) Pattern.Kind.all @ [ "circles" ])
    (List.map (fun (_, (s : Pattern.settings)) -> Pattern.Kind.name (Pattern.kind s.art)) Pattern.presets);
  Alcotest.(check bool) "no module script" false (contains html {|<script type="module"|});
  List.iter
    (fun (name, s) ->
      check_has html (name ^ " links to the playground") ({|href="|} ^ String.concat "&amp;" (String.split_on_char '&' (Routes.href (Link.route s))) ^ {|"|}))
    Pattern.presets;
  Alcotest.(check (list string)) "prerender seeds" [ "/gallery" ] (Yuka.Server.Prerender.seeds Yuka_routes.app);
  let out = Filename.temp_dir "posters" "prerender" in
  Alcotest.(check (result unit string)) "prerender" (Ok ()) (Lwt_main.run (Yuka_dream.prerender ~out config Yuka_routes.app));
  let file = Filename.concat out (Option.get (Yuka.Server.Prerender.file "/gallery")) in
  let written = In_channel.with_open_bin file In_channel.input_all in
  Alcotest.(check int) "the prerendered gallery has the posters" (List.length Pattern.presets)
    (count written {|<svg xmlns="http://www.w3.org/2000/svg" class="poster"|})

let () =
  Alcotest.run "posters"
    [
      ( "generator",
        [
          Alcotest.test_case "same seed" `Quick same_seed;
          Alcotest.test_case "keys and counts" `Quick keys;
          Alcotest.test_case "lines do not cross themselves" `Quick lines_do_not_cross_themselves;
          Alcotest.test_case "shapes stay inside the padding" `Quick inside;
          Alcotest.test_case "block count at the extremes" `Quick block_count;
          Alcotest.test_case "settings keep the number of shapes" `Quick keeps_count;
          Alcotest.test_case "counts keep the shapes" `Quick count_keeps_shapes;
          Alcotest.test_case "settings move shapes gradually" `Quick gradual;
          Alcotest.test_case "every cloud is drawn" `Quick every_cloud;
          Alcotest.test_case "the direction and length of the bolts" `Quick bolt_turn;
          Alcotest.test_case "a gap of 1" `Quick gap_of_one;
          Alcotest.test_case "date lines" `Quick date;
          Alcotest.test_case "fragments" `Quick fragments;
          Alcotest.test_case "cut at a character" `Quick cut;
          Alcotest.test_case "normalize" `Quick normalize;
          Alcotest.test_case "escaped text" `Quick escaped;
          Alcotest.test_case "links" `Quick links;
        ] );
      ( "pages",
        [
          Alcotest.test_case "download link" `Quick download;
          Alcotest.test_case "playground" `Quick page;
          Alcotest.test_case "settings in the URL" `Quick page_with_params;
          Alcotest.test_case "poster.svg" `Quick svg_route;
          Alcotest.test_case "gallery" `Quick gallery;
        ] );
    ]
