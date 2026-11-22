type grid = { seed : int; columns : int; rows : int } [@@deriving codec]
type mix = { half : int; empty : int; block : int; bar : int } [@@deriving codec]
type colours = { background : string; foreground : string } [@@deriving codec]
type text = { title : string; subtitle : string; year : string; day : string; weekday : string } [@@deriving codec]
type settings = { grid : grid; mix : mix; colours : colours; text : text } [@@deriving codec]

type side = Up | Down | Left | Right
type shape = Empty | Block | Half of side | Bar of side
type cell = { index : int; d : string }
type label = { x : int; y : int; size : int; bold : bool; spacing : int; end_ : bool; text : string }

let width = 1000
let height = 1414
let grid_bottom = 1180
let max_seed = 999_999
let max_text = 40
let dark = { background = "#333333"; foreground = "#ffffff" }
let light = { background = "#f4f4f4"; foreground = "#333333" }

let months =
  [| "January"; "February"; "March"; "April"; "May"; "June"; "July"; "August"; "September"; "October"; "November"; "December" |]

let weekdays = [| "Sunday"; "Monday"; "Tuesday"; "Wednesday"; "Thursday"; "Friday"; "Saturday" |]

let defaults ~year ~month ~day ~weekday =
  {
    grid = { seed = 2019; columns = 13; rows = 15 };
    mix = { half = 80; empty = 12; block = 2; bar = 6 };
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
let is_hex = function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false

let color ~default value =
  if String.length value = 7 && value.[0] = '#' && String.for_all is_hex (String.sub value 1 6) then
    String.lowercase_ascii value
  else default

let cut value = if String.length value > max_text then String.sub value 0 max_text else value

let normal_grid (g : grid) = { seed = clamp 0 max_seed g.seed; columns = clamp 4 24 g.columns; rows = clamp 4 30 g.rows }

let normal_mix (m : mix) =
  { half = clamp 0 100 m.half; empty = clamp 0 100 m.empty; block = clamp 0 100 m.block; bar = clamp 0 100 m.bar }

let normal_colours ~(defaults : settings) (c : colours) =
  {
    background = color ~default:defaults.colours.background c.background;
    foreground = color ~default:defaults.colours.foreground c.foreground;
  }

let normal_text (t : text) =
  { title = cut t.title; subtitle = cut t.subtitle; year = cut t.year; day = cut t.day; weekday = cut t.weekday }

let normalize ~defaults (s : settings) =
  { grid = normal_grid s.grid; mix = normal_mix s.mix; colours = normal_colours ~defaults s.colours; text = normal_text s.text }

let step state = ((state * 1103515245) + 12345) land 0x7fffffff
let next state = let state = step state in (state, (state lsr 16) land 0x7fff)
let shuffle seed = step (seed lxor 0x2545f491) mod (max_seed + 1)

let pick (m : mix) state =
  let total = m.half + m.empty + m.block + m.bar in
  let state, roll = next state in
  let state, turn = next state in
  let side = match turn mod 4 with 0 -> Up | 1 -> Down | 2 -> Left | _ -> Right in
  let shape =
    if total = 0 then Empty
    else
      let roll = roll mod total in
      if roll < m.half then Half side
      else if roll < m.half + m.empty then Empty
      else if roll < m.half + m.empty + m.block then Block
      else Bar side
  in
  (state, shape)

let shapes (g : grid) (m : mix) =
  let rec go state remaining acc =
    if remaining = 0 then List.rev acc
    else
      let state, shape = pick m state in
      go state (remaining - 1) (shape :: acc)
  in
  go (step (g.seed lxor 0x5bd1e995)) (g.columns * g.rows) []

let i = Int.to_string

let path ~x0 ~y0 ~x1 ~y1 shape =
  let r = min (x1 - x0) (y1 - y0) / 2 in
  let xm = (x0 + x1) / 2 and ym = (y0 + y1) / 2 in
  let rect x0 y0 x1 y1 = "M" ^ i x0 ^ " " ^ i y0 ^ "H" ^ i x1 ^ "V" ^ i y1 ^ "H" ^ i x0 ^ "z" in
  let half (ax, ay) (bx, by) =
    "M" ^ i ax ^ " " ^ i ay ^ "L" ^ i bx ^ " " ^ i by ^ "A" ^ i r ^ " " ^ i r ^ " 0 0 1 " ^ i ax ^ " " ^ i ay ^ "z"
  in
  match shape with
  | Empty -> ""
  | Block -> rect x0 y0 x1 y1
  | Bar Up -> rect x0 y0 x1 ym
  | Bar Down -> rect x0 ym x1 y1
  | Bar Left -> rect x0 y0 xm y1
  | Bar Right -> rect xm y0 x1 y1
  | Half Up -> half (x0, y0) (x1, y0)
  | Half Right -> half (x1, y0) (x1, y1)
  | Half Down -> half (x1, y1) (x0, y1)
  | Half Left -> half (x0, y1) (x0, y0)

let cells (g : grid) (m : mix) =
  let span, count = if width * g.rows <= grid_bottom * g.columns then (width, g.columns) else (grid_bottom, g.rows) in
  let edge k = k * span / count in
  let left = (width - edge g.columns) / 2 in
  shapes g m
  |> List.mapi (fun index shape ->
         let column = index mod g.columns and row = index / g.columns in
         {
           index;
           d = path ~x0:(left + edge column) ~y0:(edge row) ~x1:(left + edge (column + 1)) ~y1:(edge (row + 1)) shape;
         })
  |> List.filter (fun cell -> cell.d <> "")
  |> Array.of_list

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

let preset ~name ~seed ~columns ~rows ~mix ~colours ~title ~subtitle ~date:(year, day, weekday) =
  (name, { grid = { seed; columns; rows }; mix; colours; text = { title; subtitle; year; day; weekday } })

let classic = { half = 80; empty = 12; block = 2; bar = 6 }

let presets =
  [
    preset ~name:"Classic" ~seed:2019 ~columns:13 ~rows:15 ~mix:classic ~colours:dark ~title:"Classic"
      ~subtitle:"Generative Design" ~date:("2019", "March, 1", "Friday");
    preset ~name:"Paper" ~seed:42 ~columns:13 ~rows:15 ~mix:classic ~colours:light ~title:"Paper"
      ~subtitle:"Light preset" ~date:("2026", "May, 4", "Monday");
    preset ~name:"Maze" ~seed:7 ~columns:18 ~rows:21 ~mix:{ half = 40; empty = 5; block = 0; bar = 55 } ~colours:dark
      ~title:"Maze" ~subtitle:"More bars than discs" ~date:("2026", "June, 12", "Friday");
    preset ~name:"Pebbles" ~seed:314 ~columns:8 ~rows:9 ~mix:{ half = 100; empty = 0; block = 0; bar = 0 }
      ~colours:{ background = "#1d3557"; foreground = "#f1faee" } ~title:"Pebbles" ~subtitle:"Half discs only"
      ~date:("2026", "July, 3", "Friday");
    preset ~name:"Sparse" ~seed:90210 ~columns:13 ~rows:15 ~mix:{ half = 30; empty = 65; block = 0; bar = 5 }
      ~colours:{ background = "#f4f1ea"; foreground = "#c1121f" } ~title:"Sparse" ~subtitle:"Mostly empty"
      ~date:("2026", "August, 21", "Friday");
    preset ~name:"Blocks" ~seed:1234 ~columns:10 ~rows:12 ~mix:{ half = 50; empty = 10; block = 30; bar = 10 }
      ~colours:{ background = "#ffd60a"; foreground = "#111111" } ~title:"Blocks" ~subtitle:"Squares and halves"
      ~date:("2026", "September, 9", "Wednesday");
    preset ~name:"Dense" ~seed:555 ~columns:24 ~rows:30 ~mix:classic ~colours:dark ~title:"Dense"
      ~subtitle:"24 by 30 cells" ~date:("2026", "October, 31", "Saturday");
    preset ~name:"Forest" ~seed:2718 ~columns:12 ~rows:14 ~mix:{ half = 70; empty = 20; block = 0; bar = 10 }
      ~colours:{ background = "#283618"; foreground = "#fefae0" } ~title:"Forest" ~subtitle:"Custom colours"
      ~date:("2026", "November, 22", "Sunday");
  ]
