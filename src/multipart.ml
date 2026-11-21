let find text part from =
  let n = String.length part and m = String.length text in
  let rec matches i j = j = n || (Char.equal text.[i + j] part.[j] && matches i (j + 1)) in
  let rec at i = if i + n > m then None else if matches i 0 then Some i else at (i + 1) in
  at from

let at text i part =
  let n = String.length part in
  i + n <= String.length text && String.equal (String.sub text i n) part

let unquote v =
  let n = String.length v in
  if n >= 2 && v.[0] = '"' && v.[n - 1] = '"' then String.sub v 1 (n - 2) else v

let lower s = String.lowercase_ascii (String.trim s)

let boundary content_type =
  match String.split_on_char ';' content_type with
  | media :: params when lower media = "multipart/form-data" ->
      List.find_map
        (fun p ->
          match Router.cut p '=' with
          | k, Some v when lower k = "boundary" ->
              let b = unquote (String.trim v) in
              if b = "" || String.length b > 70 then None else Some b
          | _ -> None)
        params
  | _ -> None

let params s =
  let n = String.length s in
  let rec skip i = if i < n && (s.[i] = ' ' || s.[i] = '\t' || s.[i] = ';') then skip (i + 1) else i in
  let rec until i stop = if i < n && not (String.contains stop s.[i]) then until (i + 1) stop else i in
  let rec go i acc =
    let i = skip i in
    if i >= n then List.rev acc
    else
      let k = until i "=;" in
      let key = lower (String.sub s i (k - i)) in
      if k < n && s.[k] = '=' then
        if k + 1 < n && s.[k + 1] = '"' then
          let e = until (k + 2) "\"" in
          go (e + 1) ((key, String.sub s (k + 2) (e - k - 2)) :: acc)
        else
          let e = until (k + 1) ";" in
          go e ((key, String.trim (String.sub s (k + 1) (e - k - 1))) :: acc)
      else go k ((key, "") :: acc)
  in
  go 0 []

let base name =
  match (String.rindex_opt name '/', String.rindex_opt name '\\') with
  | None, None -> name
  | a, b ->
      let i = max (Option.value a ~default:(-1)) (Option.value b ~default:(-1)) in
      String.sub name (i + 1) (String.length name - i - 1)

let part headers content : ((string * Form_core.input) list, string) result =
  let headers =
    List.filter_map
      (fun line -> match Router.cut line ':' with k, Some v -> Some (lower k, String.trim v) | _, None -> None)
      (String.split_on_char '\n' (String.concat "" (String.split_on_char '\r' headers)))
  in
  match List.assoc_opt "content-disposition" headers with
  | None -> Error "a part has no Content-Disposition"
  | Some d -> (
      let ps = params d in
      match (List.assoc_opt "name" ps, List.assoc_opt "filename" ps) with
      | None, _ -> Error "a part has no name"
      | Some _, Some "" when content = "" -> Ok []
      | Some name, Some filename ->
          let content_type =
            match List.assoc_opt "content-type" headers with Some t when t <> "" -> t | _ -> "application/octet-stream"
          in
          Ok [ (name, Form_core.File { filename = base filename; content_type; size = String.length content; content }) ]
      | Some name, None -> Ok [ (name, Form_core.Text content) ])

let parse ~boundary body =
  let dash = "--" ^ boundary in
  let delimiter = "\r\n" ^ dash in
  let rec parts start acc =
    if at body start "--" then Ok (List.rev acc)
    else if not (at body start "\r\n") then Error "bad multipart delimiter"
    else
      match find body "\r\n\r\n" start with
      | None -> Error "a part has no end of headers"
      | Some h -> (
          let headers = String.sub body (start + 2) (h - start - 2) in
          match find body delimiter (h + 4) with
          | None -> Error "a part has no end"
          | Some e -> (
              match part headers (String.sub body (h + 4) (e - h - 4)) with
              | Error _ as error -> error
              | Ok found -> parts (e + String.length delimiter) (List.rev_append found acc)))
  in
  if at body 0 dash then parts (String.length dash) []
  else match find body delimiter 0 with Some i -> parts (i + String.length delimiter) [] | None -> Error "no multipart boundary"
