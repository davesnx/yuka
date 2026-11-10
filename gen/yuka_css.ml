exception Fail of string

let fail fmt = Printf.ksprintf (fun s -> raise (Fail s)) fmt
let read path = In_channel.with_open_bin path In_channel.input_all

let rec sources dir =
  Sys.readdir dir |> Array.to_list |> List.sort compare
  |> List.concat_map (fun name ->
         let path = Filename.concat dir name in
         if Sys.is_directory path then
           if name = "_build" || name.[0] = '.' then [] else sources path
         else if
           (Filename.check_suffix name ".ml" || Filename.check_suffix name ".mlx")
           && not (Filename.check_suffix name ".pp.ml")
         then [ path ]
         else [])

let declared src =
  match read src with
  | exception Sys_error _ -> []
  | text ->
  let code = Source_text.code_only text in
  let key = "[%yuka.css" in
  let k = String.length key and n = String.length text in
  let rec go i acc =
    match Source_text.find_from ~sub:key code i with
    | None -> List.rev acc
    | Some p ->
        let j = ref (p + k) in
        while !j < n && (text.[!j] = ' ' || text.[!j] = '\n' || text.[!j] = '\t' || text.[!j] = '\r') do incr j done;
        if !j < n && text.[!j] = '"' then
          match String.index_from_opt text (!j + 1) '"' with
          | Some e -> go (e + 1) (String.sub text (!j + 1) (e - !j - 1) :: acc)
          | None -> List.rev acc
        else go (p + k) acc
  in
  go 0 []

let sheet src file =
  let path = Filename.concat (Filename.dirname src) file in
  match read path with
  | text -> (
      try Css_scan.sheet ~path:file text with Css_scan.Error m -> fail "%s: %s" src m)
  | exception Sys_error _ -> fail "%s: [%%yuka.css %S]: cannot read %s" src file path

let () =
  let dirs = List.tl (Array.to_list Sys.argv) in
  if dirs = [] then begin
    prerr_endline "usage: yuka-css DIR ...  (the source directories of the libraries that use [%yuka.css])";
    exit 2
  end;
  match
    List.concat_map sources dirs
    |> List.concat_map (fun src -> List.map (sheet src) (declared src))
    |> List.fold_left
         (fun acc (s : Css_scan.sheet) ->
           if List.exists (fun (t : Css_scan.sheet) -> t.file = s.file) acc then acc else acc @ [ s ])
         []
  with
  | sheets ->
      print_string "let sheets = [\n";
      List.iter (fun (s : Css_scan.sheet) -> Printf.printf "  (%S, %S);\n" s.file s.text) sheets;
      print_string "]\n"
  | exception Fail m ->
      prerr_endline ("yuka-css: " ^ m);
      exit 1
  | exception Sys_error m ->
      prerr_endline ("yuka-css: " ^ m);
      exit 1
