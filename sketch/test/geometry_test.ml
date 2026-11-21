open Sketch_shared

let close ?(eps = 1e-6) a b = Float.abs (a -. b) <= eps
let check_float ?(eps = 1e-6) msg expected actual =
  if not (close ~eps expected actual) then Alcotest.failf "%s: expected %g, got %g" msg expected actual

let check_vec ?(eps = 1e-6) msg (e : Vec.t) (a : Vec.t) =
  check_float ~eps (msg ^ " x") e.x a.x;
  check_float ~eps (msg ^ " y") e.y a.y

let metrics = { Shape.width = (fun ~font text -> font *. 0.5 *. float_of_int (String.length text)); ascent = 0.8; descent = 0.2 }
let style = Shape.default_style
let box x y w h = { Geom.Box.x; y; w; h }

let num () =
  Alcotest.(check string) "integer" "12" (Num.to_string 12.);
  Alcotest.(check string) "negative half" "-3.5" (Num.to_string (-3.5));
  Alcotest.(check string) "rounds to two decimals" "0.33" (Num.to_string (1. /. 3.));
  Alcotest.(check string) "leading zero in decimals" "1.05" (Num.to_string 1.05);
  Alcotest.(check string) "tiny is zero" "0" (Num.to_string 0.001);
  Alcotest.(check string) "six digits" "0.333333" (Num.to_string ~digits:6 (1. /. 3.));
  Alcotest.(check string) "carry" "2" (Num.to_string 1.999);
  Alcotest.(check string) "not finite" "0" (Num.to_string Float.nan)

let freehand_points n f = Array.init n (fun i -> f (float_of_int i))

let outline_width (outline : Vec.t array) (at : Vec.t) =
  let best = ref Float.infinity in
  Array.iter (fun p -> best := Float.min !best (Vec.dist p at)) outline;
  !best

let freehand () =
  let opts = Freehand.options ~size:8. ~simulate:true ~complete:true in
  let line = freehand_points 60 (fun i -> { Freehand.x = i *. 4.; y = 0.; pressure = 0.5 }) in
  let outline = Freehand.outline opts line in
  Alcotest.(check bool) "an outline has points" true (Array.length outline > 10);
  let ys = Array.map (fun (p : Vec.t) -> p.y) outline in
  let top = Array.fold_left Float.min 0. ys and bottom = Array.fold_left Float.max 0. ys in
  Alcotest.(check bool) "the stroke is at most as wide as full pressure allows" true (bottom -. top <= 8. *. (1. +. opts.thinning) +. 0.01);
  Alcotest.(check bool) "the stroke has width" true (bottom -. top > 2.);
  let near_end = outline_width outline (Vec.make 236. 0.) in
  Alcotest.(check bool) "the end tapers to the last point" true (near_end < 0.5);
  let slow = freehand_points 60 (fun i -> { Freehand.x = i *. 1.; y = 0.; pressure = 0.5 }) in
  let fast = freehand_points 60 (fun i -> { Freehand.x = i *. 12.; y = 0.; pressure = 0.5 }) in
  let mid_width points at =
    let o = Freehand.outline { opts with taper_start = 0.; taper_end = 0. } points in
    let ys = Array.map (fun (p : Vec.t) -> Float.abs p.y) (Array.of_list (List.filter (fun (p : Vec.t) -> Float.abs (p.x -. at) < 6.) (Array.to_list o))) in
    Array.fold_left Float.max 0. ys
  in
  Alcotest.(check bool) "a fast stroke is thinner than a slow one" true (mid_width fast 360. < mid_width slow 30.);
  let dot = Freehand.outline opts [| { Freehand.x = 10.; y = 10.; pressure = 0.5 } |] in
  Array.iter (fun p -> check_float ~eps:0.01 "a dot is a circle" (Vec.dist p (Vec.make 10. 10.)) (Vec.dist dot.(0) (Vec.make 10. 10.))) dot;
  let live = Freehand.options ~size:8. ~simulate:true ~complete:false in
  let o = Freehand.outline live line in
  let farthest = Array.fold_left (fun acc (p : Vec.t) -> Float.max acc p.x) 0. o in
  Alcotest.(check bool) "a stroke in progress reaches the pointer" true (farthest >= 236.);
  Alcotest.(check string) "no path for too few points" "" (Freehand.path_of_outline [| Vec.zero; Vec.zero |]);
  let path = Freehand.path_of_outline [| Vec.make 0. 0.; Vec.make 10. 0.; Vec.make 10. 10.; Vec.make 0. 10. |] in
  Alcotest.(check string) "closed smooth path through midpoints" "M0,5Q0,0 5,0T10,5 5,10 0,5Z" path

let across_profile outline (u : Vec.t) =
  Array.map (fun (p : Vec.t) -> (Vec.dot p u, Vec.cross u p)) outline

let pen_ends () =
  let opts = Freehand.options ~size:8. ~simulate:true ~complete:true in
  let u = Vec.normalize (Vec.make 5. (-1.5)) in
  let line =
    Array.init 41 (fun i ->
        let i = float_of_int i in
        { Freehand.x = Float.round (5. *. i); y = Float.round ((-1.5 *. i) +. 0.3); pressure = 0.5 })
  in
  let profile = across_profile (Freehand.outline opts line) u in
  let side ~lo ~hi sign =
    Array.fold_left
      (fun acc (along, across) -> if along >= lo && along <= hi && across *. sign > 0. then Float.max acc (Float.abs across) else acc)
      0. profile
  in
  let total = Vec.dot (Vec.make 200. (-60.)) u in
  List.iter
    (fun (lo, hi) ->
      let a = side ~lo ~hi 1. and b = side ~lo ~hi (-1.) in
      if Float.abs (a -. b) > 0.3 then Alcotest.failf "the start taper is lopsided between %g and %g: %g vs %g" lo hi a b)
    [ (0., 4.); (0., 8.); (0., 16.) ];
  let start_width = side ~lo:0. ~hi:12. 1. +. side ~lo:0. ~hi:12. (-1.) in
  let end_width = side ~lo:(total -. 12.) ~hi:total 1. +. side ~lo:(total -. 12.) ~hi:total (-1.) in
  if Float.abs (start_width -. end_width) > 0.25 *. Float.max start_width end_width then
    Alcotest.failf "start and end tapers differ: %g vs %g" start_width end_width;
  let short = [| { Freehand.x = 0.; y = 0.; pressure = 0.5 }; { x = 5.; y = 0.; pressure = 0.5 }; { x = 10.; y = 0.; pressure = 0.5 } |] in
  let o = Freehand.outline opts short in
  let behind = Array.fold_left (fun acc (p : Vec.t) -> Float.min acc p.x) 0. o in
  let ahead = Array.fold_left (fun acc (p : Vec.t) -> Float.max acc p.x) 0. o in
  Alcotest.(check bool) "a short stroke has a round cap behind its start" true (behind < -1.5);
  Alcotest.(check bool) "and after its end" true (ahead > 11.5);
  let click = Freehand.outline opts [| { Freehand.x = 3.; y = 4.; pressure = 0.5 } |] in
  Alcotest.(check bool) "a click is a dot with a radius" true (Vec.dist click.(0) (Vec.make 3. 4.) > 1.)

let geom () =
  let b = Geom.Box.of_corners (Vec.make 10. 20.) (Vec.make 0. 5.) in
  check_float "box x" 0. b.x;
  check_float "box h" 15. b.h;
  Alcotest.(check bool) "segment through box" true (Geom.segment_hits_box (Vec.make (-5.) 10.) (Vec.make 20. 10.) b);
  Alcotest.(check bool) "segment beside box" false (Geom.segment_hits_box (Vec.make 20. 0.) (Vec.make 20. 30.) b);
  Alcotest.(check bool) "crossing" true (Geom.segments_cross (Vec.make 0. 0.) (Vec.make 2. 2.) (Vec.make 0. 2.) (Vec.make 2. 0.));
  Alcotest.(check bool) "parallel" false (Geom.segments_cross (Vec.make 0. 0.) (Vec.make 2. 0.) (Vec.make 0. 1.) (Vec.make 2. 1.));
  check_float "distance to segment" 3. (Geom.dist_to_segment (Vec.make 5. 3.) (Vec.make 0. 0.) (Vec.make 10. 0.));
  let f = { Geom.Frame.origin = Vec.make 10. 10.; w = 4.; h = 2.; rotation = Float.pi /. 2. } in
  check_vec "frame corner" (Vec.make 10. 14.) (Geom.Frame.to_world f (Vec.make 4. 0.));
  check_vec "frame round trip" (Vec.make 1. 1.5) (Geom.Frame.to_local f (Geom.Frame.to_world f (Vec.make 1. 1.5)));
  check_float "angle in range" (Float.pi /. 2.) (Geom.normalize_angle (-3. *. Float.pi /. 2.));
  check_float "snap to 15 degrees" (Float.pi /. 12.) (Geom.snap_angle ~step:(Float.pi /. 12.) 0.3)

let hits () =
  let r = Shape.rect ~id:1 ~style (box 0. 0. 100. 50.) in
  let at x y = Shape.hit r ~tolerance:2. (Vec.make x y) in
  Alcotest.(check bool) "edge of a hollow rect" true (at 100. 25. = Shape.Edge);
  Alcotest.(check bool) "middle of a hollow rect" true (at 50. 25. = Shape.Inside);
  Alcotest.(check bool) "outside" true (at 150. 25. = Shape.Miss);
  let filled = Shape.rect ~id:1 ~style:{ style with fill = Solid } (box 0. 0. 100. 50.) in
  Alcotest.(check bool) "middle of a filled rect" true (Shape.hit filled ~tolerance:2. (Vec.make 50. 25.) = Shape.Edge);
  let turned = Shape.rotate_about r ~center:(Shape.center r) (Float.pi /. 2.) in
  Alcotest.(check bool) "a turned rect is tall" true (Shape.hit turned ~tolerance:1. (Vec.make 50. (-24.)) <> Shape.Miss);
  Alcotest.(check bool) "a turned rect lost its width" true (Shape.hit turned ~tolerance:1. (Vec.make 95. 25.) = Shape.Miss);
  let e = Shape.ellipse ~id:2 ~style (box 0. 0. 100. 50.) in
  Alcotest.(check bool) "ellipse edge" true (Shape.hit e ~tolerance:2. (Vec.make 50. 0.) = Shape.Edge);
  Alcotest.(check bool) "ellipse corner is outside" true (Shape.hit e ~tolerance:2. (Vec.make 3. 3.) = Shape.Miss);
  let l = Shape.line ~id:3 ~style ~arrow:true (Vec.make 0. 0.) (Vec.make 100. 100.) in
  Alcotest.(check bool) "on the line" true (Shape.hit l ~tolerance:2. (Vec.make 50. 51.) = Shape.Edge);
  Alcotest.(check bool) "off the line" true (Shape.hit l ~tolerance:2. (Vec.make 50. 60.) = Shape.Miss);
  let d = Option.get (Shape.draw ~id:4 ~style ~simulate:true [ { Freehand.x = 0.; y = 0.; pressure = 0.5 }; { x = 50.; y = 0.; pressure = 0.5 } ]) in
  Alcotest.(check bool) "on the stroke" true (Shape.hit d ~tolerance:1. (Vec.make 25. 3.) = Shape.Edge);
  Alcotest.(check bool) "off the stroke" true (Shape.hit d ~tolerance:1. (Vec.make 25. 10.) = Shape.Miss);
  let t = Shape.text metrics ~id:5 ~style ~scale:1. (Vec.make 0. 0.) "hello" in
  Alcotest.(check bool) "in a text box" true (Shape.hit t ~tolerance:0. (Vec.make 10. 10.) = Shape.Edge);
  Alcotest.(check bool) "box touch" true (Shape.touches_box r (box 90. 40. 20. 20.));
  Alcotest.(check bool) "a box inside a hollow rect does not touch it" false (Shape.touches_box r (box 40. 20. 5. 5.));
  Alcotest.(check bool) "eraser segment" true (Shape.touches_segment l ~tolerance:1. (Vec.make 0. 100.) (Vec.make 100. 0.))

let transforms () =
  let r = Shape.rect ~id:1 ~style (box 0. 0. 100. 50.) in
  let frame = Shape.frame r in
  let flip_x p = Geom.Frame.to_world frame (let l = Geom.Frame.to_local frame p in Vec.make (100. -. l.x) l.y) in
  let flipped = Shape.resize r ~rotation:0. ~map:flip_x ~sx:(-1.) ~sy:1. in
  check_float "a flipped rect keeps its width" 100. flipped.w;
  check_float "a flipped rect keeps its place" 0. flipped.x;
  let d =
    Option.get
      (Shape.draw ~id:2 ~style ~simulate:true
         [ { Freehand.x = 0.; y = 0.; pressure = 0.5 }; { x = 10.; y = 0.; pressure = 0.5 }; { x = 10.; y = 20.; pressure = 0.5 } ])
  in
  let f = Shape.frame d in
  let mirror p = Geom.Frame.to_world f (let l = Geom.Frame.to_local f p in Vec.make (10. -. l.x) l.y) in
  let m = Shape.resize d ~rotation:0. ~map:mirror ~sx:(-1.) ~sy:1. in
  (match m.kind with
  | Draw { points; _ } -> check_float "mirrored drawing starts at the right" 10. points.(0).x
  | _ -> Alcotest.fail "not a drawing");
  let scale2 p = Vec.scale p 2. in
  let big = Shape.resize r ~rotation:0. ~map:scale2 ~sx:2. ~sy:2. in
  check_float "scaled width" 200. big.w;
  check_vec "scaled place" (Vec.make 0. 0.) (Vec.make big.x big.y);
  let turned = Shape.rotate_about r ~center:(Shape.center r) (Float.pi /. 2.) in
  let tframe = Shape.frame turned in
  let stretch p = Geom.Frame.to_world tframe (let l = Geom.Frame.to_local tframe p in Vec.make (l.x *. 2.) l.y) in
  let s = Shape.resize turned ~rotation:(Float.pi /. 2.) ~map:stretch ~sx:2. ~sy:1. in
  check_float "a turned rect stretches along its own width" 200. s.w;
  check_float "and keeps its height" 50. s.h;
  let corners = Geom.Frame.corners (Shape.frame s) in
  check_vec "its top-left corner stays" (Geom.Frame.corners tframe).(0) corners.(0);
  let l = Shape.line ~id:3 ~style ~arrow:false (Vec.make 0. 0.) (Vec.make 10. 0.) in
  let lr = Shape.rotate_about l ~center:Vec.zero (Float.pi /. 2.) in
  (match Shape.ends lr with
  | Some (_, b) -> check_vec "a turned line moves its end" (Vec.make 0. 10.) b
  | None -> Alcotest.fail "no ends");
  check_float "a line keeps no rotation" 0. lr.rotation;
  let t = Shape.text metrics ~id:4 ~style ~scale:1. (Vec.make 0. 0.) "abc" in
  let t2 = Shape.resize t ~rotation:0. ~map:scale2 ~sx:2. ~sy:2. in
  check_float "text scales its font" (Shape.font_size t *. 2.) (Shape.font_size t2);
  let grown = Shape.set_text metrics t "abcdef" in
  check_float "text grows to fit" (t.w +. (3. *. 0.5 *. Shape.font_size t)) grown.w;
  let multi = Shape.set_text metrics t "a\nb\nc" in
  check_float "three lines" (3. *. Shape.font_size t *. Shape.line_height) multi.h

let board () =
  let b = Board.empty in
  let id1, b = Board.fresh_id b in
  let b = Board.add b (Shape.rect ~id:id1 ~style (box 0. 0. 10. 10.)) in
  let id2, b = Board.fresh_id b in
  let b = Board.add b (Shape.rect ~id:id2 ~style:{ style with fill = Solid } (box 5. 5. 10. 10.)) in
  Alcotest.(check bool) "ids differ" true (id1 <> id2);
  let ids b = Array.to_list (Array.map (fun (s : Shape.t) -> s.id) (Board.shapes b)) in
  Alcotest.(check (list int)) "to back" [ id2; id1 ] (ids (Board.to_back b [ id2 ]));
  Alcotest.(check (list int)) "to front" [ id2; id1 ] (ids (Board.to_front b [ id1 ]));
  (match Board.top_hit b ~tolerance:1. (Vec.make 7. 7.) with
  | Some s -> Alcotest.(check int) "front-most filled shape" id2 s.id
  | None -> Alcotest.fail "no hit");
  Alcotest.(check (list int)) "marquee" [ id1 ] (Board.in_box b (box (-1.) (-1.) 3. 3.));
  let b2, copies = Board.insert_copies b (Array.to_list (Board.shapes b)) ~offset:(Vec.make 100. 0.) in
  Alcotest.(check int) "copies" 4 (Board.length b2);
  Alcotest.(check bool) "copies have new ids" true (List.for_all (fun id -> id <> id1 && id <> id2) copies);
  let note = "say \"hi\"\n\ttab \\ caf\xc3\xa9" in
  let id3, b2 = Board.fresh_id b2 in
  let b2 = Board.add b2 (Shape.rotate_about (Shape.text metrics ~id:id3 ~style ~scale:1.5 (Vec.make 3. 4.) note) ~center:Vec.zero 0.5) in
  let text = Board.to_json_text b2 in
  match Result.bind (Yuka.Json.of_string text) (Board.of_json metrics) with
  | Ok back ->
      Alcotest.(check (list int)) "round trip keeps order" (ids b2) (ids back);
      let t = Option.get (Board.find back id3) in
      Alcotest.(check (option string)) "round trip keeps text with quotes and newlines" (Some note) (Shape.text_of t);
      check_float ~eps:1e-6 "round trip keeps the turn" 0.5 t.rotation;
      let next, _ = Board.fresh_id back in
      Alcotest.(check bool) "round trip keeps ids free" true (not (Board.mem back next))
  | Error e -> Alcotest.fail e

let history () =
  let h = History.empty in
  let h = History.record h ~before:1 in
  let h = History.record h ~before:2 in
  match History.undo h ~current:3 with
  | None -> Alcotest.fail "no undo"
  | Some (h, v) -> (
      Alcotest.(check int) "undo" 2 v;
      match History.redo h ~current:v with
      | None -> Alcotest.fail "no redo"
      | Some (h, v) ->
          Alcotest.(check int) "redo" 3 v;
          let h, _ = Option.get (History.undo h ~current:v) in
          Alcotest.(check bool) "after an undo there is a redo" true (History.can_redo h);
          let h = History.record h ~before:2 in
          Alcotest.(check bool) "a new step drops redo" false (History.can_redo h);
          let capped = List.fold_left (fun h i -> History.record ~limit:3 h ~before:i) History.empty [ 1; 2; 3; 4; 5 ] in
          let rec count h n = match History.undo h ~current:0 with Some (h, _) -> count h (n + 1) | None -> n in
          Alcotest.(check int) "limit" 3 (count capped 0))

let camera () =
  let c = Camera.zoom_at Camera.initial (Vec.make 100. 100.) 2. in
  check_vec "the point under the cursor stays" (Vec.make 100. 100.) (Camera.to_screen c (Vec.make 100. 100.));
  check_float "zoom clamps" Camera.max_zoom (Camera.zoom_at c Vec.zero 100.).zoom;
  check_float "zoom in steps" 4. (Camera.zoom_in c Vec.zero).zoom;
  check_float "zoom out steps" 1. (Camera.zoom_out c Vec.zero).zoom;
  let f = Camera.fit (box 0. 0. 1000. 500.) ~width:1000. ~height:500. in
  Alcotest.(check bool) "fit zooms out" true (f.zoom < 1.);
  check_vec "fit centers" (Vec.make 500. 250.) (Camera.to_screen f (Vec.make 500. 250.))

let export () =
  Alcotest.(check (option string)) "empty board" None (Export.svg metrics Board.empty);
  let b = Board.add Board.empty (Shape.text metrics ~id:1 ~style ~scale:1. Vec.zero "a<b") in
  let b = Board.add b (Shape.rect ~id:2 ~style (box 0. 0. 10. 10.)) in
  match Export.svg metrics b with
  | None -> Alcotest.fail "no svg"
  | Some svg ->
      let has s = Option.is_some (Seq.find (fun i -> String.sub svg i (String.length s) = s) (Seq.init (String.length svg - String.length s + 1) Fun.id)) in
      Alcotest.(check bool) "svg root" true (has "<svg xmlns=\"http://www.w3.org/2000/svg\"");
      Alcotest.(check bool) "escaped text" true (has "a&lt;b");
      Alcotest.(check bool) "rect path" true (has "M0,0H10V10H0Z")

let () =
  Alcotest.run "sketch geometry"
    [
      ("num", [ Alcotest.test_case "format" `Quick num ]);
      ("freehand", [ Alcotest.test_case "outline" `Quick freehand; Alcotest.test_case "ends" `Quick pen_ends ]);
      ("geom", [ Alcotest.test_case "boxes and frames" `Quick geom ]);
      ("shape", [ Alcotest.test_case "hit tests" `Quick hits; Alcotest.test_case "transforms" `Quick transforms ]);
      ("board", [ Alcotest.test_case "order, hits, copies, json" `Quick board ]);
      ("history", [ Alcotest.test_case "undo and redo" `Quick history ]);
      ("camera", [ Alcotest.test_case "zoom and fit" `Quick camera ]);
      ("export", [ Alcotest.test_case "svg" `Quick export ]);
    ]
