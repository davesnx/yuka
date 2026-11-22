open Posters_app
open Posters_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/posters/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
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
let check_has html name needle = Alcotest.(check bool) name true (contains html needle)
let defaults = Poster.defaults ~year:2019 ~month:2 ~day:1 ~weekday:5

let same_seed () =
  Alcotest.(check string) "same SVG" (Poster.svg defaults) (Poster.svg (Poster.defaults ~year:2019 ~month:2 ~day:1 ~weekday:5));
  Alcotest.(check string) "first cells of seed 2019" "M0 76L0 0A38 38 0 0 1 0 76zM153 0L153 76A38 38 0 0 1 153 0zM230 76L153 76A38 38 " (String.sub (Poster.grid defaults) 0 80)

let different_seeds () =
  Alcotest.(check bool) "different grids" false (String.equal (Poster.grid defaults) (Poster.grid { defaults with seed = 7 }));
  Alcotest.(check bool) "shuffle changes the seed" true (Poster.shuffle defaults.seed <> defaults.seed)

let cell_count () =
  List.iter
    (fun (columns, rows) ->
      Alcotest.(check int)
        (Printf.sprintf "%d x %d" columns rows)
        (columns * rows)
        (List.length (Poster.cells { defaults with columns; rows })))
    [ (13, 15); (4, 4); (24, 30); (7, 11) ]

let mix () =
  let only weights = Poster.cells (weights { defaults with half = 0; empty = 0; block = 0; bar = 0 }) in
  Alcotest.(check bool) "all empty" true (List.for_all (( = ) Poster.Empty) (only (fun s -> { s with empty = 1 })));
  Alcotest.(check bool) "all blocks" true (List.for_all (( = ) Poster.Block) (only (fun s -> { s with block = 1 })));
  Alcotest.(check bool) "no weight gives empty cells" true (List.for_all (( = ) Poster.Empty) (only Fun.id))

let date () =
  Alcotest.(check (list string)) "date lines" [ "2019"; "March, 1"; "Friday" ] [ defaults.year; defaults.day; defaults.weekday ]

let normalize () =
  let s = Poster.normalize ~defaults { defaults with columns = 99; rows = 0; background = "red\"/>"; seed = -4 } in
  Alcotest.(check int) "columns" 24 s.columns;
  Alcotest.(check int) "rows" 4 s.rows;
  Alcotest.(check int) "seed" 0 s.seed;
  Alcotest.(check string) "bad colour" defaults.background s.background

let escaped () =
  let svg = Poster.svg { defaults with subtitle = "<b>&\"" } in
  check_has svg "escaped text" "&lt;b&gt;&amp;&quot;";
  Alcotest.(check bool) "no raw tag" false (contains svg "<b>")

let page () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_has html "poster" {|class="poster"|};
  check_has html "grid" (Poster.grid defaults);
  check_has html "settings panel" {|aria-label="Poster settings"|};
  check_has html "shuffle" ">Shuffle</button>";
  check_has html "columns slider" {|id="columns"|};
  check_has html "colour input" {|type="color"|};
  check_has html "download svg" ">Download SVG</button>";
  check_has html "download png" ">Download PNG</button>"

let page_with_params () =
  let status, html = get "/?seed=42&columns=9&rows=12&bg=f4f4f4&fg=333333&title=Hello" in
  Alcotest.(check int) "status" 200 status;
  let wanted = { defaults with seed = 42; columns = 9; rows = 12 } in
  check_has html "the poster of the URL" (Poster.grid wanted);
  check_has html "light background" {|fill="#f4f4f4"|};
  check_has html "title" ">HELLO</text>";
  let _, bad = get "/?columns=500&bg=%22%3E" in
  check_has bad "columns clamped" (Poster.grid { defaults with columns = 24 })

let () =
  Alcotest.run "posters"
    [
      ( "generator",
        [
          Alcotest.test_case "same seed" `Quick same_seed;
          Alcotest.test_case "different seeds" `Quick different_seeds;
          Alcotest.test_case "cell count" `Quick cell_count;
          Alcotest.test_case "shape mix" `Quick mix;
          Alcotest.test_case "date lines" `Quick date;
          Alcotest.test_case "normalize" `Quick normalize;
          Alcotest.test_case "escaped text" `Quick escaped;
        ] );
      ("pages", [ Alcotest.test_case "playground" `Quick page; Alcotest.test_case "settings in the URL" `Quick page_with_params ]);
    ]
