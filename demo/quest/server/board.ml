(* Noughts and crosses. The cells are numbered 0 to 8, by rows. *)

type mark = X | O
type t = mark option array

let empty : t = Array.make 9 None
let free (board : t) cell = board.(cell) = None

let play (board : t) cell mark : t =
  let next = Array.copy board in
  next.(cell) <- Some mark;
  next

let full (board : t) = Array.for_all Option.is_some board
let lines = [ (0, 1, 2); (3, 4, 5); (6, 7, 8); (0, 3, 6); (1, 4, 7); (2, 5, 8); (0, 4, 8); (2, 4, 6) ]
(* The cells of a full line, if there is one. *)
let line (board : t) =
  match List.find_opt (fun (a, b, c) -> board.(a) <> None && board.(a) = board.(b) && board.(b) = board.(c)) lines with
  | Some (a, b, c) -> [ a; b; c ]
  | None -> []

let wins (board : t) mark = List.exists (fun (a, b, c) -> List.for_all (fun cell -> board.(cell) = Some mark) [ a; b; c ]) lines

(* The cell that would complete a line of [mark]. *)
let completes (board : t) mark =
  List.find_map
    (fun (a, b, c) ->
      match List.filter (free board) [ a; b; c ] with
      | [ cell ] when List.length (List.filter (fun cell -> board.(cell) = Some mark) [ a; b; c ]) = 2 -> Some cell
      | _ -> None)
    lines

(* The Ash King wins when he can, blocks when he must, and else takes the centre, then
   a corner, then a side. He never sees a fork coming, so he can be beaten. *)
let reply (board : t) =
  match completes board O with
  | Some cell -> cell
  | None -> (
      match completes board X with
      | Some cell -> cell
      | None -> List.find (free board) [ 4; 0; 2; 6; 8; 1; 3; 5; 7 ])
