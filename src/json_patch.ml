let splice items index change =
  let rec go before index rest =
    if index = 0 then Option.map (List.rev_append before) (change rest)
    else match rest with x :: rest -> go (x :: before) (index - 1) rest | [] -> None
  in
  if index < 0 then None else go [] index items

let rec edit name path value (j : Json.t) : Json.t option =
  match (path, j) with
  | [], _ -> if name = "r" then value else None
  | `Int index :: rest, `List items ->
      Option.map
        (fun l -> `List l)
        (splice items index (fun tail ->
             match (rest, name, value, tail) with
             | [], "a", Some v, _ -> Some (v :: tail)
             | [], "x", None, _ :: tail -> Some tail
             | _, _, _, x :: tail -> Option.map (fun y -> y :: tail) (edit name rest value x)
             | _ -> None))
  | `String key :: rest, `Assoc fields -> (
      let has = List.exists (fun (k, _) -> k = key) fields in
      match (rest, name, value) with
      | [], "a", Some v -> if has then None else Some (`Assoc (fields @ [ (key, v) ]))
      | [], "x", None -> if has then Some (`Assoc (List.filter (fun (k, _) -> k <> key) fields)) else None
      | _ -> (
          match List.find_opt (fun (k, _) -> k = key) fields with
          | None -> None
          | Some (_, x) ->
              Option.map
                (fun y -> `Assoc (List.map (fun (k, v) -> if k = key then (k, y) else (k, v)) fields))
                (edit name rest value x)))
  | _ -> None

let apply (j : Json.t) (ops : Json.t) =
  match ops with
  | `List ops ->
      List.fold_left
        (fun acc (o : Json.t) ->
          Option.bind acc (fun j ->
              match o with
              | `List [ `String name; `List path ] -> edit name path None j
              | `List [ `String name; `List path; v ] -> edit name path (Some v) j
              | _ -> None))
        (Some j) ops
  | _ -> None
