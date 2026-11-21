let period = 120.
let margin = 3.
let cards_at_zoom_one = 200.
let omega = 6.
let min_zoom = log 0.002
let max_zoom = log 8.

type pointer = { mutable id : int; mutable x : float; mutable y : float }

type t = {
  size : int;
  mutable spread : Spread.t;
  mutable following : bool;
  mutable cx : float;
  mutable cy : float;
  mutable lz : float;
  mutable vx : float;
  mutable vy : float;
  mutable vz : float;
  mutable bx0 : float;
  mutable by0 : float;
  mutable bx1 : float;
  mutable by1 : float;
  mutable width : float;
  mutable height : float;
  mutable base : float;
  mutable last : float;
  mutable origin : float;
  mutable stepped : float;
  mutable next_step : float;
  mutable frames : int;
  mutable fps_from : float;
  mutable fps : float;
  pointers : pointer array;
}

let spread t = t.spread
let center_x t = t.cx
let center_y t = t.cy
let scale t = exp t.lz *. t.base
let zoom t = exp t.lz
let width t = t.width
let height t = t.height
let following t = t.following
let seconds t = (t.last -. t.origin) /. 1000.
let glow_level t = float_of_int (Spread.level t.spread) +. ((t.last -. t.stepped) /. period)
let readout t = Printf.sprintf "%.0f fps | zoom %.3f | %d lit" t.fps (exp t.lz) (Spread.lit_count t.spread)

let resize t ~width ~height =
  if width > 0. && height > 0. && (width <> t.width || height <> t.height) then begin
    let base = sqrt (width *. height /. cards_at_zoom_one) in
    if t.width > 0. then t.lz <- t.lz +. log (t.base /. base);
    t.width <- width;
    t.height <- height;
    t.base <- base
  end

let take_bounds t =
  let x0, y0, x1, y1 = Spread.bounds t.spread in
  t.bx0 <- float_of_int x0;
  t.by0 <- float_of_int y0;
  t.bx1 <- float_of_int (x1 + 1);
  t.by1 <- float_of_int (y1 + 1)

let target_zoom t =
  let fit =
    Float.min
      (t.width /. t.base /. (t.bx1 -. t.bx0 +. (2. *. margin)))
      (t.height /. t.base /. (t.by1 -. t.by0 +. (2. *. margin)))
  in
  Float.max min_zoom (log (Float.min 1. fit))

let seed t seed =
  let cols = int_of_float (t.width /. t.base) and rows = int_of_float (t.height /. t.base) in
  t.spread <- Spread.create ~size:t.size ~seed ~cols ~rows ();
  take_bounds t;
  t.following <- true

let create ~size ~seed:value ~width ~height =
  let t =
    {
      size;
      spread = Spread.create ~size:3 ~seed:0 ~cols:1 ~rows:1 ();
      following = true;
      cx = 0.;
      cy = 0.;
      lz = 0.;
      vx = 0.;
      vy = 0.;
      vz = 0.;
      bx0 = 0.;
      by0 = 0.;
      bx1 = 1.;
      by1 = 1.;
      width = 0.;
      height = 0.;
      base = 1.;
      last = -1.;
      origin = 0.;
      stepped = 0.;
      next_step = 0.;
      frames = 0;
      fps_from = 0.;
      fps = 0.;
      pointers = [| { id = -1; x = 0.; y = 0. }; { id = -1; x = 0.; y = 0. } |];
    }
  in
  resize t ~width ~height;
  seed t value;
  t.cx <- (t.bx0 +. t.bx1) /. 2.;
  t.cy <- (t.by0 +. t.by1) /. 2.;
  t.lz <- target_zoom t;
  t

let restart t ~seed:value =
  seed t value;
  t.stepped <- t.last;
  t.next_step <- t.last +. period

let follow t = t.following <- true
let settle_x dt e d v = (d +. ((v +. (omega *. d)) *. dt)) *. e
let settle_v dt e d v = (v -. (omega *. (v +. (omega *. d)) *. dt)) *. e

let follow_step t dt =
  let e = exp (-.omega *. dt) in
  let dx = t.cx -. ((t.bx0 +. t.bx1) /. 2.) and dy = t.cy -. ((t.by0 +. t.by1) /. 2.) and dz = t.lz -. target_zoom t in
  t.cx <- t.cx -. dx +. settle_x dt e dx t.vx;
  t.vx <- settle_v dt e dx t.vx;
  t.cy <- t.cy -. dy +. settle_x dt e dy t.vy;
  t.vy <- settle_v dt e dy t.vy;
  t.lz <- t.lz -. dz +. settle_x dt e dz t.vz;
  t.vz <- settle_v dt e dz t.vz

let tick t now =
  if t.last < 0. then begin
    t.origin <- now;
    t.stepped <- now;
    t.next_step <- now +. period;
    t.fps_from <- now;
    t.last <- now
  end;
  let dt = Float.min 0.1 ((now -. t.last) /. 1000.) in
  t.last <- now;
  let lit =
    if now >= t.next_step && not (Spread.finished t.spread) then begin
      let lit = Spread.step t.spread in
      if lit then take_bounds t;
      t.stepped <- now;
      t.next_step <- (if now -. t.next_step > period then now +. period else t.next_step +. period);
      lit
    end
    else false
  in
  if t.following then follow_step t dt;
  t.frames <- t.frames + 1;
  if now -. t.fps_from >= 500. then begin
    t.fps <- float_of_int t.frames *. 1000. /. (now -. t.fps_from);
    t.frames <- 0;
    t.fps_from <- now
  end;
  lit

let manual t =
  t.following <- false;
  t.vx <- 0.;
  t.vy <- 0.;
  t.vz <- 0.

let zoom_at t px py change =
  let before = scale t in
  let wx = t.cx +. ((px -. (t.width /. 2.)) /. before) and wy = t.cy +. ((py -. (t.height /. 2.)) /. before) in
  t.lz <- Float.max min_zoom (Float.min max_zoom (t.lz +. change));
  let after = scale t in
  t.cx <- wx -. ((px -. (t.width /. 2.)) /. after);
  t.cy <- wy -. ((py -. (t.height /. 2.)) /. after)

let pan t dx dy =
  let scale = scale t in
  t.cx <- t.cx -. (dx /. scale);
  t.cy <- t.cy -. (dy /. scale)

let wheel t ~x ~y ~delta =
  manual t;
  zoom_at t x y (-.delta *. 0.0015)

let active t = (if t.pointers.(0).id >= 0 then 1 else 0) + if t.pointers.(1).id >= 0 then 1 else 0

let slot t id =
  if t.pointers.(0).id = id then Some t.pointers.(0) else if t.pointers.(1).id = id then Some t.pointers.(1) else None

let press t ~id ~x ~y =
  match slot t (-1) with
  | Some p ->
      p.id <- id;
      p.x <- x;
      p.y <- y;
      true
  | None -> false

let move t ~id ~x ~y =
  match slot t id with
  | None -> ()
  | Some p ->
      if active t = 2 then begin
        let a = t.pointers.(0) and b = t.pointers.(1) in
        let mid_x = (a.x +. b.x) /. 2. and mid_y = (a.y +. b.y) /. 2. in
        let span = Float.hypot (a.x -. b.x) (a.y -. b.y) in
        p.x <- x;
        p.y <- y;
        let span' = Float.hypot (a.x -. b.x) (a.y -. b.y) in
        let mid_x' = (a.x +. b.x) /. 2. and mid_y' = (a.y +. b.y) /. 2. in
        manual t;
        pan t (mid_x' -. mid_x) (mid_y' -. mid_y);
        if span > 0. && span' > 0. then zoom_at t mid_x' mid_y' (log (span' /. span))
      end
      else begin
        manual t;
        pan t (x -. p.x) (y -. p.y);
        p.x <- x;
        p.y <- y
      end

let release t ~id = match slot t id with Some p -> p.id <- -1 | None -> ()
