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
let shapes (s : Pattern.settings) = Pattern.shapes s.layout s.art
let ds s = Array.to_list (Array.map (fun (x : Pattern.shape) -> x.d) (shapes s))
let with_art art = { defaults with art }
let with_seed seed (s : Pattern.settings) = { s with layout = { s.layout with seed } }
let kinds = List.map (fun k -> (Pattern.Kind.name k, with_art (Pattern.fresh k))) Pattern.Kind.all

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
      let all = shapes s in
      Alcotest.(check (list int)) (name ^ ": keys are the shape indexes") (List.init (Array.length all) Fun.id)
        (Array.to_list (Array.map (fun (x : Pattern.shape) -> x.index) all)))
    kinds;
  Alcotest.(check int) "one shape per line" 30 (Array.length (shapes (with_art (Lines { Pattern.lines_default with lines = 30 }))));
  Alcotest.(check int) "one shape per block" 20 (Array.length (shapes (with_art (Blocks { Pattern.blocks_default with blocks = 20 }))));
  Alcotest.(check int) "one shape per bolt and branch" 15
    (Array.length (shapes (with_art (Lightning { Pattern.lightning_default with bolts = 3; branches = 4 }))))

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
          let s = { (with_seed seed (with_art (Lines { lines; amplitude; waves; stroke = 4 }))) with layout = { seed; padding } } in
          List.iter
            (fun d -> Alcotest.(check bool) (Printf.sprintf "x grows along %s" (String.sub d 0 20)) true (not_crossing d))
            (ds s))
        [ 0; 1; 42; 2019; 999_999 ])
    [ (22, 60, 3, 80); (2, 100, 10, 200); (60, 100, 1, 0); (10, 0, 6, 40) ]

let inside () =
  let in_box padding d =
    List.for_all
      (fun (c, ns) ->
        let rec pairs = function
          | x :: y :: rest -> x >= padding && x <= Pattern.width - padding && y >= padding && y <= Pattern.art_bottom - padding && pairs rest
          | [] -> true
          | [ _ ] -> false
        in
        match c with 'H' -> List.for_all (fun x -> x >= padding && x <= Pattern.width - padding) ns | 'V' -> true | 'z' -> true | _ -> pairs ns)
      (commands d)
  in
  List.iter
    (fun padding ->
      List.iter
        (fun art ->
          let s = { (with_art art) with layout = { seed = 3; padding } } in
          List.iter (fun d -> Alcotest.(check bool) (Printf.sprintf "inside padding %d: %s" padding (String.sub d 0 12)) true (in_box padding d)) (ds s))
        [ Pattern.Lines Pattern.lines_default; Pattern.Blocks { Pattern.blocks_default with gap = 0 }; Pattern.Lightning Pattern.lightning_default ])
    [ 0; 80; 200 ];
  let wide = ds { (with_art (Pattern.Blocks Pattern.blocks_default)) with layout = { seed = 3; padding = 0 } } in
  let narrow = ds { (with_art (Pattern.Blocks Pattern.blocks_default)) with layout = { seed = 3; padding = 150 } } in
  Alcotest.(check bool) "padding moves the art" false (wide = narrow)

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
    (art (Lines { lines = 0; amplitude = 500; waves = -1; stroke = 99 }) = Lines { lines = 2; amplitude = 100; waves = 1; stroke = 24 });
  Alcotest.(check bool) "blocks" true
    (art (Blocks { blocks = 900; gap = -5; filled = 101; squareness = -1 }) = Blocks { blocks = 80; gap = 0; filled = 100; squareness = 0 });
  Alcotest.(check bool) "clouds" true
    (art (Clouds { clouds = 0; puffs = 1; size = 1; solid = 200 }) = Clouds { clouds = 1; puffs = 3; size = 10; solid = 100 });
  Alcotest.(check bool) "lightning" true
    (art (Lightning { bolts = 50; branches = -2; jaggedness = 300; thickness = 0 })
    = Lightning { bolts = 8; branches = 0; jaggedness = 100; thickness = 1 })

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

let page () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_has html "poster" {|class="poster"|};
  check_has html "settings panel" {|aria-label="Poster settings"|};
  check_has html "text panel" {|aria-label="Poster text"|};
  check_has html "shuffle" ">Shuffle</button>";
  Alcotest.(check bool) "no seed input" false (contains html {|id="seed"|});
  check_has html "padding slider" {|id="padding"|};
  check_has html "lines slider" {|id="waves"|};
  Alcotest.(check bool) "no slider of another kind" false (contains html {|id="gap"|});
  check_has html "colour input" {|type="color"|};
  check_has html "download svg link" {|href="/poster.svg"|};
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
    {|href="/poster.svg?kind=blocks&amp;seed=42&amp;padding=20&amp;gap=30&amp;bg=f4f4f4&amp;fg=333333&amp;title=Hello"|}

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
  Alcotest.(check (list string)) "two presets per kind"
    (List.concat_map (fun k -> [ Pattern.Kind.name k; Pattern.Kind.name k ]) Pattern.Kind.all)
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
