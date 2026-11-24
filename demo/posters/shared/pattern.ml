type layout = { seed : int; padding : int } [@@deriving codec]
type lines = { lines : int; amplitude : int; waves : int; stroke : int; direction : int } [@@deriving codec]
type blocks = { blocks : int; gap : int; filled : int; squareness : int; radius : int } [@@deriving codec]
type clouds = { clouds : int; puffs : int; size : int } [@@deriving codec]
type lightning = { bolts : int; branches : int; jaggedness : int; thickness : int; direction : int; length : int } [@@deriving codec]
type circles = { columns : int; rows : int; half : int; empty : int; block : int; bar : int } [@@deriving codec]

type art =
  | Lines of lines
  | Blocks of blocks
  | Clouds of clouds
  | Lightning of lightning
  | Circles of circles
[@@deriving codec]

type colours = { background : string; foreground : string } [@@deriving codec]
type text = { title : string; subtitle : string; year : string; day : string; weekday : string } [@@deriving codec]
type settings = { layout : layout; art : art; colours : colours; text : text } [@@deriving codec]

module Kind = struct
  type t = Lines | Blocks | Clouds | Lightning | Circles

  let all = [ Lines; Blocks; Clouds; Lightning; Circles ]

  let name = function
    | Lines -> "lines"
    | Blocks -> "blocks"
    | Clouds -> "clouds"
    | Lightning -> "lightning"
    | Circles -> "circles"

  let label = function
    | Lines -> "Lines"
    | Blocks -> "Blocks"
    | Clouds -> "Clouds"
    | Lightning -> "Lightning"
    | Circles -> "Circles"

  let param =
    Yuka.Router.Param.make
      ~decode:(function
        | "lines" -> Some Lines
        | "blocks" -> Some Blocks
        | "clouds" -> Some Clouds
        | "lightning" -> Some Lightning
        | "circles" -> Some Circles
        | _ -> None)
      ~encode:name
end

let kind = function
  | Lines _ -> Kind.Lines
  | Blocks _ -> Kind.Blocks
  | Clouds _ -> Kind.Clouds
  | Lightning _ -> Kind.Lightning
  | Circles _ -> Kind.Circles

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
  let direction = (0, 359)
  let blocks = (1, 80)
  let gap = (0, 60)
  let filled = (0, 100)
  let squareness = (0, 100)
  let radius = (0, 60)
  let clouds = (1, 20)
  let puffs = (3, 14)
  let size = (10, 100)
  let bolts = (1, 8)
  let branches = (0, 12)
  let jaggedness = (0, 100)
  let thickness = (1, 24)
  let length = (20, 100)
  let columns = (4, 24)
  let rows = (4, 30)
  let share = (0, 100)
end

let lines_default = { lines = 32; amplitude = 60; waves = 3; stroke = 6; direction = 90 }
let blocks_default = { blocks = 14; gap = 16; filled = 45; squareness = 50; radius = 0 }
let clouds_default = { clouds = 6; puffs = 6; size = 45 }
let lightning_default = { bolts = 2; branches = 4; jaggedness = 55; thickness = 7; direction = 180; length = 100 }
let circles_default = { columns = 13; rows = 15; half = 80; empty = 12; block = 2; bar = 6 }

let fresh = function
  | Kind.Lines -> Lines lines_default
  | Kind.Blocks -> Blocks blocks_default
  | Kind.Clouds -> Clouds clouds_default
  | Kind.Lightning -> Lightning lightning_default
  | Kind.Circles -> Circles circles_default

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

let cut value =
  let rec boundary n = if n > 0 && Char.code value.[n] land 0xc0 = 0x80 then boundary (n - 1) else n in
  if String.length value > max_text then String.sub value 0 (boundary max_text) else value

let normal_layout (l : layout) = { seed = clamp 0 max_seed l.seed; padding = fit Range.padding l.padding }

let normal_art = function
  | Lines l ->
      Lines
        {
          lines = fit Range.lines l.lines;
          amplitude = fit Range.amplitude l.amplitude;
          waves = fit Range.waves l.waves;
          stroke = fit Range.stroke l.stroke;
          direction = fit Range.direction l.direction;
        }
  | Blocks b ->
      Blocks
        {
          blocks = fit Range.blocks b.blocks;
          gap = fit Range.gap b.gap;
          filled = fit Range.filled b.filled;
          squareness = fit Range.squareness b.squareness;
          radius = fit Range.radius b.radius;
        }
  | Clouds c ->
      Clouds
        { clouds = fit Range.clouds c.clouds; puffs = fit Range.puffs c.puffs; size = fit Range.size c.size }
  | Lightning l ->
      Lightning
        {
          bolts = fit Range.bolts l.bolts;
          branches = fit Range.branches l.branches;
          jaggedness = fit Range.jaggedness l.jaggedness;
          thickness = fit Range.thickness l.thickness;
          direction = fit Range.direction l.direction;
          length = fit Range.length l.length;
        }
  | Circles c ->
      Circles
        {
          columns = fit Range.columns c.columns;
          rows = fit Range.rows c.rows;
          half = fit Range.share c.half;
          empty = fit Range.share c.empty;
          block = fit Range.share c.block;
          bar = fit Range.share c.bar;
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

let scramble x =
  let x = step x in
  x lxor (x lsr 15)

let draw seed parts bound =
  let hash = List.fold_left (fun h part -> scramble (scramble (h lxor part))) (scramble (seed lxor 0x5bd1e995)) parts in
  if bound <= 0 then 0 else ((hash lsr 15) land 0x7fff) * bound / 32768

let isqrt n =
  let rec go x =
    let y = (x + (n / x)) / 2 in
    if y >= x then x else go y
  in
  if n <= 0 then 0 else go n

let i = Int.to_string
let point (x, y) = i x ^ " " ^ i y
let inset k r = { left = r.left + k; top = r.top + k; right = r.right - k; bottom = r.bottom - k }
let centre_x = width / 2
let centre_y = art_bottom / 2
let cover = 1564

let wave random (l : lines) =
  let s = cover in
  let left = centre_x - (s / 2) in
  let amp = s * l.amplitude / 700 in
  let segments = 2 * l.waves in
  let jitter = s / (5 * segments) in
  let half = max 0 ((s * 3 / (10 * segments)) - 1) in
  let xs =
    Array.init (segments + 1) (fun k ->
        if k = 0 || k = segments then left + (s * k / segments)
        else left + (s * k / segments) + random [ 1; 1; k ] ((2 * jitter) + 1) - jitter)
  in
  let x k = xs.(k) in
  let profile p =
    let first = if random [ 1; 2; p ] 2 = 0 then 1 else -1 in
    Array.init (segments + 1) (fun k ->
        (if k mod 2 = 0 then first else -first) * ((amp / 4) + random [ 1; 3; p; k ] ((amp * 3 / 4) + 1)))
  in
  let a = profile 0 and b = profile 1 in
  let n = l.lines in
  Array.init n (fun index ->
      let place = (2 * index) + 1 in
      let band = s + (2 * amp) in
      let base = centre_y - (band / 2) + (band * place / (2 * n)) in
      let y k = base + (((a.(k) * ((2 * n) - place)) + (b.(k) * place)) / (2 * n)) in
      let rest = List.init (segments - 1) (fun j -> j + 2) in
      {
        index;
        d =
          "M" ^ point (x 0, y 0) ^ "C" ^ point (x 0 + half, y 0) ^ " " ^ point (x 1 - half, y 1) ^ " " ^ point (x 1, y 1)
          ^ String.concat "" (List.map (fun k -> "S" ^ point (x k - half, y k) ^ " " ^ point (x k, y k)) rest);
        paint = Stroke l.stroke;
      })

let rect r = "M" ^ point (r.left, r.top) ^ "H" ^ i r.right ^ "V" ^ i r.bottom ^ "H" ^ i r.left ^ "z"
let arc ?(large = false) r (x, y) = "A" ^ i r ^ " " ^ i r ^ (if large then " 0 1 1 " else " 0 0 1 ") ^ point (x, y)

let rounded radius r =
  if radius <= 0 then rect r
  else
    "M" ^ point (r.left + radius, r.top) ^ "H" ^ i (r.right - radius)
    ^ arc radius (r.right, r.top + radius)
    ^ "V" ^ i (r.bottom - radius)
    ^ arc radius (r.right - radius, r.bottom)
    ^ "H" ^ i (r.left + radius)
    ^ arc radius (r.left, r.bottom - radius)
    ^ "V" ^ i (r.top + radius)
    ^ arc radius (r.left + radius, r.top)
    ^ "z"

let smallest = 68
let most_blocks = snd Range.blocks

let cuts random box ~squareness ~blocks =
  let fits side = side / smallest in
  let capacity r = fits (r.right - r.left) * fits (r.bottom - r.top) in
  let splits_x r = fits (r.right - r.left) >= 2 in
  let splits_y r = fits (r.bottom - r.top) >= 2 in
  let area r = if capacity r >= 2 then (r.right - r.left) * (r.bottom - r.top) / 64 else 0 in
  let rects = ref [| box |] in
  let total = ref (capacity box) in
  for turn = 1 to blocks - 1 do
    let weight = Array.fold_left (fun sum r -> sum + area r) 0 !rects in
    if weight > 0 then begin
      let roll = random [ 2; 1; turn ] weight in
      let rec find k sum =
        let sum = sum + area !rects.(k) in
        if roll < sum then k else find (k + 1) sum
      in
      let k = find 0 0 in
      let r = !rects.(k) in
      let along_long = random [ 2; 2; turn ] 100 < 50 + (squareness / 2) in
      let across_x = (r.right - r.left >= r.bottom - r.top) = along_long in
      let across_x = if across_x then splits_x r else not (splits_y r) in
      let side = if across_x then r.right - r.left else r.bottom - r.top in
      let spread = (100 - squareness) * 40 / 100 in
      let share = 50 - spread + random [ 2; 3; turn ] ((2 * spread) + 1) in
      let cut at =
        if across_x then ({ r with right = r.left + at }, { r with left = r.left + at })
        else ({ r with bottom = r.top + at }, { r with top = r.top + at })
      in
      let first, second = cut (clamp smallest (side - smallest) (side * share / 100)) in
      let after = !total - capacity r + capacity first + capacity second in
      let first, second, after =
        if after >= most_blocks then (first, second, after)
        else
          let first, second = cut (smallest * clamp 1 (fits side - 1) (side * share / 100 / smallest)) in
          (first, second, !total)
      in
      total := after;
      !rects.(k) <- first;
      rects := Array.append !rects [| second |]
    end
  done;
  !rects

let pack random box (b : blocks) =
  let near = b.gap / 2 and far = b.gap - (b.gap / 2) in
  let visible r =
    {
      left = (if r.left > box.left then r.left + near else r.left);
      top = (if r.top > box.top then r.top + near else r.top);
      right = (if r.right < box.right then r.right - far else r.right);
      bottom = (if r.bottom < box.bottom then r.bottom - far else r.bottom);
    }
  in
  Array.mapi
    (fun index r ->
      let v = visible r in
      let radius = min b.radius (min (v.right - v.left) (v.bottom - v.top) / 2) in
      if random [ 2; 4; index ] 100 < b.filled then { index; d = rounded radius v; paint = Fill }
      else { index; d = rounded (max 0 (radius - 3)) (inset 3 v); paint = Stroke 6 })
    (cuts random box ~squareness:b.squareness ~blocks:b.blocks)

let cloud random ~id ~w ~h ~puffs =
  let weights = Array.init puffs (fun j -> 2 + random [ 3; 4; id; j ] 4) in
  let sum = Array.fold_left ( + ) 0 weights in
  let steps = Array.make (puffs + 1) 0 in
  Array.iteri (fun j weight -> steps.(j + 1) <- steps.(j) + weight) weights;
  let points =
    Array.init (puffs + 1) (fun j ->
        let along = steps.(j) in
        let num, den, sign = if 2 * along <= sum then (2 * along, sum, -1) else (2 * (sum - along), sum, 1) in
        let norm = (den * den) + (num * num) in
        let x = (w / 2) + (sign * (w / 2) * ((den * den) - (num * num)) / norm) in
        let y = -(h * 2 * num * den / norm) in
        if j = 0 || j = puffs then (x, 0)
        else
          let swell = 100 + random [ 3; 5; id; j ] 16 - 8 in
          ((w / 2) + ((x - (w / 2)) * swell / 100), y * swell / 100))
  in
  let bumps =
    Array.init puffs (fun j ->
        let (ax, ay), (bx, by) = (points.(j), points.(j + 1)) in
        let chord = isqrt (((bx - ax) * (bx - ax)) + ((by - ay) * (by - ay))) in
        let r = (chord / 2) + 1 + (chord * random [ 3; 6; id; j ] 8 / 100) in
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

let most_shrinks = 24
let smallest_cloud = 16
let scan_step = 8

let sky random box (c : clouds) =
  let bw = box.right - box.left and bh = box.bottom - box.top in
  let placed = ref [] in
  for id = 0 to c.clouds - 1 do
    let scale = 55 + random [ 3; 1; id ] 46 in
    let tall = 34 + random [ 3; 2; id ] 24 in
    let puffs = max 3 (c.puffs - 2 + random [ 3; 3; id ] 5) in
    let rec shaped w tries =
      let bounds, path = cloud random ~id ~w ~h:(w * tall / 100) ~puffs in
      if (bounds.right - bounds.left <= bw && bounds.bottom - bounds.top <= bh) || tries = 0 then (bounds, path)
      else shaped (w * 3 / 4) (tries - 1)
    in
    let rec fitted w smaller =
      let bounds, path = shaped w 6 in
      let room_x = bw - (bounds.right - bounds.left) and room_y = bh - (bounds.bottom - bounds.top) in
      let at x y =
        let dx = box.left + x - bounds.left and dy = box.top + y - bounds.top in
        let spot = { left = bounds.left + dx - 12; top = bounds.top + dy - 12; right = bounds.right + dx + 12; bottom = bounds.bottom + dy + 12 } in
        if List.exists (fun (other, _) -> overlaps spot other) !placed then None else Some (spot, path (dx, dy))
      in
      let rec place attempt =
        if attempt = 60 then None
        else
          let tries = if smaller = 0 then [ id; attempt ] else [ id; attempt; smaller ] in
          match at (random (3 :: 7 :: tries) (room_x + 1)) (random (3 :: 8 :: tries) (room_y + 1)) with
          | None -> place (attempt + 1)
          | found -> found
      in
      let scan () =
        let columns = (room_x / scan_step) + 1 and rows = (room_y / scan_step) + 1 in
        let start = random [ 3; 10; id; smaller ] (columns * rows) in
        let rec go k =
          if k = columns * rows then None
          else
            let cell = (start + k) mod (columns * rows) in
            match at (cell mod columns * scan_step) (cell / columns * scan_step) with None -> go (k + 1) | found -> found
        in
        go 0
      in
      let found = if room_x < 0 || room_y < 0 then None else match place 0 with None -> scan () | found -> found in
      match found with
      | None when smaller < most_shrinks && w > smallest_cloud -> fitted (w * 4 / 5) (smaller + 1)
      | found -> found
    in
    let widest = min (bw * c.size / 100) (bw * 12 / isqrt (100 * c.clouds)) in
    match fitted (widest * scale / 100) 0 with
    | Some (spot, d) -> placed := (spot, { index = id; d; paint = Fill }) :: !placed
    | None -> ()
  done;
  Array.of_list (List.rev_map snd !placed)

let sine degrees =
  let d = ((degrees mod 360) + 360) mod 360 in
  let half d = 4000 * d * (180 - d) / (40500 - (d * (180 - d))) in
  if d <= 180 then half d else -half (d - 180)

let cosine degrees = sine (degrees + 90)
let turn (l : lightning) = l.direction - 180

let turned box degrees =
  let w = box.right - box.left and h = box.bottom - box.top in
  let c = abs (cosine degrees) and s = abs (sine degrees) in
  let bw = ((w * c) + (h * s)) / 1000 and bh = ((w * s) + (h * c)) / 1000 in
  let h' = min (w * bh * 1000 / ((bw * c) + (bh * s))) (h * bh * 1000 / ((bw * s) + (bh * c))) in
  let h' = if c = 0 || s = 0 then h' else h' * 98 / 100 in
  let w' = h' * bw / bh in
  let x = (box.left + box.right) / 2 and y = (box.top + box.bottom) / 2 in
  { left = x - (w' / 2); top = y - (h' / 2); right = x + (w' / 2); bottom = y + (h' / 2) }

let storm random box (l : lightning) =
  let box = if turn l = 0 then box else turned box (turn l) in
  let w = box.right - box.left and h = box.bottom - box.top in
  let reach = h * l.length / 100 in
  let fold x = clamp box.left box.right (if x < box.left then (2 * box.left) - x else if x > box.right then (2 * box.right) - x else x) in
  let split ~bolt ~slot a b depth spread =
    let rec go (ax, ay) (bx, by) depth spread node =
      if depth = 0 then [ (bx, by) ]
      else
        let shift = random [ 4; 4; bolt; slot; node ] ((2 * spread) + 1) in
        let middle = (fold (((ax + bx) / 2) + shift - spread), (ay + by) / 2) in
        let first = go (ax, ay) middle (depth - 1) (spread / 2) (2 * node) in
        first @ go middle (bx, by) (depth - 1) (spread / 2) ((2 * node) + 1)
    in
    go a b depth spread 1
  in
  let polyline points =
    match points with first :: rest -> "M" ^ point first ^ "L" ^ String.concat " " (List.map point rest) | [] -> ""
  in
  let slots = snd Range.branches + 1 in
  List.concat
    (List.init l.bolts (fun bolt ->
         let sx = box.left + random [ 4; 1; bolt ] (w + 1) in
         let ex = clamp box.left box.right (sx + random [ 4; 2; bolt ] ((w / 2) + 1) - (w / 4)) in
         let ey = box.top + reach - random [ 4; 3; bolt ] ((reach / 4) + 1) in
         let start = (sx, box.top) in
         let points = start :: split ~bolt ~slot:0 start (ex, ey) 6 ((ey - box.top) * l.jaggedness / 400) in
         { index = bolt * slots; d = polyline points; paint = Stroke l.thickness }
         :: List.init l.branches (fun j ->
                let slot = j + 1 in
                let at = List.nth points (6 + random [ 4; 5; bolt; slot ] 36) in
                let side = if random [ 4; 6; bolt; slot ] 2 = 0 then 1 else -1 in
                let dx = (w / 20) + random [ 4; 7; bolt; slot ] ((w / 6) + 1) in
                let dy = (reach / 8) + random [ 4; 8; bolt; slot ] ((reach / 4) + 1) in
                let ending = (fold (fst at + (side * dx)), min box.bottom (snd at + dy)) in
                {
                  index = (bolt * slots) + slot;
                  d = polyline (at :: split ~bolt ~slot at ending 4 ((dx + dy) * l.jaggedness / 400));
                  paint = Stroke (max 1 (l.thickness * 3 / 5));
                })))
  |> Array.of_list

type side = Up | Down | Left | Right
type cell = Empty | Block | Half of side | Bar of side

let cell_path ~x0 ~y0 ~x1 ~y1 cell =
  let r = min (x1 - x0) (y1 - y0) / 2 in
  let xm = (x0 + x1) / 2 and ym = (y0 + y1) / 2 in
  let box x0 y0 x1 y1 = rect { left = x0; top = y0; right = x1; bottom = y1 } in
  let half (ax, ay) b = "M" ^ point (ax, ay) ^ "L" ^ point b ^ arc r (ax, ay) ^ "z" in
  match cell with
  | Empty -> ""
  | Block -> box x0 y0 x1 y1
  | Bar Up -> box x0 y0 x1 ym
  | Bar Down -> box x0 ym x1 y1
  | Bar Left -> box x0 y0 xm y1
  | Bar Right -> box xm y0 x1 y1
  | Half Up -> half (x0, y0) (x1, y0)
  | Half Right -> half (x1, y0) (x1, y1)
  | Half Down -> half (x1, y1) (x0, y1)
  | Half Left -> half (x0, y1) (x0, y0)

let most_columns = snd Range.columns

let grid random box (c : circles) =
  let w = box.right - box.left and h = box.bottom - box.top in
  let span, count = if w * c.rows <= h * c.columns then (w, c.columns) else (h, c.rows) in
  let edge k = k * span / count in
  let left = box.left + ((w - edge c.columns) / 2) and top = box.top + ((h - edge c.rows) / 2) in
  let total = c.half + c.empty + c.block + c.bar in
  let cell column row =
    let roll = random [ 5; 1; column; row ] total in
    let side = match random [ 5; 2; column; row ] 4 with 0 -> Up | 1 -> Down | 2 -> Left | _ -> Right in
    if total = 0 then Empty
    else if roll < c.half then Half side
    else if roll < c.half + c.empty then Empty
    else if roll < c.half + c.empty + c.block then Block
    else Bar side
  in
  List.init c.rows (fun row ->
      List.init c.columns (fun column ->
          {
            index = (row * most_columns) + column;
            d =
              cell_path ~x0:(left + edge column) ~y0:(top + edge row) ~x1:(left + edge (column + 1)) ~y1:(top + edge (row + 1))
                (cell column row);
            paint = Fill;
          }))
  |> List.concat
  |> List.filter (fun s -> s.d <> "")
  |> Array.of_list

let area padding = { left = padding; top = padding; right = width - padding; bottom = art_bottom - padding }
let clip_id padding = "art-" ^ i padding

let rotate degrees = Some ("rotate(" ^ i degrees ^ " " ^ point (centre_x, centre_y) ^ ")")

let rotation = function
  | Lines l when l.direction <> 90 -> rotate (l.direction - 90)
  | Lightning l when turn l <> 0 -> rotate (turn l)
  | _ -> None

let shapes (l : layout) art =
  let random = draw l.seed and box = area l.padding in
  match art with
  | Lines a -> wave random a
  | Blocks a -> pack random box a
  | Clouds a -> sky random box a
  | Lightning a -> storm random (if l.padding = 0 then box else inset ((a.thickness + 1) / 2) box) a
  | Circles a -> grid random box a

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
    preset ~name:"Tide" ~seed:42 ~padding:0
      ~art:(Lines { lines = 56; amplitude = 90; waves = 2; stroke = 4; direction = 120 })
      ~colours:{ background = "#1d3557"; foreground = "#f1faee" } ~title:"Tide" ~subtitle:"Tilted, full bleed"
      ~date:("2026", "April, 3", "Friday");
    preset ~name:"Grid" ~seed:7 ~padding:80 ~art:(Blocks { blocks_default with radius = 18 })
      ~colours:{ background = "#f4f1ea"; foreground = "#c1121f" } ~title:"Grid" ~subtitle:"Rounded squares and rectangles"
      ~date:("2026", "May, 8", "Friday");
    preset ~name:"Strata" ~seed:1234 ~padding:40
      ~art:(Blocks { blocks = 40; gap = 8; filled = 70; squareness = 10; radius = 0 })
      ~colours:{ background = "#ffd60a"; foreground = "#111111" } ~title:"Strata" ~subtitle:"Long strips"
      ~date:("2026", "June, 12", "Friday");
    preset ~name:"Overcast" ~seed:314 ~padding:80 ~art:(Clouds clouds_default) ~colours:light ~title:"Overcast"
      ~subtitle:"Puffs from arcs" ~date:("2026", "July, 3", "Friday");
    preset ~name:"Cumulus" ~seed:90210 ~padding:60 ~art:(Clouds { clouds = 12; puffs = 7; size = 32 })
      ~colours:{ background = "#8ecae6"; foreground = "#ffffff" } ~title:"Cumulus" ~subtitle:"Solid clouds"
      ~date:("2026", "August, 21", "Friday");
    preset ~name:"Storm" ~seed:555 ~padding:80 ~art:(Lightning lightning_default) ~colours:dark ~title:"Storm"
      ~subtitle:"Bolts with branches" ~date:("2026", "October, 30", "Friday");
    preset ~name:"Voltage" ~seed:2718 ~padding:40
      ~art:(Lightning { lightning_default with bolts = 4; branches = 3; jaggedness = 75; thickness = 5 })
      ~colours:{ background = "#283618"; foreground = "#fefae0" } ~title:"Voltage" ~subtitle:"Jagged and thin"
      ~date:("2026", "November, 20", "Friday");
    preset ~name:"Classic" ~seed:2019 ~padding:0 ~art:(Circles circles_default) ~colours:dark ~title:"Classic"
      ~subtitle:"Half discs, the first poster" ~date:("2019", "March, 1", "Friday");
    preset ~name:"Pebbles" ~seed:314 ~padding:80
      ~art:(Circles { columns = 8; rows = 9; half = 100; empty = 0; block = 0; bar = 0 })
      ~colours:{ background = "#e76f51"; foreground = "#264653" } ~title:"Pebbles" ~subtitle:"Half discs only"
      ~date:("2026", "December, 4", "Friday");
  ]
