type island = { name : string; path : string }

let fail = Cli.fail
let find_from = Source_text.find_from
let code_only = Source_text.code_only

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let is_ident_char = Source_text.is_ident_char

let has_island src =
  let code = code_only src in
  let n = String.length code in
  let rec go keyword i =
    let k = String.length keyword in
    match find_from ~sub:keyword code i with
    | None -> false
    | Some p ->
        let at_line_start = p = 0 || code.[p - 1] = '\n' in
        let whole = p + k >= n || not (is_ident_char code.[p + k] || code.[p + k] = '.') in
        (at_line_start && whole) || go keyword (p + k)
  in
  go "let%client" 0 || go "let%yuka.client" 0

type sexp = Atom of string | List of sexp list

let sexps path text =
  let n = String.length text in
  let rec skip_blank i = if i < n && String.contains " \t\n\r" text.[i] then skip_blank (i + 1) else i in
  let rec skip i =
    if i >= n then i
    else
      match text.[i] with
      | ' ' | '\t' | '\n' | '\r' -> skip (i + 1)
      | ';' -> ( match String.index_from_opt text i '\n' with Some j -> skip j | None -> n)
      | '#' when i + 1 < n && text.[i + 1] = '|' -> (
          match find_from ~sub:"|#" text (i + 2) with
          | Some j -> skip (j + 2)
          | None -> fail "%s: a #| comment has no end" path)
      | '#' when i + 1 < n && text.[i + 1] = ';' -> skip (snd (one (skip (i + 2))))
      | _ -> i
  and one i =
    if i >= n then fail "%s: unexpected end of file" path
    else
      match text.[i] with
      | '(' ->
          let rec items acc j =
            let j = skip j in
            if j >= n then fail "%s: a ( has no )" path
            else if text.[j] = ')' then (List (List.rev acc), j + 1)
            else
              let x, j = one j in
              items (x :: acc) j
          in
          items [] (i + 1)
      | ')' -> fail "%s: a ) has no (" path
      | '"' when i + 2 < n && text.[i + 1] = '\\' && (text.[i + 2] = '|' || text.[i + 2] = '>') ->
          let b = Buffer.create 16 in
          let rec lines j =
            let e = Option.value (String.index_from_opt text j '\n') ~default:n in
            Buffer.add_string b (String.sub text j (e - j));
            let k = skip_blank e in
            if k + 2 < n && text.[k] = '"' && text.[k + 1] = '\\' && (text.[k + 2] = '|' || text.[k + 2] = '>') then (
              Buffer.add_char b '\n';
              lines (k + 3))
            else (Atom (Buffer.contents b), e)
          in
          lines (i + 3)
      | '"' ->
          let b = Buffer.create 16 in
          let rec str j =
            if j >= n then fail "%s: a string has no end" path
            else if text.[j] = '"' then (Atom (Buffer.contents b), j + 1)
            else if text.[j] = '\\' && j + 1 < n then (
              Buffer.add_char b text.[j + 1];
              str (j + 2))
            else (
              Buffer.add_char b text.[j];
              str (j + 1))
          in
          str (i + 1)
      | _ ->
          let j = ref i in
          while !j < n && not (String.contains " \t\n\r();\"" text.[!j]) do incr j done;
          (Atom (String.sub text i (!j - i)), !j)
  in
  let rec all acc i =
    let i = skip i in
    if i >= n then List.rev acc
    else
      let x, i = one i in
      all (x :: acc) i
  in
  all [] 0

let field name fields = List.find_map (function List (Atom n :: v) when n = name -> Some v | _ -> None) fields

let rec module_set path ~standard items =
  let union =
    List.concat_map (function
      | Atom ":standard" -> standard
      | Atom a when a <> "" && a.[0] = ':' -> fail "%s: %s in (modules ...) is not supported" path a
      | Atom a -> [ String.capitalize_ascii a ]
      | List (Atom ":include" :: _) -> fail "%s: (:include ...) in (modules ...) is not supported; list the modules" path
      | List l -> module_set path ~standard l)
  in
  let rec split acc = function
    | [] -> (List.rev acc, [])
    | Atom "\\" :: rest -> (List.rev acc, List.filter (fun x -> x <> Atom "\\") rest)
    | x :: rest -> split (x :: acc) rest
  in
  let keep, remove = split [] items in
  let remove = union remove in
  List.filter (fun m -> not (List.mem m remove)) (union keep)

type library = { library : string; unqualified : bool; modules : sexp list option }

let check_subdirs path stanzas =
  if List.mem (List [ Atom "include_subdirs"; Atom "qualified" ]) stanzas then
    fail "%s: include_subdirs qualified is not supported; use include_subdirs unqualified" path;
  List.mem (List [ Atom "include_subdirs"; Atom "unqualified" ]) stanzas

let read_dune dir =
  let path = Filename.concat dir "dune" in
  if not (Sys.file_exists path) then fail "%s: no dune file; yuka islands reads the library name from it" path;
  let stanzas = sexps path (read_file path) in
  let unqualified = check_subdirs path stanzas in
  match List.filter_map (function List (Atom "library" :: fields) -> Some fields | _ -> None) stanzas with
  | [ fields ] -> (
      let library =
        match (field "name" fields, field "public_name" fields) with
        | Some [ Atom name ], _ -> name
        | None, Some [ Atom name ] when name <> "" && String.for_all (fun c -> is_ident_char c && c <> '\'') name -> name
        | None, Some [ Atom name ] ->
            fail "%s: the library has no (name ...), and its public_name %s is not a library name" path name
        | _ -> fail "%s: the library has no (name ...)" path
      in
      { library; unqualified; modules = field "modules" fields })
  | libs -> fail "%s: yuka islands needs one library stanza in this file, not %d" path (List.length libs)

let rec walk ~recursive dir =
  let entries = Sys.readdir dir in
  Array.sort compare entries;
  Array.to_list entries
  |> List.concat_map (fun name ->
         let path = Filename.concat dir name in
         if Sys.is_directory path then
           if recursive && name.[0] <> '.' && name <> "_build" then (
             let dune = Filename.concat path "dune" in
             if Sys.file_exists dune then ignore (check_subdirs dune (sexps dune (read_file dune)));
             walk ~recursive path)
           else []
         else [ path ])

let strip_trailing_slash dir =
  let n = String.length dir in
  if n > 1 && dir.[n - 1] = '/' then String.sub dir 0 (n - 1) else dir

let scan dir =
  let dir = strip_trailing_slash dir in
  if not (Sys.file_exists dir && Sys.is_directory dir) then fail "%s: no such directory" dir;
  let { library; unqualified; modules } = read_dune dir in
  let files = List.filter (fun f -> Filename.check_suffix f ".mlx") (walk ~recursive:unqualified dir) in
  let stem f = Filename.remove_extension (Filename.basename f) in
  let files =
    match modules with
    | None -> files
    | Some set ->
        let standard = List.map (fun f -> String.capitalize_ascii (stem f)) files in
        let kept = module_set (Filename.concat dir "dune") ~standard set in
        List.filter (fun f -> List.mem (String.capitalize_ascii (stem f)) kept) files
  in
  List.filter_map
    (fun f ->
      if not (has_island (read_file f)) then None
      else
        let name = String.capitalize_ascii library ^ "." ^ String.capitalize_ascii (stem f) in
        let path = Filename.concat (Filename.dirname f) (stem f) ^ ".js" in
        let path = if path.[0] = '.' then path else "./" ^ path in
        Some { name; path })
    files

let sorted islands = List.sort (fun a b -> compare a.name b.name) islands

let json_string = Source_text.json_string

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

let main argv =
  let manifest = ref false and dirs = ref [] in
  let c =
    { Cli.name = "islands";
      usage =
        "usage: yuka islands [--manifest] --dir DIR [--dir DIR]...\n\
         Print the island registry (or, with --manifest, the JSON manifest) of the libraries in each DIR.\n\
         DIR holds the dune file of one library; its (name ...) gives the island names.";
      specs =
        [ ("--dir", Arg.String (fun d -> dirs := !dirs @ [ d ]), "DIR The directory of a library with islands");
          ("--manifest", Arg.Set manifest, " Print the JSON manifest instead of the OCaml registry") ] }
  in
  Cli.parse c argv;
  if !dirs = [] then Cli.usage_error c "give at least one --dir";
  Cli.run c (fun () ->
      let islands = List.concat_map scan !dirs in
      print_string (if !manifest then render_manifest islands else render islands))
