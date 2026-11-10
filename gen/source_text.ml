let find_from ~sub s start =
  let n = String.length sub and m = String.length s in
  let rec go i =
    if i + n > m then None
    else if String.sub s i n = sub then Some i
    else go (i + 1)
  in
  go start

let code_only src =
  let n = String.length src in
  let out = Bytes.of_string src in
  let blank i = if Bytes.get out i <> '\n' then Bytes.set out i ' ' in
  let at i = if i < n then src.[i] else '\000' in
  let rec string_end i =
    if i >= n then n
    else if src.[i] = '\\' then string_end (i + 2)
    else if src.[i] = '"' then i + 1
    else string_end (i + 1)
  in
  let quoted_id i =
    let j = ref (i + 1) in
    while !j < n && (at !j = '_' || (at !j >= 'a' && at !j <= 'z')) do
      incr j
    done;
    if at !j = '|' then Some (String.sub src (i + 1) (!j - i - 1), !j + 1)
    else None
  in
  let quoted_end id start =
    match find_from ~sub:("|" ^ id ^ "}") src start with
    | Some k -> k + String.length id + 2
    | None -> n
  in
  let char_end i =
    if at (i + 1) = '\\' then
      match String.index_from_opt src (i + 2) '\'' with
      | Some k -> Some (k + 1)
      | None -> None
    else if at (i + 2) = '\'' && at (i + 1) <> '\000' then Some (i + 3)
    else None
  in
  let erase a b =
    for k = a to min b n - 1 do
      blank k
    done
  in
  let rec comment i depth =
    if i >= n then n
    else if at i = '(' && at (i + 1) = '*' then comment (i + 2) (depth + 1)
    else if at i = '*' && at (i + 1) = ')' then
      if depth = 1 then i + 2 else comment (i + 2) (depth - 1)
    else if at i = '"' then comment (string_end (i + 1)) depth
    else if at i = '{' then
      match quoted_id i with
      | Some (id, start) -> comment (quoted_end id start) depth
      | None -> comment (i + 1) depth
    else if at i = '\'' then
      match char_end i with
      | Some e -> comment e depth
      | None -> comment (i + 1) depth
    else comment (i + 1) depth
  in
  let rec code i =
    if i < n then
      if at i = '(' && at (i + 1) = '*' then (
        let e = comment (i + 2) 1 in
        erase i e;
        code e)
      else if at i = '"' then (
        let e = string_end (i + 1) in
        erase i e;
        code e)
      else if at i = '{' then
        match quoted_id i with
        | Some (id, start) ->
            let e = quoted_end id start in
            erase i e;
            code e
        | None -> code (i + 1)
      else if at i = '\'' then
        match char_end i with
        | Some e ->
            erase i e;
            code e
        | None -> code (i + 1)
      else code (i + 1)
  in
  code 0;
  Bytes.to_string out

let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c < 0x20 ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b
