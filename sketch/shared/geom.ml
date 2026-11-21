module Box = struct
  type t = { x : float; y : float; w : float; h : float }

  let of_corners (a : Vec.t) (b : Vec.t) =
    { x = Float.min a.x b.x; y = Float.min a.y b.y; w = Float.abs (a.x -. b.x); h = Float.abs (a.y -. b.y) }

  let of_points = function
    | [] -> None
    | (first : Vec.t) :: rest ->
        let x0, y0, x1, y1 =
          List.fold_left
            (fun (x0, y0, x1, y1) (p : Vec.t) -> (Float.min x0 p.x, Float.min y0 p.y, Float.max x1 p.x, Float.max y1 p.y))
            (first.x, first.y, first.x, first.y) rest
        in
        Some { x = x0; y = y0; w = x1 -. x0; h = y1 -. y0 }

  let union a b =
    let x = Float.min a.x b.x and y = Float.min a.y b.y in
    { x; y; w = Float.max (a.x +. a.w) (b.x +. b.w) -. x; h = Float.max (a.y +. a.h) (b.y +. b.h) -. y }

  let expand b d = { x = b.x -. d; y = b.y -. d; w = b.w +. (2. *. d); h = b.h +. (2. *. d) }
  let center b = Vec.make (b.x +. (b.w /. 2.)) (b.y +. (b.h /. 2.))
  let contains b (p : Vec.t) = p.x >= b.x && p.x <= b.x +. b.w && p.y >= b.y && p.y <= b.y +. b.h
  let intersects a b = a.x <= b.x +. b.w && b.x <= a.x +. a.w && a.y <= b.y +. b.h && b.y <= a.y +. a.h
end

module Frame = struct
  type t = { origin : Vec.t; w : float; h : float; rotation : float }

  let of_box (b : Box.t) = { origin = Vec.make b.x b.y; w = b.w; h = b.h; rotation = 0. }
  let to_world f p = Vec.add f.origin (Vec.rotate p f.rotation)
  let to_local f p = Vec.rotate (Vec.sub p f.origin) (-.f.rotation)
  let center f = to_world f (Vec.make (f.w /. 2.) (f.h /. 2.))

  let corners f =
    [| to_world f Vec.zero; to_world f (Vec.make f.w 0.); to_world f (Vec.make f.w f.h); to_world f (Vec.make 0. f.h) |]

  let around ~rotation points =
    match Box.of_points (List.map (fun p -> Vec.rotate p (-.rotation)) points) with
    | None -> None
    | Some b -> Some { origin = Vec.rotate (Vec.make b.x b.y) rotation; w = b.w; h = b.h; rotation }
end

let dist_to_segment p a b =
  let ab = Vec.sub b a in
  let l2 = Vec.dot ab ab in
  if l2 = 0. then Vec.dist p a
  else
    let t = Num.clamp ~lo:0. ~hi:1. (Vec.dot (Vec.sub p a) ab /. l2) in
    Vec.dist p (Vec.add a (Vec.scale ab t))

let orientation a b c =
  let v = Vec.cross (Vec.sub b a) (Vec.sub c a) in
  if v > 1e-12 then 1 else if v < -1e-12 then -1 else 0

let on_segment (a : Vec.t) (b : Vec.t) (p : Vec.t) =
  p.x >= Float.min a.x b.x -. 1e-9
  && p.x <= Float.max a.x b.x +. 1e-9
  && p.y >= Float.min a.y b.y -. 1e-9
  && p.y <= Float.max a.y b.y +. 1e-9

let segments_cross a b c d =
  let o1 = orientation a b c and o2 = orientation a b d and o3 = orientation c d a and o4 = orientation c d b in
  (o1 <> o2 && o3 <> o4)
  || (o1 = 0 && on_segment a b c)
  || (o2 = 0 && on_segment a b d)
  || (o3 = 0 && on_segment c d a)
  || (o4 = 0 && on_segment c d b)

let segment_hits_box a b (box : Box.t) =
  Box.contains box a || Box.contains box b
  ||
  let tl = Vec.make box.x box.y
  and tr = Vec.make (box.x +. box.w) box.y
  and br = Vec.make (box.x +. box.w) (box.y +. box.h)
  and bl = Vec.make box.x (box.y +. box.h) in
  segments_cross a b tl tr || segments_cross a b tr br || segments_cross a b br bl || segments_cross a b bl tl

let inside_polygon (poly : Vec.t array) (p : Vec.t) =
  let n = Array.length poly in
  let inside = ref false in
  let j = ref (n - 1) in
  for i = 0 to n - 1 do
    let a = poly.(i) and b = poly.(!j) in
    if a.y > p.y <> (b.y > p.y) && p.x < ((b.x -. a.x) *. (p.y -. a.y) /. (b.y -. a.y)) +. a.x then inside := not !inside;
    j := i
  done;
  !inside

let two_pi = 2. *. Float.pi

let normalize_angle a =
  let r = Float.rem a two_pi in
  let r = if r < 0. then r +. two_pi else r in
  if r >= two_pi then 0. else r

let snap_angle ~step a = Float.round (a /. step) *. step
