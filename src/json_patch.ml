let splice items index change =
  let rec go before index rest =
    if index = 0 then match change rest with Some after -> Some (List.rev_append before after) | None -> None
    else match rest with x :: rest -> go (x :: before) (index - 1) rest | [] -> None
  in
  if index < 0 then None else go [] index items

let rec edit name path value (j : Json.t) : Json.t option =
  match (path, j) with
  | [], _ -> if name = "r" then value else None
  | `Int index :: rest, `List items ->
      let spliced =
        splice items index (fun tail ->
            match (rest, name, value, tail) with
            | [], "a", Some v, _ -> Some (v :: tail)
            | [], "x", None, _ :: tail -> Some tail
            | _, _, _, x :: tail -> ( match edit name rest value x with Some y -> Some (y :: tail) | None -> None)
            | _ -> None)
      in
      (match spliced with Some l -> Some (`List l) | None -> None)
  | `String key :: rest, `Assoc fields -> (
      let has = List.exists (fun (k, _) -> k = key) fields in
      match (rest, name, value) with
      | [], "a", Some v -> if has then None else Some (`Assoc (fields @ [ (key, v) ]))
      | [], "x", None -> if has then Some (`Assoc (List.filter (fun (k, _) -> k <> key) fields)) else None
      | _ -> (
          match List.find_opt (fun (k, _) -> k = key) fields with
          | None -> None
          | Some (_, x) ->
              match edit name rest value x with
              | Some y -> Some (`Assoc (List.map (fun (k, v) -> if k = key then (k, y) else (k, v)) fields))
              | None -> None))
  | _ -> None

let apply (j : Json.t) (ops : Json.t) =
  match ops with
  | `List ops ->
      List.fold_left
        (fun acc (o : Json.t) ->
          match (acc, o) with
          | Some j, `List [ `String name; `List path ] -> edit name path None j
          | Some j, `List [ `String name; `List path; v ] -> edit name path (Some v) j
          | _ -> None)
        (Some j) ops
  | _ -> None
