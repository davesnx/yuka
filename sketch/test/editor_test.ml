open Sketch_shared

let close ?(eps = 1e-6) a b = Float.abs (a -. b) <= eps

let check_float ?(eps = 1e-6) msg expected actual =
  if not (close ~eps expected actual) then Alcotest.failf "%s: expected %g, got %g" msg expected actual

let metrics = { Shape.width = (fun ~font text -> font *. 0.5 *. float_of_int (String.length text)); ascent = 0.8; descent = 0.2 }
let fresh () = Editor.create ~metrics ~width:1000. ~height:800.

let pointer ?(shift = false) ?(alt = false) ?(ctrl = false) ?(button = 0) ?(device = Editor.Mouse) ?(id = 1) ?(pressure = 0.5) x y =
  { Editor.id; screen = Vec.make x y; device; pressure; button; shift; alt; ctrl }

let drag ?shift ?alt ?device ?id e (x0, y0) (x1, y1) =
  let e = Editor.pointer_down e (pointer ?shift ?alt ?device ?id x0 y0) in
  let steps = 8 in
  let e =
    List.fold_left
      (fun e i ->
        let t = float_of_int i /. float_of_int steps in
        Editor.pointer_move e [ pointer ?shift ?alt ?device ?id (x0 +. ((x1 -. x0) *. t)) (y0 +. ((y1 -. y0) *. t)) ])
      e (List.init steps (fun i -> i + 1))
  in
  Editor.pointer_up e (pointer ?shift ?alt ?device ?id x1 y1)

let click ?shift e x y = drag ?shift e (x, y) (x, y)
let key ?(shift = false) ?(ctrl = false) e k = fst (Editor.key_down e { Editor.key = k; shift; alt = false; ctrl })
let shapes e = Array.to_list (Board.shapes (Editor.board e))
let only e = match shapes e with [ s ] -> s | l -> Alcotest.failf "expected one shape, got %d" (List.length l)
let find e id = Option.get (Board.find (Editor.board e) id)

let rect_at e (x0, y0) (x1, y1) = drag (Editor.set_tool e Editor.Rect) (x0, y0) (x1, y1)

let creating () =
  let e = rect_at (fresh ()) (100., 100.) (300., 200.) in
  let s = only e in
  check_float "rect width" 200. s.w;
  check_float "rect height" 100. s.h;
  Alcotest.(check bool) "back to select" true (Editor.tool e = Editor.Select);
  Alcotest.(check (list int)) "new shape selected" [ s.id ] (Editor.selection e);
  let sq = only (drag ~shift:true (Editor.set_tool (fresh ()) Editor.Rect) (100., 100.) (300., 160.)) in
  check_float "shift makes a square" sq.w sq.h;
  check_float "square side is the longer drag" 200. sq.w;
  let c = only (drag ~alt:true (Editor.set_tool (fresh ()) Editor.Ellipse) (200., 200.) (250., 230.)) in
  check_float "alt draws from the centre x" 150. c.x;
  check_float "alt draws from the centre y" 170. c.y;
  check_float "alt doubles the width" 100. c.w;
  let clicked = only (click (Editor.set_tool (fresh ()) Editor.Rect) 400. 400.) in
  check_float "a click makes a default size" 100. clicked.w;
  let flipped = only (rect_at (fresh ()) (300., 300.) (100., 200.)) in
  check_float "dragging up-left" 100. flipped.x

let lines () =
  let e = drag ~shift:true (Editor.set_tool (fresh ()) Editor.Arrow) (100., 100.) (300., 117.) in
  let s = only e in
  (match (s.kind, Shape.ends s) with
  | Line { arrow = true; _ }, Some (a, b) ->
      check_float ~eps:1e-6 "shift snaps the arrow to horizontal" a.y b.y;
      check_float ~eps:0.5 "and keeps its projected length" 200. (b.x -. a.x)
  | _ -> Alcotest.fail "not an arrow");
  let e = drag ~shift:true (Editor.set_tool (fresh ()) Editor.Line) (100., 100.) (200., 190.) in
  (match Shape.ends (only e) with
  | Some (a, b) ->
      let angle = Float.atan2 (b.y -. a.y) (b.x -. a.x) in
      check_float ~eps:1e-9 "snaps to 45 degrees" (Float.pi /. 4.) angle
  | None -> Alcotest.fail "no ends");
  let none = click (Editor.set_tool (fresh ()) Editor.Line) 100. 100. in
  Alcotest.(check int) "a click draws no line" 0 (List.length (shapes none));
  let e = drag ~shift:true (Editor.set_tool (fresh ()) Editor.Line) (100., 100.) (300., 100.) in
  let e = drag e (300., 100.) (300., 250.) in
  match Shape.ends (only e) with
  | Some (_, b) -> check_float "dragging the end handle moves the end" 250. b.y
  | None -> Alcotest.fail "no ends"

let pen () =
  let e = Editor.set_tool (fresh ()) Editor.Draw in
  let e = Editor.pointer_down e (pointer 100. 100.) in
  let e = Editor.pointer_move e (List.init 20 (fun i -> pointer (100. +. float_of_int (i * 5)) 100.)) in
  (match Editor.drawing e with Some (path, _) -> Alcotest.(check bool) "live path" true (String.length path > 10) | None -> Alcotest.fail "no live stroke");
  Alcotest.(check int) "no shape while drawing" 0 (List.length (shapes e));
  let e = Editor.pointer_up e (pointer 195. 100.) in
  Alcotest.(check bool) "stroke done" true (Option.is_none (Editor.drawing e));
  let s = only e in
  (match s.kind with Draw { simulate; _ } -> Alcotest.(check bool) "mouse simulates pressure" true simulate | _ -> Alcotest.fail "not a drawing");
  check_float "stroke box" 95. s.w;
  Alcotest.(check bool) "pen stays" true (Editor.tool e = Editor.Draw);
  let p = drag ~device:Editor.Pen (Editor.set_tool (fresh ()) Editor.Draw) (0., 0.) (50., 50.) in
  match (only p).kind with Draw { simulate; _ } -> Alcotest.(check bool) "pen pressure is real" false simulate | _ -> Alcotest.fail "not a drawing"

let text () =
  let e = click (Editor.set_tool (fresh ()) Editor.Text) 200. 200. in
  let id = Option.get (Editor.editing e) in
  let e = Editor.set_text e "hello" in
  let w1 = (find e id).w in
  let e = Editor.set_text e "hello world" in
  Alcotest.(check bool) "auto size" true ((find e id).w > w1);
  let e = Editor.stop_editing e in
  Alcotest.(check (option int)) "not editing" None (Editor.editing e);
  Alcotest.(check (option string)) "text kept" (Some "hello world") (Shape.text_of (only e));
  let e = Editor.undo e in
  Alcotest.(check int) "creating and typing is one step" 0 (List.length (shapes e));
  let e = click (Editor.set_tool (fresh ()) Editor.Text) 200. 200. in
  let e = Editor.set_text e "   " in
  let e = Editor.stop_editing e in
  Alcotest.(check int) "empty text is removed" 0 (List.length (shapes e));
  Alcotest.(check bool) "and leaves no undo step" false (Editor.can_undo e);
  let e = click (Editor.set_tool (fresh ()) Editor.Text) 200. 200. in
  let e = Editor.stop_editing (Editor.set_text e "note") in
  let s = only e in
  let at = Camera.to_screen (Editor.camera e) (Shape.center s) in
  let e = Editor.double_click e at in
  Alcotest.(check (option int)) "double click edits" (Some s.id) (Editor.editing e);
  let e = Editor.stop_editing (Editor.set_text e "") in
  Alcotest.(check int) "emptied text is removed" 0 (List.length (shapes e));
  let e = Editor.undo e in
  Alcotest.(check int) "and that is undoable" 1 (List.length (shapes e))

let two_rects () =
  let e = rect_at (fresh ()) (100., 100.) (200., 200.) in
  let e = rect_at e (400., 100.) (500., 200.) in
  match shapes e with [ a; b ] -> (e, a.id, b.id) | _ -> Alcotest.fail "two shapes"

let selection () =
  let e, a, b = two_rects () in
  let e = click e 100. 150. in
  Alcotest.(check (list int)) "click selects" [ a ] (Editor.selection e);
  let e = click ~shift:true e 400. 150. in
  Alcotest.(check (list int)) "shift click adds" [ a; b ] (Editor.selection e);
  let e = click ~shift:true e 400. 150. in
  Alcotest.(check (list int)) "shift click removes" [ a ] (Editor.selection e);
  let e = click e 700. 600. in
  Alcotest.(check (list int)) "click on empty clears" [] (Editor.selection e);
  let e = drag e (50., 50.) (250., 250.) in
  Alcotest.(check (list int)) "marquee" [ a ] (Editor.selection e);
  let e = drag (key e "Escape") (250., 50.) (350., 250.) in
  Alcotest.(check (list int)) "a marquee over empty space selects nothing" [] (Editor.selection e);
  let e = click e 150. 150. in
  Alcotest.(check (list int)) "a click inside a hollow rect selects it" [ a ] (Editor.selection e);
  let e = drag ~device:Editor.Touch e (50., 50.) (600., 250.) in
  Alcotest.(check (list int)) "touch drag selects" [ a; b ] (Editor.selection e);
  let e = key e "Escape" in
  Alcotest.(check (list int)) "escape clears" [] (Editor.selection e);
  let e = key ~ctrl:true e "a" in
  Alcotest.(check (list int)) "select all" [ a; b ] (Editor.selection e);
  let e = Editor.pointer_move (key e "Escape") [ pointer 100. 150. ] in
  Alcotest.(check (option int)) "hover" (Some a) (Editor.hover e)

let moving () =
  let e, a, b = two_rects () in
  let e = key ~ctrl:true e "a" in
  let e = drag e (150., 150.) (200., 180.) in
  check_float "moved a" 150. (find e a).x;
  check_float "moved b" 450. (find e b).x;
  let e = Editor.undo e in
  check_float "a drag is one undo step" 100. (find e a).x;
  let e = Editor.redo e in
  check_float "redo" 150. (find e a).x;
  let e = key e "ArrowRight" in
  check_float "nudge" 151. (find e a).x;
  let e = key ~shift:true e "ArrowDown" in
  check_float "shift nudge" 140. (find e a).y;
  let e = drag ~shift:true e (200., 190.) (300., 200.) in
  check_float "shift drag keeps one axis" 140. (find e a).y;
  check_float "shift drag moves along x" 251. (find e a).x

let handle e h =
  match List.assoc_opt h (Editor.handles e) with Some (p : Vec.t) -> p | None -> Alcotest.fail "no such handle"

let drag_handle ?shift ?alt e h (dx, dy) =
  let p = handle e h in
  drag ?shift ?alt e (p.x, p.y) (p.x +. dx, p.y +. dy)

let resizing () =
  let e = rect_at (fresh ()) (100., 100.) (300., 200.) in
  let id = (only e).id in
  Alcotest.(check int) "eight resize handles and a rotate handle" 9 (List.length (Editor.handles e));
  let e = drag_handle e Editor.SE (100., 60.) in
  let s = find e id in
  check_float "corner resize w" 300. s.w;
  check_float "corner resize h" 160. s.h;
  let e = Editor.undo e in
  let e = drag_handle ~shift:true e Editor.SE (100., 10.) in
  let s = find e id in
  check_float "shift keeps the ratio" 2. (s.w /. s.h);
  let e = Editor.undo e in
  let e = drag_handle ~alt:true e Editor.E (50., 0.) in
  let s = find e id in
  check_float "alt resizes from the centre" 50. s.x;
  check_float "alt doubles the change" 300. s.w;
  let e = Editor.undo e in
  let e = drag_handle e Editor.N (0., -40.) in
  let s = find e id in
  check_float "the top handle moves the top" 60. s.y;
  check_float "and keeps the width" 200. s.w;
  let e = Editor.undo e in
  let e = drag_handle e Editor.E (-300., 0.) in
  let s = find e id in
  check_float "flip across the left edge" 0. s.x;
  check_float "flipped width" 100. s.w;
  let e = Editor.undo e in
  let e = Editor.set_tool e Editor.Select in
  let e = drag_handle e Editor.Rotate (100., 100.) in
  let s = find e id in
  Alcotest.(check bool) "the rotate handle turns the shape" true (s.rotation > 0.1);
  let e = Editor.undo e in
  let e = drag_handle ~shift:true e Editor.Rotate (110., 38.) in
  let s = find e id in
  let deg = s.rotation *. 180. /. Float.pi in
  let off = Float.rem deg 15. in
  check_float ~eps:1e-6 "shift snaps to 15 degrees" 0. (Float.min off (15. -. off));
  Alcotest.(check bool) "and the turn is not zero" true (deg > 1.);
  let frame = Option.get (Editor.selection_frame e) in
  check_float ~eps:1e-6 "the frame follows the turn" s.rotation frame.rotation;
  let se = handle e Editor.SE in
  let corner = Camera.to_screen (Editor.camera e) (Geom.Frame.corners frame).(2) in
  check_float ~eps:1e-6 "handles sit on the turned corners x" corner.x se.x;
  check_float ~eps:1e-6 "handles sit on the turned corners y" corner.y se.y;
  let shape_corner = Camera.to_screen (Editor.camera e) (Geom.Frame.corners (Shape.frame s)).(2) in
  let gap = Vec.dist corner shape_corner in
  Alcotest.(check bool) "the frame is just outside the stroke" true (gap > Shape.half_stroke s && gap < 10.);
  let tiny = rect_at (fresh ()) (100., 100.) (120., 300.) in
  let names = List.map fst (Editor.handles tiny) in
  Alcotest.(check bool) "a narrow shape hides its top and bottom handles" true
    ((not (List.mem Editor.N names)) && List.mem Editor.E names && List.mem Editor.SE names)

let turned_resize () =
  let e = rect_at (fresh ()) (100., 100.) (300., 200.) in
  let id = (only e).id in
  let e = drag e (200., 82.) (300., 150.) in
  let before = find e id in
  let handles = Editor.handles e in
  let ep = List.assoc Editor.E handles in
  let dir = Vec.rotate (Vec.make 1. 0.) before.rotation in
  let target = Vec.add ep (Vec.scale dir 50.) in
  let e = drag e (ep.x, ep.y) (target.x, target.y) in
  let after = find e id in
  check_float ~eps:1e-6 "a turned shape grows along its own axis" (before.w +. 50.) after.w;
  check_float ~eps:1e-6 "and keeps its height" before.h after.h;
  check_float ~eps:1e-6 "and its turn" before.rotation after.rotation;
  let c0 = (Geom.Frame.corners (Shape.frame before)).(0) and c1 = (Geom.Frame.corners (Shape.frame after)).(0) in
  check_float ~eps:1e-6 "the opposite side stays x" c0.x c1.x;
  check_float ~eps:1e-6 "the opposite side stays y" c0.y c1.y

let multi_resize () =
  let e, a, b = two_rects () in
  let e = key ~ctrl:true e "a" in
  let e = drag e (500., 200.) (900., 300.) in
  let sa = find e a and sb = find e b in
  check_float "group resize scales shapes" 200. sa.w;
  check_float "and their places" 900. (sb.x +. sb.w);
  let e = Editor.undo e in
  let e = drag e (500., 150.) (0., 150.) in
  let sa = find e a and sb = find e b in
  Alcotest.(check bool) "a group flip swaps the order" true (sb.x < sa.x)

let styles () =
  let e = rect_at (fresh ()) (100., 100.) (300., 200.) in
  let e = Editor.set_color e Shape.Red in
  Alcotest.(check bool) "selection gets the color" true ((only e).style.color = Shape.Red);
  let e = Editor.set_color e Shape.Red in
  let e = Editor.undo e in
  Alcotest.(check bool) "the same color again is no step" true ((only e).style.color = Shape.Black);
  let e = Editor.set_color (Editor.redo e) Shape.Red in
  let e = Editor.set_fill e Shape.Semi in
  let e = Editor.set_size e Shape.L in
  Alcotest.(check bool) "fill and size" true ((only e).style.fill = Shape.Semi && (only e).style.size = Shape.L);
  let e = key e "Escape" in
  let e = rect_at e (400., 400.) (500., 500.) in
  let latest = List.nth (shapes e) 1 in
  Alcotest.(check bool) "the next shape gets the style" true (latest.style.color = Shape.Red && latest.style.fill = Shape.Semi);
  let e = Editor.undo e in
  let e = Editor.undo e in
  Alcotest.(check bool) "a style change is one step" true ((only e).style.size = Shape.M)

let editing_commands () =
  let e, a, b = two_rects () in
  let e = click e 100. 150. in
  let e = key ~ctrl:true e "d" in
  Alcotest.(check int) "duplicate" 3 (List.length (shapes e));
  let copy = List.hd (Editor.selection e) in
  Alcotest.(check bool) "the copy is selected and moved" true (copy <> a && (find e copy).x > 100.);
  let e = key e "Delete" in
  Alcotest.(check int) "delete" 2 (List.length (shapes e));
  let e = click e 100. 150. in
  let e = key ~ctrl:true e "c" in
  let e = Editor.pointer_move e [ pointer 700. 600. ] in
  let e = key ~ctrl:true e "v" in
  let pasted = find e (List.hd (Editor.selection e)) in
  check_float "pasted at the cursor x" 700. (Shape.center pasted).x;
  check_float "pasted at the cursor y" 600. (Shape.center pasted).y;
  let e = click e 100. 150. in
  let e = key e "]" in
  Alcotest.(check int) "to front" a (List.nth (shapes e) 2).id;
  let e = key e "[" in
  Alcotest.(check int) "to back" a (List.hd (shapes e)).id;
  let e = Editor.set_tool e Editor.Eraser in
  let e = Editor.pointer_down e (pointer 50. 150.) in
  let e = Editor.pointer_move e [ pointer 450. 150. ] in
  Alcotest.(check bool) "erase marks" true (List.length (Editor.erasing e) = 2);
  let e = Editor.pointer_up e (pointer 450. 150. ) in
  Alcotest.(check bool) "erase removes" true (not (Board.mem (Editor.board e) a) && not (Board.mem (Editor.board e) b));
  let e = Editor.undo e in
  Alcotest.(check bool) "erase is one step" true (Board.mem (Editor.board e) a && Board.mem (Editor.board e) b);
  let e = key ~ctrl:true ~shift:true e "z" in
  Alcotest.(check bool) "ctrl shift z redoes" false (Board.mem (Editor.board e) a);
  let e = key ~ctrl:true e "z" in
  let e = key ~ctrl:true e "y" in
  Alcotest.(check bool) "ctrl y redoes" false (Board.mem (Editor.board e) a)

let canvas () =
  let e = fresh () in
  let e = Editor.wheel e ~at:(Vec.make 500. 400.) ~dx:0. ~dy:(-10.) ~ctrl:true in
  let c = Editor.camera e in
  Alcotest.(check bool) "pinch zooms in" true (c.zoom > 1.);
  let w = Camera.to_world c (Vec.make 500. 400.) in
  check_float ~eps:1e-9 "the point under the cursor stays x" 500. w.x;
  let e = Editor.wheel e ~at:Vec.zero ~dx:30. ~dy:40. ~ctrl:false in
  check_float "wheel pans" (c.y -. 40.) (Editor.camera e).y;
  let e = fresh () in
  let e = fst (Editor.key_down e { key = " "; shift = false; alt = false; ctrl = false }) in
  let e = drag e (100., 100.) (150., 130.) in
  check_float "space drag pans" 50. (Editor.camera e).x;
  let e = Editor.key_up e { key = " "; shift = false; alt = false; ctrl = false } in
  let e = Editor.pointer_down e (pointer ~button:1 100. 100.) in
  let e = Editor.pointer_move e [ pointer 120. 100. ] in
  let e = Editor.pointer_up e (pointer 120. 100.) in
  check_float "middle drag pans" 70. (Editor.camera e).x;
  let e = key e "=" in
  check_float "plus zooms in a step" 2. (Editor.camera e).zoom;
  let e = key ~shift:true e ")" in
  check_float "shift 0 resets" 1. (Editor.camera e).zoom;
  let e = rect_at e (100., 100.) (2000., 1500.) in
  let e = key ~shift:true e "!" in
  Alcotest.(check bool) "zoom to fit" true ((Editor.camera e).zoom < 1.);
  let e = fresh () in
  let e = Editor.pointer_down e (pointer ~device:Editor.Touch ~id:1 100. 100.) in
  let e = Editor.pointer_down e (pointer ~device:Editor.Touch ~id:2 200. 100.) in
  let e = Editor.pointer_move e [ pointer ~device:Editor.Touch ~id:2 300. 100. ] in
  check_float "two fingers pinch" 2. (Editor.camera e).zoom;
  let e = Editor.pointer_up e (pointer ~device:Editor.Touch ~id:2 300. 100.) in
  let e = Editor.pointer_up e (pointer ~device:Editor.Touch ~id:1 100. 100.) in
  Alcotest.(check int) "pinch draws nothing" 0 (List.length (shapes e))

let tools () =
  let e = fresh () in
  let check k tool = Alcotest.(check bool) ("key " ^ k) true (Editor.tool (key e k) = tool) in
  check "v" Editor.Select;
  check "h" Editor.Hand;
  check "d" Editor.Draw;
  check "p" Editor.Draw;
  check "r" Editor.Rect;
  check "o" Editor.Ellipse;
  check "a" Editor.Arrow;
  check "l" Editor.Line;
  check "t" Editor.Text;
  check "e" Editor.Eraser;
  let _, used = Editor.key_down e { key = "q"; shift = false; alt = false; ctrl = false } in
  Alcotest.(check bool) "an unknown key is not used" false used

let cancel () =
  let e = rect_at (fresh ()) (100., 100.) (300., 200.) in
  let id = (only e).id in
  let e = Editor.pointer_down e (pointer 200. 150.) in
  let e = Editor.pointer_move e [ pointer 260. 150. ] in
  let e = key e "Escape" in
  check_float "escape during a drag puts the shape back" 100. (find e id).x;
  let e = Editor.pointer_up e (pointer 260. 150.) in
  check_float "and the release does nothing" 100. (find e id).x

let () =
  Alcotest.run "sketch editor"
    [
      ( "editor",
        [
          Alcotest.test_case "rectangle and ellipse" `Quick creating;
          Alcotest.test_case "arrow and line" `Quick lines;
          Alcotest.test_case "pen" `Quick pen;
          Alcotest.test_case "text" `Quick text;
          Alcotest.test_case "selection" `Quick selection;
          Alcotest.test_case "move and undo" `Quick moving;
          Alcotest.test_case "resize and rotate" `Quick resizing;
          Alcotest.test_case "resize a turned shape" `Quick turned_resize;
          Alcotest.test_case "resize a group" `Quick multi_resize;
          Alcotest.test_case "style" `Quick styles;
          Alcotest.test_case "edit commands" `Quick editing_commands;
          Alcotest.test_case "canvas" `Quick canvas;
          Alcotest.test_case "tool keys" `Quick tools;
          Alcotest.test_case "cancel" `Quick cancel;
        ] );
    ]
