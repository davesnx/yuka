type t = { x : float; y : float; zoom : float }

let initial = { x = 0.; y = 0.; zoom = 1. }
let min_zoom = 0.1
let max_zoom = 8.
let steps = [ 0.1; 0.25; 0.5; 1.; 2.; 4.; 8. ]
let to_screen c (p : Vec.t) = Vec.make ((p.x *. c.zoom) +. c.x) ((p.y *. c.zoom) +. c.y)
let to_world c (p : Vec.t) = Vec.make ((p.x -. c.x) /. c.zoom) ((p.y -. c.y) /. c.zoom)
let pan c (d : Vec.t) = { c with x = c.x +. d.x; y = c.y +. d.y }

let zoom_at c (s : Vec.t) zoom =
  let zoom = Num.clamp ~lo:min_zoom ~hi:max_zoom zoom in
  let w = to_world c s in
  { x = s.x -. (w.x *. zoom); y = s.y -. (w.y *. zoom); zoom }

let zoom_in c s =
  let next = List.find_opt (fun z -> z > c.zoom *. 1.01) steps in
  zoom_at c s (Option.value next ~default:max_zoom)

let zoom_out c s =
  let next = List.find_opt (fun z -> z < c.zoom /. 1.01) (List.rev steps) in
  zoom_at c s (Option.value next ~default:min_zoom)

let fit (b : Geom.Box.t) ~width ~height =
  let margin = 64. in
  let zx = if b.w > 0. then (width -. (2. *. margin)) /. b.w else max_zoom in
  let zy = if b.h > 0. then (height -. (2. *. margin)) /. b.h else max_zoom in
  let zoom = Num.clamp ~lo:min_zoom ~hi:1. (Float.min zx zy) in
  let center = Geom.Box.center b in
  { x = (width /. 2.) -. (center.x *. zoom); y = (height /. 2.) -. (center.y *. zoom); zoom }

let to_json_text c =
  "{\"x\":" ^ Num.to_string c.x ^ ",\"y\":" ^ Num.to_string c.y ^ ",\"zoom\":" ^ Num.to_string ~digits:6 c.zoom ^ "}"

let of_json = function
  | `Assoc fields -> (
      let number name =
        match List.assoc_opt name fields with Some (`Int i) -> Some (float_of_int i) | Some (`Float f) -> Some f | _ -> None
      in
      match (number "x", number "y", number "zoom") with
      | Some x, Some y, Some zoom when Float.is_finite x && Float.is_finite y && zoom > 0. ->
          Some { x; y; zoom = Num.clamp ~lo:min_zoom ~hi:max_zoom zoom }
      | _ -> None)
  | _ -> None
