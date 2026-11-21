type t = { shapes : Shape.t array; next_id : int }

let empty = { shapes = [||]; next_id = 1 }
let shapes t = t.shapes
let length t = Array.length t.shapes
let find t id = Array.find_opt (fun (s : Shape.t) -> s.id = id) t.shapes
let mem t id = Array.exists (fun (s : Shape.t) -> s.id = id) t.shapes
let fresh_id t = (t.next_id, { t with next_id = t.next_id + 1 })
let member ids (s : Shape.t) = List.exists (fun id -> id = s.id) ids

let add t (shape : Shape.t) =
  let others = if mem t shape.id then Array.of_list (List.filter (fun (s : Shape.t) -> s.id <> shape.id) (Array.to_list t.shapes)) else t.shapes in
  { shapes = Array.append others [| shape |]; next_id = max t.next_id (shape.id + 1) }

let replace t changed =
  match changed with
  | [] -> t
  | _ ->
      let table = Hashtbl.create (List.length changed) in
      List.iter (fun (s : Shape.t) -> Hashtbl.replace table s.id s) changed;
      {
        t with
        shapes = Array.map (fun (s : Shape.t) -> match Hashtbl.find_opt table s.id with Some n -> n | None -> s) t.shapes;
      }

let filter f t = Array.of_list (List.filter f (Array.to_list t.shapes))

let remove t ids =
  match ids with [] -> t | _ -> { t with shapes = filter (fun s -> not (member ids s)) t }

let to_front t ids =
  { t with shapes = Array.append (filter (fun s -> not (member ids s)) t) (filter (member ids) t) }

let to_back t ids =
  { t with shapes = Array.append (filter (member ids) t) (filter (fun s -> not (member ids s)) t) }

let insert_copies t shapes ~offset =
  List.fold_left
    (fun (board, ids) shape ->
      let id, board = fresh_id board in
      (add board (Shape.translate (Shape.with_id shape id) offset), ids @ [ id ]))
    (t, []) shapes

let top_hit t ~tolerance p =
  let n = Array.length t.shapes in
  let rec go i hollow =
    if i < 0 then hollow
    else
      let s = t.shapes.(i) in
      match Shape.hit s ~tolerance p with
      | Shape.Edge -> Some s
      | Inside -> (
          match hollow with
          | Some (h : Shape.t) when h.w *. h.h <= s.w *. s.h -> go (i - 1) hollow
          | _ -> go (i - 1) (Some s))
      | Miss -> go (i - 1) hollow
  in
  go (n - 1) None

let in_box t box =
  Array.fold_right
    (fun (s : Shape.t) acc -> if Geom.Box.intersects (Shape.bounds s) box && Shape.touches_box s box then s.id :: acc else acc)
    t.shapes []

let union_of shapes =
  List.fold_left
    (fun acc s ->
      let b = Shape.visual_bounds s in
      match acc with None -> Some b | Some a -> Some (Geom.Box.union a b))
    None shapes

let bounds t ids = union_of (List.filter (member ids) (Array.to_list t.shapes))
let all_bounds t = union_of (Array.to_list t.shapes)
let to_json_text t =
  let b = Buffer.create (256 * (Array.length t.shapes + 1)) in
  Buffer.add_string b "{\"next\":";
  Buffer.add_string b (Int.to_string t.next_id);
  Buffer.add_string b ",\"shapes\":[";
  Array.iteri
    (fun i s ->
      if i > 0 then Buffer.add_char b ',';
      Shape.write_json b s)
    t.shapes;
  Buffer.add_string b "]}";
  Buffer.contents b

let of_json metrics = function
  | `Assoc fields -> (
      match List.assoc_opt "shapes" fields with
      | Some (`List items) ->
          let rec go acc = function
            | [] -> Ok (List.rev acc)
            | item :: rest -> ( match Shape.of_json metrics item with Ok s -> go (s :: acc) rest | Error e -> Error e)
          in
          Result.bind (go [] items) (fun shapes ->
              let seen = Hashtbl.create 64 in
              let unique =
                List.filter
                  (fun (s : Shape.t) ->
                    if Hashtbl.mem seen s.id then false
                    else (
                      Hashtbl.replace seen s.id ();
                      true))
                  shapes
              in
              let top = List.fold_left (fun acc (s : Shape.t) -> max acc s.id) 0 unique in
              let next = match List.assoc_opt "next" fields with Some (`Int n) -> max n (top + 1) | _ -> top + 1 in
              Ok { shapes = Array.of_list unique; next_id = next })
      | _ -> Error "board: no shapes list")
  | _ -> Error "board: not an object"
