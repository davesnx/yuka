open Genart_app
open Genart_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:(Filename.temp_dir "genart" "js") ~entry:"demo/genart/client/main.js" ~manifest:"{}"
            ~packages:[] ~digest:""))
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

let check_count html name expected needle = Alcotest.(check int) name expected (count html needle)
let settings = Sketch.default
let lines s = Sketch.segments s (Sketch.fresh ())

let home () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_count html "the island" 1 {|data-name="Genart_shared.Studio"|};
  check_count html "a line per dot" 400 "<line ";
  check_count html "the svg" 1 {|<svg id="sketch"|};
  check_count html "the default stroke" 1 {|stroke-width="10"|};
  check_count html "every palette and Mixed" (Array.length Sketch.palettes + 1) {|class="swatch"|}

let params () =
  let _, html = get "/?grid=3&stroke=24&seed=7&palette=2" in
  check_count html "a line per dot" 9 "<line ";
  check_count html "the stroke" 1 {|stroke-width="24"|};
  let _, html = get "/?grid=500&stroke=-3&palette=99" in
  check_count html "the grid is clamped" 1600 "<line ";
  check_count html "the stroke is clamped" 1 {|stroke-width="1"|}

let same_seed () =
  Alcotest.(check bool) "same settings, same lines" true (lines settings = lines settings);
  Alcotest.(check bool) "another seed, other lines" false (lines settings = lines { settings with seed = 5 });
  let _, a = get "/?seed=12" and _, b = get "/?seed=12" in
  Alcotest.(check string) "same page" a b

let neighbours () =
  let step = (Sketch.size - (2 * Sketch.margin)) / (settings.grid - 1) in
  let kinds = Array.make 4 0 in
  Array.iter
    (fun (s : Sketch.segment) ->
      let dx = s.x2 - s.x1 and dy = s.y2 - s.y1 in
      let near d = d = 0 || abs (d - step) <= 1 in
      Alcotest.(check bool) "to itself or a neighbour" true (near dx && near dy);
      let k = (if dx > 0 then 1 else 0) + if dy > 0 then 2 else 0 in
      kinds.(k) <- kinds.(k) + 1;
      Alcotest.(check bool) "alpha" true (s.alpha >= 0 && s.alpha < 1000))
    (lines settings);
  Array.iteri (fun k n -> Alcotest.(check bool) (Printf.sprintf "direction %d is used" k) true (n > 40)) kinds

let palette () =
  let _, colors = Sketch.palettes.(3) in
  Array.iter
    (fun (s : Sketch.segment) -> Alcotest.(check bool) "colour of the palette" true (Array.mem s.color colors))
    (lines { settings with palette = Some 3 })

let larger_grid () =
  let small = lines { settings with grid = 10 } and large = lines { settings with grid = 11 } in
  let find key = Array.find_opt (fun (s : Sketch.segment) -> s.key = key) large in
  Array.iter
    (fun (s : Sketch.segment) ->
      match find s.key with
      | None -> Alcotest.fail ("missing " ^ s.key)
      | Some t ->
          Alcotest.(check string) "same colour" s.color t.color;
          Alcotest.(check int) "same alpha" s.alpha t.alpha;
          Alcotest.(check bool) "same direction" true
            (compare (s.x2 - s.x1) 0 = compare (t.x2 - t.x1) 0 && compare (s.y2 - s.y1) 0 = compare (t.y2 - t.y1) 0))
    small

let drift () =
  let before = Sketch.fresh () in
  let after = Sketch.drift ~seed:settings.seed ~grid:settings.grid ~tick:1 before in
  Alcotest.(check bool) "keeps the input" true (Array.for_all (( = ) 0) before);
  let bumped = Array.fold_left ( + ) 0 after in
  Alcotest.(check int) "one line in 60" (400 / 60) bumped;
  let a = lines settings and b = Sketch.segments settings after in
  let changed = ref 0 in
  Array.iteri
    (fun i (s : Sketch.segment) ->
      let t = b.(i) in
      Alcotest.(check int) "the drift keeps the alpha" s.alpha t.alpha;
      if s <> t then incr changed)
    a;
  Alcotest.(check bool) "at most the drawn lines change" true (!changed <= bumped)

let opacity () =
  Alcotest.(check string) "0" "0.000" (Sketch.opacity 0);
  Alcotest.(check string) "42" "0.042" (Sketch.opacity 42);
  Alcotest.(check string) "999" "0.999" (Sketch.opacity 999)

let not_found () =
  let status, _ = get "/nope" in
  Alcotest.(check int) "status" 404 status

let () =
  Alcotest.run "genart"
    [
      ( "page",
        [
          Alcotest.test_case "home" `Quick home;
          Alcotest.test_case "search params" `Quick params;
          Alcotest.test_case "not found" `Quick not_found;
        ] );
      ( "sketch",
        [
          Alcotest.test_case "same seed" `Quick same_seed;
          Alcotest.test_case "neighbours" `Quick neighbours;
          Alcotest.test_case "palette" `Quick palette;
          Alcotest.test_case "larger grid" `Quick larger_grid;
          Alcotest.test_case "drift" `Quick drift;
          Alcotest.test_case "opacity" `Quick opacity;
        ] );
    ]
