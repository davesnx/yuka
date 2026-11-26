(* A port of sketch-004 of Amie Chen's genart series
   (https://github.com/amiechen/genart/blob/master/sketch-004.js): a grid of dots, each
   joined by a round line to itself, or to its right, lower right or lower neighbour,
   in a colour picked from a palette, with an opacity of its own, on black.

   The original draws with Math.random. Here each random number is a hash of the seed
   and of the cell, so the server and the browser draw the same lines and the island
   hydrates. All the math is on integers below 2^31, which native code and JavaScript
   compute the same way. *)

let size = 2048
let margin = 300
let view_box = "0 0 2048 2048"

module Range = struct
  let seed = (0, 999_999)
  let grid = (2, 40)
  let stroke = (1, 40)
end

let palettes =
  [|
    ("Sunset", [| "#ff5f5d"; "#ff9a5c"; "#ffd166"; "#f4f1de"; "#3d5a80" |]);
    ("Lagoon", [| "#0081a7"; "#00afb9"; "#a8e6cf"; "#fdfcdc"; "#f07167" |]);
    ("Orchard", [| "#d62839"; "#f4a259"; "#f4e285"; "#8cb369"; "#5b8e7d" |]);
    ("Neon", [| "#ff2e88"; "#ffd400"; "#00e5ff"; "#7c4dff"; "#f5f5f5" |]);
    ("Dune", [| "#e9c46a"; "#f4a261"; "#e76f51"; "#d4a373"; "#faedcd" |]);
    ("Glacier", [| "#caf0f8"; "#90e0ef"; "#48cae4"; "#0096c7"; "#ade8f4" |]);
    ("Pop", [| "#ff1f7a"; "#ff6b1a"; "#ffc21a"; "#9146ff"; "#3d8bff" |]);
    ("Moss", [| "#a3b18a"; "#dad7cd"; "#588157"; "#c9e4ca"; "#e9f5db" |]);
    ("Sorbet", [| "#ffa8a8"; "#ffd3a1"; "#fbf8b0"; "#c4f5b8"; "#a0eefa" |]);
    ("Ember", [| "#ff3c38"; "#ff8c42"; "#fff275"; "#a23e48"; "#f6e8ea" |]);
    ("Lilac", [| "#cbb2dd"; "#ffc6de"; "#ffaac9"; "#b9dcfa"; "#9fcdfa" |]);
    ("Ash", [| "#ffffff"; "#d9d9d9"; "#a6a6a6"; "#f2f2f2"; "#8c8c8c" |]);
  |]

(* [palette] is an index in [palettes]; [None] picks a palette for each line, as the
   original does. *)
type settings = { seed : int; grid : int; stroke : int; palette : int option } [@@deriving codec]

let default = { seed = 4; grid = 20; stroke = 10; palette = None }
let clamp (low, high) n = Int.max low (Int.min high n)

let normalize s =
  {
    seed = clamp Range.seed s.seed;
    grid = clamp Range.grid s.grid;
    stroke = clamp Range.stroke s.stroke;
    palette = (match s.palette with Some p when p >= 0 && p < Array.length palettes -> Some p | _ -> None);
  }

let step state = ((state * 1103515245) + 12345) land 0x7fffffff

let scramble x =
  let x = step x in
  x lxor (x lsr 15)

(* A number in [0, bound), from the seed and the parts, all of them at least 0. *)
let draw seed parts bound =
  let hash = List.fold_left (fun h part -> scramble (scramble (h lxor part))) (scramble (seed lxor 0x5bd1e995)) parts in
  if bound <= 0 then 0 else ((hash lsr 15) land 0x7fff) * bound / 32768

let shuffle seed = step (seed lxor 0x2545f491) mod (snd Range.seed + 1)

(* The number of times each cell was drawn again by the drift, by [cell]. A cell keeps
   its index at every grid size, so a larger grid keeps the lines of the smaller one. *)
type versions = int array

let side = snd Range.grid
let cell ~col ~row = (col * side) + row
let fresh () : versions = Array.make (side * side) 0

type segment = { key : string; x1 : int; y1 : int; x2 : int; y2 : int; color : string; alpha : int }

(* lerp(margin, size - margin, i / (grid - 1)); a neighbour past the last dot is one
   step further, as in the original. *)
let position ~grid i = margin + ((size - (2 * margin)) * i / (grid - 1))

let segment (s : settings) (versions : versions) ~col ~row =
  let version = versions.(cell ~col ~row) in
  let pick purpose bound = draw s.seed [ col; row; version; purpose ] bound in
  let at = position ~grid:s.grid in
  let x = at col and y = at row in
  let x2, y2 =
    match pick 0 4 with 0 -> (x, y) | 1 -> (at (col + 1), y) | 2 -> (at (col + 1), at (row + 1)) | _ -> (x, at (row + 1))
  in
  let _, colors = palettes.(match s.palette with Some p -> p | None -> pick 1 (Array.length palettes)) in
  {
    key = Int.to_string col ^ "-" ^ Int.to_string row;
    x1 = x;
    y1 = y;
    x2;
    y2;
    color = colors.(pick 2 (Array.length colors));
    (* The original picks the opacity once, when it makes the grid: the drift keeps it. *)
    alpha = draw s.seed [ col; row; 3 ] 1000;
  }

let segments (s : settings) versions =
  Array.init (s.grid * s.grid) (fun i -> segment s versions ~col:(i / s.grid) ~row:(i mod s.grid))

(* One step of the drift: about one line in 60 of the grid, at least one, picked from
   the seed and the step, is drawn again. *)
let drift ~seed ~grid ~tick (versions : versions) : versions =
  let copy = Array.copy versions in
  let cells = grid * grid in
  for j = 0 to Int.max 1 (cells / 60) - 1 do
    let i = draw seed [ tick; j; 9 ] cells in
    let c = cell ~col:(i / grid) ~row:(i mod grid) in
    copy.(c) <- copy.(c) + 1
  done;
  copy

(* An alpha of 0 to 999 thousandths, as "0.042". *)
let opacity alpha =
  let digits = Int.to_string (clamp (0, 999) alpha) in
  "0." ^ String.make (3 - String.length digits) '0' ^ digits
