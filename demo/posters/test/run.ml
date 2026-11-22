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
let check_has html name needle = Alcotest.(check bool) name true (contains html needle)
let defaults = Pattern.defaults ~year:2019 ~month:2 ~day:1 ~weekday:5
let svg (s : Pattern.settings) = Yuka.Server.to_string (fun () -> Poster.still s)
let grid_of s = String.concat "" (List.map (fun (c : Pattern.cell) -> {|<path d="|} ^ c.d ^ {|"></path>|}) (Array.to_list (Pattern.cells s.Pattern.grid s.mix)))
let with_grid (s : Pattern.settings) f = { s with grid = f s.grid }

let same_seed () =
  Alcotest.(check string) "same SVG" (svg defaults) (svg (Pattern.defaults ~year:2019 ~month:2 ~day:1 ~weekday:5));
  let first = (Pattern.cells defaults.grid defaults.mix).(0) in
  Alcotest.(check (pair int string)) "first cell of seed 2019" (0, "M0 76L0 0A38 38 0 0 1 0 76z") (first.index, first.d)

let different_seeds () =
  Alcotest.(check bool) "different grids" false (String.equal (svg defaults) (svg (with_grid defaults (fun g -> { g with seed = 7 }))));
  Alcotest.(check bool) "shuffle changes the seed" true (Pattern.shuffle defaults.grid.seed <> defaults.grid.seed)

let cell_count () =
  List.iter
    (fun (columns, rows) ->
      let grid = { defaults.grid with columns; rows } in
      Alcotest.(check int) (Printf.sprintf "%d x %d shapes" columns rows) (columns * rows) (List.length (Pattern.shapes grid defaults.mix));
      let full = Pattern.cells grid { half = 1; empty = 0; block = 0; bar = 0 } in
      Alcotest.(check int) (Printf.sprintf "%d x %d cells" columns rows) (columns * rows) (Array.length full);
      Alcotest.(check (list int)) "keys are the cell indexes" (List.init (columns * rows) Fun.id)
        (Array.to_list (Array.map (fun (c : Pattern.cell) -> c.index) full)))
    [ (13, 15); (4, 4); (24, 30); (7, 11) ]

let mix () =
  let only weights = Pattern.shapes defaults.grid (weights { Pattern.half = 0; empty = 0; block = 0; bar = 0 }) in
  Alcotest.(check bool) "all empty" true (List.for_all (( = ) Pattern.Empty) (only (fun m -> { m with empty = 1 })));
  Alcotest.(check bool) "all blocks" true (List.for_all (( = ) Pattern.Block) (only (fun m -> { m with block = 1 })));
  Alcotest.(check bool) "no weight gives empty cells" true (List.for_all (( = ) Pattern.Empty) (only Fun.id));
  Alcotest.(check int) "empty cells have no path" 0 (Array.length (Pattern.cells defaults.grid { half = 0; empty = 1; block = 0; bar = 0 }))

let date () =
  Alcotest.(check (list string)) "date lines" [ "2019"; "March, 1"; "Friday" ] [ defaults.text.year; defaults.text.day; defaults.text.weekday ]

let normalize () =
  let s =
    Pattern.normalize ~defaults
      { defaults with grid = { columns = 99; rows = 0; seed = -4 }; colours = { defaults.colours with background = "red\"/>" } }
  in
  Alcotest.(check (list int)) "grid" [ 0; 24; 4 ] [ s.grid.seed; s.grid.columns; s.grid.rows ];
  Alcotest.(check string) "bad colour" defaults.colours.background s.colours.background

let escaped () =
  let svg = svg { defaults with text = { defaults.text with subtitle = "<b>&" } } in
  check_has svg "escaped text" "&lt;b&gt;&amp;";
  Alcotest.(check bool) "no raw tag" false (contains svg "<b>")

let links () =
  Alcotest.(check string) "defaults give no query" "/" (Routes.href (Link.route ~defaults defaults));
  let light = { (with_grid defaults (fun g -> { g with seed = 42 })) with colours = Pattern.light } in
  Alcotest.(check string) "svg link" "/poster.svg?seed=42&bg=f4f4f4&fg=333333" (Link.svg (Link.route ~defaults light));
  List.iter
    (fun (name, (s : Pattern.settings)) ->
      Alcotest.(check bool) (name ^ " round trip") true (Link.settings ~defaults (Link.route s) = s))
    Pattern.presets

let page () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_has html "poster" {|class="poster"|};
  check_has html "settings panel" {|aria-label="Poster settings"|};
  check_has html "shuffle" ">Shuffle</button>";
  check_has html "columns slider" {|id="columns"|};
  check_has html "colour input" {|type="color"|};
  check_has html "download svg link" {|href="/poster.svg"|};
  check_has html "download png" ">Download PNG</button>"

let page_with_params () =
  let status, html = get "/?seed=42&columns=9&rows=12&bg=f4f4f4&fg=333333&title=Hello" in
  Alcotest.(check int) "status" 200 status;
  let wanted = with_grid defaults (fun _ -> { seed = 42; columns = 9; rows = 12 }) in
  Alcotest.(check bool) "every cell of the URL poster" true
    (Array.for_all (fun (c : Pattern.cell) -> contains html ({|d="|} ^ c.d ^ {|"|})) (Pattern.cells wanted.grid wanted.mix));
  check_has html "light background" {|fill="#f4f4f4"|};
  check_has html "title" ">HELLO</text>";
  check_has html "svg link keeps the settings" {|href="/poster.svg?seed=42&amp;columns=9&amp;rows=12&amp;bg=f4f4f4&amp;fg=333333&amp;title=Hello"|}

let svg_route () =
  let response = Dream.test handler (Dream.request ~target:"/poster.svg?seed=42&columns=9&bg=f4f4f4" "") in
  let body = Lwt_main.run (Dream.body response) in
  Alcotest.(check int) "status" 200 (Dream.status_to_int (Dream.status response));
  Alcotest.(check (option string)) "type" (Some "image/svg+xml; charset=utf-8") (Dream.header response "content-type");
  Alcotest.(check (option string)) "cache" (Some "public, max-age=3600") (Dream.header response "cache-control");
  check_has body "an SVG file" {|<svg xmlns="http://www.w3.org/2000/svg"|};
  let wanted = with_grid defaults (fun g -> { g with seed = 42; columns = 9 }) in
  check_has body "the cells of the query" (grid_of wanted);
  check_has body "light" {|fill="#f4f4f4"|};
  Alcotest.(check bool) "no island markers" false (contains body "yuka")

let gallery () =
  let status, html = get "/gallery" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check int) "one poster per preset" (List.length Pattern.presets) (count html {|<svg xmlns="http://www.w3.org/2000/svg" class="poster"|});
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
          Alcotest.test_case "different seeds" `Quick different_seeds;
          Alcotest.test_case "cell count" `Quick cell_count;
          Alcotest.test_case "shape mix" `Quick mix;
          Alcotest.test_case "date lines" `Quick date;
          Alcotest.test_case "normalize" `Quick normalize;
          Alcotest.test_case "escaped text" `Quick escaped;
          Alcotest.test_case "links" `Quick links;
        ] );
      ( "pages",
        [
          Alcotest.test_case "playground" `Quick page;
          Alcotest.test_case "settings in the URL" `Quick page_with_params;
          Alcotest.test_case "poster.svg" `Quick svg_route;
          Alcotest.test_case "gallery" `Quick gallery;
        ] );
    ]
