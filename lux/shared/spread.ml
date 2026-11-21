type t = {
  size : int;
  rng : Random.State.t;
  cells : Bytes.t;
  mutable level : int;
  mutable front : int array;
  mutable front_len : int;
  mutable next : int array;
  mutable lit : int;
  mutable min_x : int;
  mutable min_y : int;
  mutable max_x : int;
  mutable max_y : int;
}

let styles = 5
let margin = 3
let probability level = if level <= 2 then 3. /. 5. else 5. /. 6.
let size t = t.size
let level t = t.level
let fresh_count t = t.front_len
let fresh t i = t.front.(i)
let lit_count t = t.lit
let finished t = t.front_len = 0
let bounds t = (t.min_x, t.min_y, t.max_x, t.max_y)

let style t cell =
  if cell < 0 || cell >= t.size * t.size then None
  else match Bytes.get_uint8 t.cells cell with 0 -> None | code -> Some (code - 1)

let light t ~x ~y ~style ~len =
  let cell = (y * t.size) + x in
  Bytes.set_uint8 t.cells cell (style + 1);
  if len = Array.length t.next then begin
    let grown = Array.make (2 * len) 0 in
    Array.blit t.next 0 grown 0 len;
    t.next <- grown
  end;
  t.next.(len) <- cell;
  t.lit <- t.lit + 1;
  t.min_x <- min t.min_x x;
  t.min_y <- min t.min_y y;
  t.max_x <- max t.max_x x;
  t.max_y <- max t.max_y y

let swap t len =
  let front = t.front in
  t.front <- t.next;
  t.front_len <- len;
  t.next <- front

let step t =
  let p = probability t.level in
  let len = ref 0 in
  for i = t.front_len - 1 downto 1 do
    let j = Random.State.int t.rng (i + 1) in
    let cell = t.front.(i) in
    t.front.(i) <- t.front.(j);
    t.front.(j) <- cell
  done;
  for i = 0 to t.front_len - 1 do
    let cell = t.front.(i) in
    let x = cell mod t.size and y = cell / t.size in
    let style = Bytes.get_uint8 t.cells cell - 1 in
    for dy = -1 to 1 do
      for dx = -1 to 1 do
        let nx = x + dx and ny = y + dy in
        if
          (dx <> 0 || dy <> 0)
          && nx >= 0 && ny >= 0 && nx < t.size && ny < t.size
          && Bytes.get_uint8 t.cells ((ny * t.size) + nx) = 0
          && Random.State.float t.rng 1. < p
        then begin
          light t ~x:nx ~y:ny ~style ~len:!len;
          incr len
        end
      done
    done
  done;
  swap t !len;
  if !len > 0 then t.level <- t.level + 1;
  !len > 0

let of_seeds ?(size = 1024) ?(level = 1) ~seed cards =
  let valid (x, y, style) = x >= 0 && y >= 0 && x < size && y < size && style >= 0 && style < styles in
  let cells = List.map (fun (x, y, _) -> (y * size) + x) cards in
  if cards = [] then Error "no seed"
  else if level < 1 then Error "the level is less than 1"
  else
    match List.find_opt (fun card -> not (valid card)) cards with
    | Some (x, y, style) -> Error (Printf.sprintf "seed (%d, %d) of style %d is outside the grid or the styles" x y style)
    | None when List.length (List.sort_uniq compare cells) <> List.length cells -> Error "two seeds on one cell"
    | None ->
        let t =
          {
            size;
            rng = Random.State.make [| seed |];
            cells = Bytes.make (size * size) '\000';
            level;
            front = Array.make 64 0;
            front_len = 0;
            next = Array.make 64 0;
            lit = 0;
            min_x = size;
            min_y = size;
            max_x = -1;
            max_y = -1;
          }
        in
        let len = List.fold_left (fun len (x, y, style) -> light t ~x ~y ~style ~len; len + 1) 0 cards in
        swap t len;
        Ok t

let create ?(size = 1024) ~seed ~cols ~rows () =
  if size < 3 then invalid_arg "Spread.create: size is less than 3";
  let rng = Random.State.make [| seed; 1 |] in
  let span view =
    let view = max 3 (min size view) in
    let inner = if view - (2 * margin) >= 3 then view - (2 * margin) else view in
    let start = (size - view) / 2 + ((view - inner) / 2) in
    (start, inner)
  in
  let x0, w = span cols and y0, h = span rows in
  let rec pick taken style =
    if style = styles then List.rev taken
    else
      let x = x0 + Random.State.int rng w and y = y0 + Random.State.int rng h in
      if List.exists (fun (tx, ty, _) -> tx = x && ty = y) taken then pick taken style
      else pick ((x, y, style) :: taken) (style + 1)
  in
  match of_seeds ~size ~seed (pick [] 0) with Ok t -> t | Error message -> invalid_arg ("Spread.create: " ^ message)
