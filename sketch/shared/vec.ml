type t = { x : float; y : float }

let make x y = { x; y }
let zero = { x = 0.; y = 0. }
let add a b = { x = a.x +. b.x; y = a.y +. b.y }
let sub a b = { x = a.x -. b.x; y = a.y -. b.y }
let scale a k = { x = a.x *. k; y = a.y *. k }
let neg a = { x = -.a.x; y = -.a.y }
let dot a b = (a.x *. b.x) +. (a.y *. b.y)
let cross a b = (a.x *. b.y) -. (a.y *. b.x)
let length a = Float.sqrt ((a.x *. a.x) +. (a.y *. a.y))
let dist2 a b = ((a.x -. b.x) *. (a.x -. b.x)) +. ((a.y -. b.y) *. (a.y -. b.y))
let dist a b = Float.sqrt (dist2 a b)
let lerp a b t = { x = a.x +. ((b.x -. a.x) *. t); y = a.y +. ((b.y -. a.y) *. t) }
let mid a b = { x = (a.x +. b.x) /. 2.; y = (a.y +. b.y) /. 2. }

let normalize a =
  let l = length a in
  if l = 0. then zero else { x = a.x /. l; y = a.y /. l }

let perp a = { x = a.y; y = -.a.x }

let rotate a angle =
  let c = Float.cos angle and s = Float.sin angle in
  { x = (a.x *. c) -. (a.y *. s); y = (a.x *. s) +. (a.y *. c) }

let rotate_about ~center a angle = add center (rotate (sub a center) angle)
let angle a = Float.atan2 a.y a.x
let equal a b = Float.equal a.x b.x && Float.equal a.y b.y
