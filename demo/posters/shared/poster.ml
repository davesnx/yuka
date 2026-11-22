type settings = {
  seed : int;
  columns : int;
  rows : int;
  half : int;
  empty : int;
  block : int;
  bar : int;
  background : string;
  foreground : string;
  title : string;
  subtitle : string;
  year : string;
  day : string;
  weekday : string;
}
[@@deriving codec]

type side = Up | Down | Left | Right
type cell = Empty | Block | Half of side | Bar of side

type label = { x : int; y : int; size : int; bold : bool; spacing : int; end_ : bool; text : string }

let width = 1000
let height = 1414
let grid_bottom = 1180
let max_seed = 999_999
let max_text = 40
let dark = ("#333333", "#ffffff")
let light = ("#f4f4f4", "#333333")

let months =
  [| "January"; "February"; "March"; "April"; "May"; "June"; "July"; "August"; "September"; "October"; "November"; "December" |]

let weekdays = [| "Sunday"; "Monday"; "Tuesday"; "Wednesday"; "Thursday"; "Friday"; "Saturday" |]

let defaults ~year ~month ~day ~weekday =
  {
    seed = 2019;
    columns = 13;
    rows = 15;
    half = 80;
    empty = 12;
    block = 2;
    bar = 6;
    background = fst dark;
    foreground = snd dark;
    title = "Yuka";
    subtitle = "Generative Design";
    year = Int.to_string year;
    day = months.(month) ^ ", " ^ Int.to_string day;
    weekday = weekdays.(weekday);
  }

let clamp low high value = max low (min high value)

let is_hex = function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false

let color ~default value =
  if String.length value = 7 && value.[0] = '#' && String.for_all is_hex (String.sub value 1 6) then
    String.lowercase_ascii value
  else default

let text value = if String.length value > max_text then String.sub value 0 max_text else value

let normalize ~(defaults : settings) (s : settings) =
  {
    seed = clamp 0 max_seed s.seed;
    columns = clamp 4 24 s.columns;
    rows = clamp 4 30 s.rows;
    half = clamp 0 100 s.half;
    empty = clamp 0 100 s.empty;
    block = clamp 0 100 s.block;
    bar = clamp 0 100 s.bar;
    background = color ~default:defaults.background s.background;
    foreground = color ~default:defaults.foreground s.foreground;
    title = text s.title;
    subtitle = text s.subtitle;
    year = text s.year;
    day = text s.day;
    weekday = text s.weekday;
  }

let step state = ((state * 1103515245) + 12345) land 0x7fffffff
let next state = let state = step state in (state, (state lsr 16) land 0x7fff)

let shuffle seed = step (seed lxor 0x2545f491) mod (max_seed + 1)

let pick (s : settings) state =
  let total = s.half + s.empty + s.block + s.bar in
  let state, roll = next state in
  let state, turn = next state in
  let side = match turn mod 4 with 0 -> Up | 1 -> Down | 2 -> Left | _ -> Right in
  let cell =
    if total = 0 then Empty
    else
      let roll = roll mod total in
      if roll < s.half then Half side
      else if roll < s.half + s.empty then Empty
      else if roll < s.half + s.empty + s.block then Block
      else Bar side
  in
  (state, cell)

let cells (s : settings) =
  let rec go state remaining acc =
    if remaining = 0 then List.rev acc
    else
      let state, cell = pick s state in
      go state (remaining - 1) (cell :: acc)
  in
  go (step (s.seed lxor 0x5bd1e995)) (s.columns * s.rows) []

let i = Int.to_string

let shape ~x0 ~y0 ~x1 ~y1 cell =
  let r = min (x1 - x0) (y1 - y0) / 2 in
  let xm = (x0 + x1) / 2 and ym = (y0 + y1) / 2 in
  let rect x0 y0 x1 y1 = "M" ^ i x0 ^ " " ^ i y0 ^ "H" ^ i x1 ^ "V" ^ i y1 ^ "H" ^ i x0 ^ "z" in
  let half (ax, ay) (bx, by) =
    "M" ^ i ax ^ " " ^ i ay ^ "L" ^ i bx ^ " " ^ i by ^ "A" ^ i r ^ " " ^ i r ^ " 0 0 1 " ^ i ax ^ " " ^ i ay ^ "z"
  in
  match cell with
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

let grid (s : settings) =
  let span, count = if width * s.rows <= grid_bottom * s.columns then (width, s.columns) else (grid_bottom, s.rows) in
  let edge k = k * span / count in
  let left = (width - edge s.columns) / 2 in
  String.concat ""
    (List.mapi
       (fun index cell ->
         let column = index mod s.columns and row = index / s.columns in
         shape ~x0:(left + edge column) ~y0:(edge row) ~x1:(left + edge (column + 1)) ~y1:(edge (row + 1)) cell)
       (cells s))

let labels (s : settings) =
  let line y size text = { x = 918; y; size; bold = false; spacing = 0; end_ = true; text } in
  [
    { x = 82; y = 1262; size = 36; bold = true; spacing = 5; end_ = false; text = String.uppercase_ascii s.title };
    { x = 82; y = 1320; size = 25; bold = false; spacing = 0; end_ = false; text = s.subtitle };
    line 1258 24 s.year;
    line 1291 24 s.day;
    line 1324 24 s.weekday;
  ]

let font = "Helvetica Neue, Helvetica, Arial, sans-serif"
let view_box = "0 0 " ^ i width ^ " " ^ i height

let escape text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (function
      | '&' -> Buffer.add_string buffer "&amp;"
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | c -> Buffer.add_char buffer c)
    text;
  Buffer.contents buffer

let svg (s : settings) =
  let label l =
    "<text x=\"" ^ i l.x ^ "\" y=\"" ^ i l.y ^ "\" font-size=\"" ^ i l.size ^ "\" font-weight=\""
    ^ (if l.bold then "700" else "400")
    ^ "\" letter-spacing=\"" ^ i l.spacing ^ "\" text-anchor=\""
    ^ (if l.end_ then "end" else "start")
    ^ "\">" ^ escape l.text ^ "</text>"
  in
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" ^ i width ^ "\" height=\"" ^ i height ^ "\" viewBox=\""
  ^ view_box ^ "\"><rect width=\"" ^ i width ^ "\" height=\"" ^ i height ^ "\" fill=\"" ^ s.background
  ^ "\"/><path fill=\"" ^ s.foreground ^ "\" d=\"" ^ grid s ^ "\"/><g fill=\"" ^ s.foreground ^ "\" font-family=\""
  ^ font ^ "\">"
  ^ String.concat "" (List.map label (labels s))
  ^ "</g></svg>"
