type island = { name : string; path : string }

exception Fail of string

let fail fmt = Printf.ksprintf (fun s -> raise (Fail s)) fmt
let find_from = Source_text.find_from
let code_only = Source_text.code_only

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

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

let is_ident_char c =
  (c >= 'a' && c <= 'z')
  || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '_' || c = '\''

let has_island src =
  let code = code_only src in
  let keyword = "let%client" in
  let k = String.length keyword in
  let n = String.length code in
  let rec go i =
    match find_from ~sub:keyword code i with
    | None -> false
    | Some p ->
        let at_line_start = p = 0 || code.[p - 1] = '\n' in
        let whole = p + k >= n || not (is_ident_char code.[p + k]) in
        (at_line_start && whole) || go (p + k)
  in
  go 0


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
      if not (Filename.check_suffix f ".mlx") then None
      else
        if not (has_island (read_file f)) then None
        else
            let stem = Filename.remove_extension (Filename.basename f) in
            let name =
              String.capitalize_ascii library ^ "." ^ String.capitalize_ascii stem
            in
            let path = Filename.concat (Filename.dirname f) stem ^ ".js" in
            let path = if path.[0] = '.' then path else "./" ^ path in
            Some { name; path })
    (walk ~recursive:unqualified dir)

let parse_args args =
  let rec go manifest acc = function
    | [] -> (manifest, List.rev acc)
    | "--manifest" :: rest -> go true acc rest
    | "--library" :: lib :: dir :: rest -> go manifest ((lib, dir) :: acc) rest
    | arg :: _ ->
        fail "unexpected argument %S; expected [--manifest] --library NAME DIR"
          arg
  in
  match go false [] args with
  | _, [] ->
      fail
        "usage: yuka-islands [--manifest] --library NAME DIR [--library NAME \
         DIR ...]"
  | result -> result

let sorted islands = List.sort (fun a b -> compare a.name b.name) islands

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

let render_manifest islands =
  match sorted islands with
  | [] -> "{}\n"
  | islands ->
      let lines =
        List.map (fun i -> Printf.sprintf "  %s: %s" (json_string i.name) (json_string i.path)) islands
      in
      "{\n" ^ String.concat ",\n" lines ^ "\n}\n"

let render islands =
  let lazies = sorted islands in
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
    Buffer.add_string b "    ~lazy_entries:\n      [ ";
    Buffer.add_string b (String.concat "\n      ; " items);
    Buffer.add_string b " ]\n"
  end;
  Buffer.add_string b "    []\n";
  Buffer.contents b

let () =
  match
    let manifest, pairs = parse_args (List.tl (Array.to_list Sys.argv)) in
    ( manifest,
      List.concat_map (fun (library, dir) -> scan ~library dir) pairs )
  with
  | manifest, islands ->
      print_string
        (if manifest then render_manifest islands else render islands)
  | exception Fail msg ->
      prerr_endline ("yuka-islands: " ^ msg);
      exit 1
  | exception Sys_error msg ->
      prerr_endline ("yuka-islands: " ^ msg);
      exit 1
