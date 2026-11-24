type layout = { seed : int; padding : int } [@@deriving codec]
type lines = { lines : int; amplitude : int; waves : int; stroke : int } [@@deriving codec]
type blocks = { blocks : int; gap : int; filled : int; squareness : int } [@@deriving codec]
type clouds = { clouds : int; puffs : int; size : int; solid : int } [@@deriving codec]
type lightning = { bolts : int; branches : int; jaggedness : int; thickness : int } [@@deriving codec]

type art = Lines of lines | Blocks of blocks | Clouds of clouds | Lightning of lightning [@@deriving codec]

type colours = { background : string; foreground : string } [@@deriving codec]
type text = { title : string; subtitle : string; year : string; day : string; weekday : string } [@@deriving codec]
type settings = { layout : layout; art : art; colours : colours; text : text } [@@deriving codec]

module Kind = struct
  type t = Lines | Blocks | Clouds | Lightning

  let all = [ Lines; Blocks; Clouds; Lightning ]
  let name = function Lines -> "lines" | Blocks -> "blocks" | Clouds -> "clouds" | Lightning -> "lightning"
  let label = function Lines -> "Lines" | Blocks -> "Blocks" | Clouds -> "Clouds" | Lightning -> "Lightning"

  let param =
    Yuka.Router.Param.make
      ~decode:(function
        | "lines" -> Some Lines | "blocks" -> Some Blocks | "clouds" -> Some Clouds | "lightning" -> Some Lightning | _ -> None)
      ~encode:name
end

let kind = function
  | Lines _ -> Kind.Lines
  | Blocks _ -> Kind.Blocks
  | Clouds _ -> Kind.Clouds
  | Lightning _ -> Kind.Lightning

type paint = Fill | Stroke of int
type shape = { index : int; d : string; paint : paint }
type label = { x : int; y : int; size : int; bold : bool; spacing : int; end_ : bool; text : string }
type box = { left : int; top : int; right : int; bottom : int }

let width = 1000
let height = 1414
let art_bottom = 1200
let max_seed = 999_999
let max_text = 40
let dark = { background = "#333333"; foreground = "#ffffff" }
let light = { background = "#f4f4f4"; foreground = "#333333" }

module Range = struct
  let padding = (0, 200)
  let lines = (2, 60)
  let amplitude = (0, 100)
  let waves = (1, 10)
  let stroke = (1, 24)
  let blocks = (1, 80)
  let gap = (0, 60)
  let filled = (0, 100)
  let squareness = (0, 100)
  let clouds = (1, 20)
  let puffs = (3, 14)
  let size = (10, 100)
  let solid = (0, 100)
  let bolts = (1, 8)
  let branches = (0, 12)
  let jaggedness = (0, 100)
  let thickness = (1, 24)
end

let lines_default = { lines = 22; amplitude = 60; waves = 3; stroke = 6 }
let blocks_default = { blocks = 14; gap = 16; filled = 45; squareness = 50 }
let clouds_default = { clouds = 6; puffs = 6; size = 45; solid = 50 }
let lightning_default = { bolts = 2; branches = 4; jaggedness = 55; thickness = 7 }

let fresh = function
  | Kind.Lines -> Lines lines_default
  | Kind.Blocks -> Blocks blocks_default
  | Kind.Clouds -> Clouds clouds_default
  | Kind.Lightning -> Lightning lightning_default

let start ~(defaults : settings) k = if kind defaults.art = k then defaults.art else fresh k

let months =
  [| "January"; "February"; "March"; "April"; "May"; "June"; "July"; "August"; "September"; "October"; "November"; "December" |]

let weekdays = [| "Sunday"; "Monday"; "Tuesday"; "Wednesday"; "Thursday"; "Friday"; "Saturday" |]

let defaults ~year ~month ~day ~weekday =
  {
    layout = { seed = 2019; padding = 80 };
    art = Lines lines_default;
    colours = dark;
    text =
      {
        title = "Yuka";
        subtitle = "Generative Design";
        year = Int.to_string year;
        day = months.(month) ^ ", " ^ Int.to_string day;
        weekday = weekdays.(weekday);
      };
  }

let clamp low high value = max low (min high value)
let fit (low, high) value = clamp low high value
let is_hex = function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false

let color ~default value =
  if String.length value = 7 && value.[0] = '#' && String.for_all is_hex (String.sub value 1 6) then
    String.lowercase_ascii value
  else default

let cut value = if String.length value > max_text then String.sub value 0 max_text else value
let normal_layout (l : layout) = { seed = clamp 0 max_seed l.seed; padding = fit Range.padding l.padding }

let normal_art = function
  | Lines l ->
      Lines
        {
          lines = fit Range.lines l.lines;
          amplitude = fit Range.amplitude l.amplitude;
          waves = fit Range.waves l.waves;
          stroke = fit Range.stroke l.stroke;
        }
  | Blocks b ->
      Blocks
        {
          blocks = fit Range.blocks b.blocks;
          gap = fit Range.gap b.gap;
          filled = fit Range.filled b.filled;
          squareness = fit Range.squareness b.squareness;
        }
  | Clouds c ->
      Clouds
        { clouds = fit Range.clouds c.clouds; puffs = fit Range.puffs c.puffs; size = fit Range.size c.size; solid = fit Range.solid c.solid }
  | Lightning l ->
      Lightning
        {
          bolts = fit Range.bolts l.bolts;
          branches = fit Range.branches l.branches;
          jaggedness = fit Range.jaggedness l.jaggedness;
          thickness = fit Range.thickness l.thickness;
        }

let normal_colours ~(defaults : settings) (c : colours) =
  {
    background = color ~default:defaults.colours.background c.background;
    foreground = color ~default:defaults.colours.foreground c.foreground;
  }

let normal_text (t : text) =
  { title = cut t.title; subtitle = cut t.subtitle; year = cut t.year; day = cut t.day; weekday = cut t.weekday }

let normalize ~defaults (s : settings) =
  { layout = normal_layout s.layout; art = normal_art s.art; colours = normal_colours ~defaults s.colours; text = normal_text s.text }

let step state = ((state * 1103515245) + 12345) land 0x7fffffff
let shuffle seed = step (seed lxor 0x2545f491) mod (max_seed + 1)

let random seed =
  let state = ref (step (seed lxor 0x5bd1e995)) in
  let draw () =
    state := step !state;
    (!state lsr 16) land 0x7fff
  in
  fun bound ->
    let high = draw () in
    let low = draw () in
    if bound <= 0 then 0 else ((high lsl 15) lor low) mod bound

let isqrt n =
  let rec go x =
    let y = (x + (n / x)) / 2 in
    if y >= x then x else go y
  in
  if n <= 0 then 0 else go n

let i = Int.to_string
let point (x, y) = i x ^ " " ^ i y

let wave random box (l : lines) =
  let w = box.right - box.left and h = box.bottom - box.top in
  let amp = h * l.amplitude / 500 in
  let segments = 2 * l.waves in
  let jitter = w / (5 * segments) in
  let half = max 0 ((w * 3 / (10 * segments)) - 1) in
  let xs =
    Array.init (segments + 1) (fun k ->
        if k = 0 || k = segments then box.left + (w * k / segments)
        else box.left + (w * k / segments) + random ((2 * jitter) + 1) - jitter)
  in
  let x k = xs.(k) in
  let profile () =
    let first = if random 2 = 0 then 1 else -1 in
    Array.init (segments + 1) (fun k -> (if k mod 2 = 0 then first else -first) * ((amp / 4) + random ((amp * 3 / 4) + 1)))
  in
  let a = profile () in
  let b = profile () in
  let n = l.lines in
  Array.init n (fun index ->
      let base = box.top + amp + ((h - (2 * amp)) * index / (n - 1)) in
      let y k = base + (((a.(k) * (n - 1 - index)) + (b.(k) * index)) / (n - 1)) in
      let rest = List.init (segments - 1) (fun j -> j + 2) in
      {
        index;
        d =
          "M" ^ point (x 0, y 0) ^ "C" ^ point (x 0 + half, y 0) ^ " " ^ point (x 1 - half, y 1) ^ " " ^ point (x 1, y 1)
          ^ String.concat "" (List.map (fun k -> "S" ^ point (x k - half, y k) ^ " " ^ point (x k, y k)) rest);
        paint = Stroke l.stroke;
      })

let rect r = "M" ^ point (r.left, r.top) ^ "H" ^ i r.right ^ "V" ^ i r.bottom ^ "H" ^ i r.left ^ "z"
let inset k r = { left = r.left + k; top = r.top + k; right = r.right - k; bottom = r.bottom - k }

let pack random box (b : blocks) =
  let half = b.gap / 2 in
  let smallest = b.gap + 24 in
  let rects = ref [| inset (-half) box |] in
  let splits_x r = r.right - r.left >= 2 * smallest in
  let splits_y r = r.bottom - r.top >= 2 * smallest in
  let area r = if splits_x r || splits_y r then (r.right - r.left) * (r.bottom - r.top) / 64 else 0 in
  for _ = 2 to b.blocks do
    let total = Array.fold_left (fun sum r -> sum + area r) 0 !rects in
    if total > 0 then begin
      let roll = random total in
      let rec find k sum =
        let sum = sum + area !rects.(k) in
        if roll < sum then k else find (k + 1) sum
      in
      let k = find 0 0 in
      let r = !rects.(k) in
      let along_long = random 100 < 50 + (b.squareness / 2) in
      let across_x = (r.right - r.left >= r.bottom - r.top) = along_long in
      let across_x = if across_x then splits_x r else not (splits_y r) in
      let side = if across_x then r.right - r.left else r.bottom - r.top in
      let spread = (100 - b.squareness) * 40 / 100 in
      let share = 50 - spread + random ((2 * spread) + 1) in
      let at = clamp smallest (side - smallest) (side * share / 100) in
      let first, second =
        if across_x then ({ r with right = r.left + at }, { r with left = r.left + at })
        else ({ r with bottom = r.top + at }, { r with top = r.top + at })
      in
      !rects.(k) <- first;
      rects := Array.append !rects [| second |]
    end
  done;
  Array.mapi
    (fun index r ->
      if random 100 < b.filled then { index; d = rect (inset half r); paint = Fill }
      else { index; d = rect (inset (half + 3) r); paint = Stroke 6 })
    !rects

let arc r (x, y) = "A" ^ i r ^ " " ^ i r ^ " 0 0 1 " ^ point (x, y)

let cloud random ~w ~h ~puffs =
  let points =
    Array.init (puffs + 1) (fun j ->
        if j = 0 || j = puffs then (w * j / puffs, 0)
        else
          let shift = random ((w / (4 * puffs)) + 1) in
          let lift = random ((h / 5) + 1) in
          ((w * j / puffs) + shift - (w / (8 * puffs)), -(h * 4 * j * (puffs - j) / (puffs * puffs)) - lift + (h / 10)))
  in
  let bumps =
    Array.init puffs (fun j ->
        let (ax, ay), (bx, by) = (points.(j), points.(j + 1)) in
        let chord = isqrt (((bx - ax) * (bx - ax)) + ((by - ay) * (by - ay))) in
        let r = chord * (50 + random 14) / 100 in
        let r = max r ((chord / 2) + 1) in
        let bulge = r - isqrt ((r * r) - (chord * chord / 4)) in
        (r, points.(j + 1), bulge))
  in
  let margin = Array.fold_left (fun m (_, _, bulge) -> max m bulge) 0 bumps + 4 in
  let floor_radius = 2 * w in
  let sag = floor_radius - isqrt ((floor_radius * floor_radius) - (w * w / 4)) in
  let top = Array.fold_left (fun m (_, (_, y), _) -> min m y) 0 bumps - margin in
  let path (dx, dy) =
    let at (x, y) = (x + dx, y + dy) in
    "M" ^ point (at points.(0))
    ^ String.concat "" (Array.to_list (Array.map (fun (r, p, _) -> arc r (at p)) bumps))
    ^ arc floor_radius (at points.(0)) ^ "z"
  in
  ({ left = -margin; top; right = w + margin; bottom = sag + 4 }, path)

let overlaps a b = a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom

let sky random box (c : clouds) =
  let bw = box.right - box.left and bh = box.bottom - box.top in
  let placed = ref [] in
  for _ = 1 to c.clouds do
    let scale = 60 + random 41 in
    let tall = 38 + random 20 in
    let puffs = max 3 (c.puffs - 1 + random 3) in
    let rec shaped w tries =
      let bounds, path = cloud random ~w ~h:(w * tall / 100) ~puffs in
      if (bounds.right - bounds.left <= bw && bounds.bottom - bounds.top <= bh) || tries = 0 then (bounds, path)
      else shaped (w * 3 / 4) (tries - 1)
    in
    let bounds, path = shaped (bw * c.size / 100 * scale / 100) 6 in
    let room_x = bw - (bounds.right - bounds.left) and room_y = bh - (bounds.bottom - bounds.top) in
    let rec place tries =
      if tries = 0 || room_x < 0 || room_y < 0 then None
      else
        let x = random (room_x + 1) in
        let y = random (room_y + 1) in
        let dx = box.left + x - bounds.left and dy = box.top + y - bounds.top in
        let spot = { left = bounds.left + dx - 12; top = bounds.top + dy - 12; right = bounds.right + dx + 12; bottom = bounds.bottom + dy + 12 } in
        if List.exists (fun (other, _) -> overlaps spot other) !placed then place (tries - 1) else Some (spot, path (dx, dy))
    in
    match place 60 with
    | Some (spot, d) ->
        let solid = random 100 < c.solid in
        placed := (spot, (d, solid)) :: !placed
    | None -> ()
  done;
  Array.of_list
    (List.mapi
       (fun index (_, (d, solid)) -> { index; d; paint = (if solid then Fill else Stroke 6) })
       (List.rev !placed))

let storm random box (l : lightning) =
  let w = box.right - box.left and h = box.bottom - box.top in
  let fold x = clamp box.left box.right (if x < box.left then (2 * box.left) - x else if x > box.right then (2 * box.right) - x else x) in
  let rec split (ax, ay) (bx, by) depth spread =
    if depth = 0 then [ (bx, by) ]
    else
      let shift = random ((2 * spread) + 1) in
      let middle = (fold ((ax + bx) / 2 + shift - spread), (ay + by) / 2) in
      let first = split (ax, ay) middle (depth - 1) (spread / 2) in
      first @ split middle (bx, by) (depth - 1) (spread / 2)
  in
  let polyline points =
    match points with
    | first :: rest -> "M" ^ point first ^ "L" ^ String.concat " " (List.map point rest)
    | [] -> ""
  in
  let shapes = ref [] in
  let add d paint = shapes := { index = List.length !shapes; d; paint } :: !shapes in
  for k = 0 to l.bolts - 1 do
    let lane = w / l.bolts in
    let jitter = random ((lane / 2) + 1) in
    let sx = box.left + (lane * k) + (lane / 4) + jitter in
    let drift = random ((w / 2) + 1) in
    let ex = clamp box.left box.right (sx + drift - (w / 4)) in
    let shorten = random ((h / 4) + 1) in
    let ey = box.bottom - shorten in
    let start = (sx, box.top) in
    let points = start :: split start (ex, ey) 6 ((ey - box.top) * l.jaggedness / 400) in
    add (polyline points) (Stroke l.thickness);
    for _ = 1 to l.branches do
      let at = List.nth points (6 + random 36) in
      let side = if random 2 = 0 then 1 else -1 in
      let dx = (w / 20) + random ((w / 6) + 1) in
      let dy = (h / 8) + random ((h / 4) + 1) in
      let ending = (fold (fst at + (side * dx)), min box.bottom (snd at + dy)) in
      add (polyline (at :: split at ending 4 ((dx + dy) * l.jaggedness / 400))) (Stroke (max 1 (l.thickness * 3 / 5)))
    done
  done;
  Array.of_list (List.rev !shapes)

let area padding = { left = padding; top = padding; right = width - padding; bottom = art_bottom - padding }

let shapes (l : layout) art =
  let random = random l.seed and box = area l.padding in
  match art with
  | Lines a -> wave random box a
  | Blocks a -> pack random box a
  | Clouds a -> sky random box a
  | Lightning a -> storm random box a

let labels (t : text) =
  let line y text = { x = 918; y; size = 24; bold = false; spacing = 0; end_ = true; text } in
  [
    { x = 82; y = 1262; size = 36; bold = true; spacing = 5; end_ = false; text = String.uppercase_ascii t.title };
    { x = 82; y = 1320; size = 25; bold = false; spacing = 0; end_ = false; text = t.subtitle };
    line 1258 t.year;
    line 1291 t.day;
    line 1324 t.weekday;
  ]

let font = "Helvetica Neue, Helvetica, Arial, sans-serif"
let view_box = "0 0 " ^ i width ^ " " ^ i height

let preset ~name ~seed ~padding ~art ~colours ~title ~subtitle ~date:(year, day, weekday) =
  (name, { layout = { seed; padding }; art; colours; text = { title; subtitle; year; day; weekday } })

let presets =
  [
    preset ~name:"Contours" ~seed:2019 ~padding:80 ~art:(Lines lines_default) ~colours:dark ~title:"Contours"
      ~subtitle:"Lines that never cross" ~date:("2026", "March, 6", "Friday");
    preset ~name:"Tide" ~seed:42 ~padding:0 ~art:(Lines { lines = 40; amplitude = 90; waves = 2; stroke = 4 })
      ~colours:{ background = "#1d3557"; foreground = "#f1faee" } ~title:"Tide" ~subtitle:"Forty lines, full bleed"
      ~date:("2026", "April, 3", "Friday");
    preset ~name:"Grid" ~seed:7 ~padding:80 ~art:(Blocks blocks_default) ~colours:{ background = "#f4f1ea"; foreground = "#c1121f" }
      ~title:"Grid" ~subtitle:"Packed squares and rectangles" ~date:("2026", "May, 8", "Friday");
    preset ~name:"Strata" ~seed:1234 ~padding:40
      ~art:(Blocks { blocks = 40; gap = 8; filled = 70; squareness = 10 })
      ~colours:{ background = "#ffd60a"; foreground = "#111111" } ~title:"Strata" ~subtitle:"Long strips"
      ~date:("2026", "June, 12", "Friday");
    preset ~name:"Overcast" ~seed:314 ~padding:80 ~art:(Clouds clouds_default) ~colours:light ~title:"Overcast"
      ~subtitle:"Puffs from arcs" ~date:("2026", "July, 3", "Friday");
    preset ~name:"Cumulus" ~seed:90210 ~padding:60 ~art:(Clouds { clouds = 12; puffs = 9; size = 30; solid = 100 })
      ~colours:{ background = "#8ecae6"; foreground = "#ffffff" } ~title:"Cumulus" ~subtitle:"Solid clouds"
      ~date:("2026", "August, 21", "Friday");
    preset ~name:"Storm" ~seed:555 ~padding:80 ~art:(Lightning lightning_default) ~colours:dark ~title:"Storm"
      ~subtitle:"Bolts with branches" ~date:("2026", "October, 30", "Friday");
    preset ~name:"Voltage" ~seed:2718 ~padding:40
      ~art:(Lightning { bolts = 4; branches = 3; jaggedness = 75; thickness = 5 })
      ~colours:{ background = "#283618"; foreground = "#fefae0" } ~title:"Voltage" ~subtitle:"Jagged and thin"
      ~date:("2026", "November, 20", "Friday");
  ]
