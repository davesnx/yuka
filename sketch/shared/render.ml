type paint = Ink of Shape.color | Tint of Shape.color | No_paint

type part =
  | Path of { d : string; fill : paint; stroke : paint; width : float }
  | Text of { lines : (string * float) list; x : float; size : float; color : Shape.color }

let n = Num.to_string
let pt (p : Vec.t) = n p.x ^ "," ^ n p.y

let transform (s : Shape.t) =
  let base = "translate(" ^ n s.x ^ " " ^ n s.y ^ ")" in
  if s.rotation = 0. then base
  else base ^ " rotate(" ^ n (s.rotation *. 180. /. Float.pi) ^ " " ^ n (s.w /. 2.) ^ " " ^ n (s.h /. 2.) ^ ")"

let rect_d w h = "M0,0H" ^ n w ^ "V" ^ n h ^ "H0Z"

let ellipse_d w h =
  let rx = n (w /. 2.) and ry = n (h /. 2.) in
  "M0," ^ n (h /. 2.) ^ "A" ^ rx ^ "," ^ ry ^ " 0 1 0 " ^ n w ^ "," ^ n (h /. 2.) ^ "A" ^ rx ^ "," ^ ry ^ " 0 1 0 0,"
  ^ n (h /. 2.) ^ "Z"

let fill_paint (style : Shape.style) =
  match style.fill with Hollow -> No_paint | Semi -> Tint style.color | Solid -> Ink style.color

let baseline (m : Shape.metrics) ~font i =
  let lh = font *. Shape.line_height in
  (float_of_int i *. lh) +. ((lh -. ((m.ascent +. m.descent) *. font)) /. 2.) +. (m.ascent *. font)

let arrowhead (s : Shape.t) start end_ =
  let d = Vec.sub end_ start in
  let len = Vec.length d in
  if len < 1. then ""
  else
    let u = Vec.scale d (1. /. len) in
    let head = Shape.arrowhead_length s in
    let back = Vec.scale (Vec.neg u) head in
    let a = Vec.add end_ (Vec.rotate back (Float.pi /. 6.)) in
    let b = Vec.add end_ (Vec.rotate back (-.Float.pi /. 6.)) in
    "M" ^ pt a ^ "L" ^ pt end_ ^ "L" ^ pt b

let parts metrics (s : Shape.t) =
  let ink = Ink s.style.color and width = Shape.stroke_width s.style in
  match s.kind with
  | Rect -> [ Path { d = rect_d s.w s.h; fill = fill_paint s.style; stroke = ink; width } ]
  | Ellipse -> [ Path { d = ellipse_d s.w s.h; fill = fill_paint s.style; stroke = ink; width } ]
  | Draw { path; _ } -> [ Path { d = path; fill = ink; stroke = No_paint; width = 0. } ]
  | Line { start; end_; arrow } ->
      let shaft = Path { d = "M" ^ pt start ^ "L" ^ pt end_; fill = No_paint; stroke = ink; width } in
      if arrow then [ shaft; Path { d = arrowhead s start end_; fill = No_paint; stroke = ink; width } ] else [ shaft ]
  | Text { text; _ } ->
      let font = Shape.font_size s in
      let lines = List.mapi (fun i line -> (line, baseline metrics ~font i)) (String.split_on_char '\n' text) in
      [ Text { lines; x = Shape.text_padding *. font; size = font; color = s.style.color } ]

let outline (s : Shape.t) =
  match s.kind with
  | Rect | Text _ -> rect_d s.w s.h
  | Ellipse -> ellipse_d s.w s.h
  | Draw { path; _ } -> path
  | Line { start; end_; _ } -> "M" ^ pt start ^ "L" ^ pt end_
