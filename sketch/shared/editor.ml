type tool = Select | Hand | Draw | Rect | Ellipse | Arrow | Line | Text | Eraser

let tools = [ Select; Hand; Draw; Rect; Ellipse; Arrow; Line; Text; Eraser ]

let tool_name = function
  | Select -> "Select"
  | Hand -> "Hand"
  | Draw -> "Pen"
  | Rect -> "Rectangle"
  | Ellipse -> "Ellipse"
  | Arrow -> "Arrow"
  | Line -> "Line"
  | Text -> "Text"
  | Eraser -> "Eraser"

let tool_key = function
  | Select -> "V"
  | Hand -> "H"
  | Draw -> "D"
  | Rect -> "R"
  | Ellipse -> "O"
  | Arrow -> "A"
  | Line -> "L"
  | Text -> "T"
  | Eraser -> "E"

type device = Mouse | Pen | Touch

type pointer = {
  id : int;
  screen : Vec.t;
  device : device;
  pressure : float;
  button : int;
  shift : bool;
  alt : bool;
  ctrl : bool;
}

type key = { key : string; shift : bool; alt : bool; ctrl : bool }
type handle = N | S | E | W | NE | NW | SE | SW | Rotate | Start | End

type cursor =
  | Default
  | Cross
  | Grab
  | Grabbing
  | Move
  | Resize of float
  | Rotate_cursor
  | Text_cursor

type snapshot = { board : Board.t; selection : int list }
type shape_kind = Make_rect | Make_ellipse | Make_line | Make_arrow
type on_up = Keep | Select_only of int | Deselect of int | Clear

type gesture =
  | Idle
  | Panning of { pointer : int; last : Vec.t }
  | Pinching of { a : int; b : int; distance : float; center : Vec.t; camera : Camera.t }
  | Drawing of { pointer : int; points : Freehand.point list; simulate : bool; path : string }
  | Creating of { pointer : int; kind : shape_kind; start : Vec.t; id : int option; before : snapshot }
  | Pointing of { pointer : int; start_screen : Vec.t; start : Vec.t; on_up : on_up; before : snapshot }
  | Translating of { pointer : int; start : Vec.t; originals : Shape.t list; before : snapshot }
  | Resizing of {
      pointer : int;
      handle : handle;
      frame : Geom.Frame.t;
      start : Vec.t;
      originals : Shape.t list;
      locked : bool;
      before : snapshot;
    }
  | Rotating of {
      pointer : int;
      center : Vec.t;
      start_angle : float;
      base : float;
      originals : Shape.t list;
      before : snapshot;
    }
  | Moving_end of { pointer : int; which : handle; original : Shape.t; before : snapshot }
  | Marquee of { pointer : int; start : Vec.t; current : Vec.t; base : int list }
  | Erasing of { pointer : int; last : Vec.t; marked : int list }

type editing = { shape : int; before : snapshot; created : bool }

type t = {
  board : Board.t;
  selection : int list;
  camera : Camera.t;
  tool : tool;
  style : Shape.style;
  gesture : gesture;
  history : snapshot History.t;
  hover : int option;
  hover_handle : handle option;
  editing : editing option;
  clipboard : Shape.t list;
  pointer : Vec.t option;
  width : float;
  height : float;
  space : bool;
  touches : (int * Vec.t) list;
  metrics : Shape.metrics;
}

let create ~metrics ~width ~height =
  {
    board = Board.empty;
    selection = [];
    camera = Camera.initial;
    tool = Select;
    style = Shape.default_style;
    gesture = Idle;
    history = History.empty;
    hover = None;
    hover_handle = None;
    editing = None;
    clipboard = [];
    pointer = None;
    width;
    height;
    space = false;
    touches = [];
    metrics;
  }

let load t board camera =
  { t with board; camera; selection = []; history = History.empty; gesture = Idle; editing = None; hover = None }

let resize_viewport t ~width ~height = { t with width; height }
let board t = t.board
let camera t = t.camera
let tool t = t.tool
let hover t = t.hover
let metrics t = t.metrics
let editing t = Option.map (fun e -> e.shape) t.editing
let can_undo t = History.can_undo t.history
let can_redo t = History.can_redo t.history
let snapshot t = { board = t.board; selection = t.selection }
let world t p = Camera.to_world t.camera p
let mem id ids = List.exists (fun i -> i = id) ids
let without id ids = List.filter (fun i -> i <> id) ids

let commit t ~(before : snapshot) =
  if t.board == before.board then t else { t with history = History.record t.history ~before }

let selected t = List.filter (fun (s : Shape.t) -> mem s.id t.selection) (Array.to_list (Board.shapes t.board))
let selection t = t.selection

let tolerance t device =
  (match device with Touch -> 12. | Pen -> 6. | Mouse -> 5.) /. t.camera.zoom

let drag_threshold = function Touch -> 6. | Pen | Mouse -> 3.

let style t = match selected t with [] -> t.style | s :: _ -> s.style

let selection_frame_of shapes =
  match shapes with
  | [] -> None
  | [ (s : Shape.t) ] when not (Shape.is_line s) -> Some (Shape.frame s)
  | shapes ->
      let rotations = List.filter_map (fun (s : Shape.t) -> if Shape.is_line s then None else Some s.rotation) shapes in
      let rotation =
        match rotations with
        | r :: rest when List.for_all (fun x -> Float.abs (x -. r) < 1e-6) rest -> r
        | _ -> 0.
      in
      let points =
        List.concat_map
          (fun (s : Shape.t) ->
            match s.kind with
            | Rect | Text _ -> Array.to_list (Geom.Frame.corners (Shape.frame s))
            | Ellipse | Draw _ | Line _ ->
                let b = Shape.bounds s in
                if rotation = 0. || Shape.is_line s then
                  [ Vec.make b.x b.y; Vec.make (b.x +. b.w) (b.y +. b.h) ]
                  @
                  match Shape.ends s with
                  | Some (a, e) -> [ a; e ]
                  | None -> []
                else Array.to_list (Geom.Frame.corners (Shape.frame s)))
          shapes
      in
      Geom.Frame.around ~rotation points

let tight_frame t = selection_frame_of (selected t)

let pad_frame (f : Geom.Frame.t) a =
  {
    f with
    Geom.Frame.origin = Vec.sub f.origin (Vec.rotate (Vec.make a a) f.rotation);
    w = f.w +. (2. *. a);
    h = f.h +. (2. *. a);
  }

let frame_gap = 4.

let padding t shapes =
  List.fold_left
    (fun acc s -> Float.max acc (Shape.half_stroke s +. (Shape.arrowhead_length s *. Float.sin (Float.pi /. 6.))))
    0. shapes
  +. (frame_gap /. t.camera.zoom)

let selection_frame t =
  let shapes = selected t in
  Option.map (fun f -> pad_frame f (padding t shapes)) (selection_frame_of shapes)

let shape_box t (s : Shape.t) =
  let f =
    match Shape.ends s with
    | Some (a, b) -> { Geom.Frame.origin = a; w = Vec.dist a b; h = 0.; rotation = Vec.angle (Vec.sub b a) }
    | None -> Shape.frame s
  in
  pad_frame f (padding t [ s ])

let selection_boxes t =
  match t.gesture with
  | Translating _ | Resizing _ | Rotating _ | Moving_end _ -> []
  | _ -> (
      match (t.editing, selected t) with
      | None, (_ :: _ :: _ as shapes) -> List.map (shape_box t) shapes
      | None, [ s ] when Shape.is_line s -> [ shape_box t s ]
      | _ -> [])

let transforming t =
  match t.gesture with Translating _ | Resizing _ | Rotating _ | Moving_end _ -> true | _ -> false

let busy t = (match t.gesture with Idle -> false | _ -> true) || Option.is_some t.editing

let edge_handle_room = 40.

let handles t =
  if transforming t || Option.is_some t.editing then []
  else
    match t.gesture with
    | Marquee _ | Creating _ | Drawing _ | Erasing _ -> []
    | _ -> (
        let screen p = Camera.to_screen t.camera p in
        match selected t with
        | [] -> []
        | [ s ] when Shape.is_line s -> (
            match Shape.ends s with Some (a, b) -> [ (Start, screen a); (End, screen b) ] | None -> [])
        | _ -> (
            match selection_frame t with
            | None -> []
            | Some f ->
                let c = Array.map screen (Geom.Frame.corners f) in
                let tl = c.(0) and tr = c.(1) and br = c.(2) and bl = c.(3) in
                let sw = Vec.dist tl tr and sh = Vec.dist tl bl in
                let up = Vec.rotate (Vec.make 0. (-1.)) f.rotation in
                let rotate = Vec.add (Vec.mid tl tr) (Vec.scale up 22.) in
                let edges_x = sh >= edge_handle_room and edges_y = sw >= edge_handle_room in
                [ (Rotate, rotate); (NW, tl); (NE, tr); (SE, br); (SW, bl) ]
                @ (if edges_y then [ (N, Vec.mid tl tr); (S, Vec.mid bl br) ] else [])
                @ if edges_x then [ (W, Vec.mid tl bl); (E, Vec.mid tr br) ] else []))

let handle_at t (p : pointer) =
  let reach = match p.device with Touch -> 16. | Pen -> 10. | Mouse -> 8. in
  let hs = handles t in
  let near =
    List.fold_left
      (fun best (h, at) ->
        let d = Vec.dist at p.screen in
        if d > reach then best else match best with Some (_, bd) when bd <= d -> best | _ -> Some (h, d))
      None hs
  in
  match near with
  | Some (h, _) -> Some h
  | None -> (
      match selection_frame t with
      | None -> None
      | Some f -> (
          match hs with
          | [] | [ _; _ ] -> None
          | _ ->
              let c = Array.map (Camera.to_screen t.camera) (Geom.Frame.corners f) in
              let edge h a b =
                let has = List.exists (fun (x, _) -> x = h) hs in
                if has && Geom.dist_to_segment p.screen a b <= reach *. 0.75 then Some h else None
              in
              List.find_map Fun.id [ edge N c.(0) c.(1); edge E c.(1) c.(2); edge S c.(2) c.(3); edge W c.(3) c.(0) ]))

let erasing t = match t.gesture with Erasing { marked; _ } -> marked | _ -> []
let drawing t = match t.gesture with Drawing { path; _ } -> Some (path, t.style) | _ -> None

let marquee t =
  match t.gesture with Marquee { start; current; _ } -> Some (Geom.Box.of_corners start current) | _ -> None

let handle_angle = function
  | E -> 0.
  | SE -> Float.pi /. 4.
  | S -> Float.pi /. 2.
  | SW -> 3. *. Float.pi /. 4.
  | W -> Float.pi
  | NW -> 5. *. Float.pi /. 4.
  | N -> 3. *. Float.pi /. 2.
  | NE -> 7. *. Float.pi /. 4.
  | Rotate | Start | End -> 0.

let frame_rotation t = match selection_frame t with Some f -> f.rotation | None -> 0.

let cursor t =
  match t.gesture with
  | Panning _ | Pinching _ -> Grabbing
  | Resizing { handle; frame; _ } -> Resize (handle_angle handle +. frame.rotation)
  | Rotating _ -> Rotate_cursor
  | Moving_end _ | Translating _ -> Default
  | Drawing _ | Creating _ | Erasing _ -> Cross
  | Pointing _ | Marquee _ -> Default
  | Idle -> (
      if t.space || t.tool = Hand then Grab
      else
        match t.tool with
        | Select -> (
            match t.hover_handle with
            | Some Rotate -> Rotate_cursor
            | Some (Start | End) -> Move
            | Some h -> Resize (handle_angle h +. frame_rotation t)
            | None -> Default)
        | Text -> Text_cursor
        | Hand -> Grab
        | Draw | Rect | Ellipse | Arrow | Line | Eraser -> Cross)

let gesture_pointer = function
  | Idle | Pinching _ -> None
  | Panning { pointer; _ }
  | Drawing { pointer; _ }
  | Creating { pointer; _ }
  | Pointing { pointer; _ }
  | Translating { pointer; _ }
  | Resizing { pointer; _ }
  | Rotating { pointer; _ }
  | Moving_end { pointer; _ }
  | Marquee { pointer; _ }
  | Erasing { pointer; _ } ->
      Some pointer

let restore t (before : snapshot) = { t with board = before.board; selection = before.selection }

let cancel_gesture t =
  let t =
    match t.gesture with
    | Idle | Panning _ | Pinching _ | Drawing _ | Erasing _ -> t
    | Marquee { base; _ } -> { t with selection = base }
    | Creating { before; _ }
    | Pointing { before; _ }
    | Translating { before; _ }
    | Resizing { before; _ }
    | Rotating { before; _ }
    | Moving_end { before; _ } ->
        restore t before
  in
  { t with gesture = Idle }

let stop_editing t =
  match t.editing with
  | None -> t
  | Some e -> (
      let t = { t with editing = None; tool = Select } in
      match Board.find t.board e.shape with
      | None -> t
      | Some s ->
          let empty = String.trim (Option.value (Shape.text_of s) ~default:"") = "" in
          if empty && e.created then restore t e.before
          else if empty then commit { t with board = Board.remove t.board [ e.shape ]; selection = [] } ~before:e.before
          else commit { t with selection = [ e.shape ] } ~before:e.before)

let start_editing t ~shape ~before ~created =
  { t with editing = Some { shape; before; created }; selection = [ shape ]; hover = None; gesture = Idle }

let set_text t text =
  match t.editing with
  | None -> t
  | Some e -> (
      match Board.find t.board e.shape with
      | Some s -> { t with board = Board.replace t.board [ Shape.set_text t.metrics s text ] }
      | None -> t)

let new_text t (at : Vec.t) =
  let before = snapshot t in
  let id, board = Board.fresh_id t.board in
  let font = Shape.font_size (Shape.text t.metrics ~id ~style:t.style ~scale:1. Vec.zero "") in
  let origin = Vec.sub at (Vec.make 2. (font *. Shape.line_height /. 2.)) in
  let shape = Shape.text t.metrics ~id ~style:t.style ~scale:1. origin "" in
  start_editing { t with board = Board.add board shape; tool = Text } ~shape:id ~before ~created:true

let sole_text t = match selected t with [ s ] when Shape.is_text s -> true | _ -> false

let needs_ratio_lock t (frame : Geom.Frame.t) =
  sole_text t
  || List.exists
       (fun (s : Shape.t) ->
         (not (Shape.is_line s))
         &&
         let d = Geom.normalize_angle (s.rotation -. frame.rotation) /. (Float.pi /. 2.) in
         Float.abs (d -. Float.round d) > 1e-6)
       (selected t)

let start_select t (p : pointer) =
  let w = world t p.screen in
  let before = snapshot t in
  let pointing on_up = Pointing { pointer = p.id; start_screen = p.screen; start = w; on_up; before } in
  match handle_at t p with
  | Some ((Start | End) as which) -> (
      match selected t with
      | [ s ] -> { t with gesture = Moving_end { pointer = p.id; which; original = s; before } }
      | _ -> t)
  | Some Rotate -> (
      match selection_frame t with
      | Some f ->
          let center = Geom.Frame.center f in
          {
            t with
            gesture =
              Rotating
                {
                  pointer = p.id;
                  center;
                  start_angle = Vec.angle (Vec.sub w center);
                  base = f.rotation;
                  originals = selected t;
                  before;
                };
          }
      | None -> t)
  | Some handle -> (
      match tight_frame t with
      | Some frame ->
          {
            t with
            gesture =
              Resizing
                {
                  pointer = p.id;
                  handle;
                  frame;
                  start = w;
                  originals = selected t;
                  locked = needs_ratio_lock t frame;
                  before;
                };
          }
      | None -> t)
  | None -> (
      match Board.top_hit t.board ~tolerance:(tolerance t p.device) w with
      | Some s ->
          let is_selected = mem s.id t.selection in
          if p.shift then
            if is_selected then { t with gesture = pointing (Deselect s.id) }
            else { t with selection = t.selection @ [ s.id ]; gesture = pointing Keep }
          else if is_selected then { t with gesture = pointing (Select_only s.id) }
          else { t with selection = [ s.id ]; gesture = pointing Keep }
      | None -> (
          let inside_frame =
            match (selection_frame t, selected t) with
            | Some f, shapes when not (match shapes with [ s ] -> Shape.is_line s | _ -> false) ->
                let l = Geom.Frame.to_local f w in
                l.x >= 0. && l.y >= 0. && l.x <= f.w && l.y <= f.h
            | _ -> false
          in
          if inside_frame && not p.shift then { t with gesture = pointing Clear }
          else
            let base = if p.shift then t.selection else [] in
            { t with selection = base; gesture = Marquee { pointer = p.id; start = w; current = w; base } }))

let pressure_of (p : pointer) = match p.device with Pen when p.pressure > 0. -> p.pressure | _ -> 0.5

let freehand_point t (p : pointer) =
  let w = world t p.screen in
  { Freehand.x = w.x; y = w.y; pressure = pressure_of p }

let draw_path t ~simulate points =
  Freehand.path
    (Freehand.options ~size:(Shape.pen_size t.style.size) ~simulate ~complete:false)
    (Array.of_list (List.rev points))

let erase_hits t ~device a b =
  let tol = tolerance t device in
  let reach = Geom.Box.expand (Geom.Box.of_corners a b) (tol +. 8.) in
  Array.fold_left
    (fun acc (s : Shape.t) ->
      if Geom.Box.intersects (Shape.visual_bounds s) reach && Shape.touches_segment s ~tolerance:tol a b then s.id :: acc
      else acc)
    [] (Board.shapes t.board)

let start_pinch t =
  match t.touches with
  | (b, pb) :: (a, pa) :: _ ->
      let t = cancel_gesture t in
      { t with gesture = Pinching { a; b; distance = Vec.dist pa pb; center = Vec.mid pa pb; camera = t.camera }; hover = None }
  | _ -> t

let pointer_down t (p : pointer) =
  let t = { t with pointer = Some p.screen } in
  let t =
    match p.device with
    | Touch -> { t with touches = (p.id, p.screen) :: List.filter (fun (i, _) -> i <> p.id) t.touches }
    | Mouse | Pen -> t
  in
  match (p.device, t.touches) with
  | Touch, [ _; _ ] -> start_pinch t
  | _ -> (
      match t.gesture with
      | Idle when Option.is_some t.editing -> stop_editing t
      | Idle ->
          let w = world t p.screen in
          let before = snapshot t in
          if p.button = 1 || (p.button = 0 && t.space) || (p.button = 0 && t.tool = Hand) then
            { t with gesture = Panning { pointer = p.id; last = p.screen } }
          else if p.button = 5 || (p.button = 0 && t.tool = Eraser) then
            { t with gesture = Erasing { pointer = p.id; last = w; marked = erase_hits t ~device:p.device w w }; hover = None }
          else if p.button <> 0 then t
          else begin
            match t.tool with
            | Select -> start_select t p
            | Draw ->
                let points = [ freehand_point t p ] in
                let simulate = match p.device with Pen when p.pressure > 0. -> false | _ -> true in
                { t with gesture = Drawing { pointer = p.id; points; simulate; path = draw_path t ~simulate points }; hover = None }
            | Rect | Ellipse | Arrow | Line ->
                let kind =
                  match t.tool with Rect -> Make_rect | Ellipse -> Make_ellipse | Arrow -> Make_arrow | _ -> Make_line
                in
                { t with gesture = Creating { pointer = p.id; kind; start = w; id = None; before }; hover = None; selection = [] }
            | Text -> new_text t w
            | Hand | Eraser -> t
          end
      | _ -> t)

let snap15 = Float.pi /. 12.

let snapped_end (a : Vec.t) (b : Vec.t) =
  let d = Vec.sub b a in
  let angle = Geom.snap_angle ~step:snap15 (Vec.angle d) in
  let u = Vec.make (Float.cos angle) (Float.sin angle) in
  Vec.add a (Vec.scale u (Vec.dot d u))

let box_for ~start ~(current : Vec.t) ~(p : pointer) =
  let d = Vec.sub current start in
  let d =
    if p.shift then
      let side = Float.max (Float.abs d.x) (Float.abs d.y) in
      Vec.make (if d.x < 0. then -.side else side) (if d.y < 0. then -.side else side)
    else d
  in
  if p.alt then Geom.Box.of_corners (Vec.sub start d) (Vec.add start d) else Geom.Box.of_corners start (Vec.add start d)

let make_shape t kind ~id ~start ~current ~(p : pointer) =
  match kind with
  | Make_rect -> Shape.rect ~id ~style:t.style (box_for ~start ~current ~p)
  | Make_ellipse -> Shape.ellipse ~id ~style:t.style (box_for ~start ~current ~p)
  | Make_line | Make_arrow ->
      let b = if p.shift then snapped_end start current else current in
      let a = if p.alt then Vec.sub start (Vec.sub b start) else start in
      Shape.line ~id ~style:t.style ~arrow:(kind = Make_arrow) a b

let translate_selection t ~start ~originals (p : pointer) =
  let w = world t p.screen in
  let d = Vec.sub w start in
  let d = if p.shift then if Float.abs d.x >= Float.abs d.y then Vec.make d.x 0. else Vec.make 0. d.y else d in
  { t with board = Board.replace t.board (List.map (fun s -> Shape.translate s d) originals) }

let sign v = if v < 0. then -1. else 1.

let resize_selection t ~handle ~(frame : Geom.Frame.t) ~start ~originals ~locked (p : pointer) =
  let w = world t p.screen in
  let d = Vec.rotate (Vec.sub w start) (-.frame.rotation) in
  let fw = frame.w and fh = frame.h in
  let moves_e = (match handle with E | NE | SE -> true | _ -> false)
  and moves_w = (match handle with W | NW | SW -> true | _ -> false)
  and moves_n = (match handle with N | NE | NW -> true | _ -> false)
  and moves_s = match handle with S | SE | SW -> true | _ -> false in
  let x0 = ref 0. and x1 = ref fw and y0 = ref 0. and y1 = ref fh in
  if moves_e then (
    x1 := fw +. d.x;
    if p.alt then x0 := -.d.x);
  if moves_w then (
    x0 := d.x;
    if p.alt then x1 := fw -. d.x);
  if moves_s then (
    y1 := fh +. d.y;
    if p.alt then y0 := -.d.y);
  if moves_n then (
    y0 := d.y;
    if p.alt then y1 := fh -. d.y);
  let sx = if fw > 1e-9 then (!x1 -. !x0) /. fw else 1. in
  let sy = if fh > 1e-9 then (!y1 -. !y0) /. fh else 1. in
  let horizontal = moves_e || moves_w and vertical = moves_n || moves_s in
  let sx, sy =
    if not (locked || p.shift) then ((if horizontal then sx else 1.), if vertical then sy else 1.)
    else if horizontal && vertical then
      let s = Float.max (Float.abs sx) (Float.abs sy) in
      (sign sx *. s, sign sy *. s)
    else if horizontal then (sx, Float.abs sx)
    else (Float.abs sy, sy)
  in
  let ax = if p.alt || not horizontal then fw /. 2. else if moves_e then 0. else fw in
  let ay = if p.alt || not vertical then fh /. 2. else if moves_s then 0. else fh in
  let map world_point =
    let l = Geom.Frame.to_local frame world_point in
    Geom.Frame.to_world frame (Vec.make (ax +. (sx *. (l.x -. ax))) (ay +. (sy *. (l.y -. ay))))
  in
  {
    t with
    board =
      Board.replace t.board (List.map (fun s -> Shape.resize s ~rotation:frame.rotation ~map ~sx ~sy) originals);
  }

let rotate_selection t ~center ~start_angle ~base ~originals (p : pointer) =
  let w = world t p.screen in
  let delta = Vec.angle (Vec.sub w center) -. start_angle in
  let delta = if p.shift then Geom.snap_angle ~step:snap15 (base +. delta) -. base else delta in
  { t with board = Board.replace t.board (List.map (fun s -> Shape.rotate_about s ~center delta) originals) }

let move_end t ~which ~original (p : pointer) =
  match Shape.ends original with
  | None -> t
  | Some (a, b) ->
      let w = world t p.screen in
      let a, b =
        match which with
        | Start -> ((if p.shift then snapped_end b w else w), b)
        | _ -> (a, if p.shift then snapped_end a w else w)
      in
      { t with board = Board.replace t.board [ Shape.set_ends original a b ] }

let update_hover t (p : pointer) =
  match (t.tool, p.device) with
  | Select, (Mouse | Pen) ->
      let hover_handle = handle_at t p in
      let hover =
        match hover_handle with
        | Some _ -> None
        | None -> Option.map (fun (s : Shape.t) -> s.id) (Board.top_hit t.board ~tolerance:(tolerance t p.device) (world t p.screen))
      in
      if hover = t.hover && hover_handle = t.hover_handle then t else { t with hover; hover_handle }
  | _ -> if Option.is_none t.hover && Option.is_none t.hover_handle then t else { t with hover = None; hover_handle = None }

let move_one t (p : pointer) =
  match t.gesture with
  | Idle -> update_hover t p
  | Pinching _ -> t
  | g when gesture_pointer g <> Some p.id -> t
  | Panning { pointer; last } ->
      { t with camera = Camera.pan t.camera (Vec.sub p.screen last); gesture = Panning { pointer; last = p.screen } }
  | Drawing { pointer; points; simulate; _ } ->
      let points = freehand_point t p :: points in
      { t with gesture = Drawing { pointer; points; simulate; path = "" } }
  | Creating { pointer; kind; start; id; before } ->
      let w = world t p.screen in
      let dragged = Vec.dist (Camera.to_screen t.camera start) p.screen > drag_threshold p.device in
      if Option.is_none id && not dragged then t
      else
        let id, board = match id with Some id -> (id, t.board) | None -> Board.fresh_id t.board in
        let shape = make_shape t kind ~id ~start ~current:w ~p in
        { t with board = Board.add board shape; gesture = Creating { pointer; kind; start; id = Some id; before } }
  | Pointing { pointer; start_screen; start; before; _ } ->
      if Vec.dist start_screen p.screen <= drag_threshold p.device then t
      else
        let originals = selected t in
        let t = { t with gesture = Translating { pointer; start; originals; before }; hover = None } in
        translate_selection t ~start ~originals p
  | Translating { start; originals; _ } -> translate_selection t ~start ~originals p
  | Resizing { handle; frame; start; originals; locked; _ } -> resize_selection t ~handle ~frame ~start ~originals ~locked p
  | Rotating { center; start_angle; base; originals; _ } -> rotate_selection t ~center ~start_angle ~base ~originals p
  | Moving_end { which; original; _ } -> move_end t ~which ~original p
  | Marquee { pointer; start; base; _ } ->
      let current = world t p.screen in
      let inside = Board.in_box t.board (Geom.Box.of_corners start current) in
      let selection = base @ List.filter (fun id -> not (mem id base)) inside in
      { t with gesture = Marquee { pointer; start; current; base }; selection }
  | Erasing { pointer; last; marked } ->
      let w = world t p.screen in
      let hits = erase_hits t ~device:p.device last w in
      let marked = List.fold_left (fun acc id -> if mem id acc then acc else id :: acc) marked hits in
      { t with gesture = Erasing { pointer; last = w; marked } }

let pinch_move t =
  match t.gesture with
  | Pinching { a; b; distance; center; camera } -> (
      match (List.assoc_opt a t.touches, List.assoc_opt b t.touches) with
      | Some pa, Some pb ->
          let now = Vec.mid pa pb in
          let zoom = if distance > 0. then camera.zoom *. (Vec.dist pa pb /. distance) else camera.zoom in
          { t with camera = Camera.pan (Camera.zoom_at camera center zoom) (Vec.sub now center) }
      | _ -> t)
  | _ -> t

let pointer_move t samples =
  match List.rev samples with
  | [] -> t
  | (last : pointer) :: _ -> (
      let t = { t with pointer = Some last.screen } in
      let t =
        match last.device with
        | Touch when List.mem_assoc last.id t.touches ->
            { t with touches = List.map (fun (i, s) -> if i = last.id then (i, last.screen) else (i, s)) t.touches }
        | _ -> t
      in
      match t.gesture with
      | Pinching _ -> pinch_move t
      | Drawing { pointer; _ } when pointer = last.id ->
          let t = List.fold_left move_one t samples in
          (match t.gesture with
          | Drawing { pointer; points; simulate; _ } ->
              { t with gesture = Drawing { pointer; points; simulate; path = draw_path t ~simulate points } }
          | _ -> t)
      | _ -> move_one t last)

let finish t (p : pointer) =
  match t.gesture with
  | Idle | Pinching _ -> t
  | g when gesture_pointer g <> Some p.id -> t
  | Panning _ -> { t with gesture = Idle }
  | Drawing { points; simulate; _ } -> (
      let before = snapshot t in
      let id, board = Board.fresh_id t.board in
      let points = List.rev (freehand_point t p :: points) in
      let points =
        match points with
        | first :: rest ->
            let rec drop_dup = function
              | [ a; b ] when a.Freehand.x = b.Freehand.x && a.y = b.y -> [ a ]
              | x :: rest -> x :: drop_dup rest
              | [] -> []
            in
            drop_dup (first :: rest)
        | [] -> []
      in
      match Shape.draw ~id ~style:t.style ~simulate points with
      | Some shape -> commit { t with board = Board.add board shape; gesture = Idle } ~before
      | None -> { t with gesture = Idle })
  | Creating { kind; start; id; before; _ } -> (
      match (id, kind) with
      | Some id, _ -> commit { t with gesture = Idle; tool = Select; selection = [ id ] } ~before
      | None, (Make_rect | Make_ellipse) ->
          let id, board = Board.fresh_id t.board in
          let box = { Geom.Box.x = start.x -. 50.; y = start.y -. 50.; w = 100.; h = 100. } in
          let shape =
            if kind = Make_rect then Shape.rect ~id ~style:t.style box else Shape.ellipse ~id ~style:t.style box
          in
          commit { t with board = Board.add board shape; gesture = Idle; tool = Select; selection = [ id ] } ~before
      | None, (Make_line | Make_arrow) -> { t with gesture = Idle })
  | Pointing { on_up; _ } ->
      let selection =
        match on_up with
        | Keep -> t.selection
        | Select_only id -> [ id ]
        | Deselect id -> without id t.selection
        | Clear -> []
      in
      { t with gesture = Idle; selection }
  | Translating { before; _ } | Resizing { before; _ } | Rotating { before; _ } | Moving_end { before; _ } ->
      commit { t with gesture = Idle } ~before
  | Marquee _ -> { t with gesture = Idle }
  | Erasing { marked; _ } ->
      let before = snapshot t in
      let t = { t with gesture = Idle } in
      match marked with
      | [] -> t
      | _ ->
        commit
          { t with board = Board.remove t.board marked; selection = List.filter (fun id -> not (mem id marked)) t.selection }
          ~before

let drop_touch t id = { t with touches = List.filter (fun (i, _) -> i <> id) t.touches }

let pointer_up t (p : pointer) =
  let t = { t with pointer = Some p.screen } in
  match t.gesture with
  | Pinching { a; b; _ } when p.id = a || p.id = b -> { (drop_touch t p.id) with gesture = Idle }
  | _ ->
      let t = finish t p in
      let t = drop_touch t p.id in
      update_hover t p

let pointer_cancel t id =
  let t = drop_touch t id in
  match t.gesture with
  | Pinching { a; b; _ } when id = a || id = b -> { t with gesture = Idle }
  | g when gesture_pointer g = Some id -> cancel_gesture t
  | _ -> t

let blur t = { (cancel_gesture t) with space = false; touches = [] }

let double_click t screen =
  match (t.tool, t.gesture) with
  | Select, Idle -> (
      let w = world t screen in
      match Board.top_hit t.board ~tolerance:(tolerance t Mouse) w with
      | Some s when Shape.is_text s -> start_editing t ~shape:s.id ~before:(snapshot t) ~created:false
      | Some _ -> t
      | None -> new_text t w)
  | _ -> t

let wheel t ~at ~dx ~dy ~ctrl =
  if ctrl then
    let dy = Num.clamp ~lo:(-20.) ~hi:20. dy in
    { t with camera = Camera.zoom_at t.camera at (t.camera.zoom *. Float.exp (-.dy /. 100.)) }
  else { t with camera = Camera.pan t.camera (Vec.make (-.dx) (-.dy)) }

let viewport_center t = Vec.make (t.width /. 2.) (t.height /. 2.)

let set_tool t tool =
  if t.tool = tool && Option.is_none t.editing then t
  else
    let t = stop_editing (cancel_gesture t) in
    { t with tool; selection = (if tool = Select then t.selection else []); hover = None; hover_handle = None }

let set_style t change =
  let t = { t with style = change t.style } in
  match List.filter (fun (s : Shape.t) -> change s.style <> s.style) (selected t) with
  | [] -> t
  | shapes ->
      let before = snapshot t in
      let t = { t with board = Board.replace t.board (List.map (fun (s : Shape.t) -> Shape.set_style t.metrics s (change s.style)) shapes) } in
      if Option.is_some t.editing then t else commit t ~before

let set_color t color = set_style t (fun s -> { s with color })
let set_size t size = set_style t (fun s -> { s with size })
let set_fill t fill = set_style t (fun s -> { s with fill })

let undo t =
  let t = stop_editing (cancel_gesture t) in
  match History.undo t.history ~current:(snapshot t) with
  | Some (history, s) -> { (restore t s) with history; hover = None }
  | None -> t

let redo t =
  let t = stop_editing (cancel_gesture t) in
  match History.redo t.history ~current:(snapshot t) with
  | Some (history, s) -> { (restore t s) with history; hover = None }
  | None -> t

let delete t =
  match t.selection with
  | [] -> t
  | ids -> commit { t with board = Board.remove t.board ids; selection = []; hover = None } ~before:(snapshot t)

let copy t = match selected t with [] -> t | shapes -> { t with clipboard = shapes }
let cut t = delete (copy t)

let insert t shapes ~offset =
  let before = snapshot t in
  let board, ids = Board.insert_copies t.board shapes ~offset in
  commit { t with board; selection = ids; tool = Select } ~before

let duplicate t =
  match selected t with
  | [] -> t
  | shapes ->
      let d = 16. /. t.camera.zoom in
      insert t shapes ~offset:(Vec.make d d)

let paste t =
  match t.clipboard with
  | [] -> t
  | shapes -> (
      let t = stop_editing t in
      let inside (p : Vec.t) = p.x >= 0. && p.y >= 0. && p.x <= t.width && p.y <= t.height in
      let bounds =
        List.fold_left
          (fun acc s ->
            let b = Shape.bounds s in
            match acc with None -> Some b | Some a -> Some (Geom.Box.union a b))
          None shapes
      in
      match (t.pointer, bounds) with
      | Some p, Some b when inside p -> insert t shapes ~offset:(Vec.sub (world t p) (Geom.Box.center b))
      | _ ->
          let d = 16. /. t.camera.zoom in
          insert t shapes ~offset:(Vec.make d d))

let to_front t =
  match t.selection with [] -> t | ids -> commit { t with board = Board.to_front t.board ids } ~before:(snapshot t)

let to_back t =
  match t.selection with [] -> t | ids -> commit { t with board = Board.to_back t.board ids } ~before:(snapshot t)

let select_all t =
  let t = stop_editing (cancel_gesture t) in
  { t with tool = Select; selection = Array.to_list (Array.map (fun (s : Shape.t) -> s.id) (Board.shapes t.board)) }

let zoom_in t = { t with camera = Camera.zoom_in t.camera (viewport_center t) }
let zoom_out t = { t with camera = Camera.zoom_out t.camera (viewport_center t) }

let zoom_to_fit t =
  match Board.all_bounds t.board with
  | Some b -> { t with camera = Camera.fit b ~width:t.width ~height:t.height }
  | None -> { t with camera = Camera.initial }

let zoom_reset t = { t with camera = Camera.zoom_at t.camera (viewport_center t) 1. }

let nudge t (d : Vec.t) =
  match selected t with
  | [] -> t
  | shapes ->
      commit { t with board = Board.replace t.board (List.map (fun s -> Shape.translate s d) shapes) } ~before:(snapshot t)

let escape t =
  match t.gesture with
  | Idle -> (
      match t.selection with
      | _ :: _ -> { t with selection = [] }
      | [] -> if t.tool <> Select then { t with tool = Select } else t)
  | _ -> cancel_gesture t

let tool_of_key = function
  | "v" -> Some Select
  | "h" -> Some Hand
  | "d" | "p" -> Some Draw
  | "r" -> Some Rect
  | "o" -> Some Ellipse
  | "a" -> Some Arrow
  | "l" -> Some Line
  | "t" -> Some Text
  | "e" -> Some Eraser
  | _ -> None

let key_down t (k : key) =
  if Option.is_some t.editing then
    match k.key with
    | "Escape" -> (stop_editing t, true)
    | "Enter" when k.ctrl -> (stop_editing t, true)
    | _ -> (t, false)
  else
    let lower = String.lowercase_ascii k.key in
    if k.ctrl then
      match lower with
      | "z" when k.shift -> (redo t, true)
      | "z" -> (undo t, true)
      | "y" -> (redo t, true)
      | "a" -> (select_all t, true)
      | "d" -> (duplicate t, true)
      | "c" -> (copy t, true)
      | "x" -> (cut t, true)
      | "v" -> (paste t, true)
      | "=" | "+" -> (zoom_in t, true)
      | "-" -> (zoom_out t, true)
      | "0" -> (zoom_reset t, true)
      | _ -> (t, false)
    else
      let step = if k.shift then 10. else 1. in
      match k.key with
      | " " -> ({ t with space = true; hover = None }, true)
      | "Escape" -> (escape t, true)
      | "Delete" | "Backspace" -> (delete t, true)
      | "ArrowLeft" -> (nudge t (Vec.make (-.step) 0.), true)
      | "ArrowRight" -> (nudge t (Vec.make step 0.), true)
      | "ArrowUp" -> (nudge t (Vec.make 0. (-.step)), true)
      | "ArrowDown" -> (nudge t (Vec.make 0. step), true)
      | "=" | "+" -> (zoom_in t, true)
      | "-" | "_" -> (zoom_out t, true)
      | "!" -> (zoom_to_fit t, true)
      | ")" -> (zoom_reset t, true)
      | "1" when k.shift -> (zoom_to_fit t, true)
      | "0" when k.shift -> (zoom_reset t, true)
      | "]" -> (to_front t, true)
      | "[" -> (to_back t, true)
      | _ when k.alt || k.shift -> (t, false)
      | _ -> ( match tool_of_key lower with Some tool -> (set_tool t tool, true) | None -> (t, false))

let key_up t (k : key) = if k.key = " " then { t with space = false } else t
