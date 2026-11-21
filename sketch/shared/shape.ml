type color = Black | Grey | Red | Orange | Yellow | Green | Blue | Violet
type size = S | M | L
type fill = Hollow | Semi | Solid
type style = { color : color; size : size; fill : fill }

let colors = [ Black; Grey; Red; Orange; Yellow; Green; Blue; Violet ]

let color_name = function
  | Black -> "black"
  | Grey -> "grey"
  | Red -> "red"
  | Orange -> "orange"
  | Yellow -> "yellow"
  | Green -> "green"
  | Blue -> "blue"
  | Violet -> "violet"

let size_name = function S -> "s" | M -> "m" | L -> "l"
let fill_name = function Hollow -> "none" | Semi -> "semi" | Solid -> "solid"
let default_style = { color = Black; size = M; fill = Hollow }

type metrics = { width : font:float -> string -> float; ascent : float; descent : float }

type kind =
  | Rect
  | Ellipse
  | Draw of { points : Freehand.point array; simulate : bool; path : string }
  | Line of { start : Vec.t; end_ : Vec.t; arrow : bool }
  | Text of { text : string; scale : float }

type t = { id : int; x : float; y : float; w : float; h : float; rotation : float; style : style; kind : kind }

let stroke_width style = match style.size with S -> 2. | M -> 3.5 | L -> 6.
let pen_size = function S -> 4.5 | M -> 8. | L -> 14.
let base_font = function S -> 18. | M -> 26. | L -> 38.
let line_height = 1.3
let font_of style scale = base_font style.size *. scale
let font_size t = match t.kind with Text { scale; _ } -> font_of t.style scale | _ -> 0.
let is_line t = match t.kind with Line _ -> true | _ -> false
let is_text t = match t.kind with Text _ -> true | _ -> false
let with_id t id = { t with id }

let rect ~id ~style (b : Geom.Box.t) = { id; x = b.x; y = b.y; w = b.w; h = b.h; rotation = 0.; style; kind = Rect }
let ellipse ~id ~style (b : Geom.Box.t) = { (rect ~id ~style b) with kind = Ellipse }

let draw_path ~style ~simulate points =
  Freehand.path (Freehand.options ~size:(pen_size style.size) ~simulate ~complete:true) points

let draw ~id ~style ~simulate (points : Freehand.point list) =
  match Geom.Box.of_points (List.map (fun (p : Freehand.point) -> Vec.make p.x p.y) points) with
  | None -> None
  | Some b ->
      let points =
        Array.of_list (List.map (fun (p : Freehand.point) -> { p with x = p.x -. b.x; y = p.y -. b.y }) points)
      in
      Some
        {
          id;
          x = b.x;
          y = b.y;
          w = b.w;
          h = b.h;
          rotation = 0.;
          style;
          kind = Draw { points; simulate; path = draw_path ~style ~simulate points };
        }

let line ~id ~style ~arrow (a : Vec.t) (b : Vec.t) =
  let box = Geom.Box.of_corners a b in
  let origin = Vec.make box.x box.y in
  {
    id;
    x = box.x;
    y = box.y;
    w = box.w;
    h = box.h;
    rotation = 0.;
    style;
    kind = Line { start = Vec.sub a origin; end_ = Vec.sub b origin; arrow };
  }

let text_padding = 0.2

let text_size metrics ~font text =
  let lines = String.split_on_char '\n' text in
  let width = List.fold_left (fun acc line -> Float.max acc (metrics.width ~font line)) 0. lines in
  (Float.max width (font *. 0.5) +. (2. *. text_padding *. font), float_of_int (List.length lines) *. font *. line_height)

let text metrics ~id ~style ~scale (at : Vec.t) text =
  let w, h = text_size metrics ~font:(font_of style scale) text in
  { id; x = at.x; y = at.y; w; h; rotation = 0.; style; kind = Text { text; scale } }

let center t = Vec.make (t.x +. (t.w /. 2.)) (t.y +. (t.h /. 2.))

let frame t =
  let c = center t in
  { Geom.Frame.origin = Vec.add c (Vec.rotate (Vec.make (-.t.w /. 2.) (-.t.h /. 2.)) t.rotation); w = t.w; h = t.h; rotation = t.rotation }

let to_world t (p : Vec.t) =
  if t.rotation = 0. then Vec.make (t.x +. p.x) (t.y +. p.y)
  else Vec.add (center t) (Vec.rotate (Vec.make (p.x -. (t.w /. 2.)) (p.y -. (t.h /. 2.))) t.rotation)

let ends t =
  match t.kind with Line { start; end_; _ } -> Some (to_world t start, to_world t end_) | _ -> None

let ellipse_points t =
  let n = 64 in
  let rx = t.w /. 2. and ry = t.h /. 2. in
  Array.init n (fun i ->
      let a = 2. *. Float.pi *. float_of_int i /. float_of_int n in
      to_world t (Vec.make (rx +. (rx *. Float.cos a)) (ry +. (ry *. Float.sin a))))

let box_points t = Array.map (to_world t) [| Vec.zero; Vec.make t.w 0.; Vec.make t.w t.h; Vec.make 0. t.h |]

type outline = { points : Vec.t array; closed : bool }

let outline t =
  match t.kind with
  | Rect | Text _ -> { points = box_points t; closed = true }
  | Ellipse -> { points = ellipse_points t; closed = true }
  | Draw { points; _ } -> { points = Array.map (fun (p : Freehand.point) -> to_world t (Vec.make p.x p.y)) points; closed = false }
  | Line { start; end_; _ } -> { points = [| to_world t start; to_world t end_ |]; closed = false }

let iter_segments o f =
  let n = Array.length o.points in
  if n = 1 then f o.points.(0) o.points.(0)
  else begin
    for i = 0 to n - 2 do
      f o.points.(i) o.points.(i + 1)
    done;
    if o.closed && n > 2 then f o.points.(n - 1) o.points.(0)
  end

let exists_segment o f =
  let found = ref false in
  iter_segments o (fun a b -> if (not !found) && f a b then found := true);
  !found

let bounds t =
  match Geom.Box.of_points (Array.to_list (outline t).points) with
  | Some b -> b
  | None -> { Geom.Box.x = t.x; y = t.y; w = t.w; h = t.h }

let half_stroke t =
  match t.kind with
  | Draw _ -> pen_size t.style.size /. 2.
  | Text _ -> 0.
  | Rect | Ellipse | Line _ -> stroke_width t.style /. 2.

let arrowhead_length t =
  match t.kind with
  | Line { arrow = true; start; end_ } -> Float.min ((stroke_width t.style *. 3.) +. 8.) (Vec.dist start end_ *. 0.4)
  | _ -> 0.

let visual_bounds t =
  let extra = arrowhead_length t in
  Geom.Box.expand (bounds t) (half_stroke t +. extra +. 1.)

type hit = Miss | Edge | Inside

let distance_to o p =
  let best = ref Float.infinity in
  iter_segments o (fun a b -> best := Float.min !best (Geom.dist_to_segment p a b));
  !best

let hit t ~tolerance p =
  match t.kind with
  | Text _ ->
      let l = Geom.Frame.to_local (frame t) p in
      if l.x >= -.tolerance && l.x <= t.w +. tolerance && l.y >= -.tolerance && l.y <= t.h +. tolerance then Edge else Miss
  | Rect | Ellipse ->
      let o = outline t in
      if distance_to o p <= tolerance +. half_stroke t then Edge
      else if Geom.inside_polygon o.points p then if t.style.fill = Hollow then Inside else Edge
      else Miss
  | Draw _ | Line _ -> if distance_to (outline t) p <= tolerance +. half_stroke t then Edge else Miss

let touches_box t box =
  let o = outline t in
  exists_segment o (fun a b -> Geom.segment_hits_box a b box)

let segment_distance a b c d =
  if Geom.segments_cross a b c d then 0.
  else
    Float.min
      (Float.min (Geom.dist_to_segment a c d) (Geom.dist_to_segment b c d))
      (Float.min (Geom.dist_to_segment c a b) (Geom.dist_to_segment d a b))

let touches_segment t ~tolerance a b =
  let o = outline t in
  let reach = tolerance +. half_stroke t in
  exists_segment o (fun c d -> segment_distance a b c d <= reach)
  || (match t.kind with Text _ -> hit t ~tolerance a = Edge | _ -> false)

let translate t (d : Vec.t) = { t with x = t.x +. d.x; y = t.y +. d.y }

let with_line_ends t a b =
  match t.kind with
  | Line { arrow; _ } -> { (line ~id:t.id ~style:t.style ~arrow a b) with id = t.id }
  | _ -> t

let place_center t ~w ~h (c : Vec.t) = { t with x = c.x -. (w /. 2.); y = c.y -. (h /. 2.); w; h }

let rotate_about t ~center:pivot angle =
  match ends t with
  | Some (a, b) -> with_line_ends t (Vec.rotate_about ~center:pivot a angle) (Vec.rotate_about ~center:pivot b angle)
  | None ->
      let c = Vec.rotate_about ~center:pivot (center t) angle in
      { (place_center t ~w:t.w ~h:t.h c) with rotation = Geom.normalize_angle (t.rotation +. angle) }

let quarter = Float.pi /. 2.

let resize t ~rotation:theta ~map ~sx ~sy =
  match ends t with
  | Some (a, b) -> with_line_ends t (map a) (map b)
  | None ->
      let c = map (center t) in
      let delta = Geom.normalize_angle (t.rotation -. theta) in
      let turns = Float.round (delta /. quarter) in
      let aligned = Float.abs ((delta /. quarter) -. turns) < 1e-6 in
      let ax = Float.abs sx and ay = Float.abs sy in
      let kx, ky =
        if not aligned then
          let k = Float.sqrt (ax *. ay) in
          (k, k)
        else if Float.rem turns 2. = 0. then (ax, ay)
        else (ay, ax)
      in
      let kx, ky =
        match t.kind with
        | Text _ ->
            let k = Float.sqrt (kx *. ky) in
            (k, k)
        | _ -> (kx, ky)
      in
      let fx = sx < 0. and fy = sy < 0. in
      let rotation, mirror_x, mirror_y =
        if fx && fy then (t.rotation +. Float.pi, false, false)
        else if fx then ((2. *. theta) -. t.rotation, true, false)
        else if fy then ((2. *. theta) -. t.rotation, false, true)
        else (t.rotation, false, false)
      in
      let w = t.w *. kx and h = t.h *. ky in
      let kind =
        match t.kind with
        | Draw { points; simulate; _ } ->
            let points =
              Array.map
                (fun (p : Freehand.point) ->
                  let x = p.x *. kx and y = p.y *. ky in
                  { p with x = (if mirror_x then w -. x else x); y = (if mirror_y then h -. y else y) })
                points
            in
            Draw { points; simulate; path = draw_path ~style:t.style ~simulate points }
        | Text { text; scale } -> Text { text; scale = scale *. kx }
        | (Rect | Ellipse | Line _) as kind -> kind
      in
      { (place_center t ~w ~h c) with rotation = Geom.normalize_angle rotation; kind }

let set_ends t a b = match t.kind with Line _ -> with_line_ends t a b | _ -> t

let refit_text metrics t ~style text scale =
  let w, h = text_size metrics ~font:(font_of style scale) text in
  let origin = (frame t).origin in
  let c = Vec.add origin (Vec.rotate (Vec.make (w /. 2.) (h /. 2.)) t.rotation) in
  { (place_center t ~w ~h c) with style; kind = Text { text; scale } }

let set_style metrics t style =
  match t.kind with
  | Draw { points; simulate; _ } -> { t with style; kind = Draw { points; simulate; path = draw_path ~style ~simulate points } }
  | Text { text; scale } -> refit_text metrics t ~style text scale
  | Rect | Ellipse | Line _ -> { t with style }

let set_text metrics t text =
  match t.kind with Text { scale; _ } -> refit_text metrics t ~style:t.style text scale | _ -> t

let text_of t = match t.kind with Text { text; _ } -> Some text | _ -> None

let color_of_name = function
  | "black" -> Some Black
  | "grey" -> Some Grey
  | "red" -> Some Red
  | "orange" -> Some Orange
  | "yellow" -> Some Yellow
  | "green" -> Some Green
  | "blue" -> Some Blue
  | "violet" -> Some Violet
  | _ -> None

let size_of_name = function "s" -> Some S | "m" -> Some M | "l" -> Some L | _ -> None
let fill_of_name = function "none" -> Some Hollow | "semi" -> Some Semi | "solid" -> Some Solid | _ -> None
let json_string b s =
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 ->
          let hex = "0123456789abcdef" in
          Buffer.add_string b "\\u00";
          Buffer.add_char b hex.[Char.code c lsr 4];
          Buffer.add_char b hex.[Char.code c land 15]
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"'

let write_json b t =
  let field name = Buffer.add_string b (",\"" ^ name ^ "\":") in
  let num ?(digits = 2) v = Buffer.add_string b (Num.to_string ~digits v) in
  Buffer.add_string b "{\"id\":";
  Buffer.add_string b (Int.to_string t.id);
  field "x";
  num t.x;
  field "y";
  num t.y;
  field "w";
  num t.w;
  field "h";
  num t.h;
  field "r";
  num ~digits:6 t.rotation;
  field "color";
  json_string b (color_name t.style.color);
  field "size";
  json_string b (size_name t.style.size);
  field "fill";
  json_string b (fill_name t.style.fill);
  field "kind";
  (match t.kind with
  | Rect -> json_string b "rect"
  | Ellipse -> json_string b "ellipse"
  | Draw { points; simulate; _ } ->
      json_string b "draw";
      field "simulate";
      Buffer.add_string b (if simulate then "true" else "false");
      field "points";
      Buffer.add_char b '[';
      Array.iteri
        (fun i (p : Freehand.point) ->
          if i > 0 then Buffer.add_char b ',';
          num p.x;
          Buffer.add_char b ',';
          num p.y;
          Buffer.add_char b ',';
          num ~digits:3 p.pressure)
        points;
      Buffer.add_char b ']'
  | Line { start; end_; arrow } ->
      json_string b (if arrow then "arrow" else "line");
      field "ends";
      Buffer.add_char b '[';
      num start.x;
      Buffer.add_char b ',';
      num start.y;
      Buffer.add_char b ',';
      num end_.x;
      Buffer.add_char b ',';
      num end_.y;
      Buffer.add_char b ']'
  | Text { text; scale } ->
      json_string b "text";
      field "text";
      json_string b text;
      field "scale";
      num ~digits:6 scale);
  Buffer.add_char b '}'

let ( let* ) = Result.bind

let field name fields =
  match List.assoc_opt name fields with Some v -> Ok v | None -> Error ("shape: no field " ^ name)

let number name fields =
  let* v = field name fields in
  match v with `Int i -> Ok (float_of_int i) | `Float f -> Ok f | _ -> Error ("shape: " ^ name ^ " is not a number")

let string name fields =
  let* v = field name fields in
  match v with `String s -> Ok s | _ -> Error ("shape: " ^ name ^ " is not a string")

let numbers name fields =
  let* v = field name fields in
  match v with
  | `List items ->
      List.fold_right
        (fun item acc ->
          let* acc = acc in
          match item with
          | `Int i -> Ok (float_of_int i :: acc)
          | `Float f -> Ok (f :: acc)
          | _ -> Error ("shape: " ^ name ^ " holds a value that is not a number"))
        items (Ok [])
  | _ -> Error ("shape: " ^ name ^ " is not a list")

let named name parse fields =
  let* s = string name fields in
  match parse s with Some v -> Ok v | None -> Error ("shape: unknown " ^ name ^ " " ^ s)

let rec triples = function
  | x :: y :: pressure :: rest -> { Freehand.x; y; pressure } :: triples rest
  | _ -> []

let of_json metrics json =
  match json with
  | `Assoc fields ->
      let* id = field "id" fields in
      let* id = match id with `Int i -> Ok i | _ -> Error "shape: id is not an int" in
      let* x = number "x" fields in
      let* y = number "y" fields in
      let* w = number "w" fields in
      let* h = number "h" fields in
      let* rotation = number "r" fields in
      let* color = named "color" color_of_name fields in
      let* size = named "size" size_of_name fields in
      let* fill = named "fill" fill_of_name fields in
      let style = { color; size; fill } in
      let base = { id; x; y; w; h; rotation = Geom.normalize_angle rotation; style; kind = Rect } in
      let* kind = string "kind" fields in
      (match kind with
      | "rect" -> Ok base
      | "ellipse" -> Ok { base with kind = Ellipse }
      | "draw" ->
          let* simulate = field "simulate" fields in
          let simulate = match simulate with `Bool b -> b | _ -> true in
          let* values = numbers "points" fields in
          let points = Array.of_list (triples values) in
          if Array.length points = 0 then Error "shape: a drawing with no point"
          else Ok { base with kind = Draw { points; simulate; path = draw_path ~style ~simulate points } }
      | "line" | "arrow" -> (
          let* values = numbers "ends" fields in
          match values with
          | [ ax; ay; bx; by ] ->
              Ok { base with rotation = 0.; kind = Line { start = Vec.make ax ay; end_ = Vec.make bx by; arrow = kind = "arrow" } }
          | _ -> Error "shape: a line needs four numbers")
      | "text" ->
          let* text = string "text" fields in
          let* scale = number "scale" fields in
          if scale <= 0. then Error "shape: a text scale must be positive"
          else Ok (refit_text metrics { base with kind = Text { text; scale } } ~style text scale)
      | other -> Error ("shape: unknown kind " ^ other))
  | _ -> Error "shape: not an object"
