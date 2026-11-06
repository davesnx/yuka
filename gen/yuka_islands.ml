type island = { name : string; path : string; lazy_ : bool }

exception Fail of string

let fail fmt = Printf.ksprintf (fun s -> raise (Fail s)) fmt

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let squeeze s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      if not (c = ' ' || c = '\t' || c = '\n' || c = '\r') then
        Buffer.add_char b c)
    s;
  Buffer.contents b

let normalise s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let last () = if Buffer.length b = 0 then ' ' else Buffer.nth b (Buffer.length b - 1) in
  let i = ref 0 in
  while !i < n do
    if is_space s.[!i] then begin
      while !i < n && is_space s.[!i] do incr i done;
      if last () <> '(' && last () <> ' ' && !i < n && s.[!i] <> ')' then
        Buffer.add_char b ' '
    end
    else begin
      Buffer.add_char b s.[!i];
      incr i
    end
  done;
  Buffer.contents b

let find_from ~sub s start =
  let n = String.length sub and m = String.length s in
  let rec go i =
    if i + n > m then None
    else if String.sub s i n = sub then Some i
    else go (i + 1)
  in
  go start

let is_ident_char c =
  (c >= 'a' && c <= 'z')
  || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '_' || c = '\''

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

let island_kind src =
  let code = code_only src in
  let keyword = "let%client" in
  let k = String.length keyword in
  let n = String.length code in
  let rec has_island i =
    match find_from ~sub:keyword code i with
    | None -> false
    | Some p ->
        let at_line_start = p = 0 || code.[p - 1] = '\n' in
        let whole = p + k >= n || not (is_ident_char code.[p + k]) in
        (at_line_start && whole) || has_island (p + k)
  in
  if not (has_island 0) then None
  else
    let squeezed = squeeze code in
    let mem sub = find_from ~sub squeezed 0 <> None in
    Some (mem "[@yuka.lazy]" || mem "[@@yuka.lazy]")

let has_extension path =
  Filename.check_suffix path ".ml" || Filename.check_suffix path ".mlx"

let strip_dune_comments text =
  String.split_on_char '\n' text
  |> List.map (fun line ->
         match String.index_opt line ';' with
         | Some i -> String.sub line 0 i
         | None -> line)
  |> String.concat "\n"

let has_field ~field text =
  let sub = "(" ^ field in
  let n = String.length sub in
  let rec go i =
    match find_from ~sub text i with
    | None -> false
    | Some p ->
        p + n >= String.length text
        || (not (is_ident_char text.[p + n]))
        || go (p + n)
  in
  go 0

type dune_info = { unqualified : bool }

let read_dune dir =
  let path = Filename.concat dir "dune" in
  if not (Sys.file_exists path) then { unqualified = false }
  else
    let text = normalise (strip_dune_comments (read_file path)) in
    if has_field ~field:"include_subdirs qualified" text then
      fail
        "%s: include_subdirs qualified is not supported; use include_subdirs \
         unqualified"
        path;
    if has_field ~field:"modules" text then
      fail "%s: (modules ...) is not supported" path;
    { unqualified = has_field ~field:"include_subdirs unqualified" text }

let rec walk ~recursive dir =
  let entries = Sys.readdir dir in
  Array.sort compare entries;
  Array.to_list entries
  |> List.concat_map (fun name ->
         let path = Filename.concat dir name in
         if Sys.is_directory path then
           if recursive && name.[0] <> '.' && name <> "_build" then (
             ignore (read_dune path);
             walk ~recursive path)
           else []
         else [ path ])

let strip_trailing_slash dir =
  let n = String.length dir in
  if n > 1 && dir.[n - 1] = '/' then String.sub dir 0 (n - 1) else dir

let scan ~library dir =
  let dir = strip_trailing_slash dir in
  if not (Sys.file_exists dir && Sys.is_directory dir) then
    fail "%s: no such directory" dir;
  let { unqualified } = read_dune dir in
  List.filter_map
    (fun f ->
      if not (has_extension f) then None
      else
        match island_kind (read_file f) with
        | None -> None
        | Some lazy_ ->
            let stem = Filename.remove_extension (Filename.basename f) in
            let name =
              String.capitalize_ascii library ^ "." ^ String.capitalize_ascii stem
            in
            let path = Filename.concat (Filename.dirname f) stem ^ ".js" in
            let path = if path.[0] = '.' then path else "./" ^ path in
            Some { name; path; lazy_ })
    (walk ~recursive:unqualified dir)

let parse_args args =
  let rec go acc = function
    | [] -> List.rev acc
    | "--library" :: lib :: dir :: rest -> go ((lib, dir) :: acc) rest
    | arg :: _ -> fail "unexpected argument %S; expected --library NAME DIR" arg
  in
  match go [] args with
  | [] -> fail "usage: yuka-islands --library NAME DIR [--library NAME DIR ...]"
  | pairs -> pairs

let render islands =
  let islands = List.sort (fun a b -> compare a.name b.name) islands in
  let eager = List.filter (fun i -> not i.lazy_) islands in
  let lazies = List.filter (fun i -> i.lazy_) islands in
  let list_of ~indent items =
    match items with
    | [] -> "[]"
    | first :: rest ->
        let sep = "\n" ^ String.make indent ' ' ^ "; " in
        "[ " ^ first ^ String.concat "" (List.map (fun s -> sep ^ s) rest) ^ " ]"
  in
  let b = Buffer.create 512 in
  Buffer.add_string b
    "type m\n\
     type entry = Yuka.Client.entry\n\
     external import : string -> m Yuka.Client.promise = \"import\"\n\
     external register : m -> entry = \"register\" [@@mel.get]\n\n\
     let registry =\n\
    \  Yuka.Client.registry\n";
  if lazies <> [] then begin
    let items =
      List.map
        (fun i ->
          Printf.sprintf
            "Yuka.Client.lazy_entry ~name:%S (fun () ->\n\
            \              Yuka.Client.promise_map register (import %S))"
            i.name i.path)
        lazies
    in
    Buffer.add_string b "    ~lazy_entries:\n      ";
    Buffer.add_string b (list_of ~indent:6 items);
    Buffer.add_char b '\n'
  end;
  Buffer.add_string b "    ";
  Buffer.add_string b (list_of ~indent:4 (List.map (fun i -> i.name ^ ".register") eager));
  Buffer.add_char b '\n';
  Buffer.contents b

let () =
  match
    let pairs = parse_args (List.tl (Array.to_list Sys.argv)) in
    List.concat_map (fun (library, dir) -> scan ~library dir) pairs
  with
  | islands -> print_string (render islands)
  | exception Fail msg ->
      prerr_endline ("yuka-islands: " ^ msg);
      exit 1
  | exception Sys_error msg ->
      prerr_endline ("yuka-islands: " ^ msg);
      exit 1
