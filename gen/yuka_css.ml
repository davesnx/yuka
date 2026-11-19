let fail = Cli.fail
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
  let n = String.length text in
  let key = "[%yuka.css" in
  let rec go i acc =
    match Source_text.find_from ~sub:key code i with
    | None -> List.rev acc
    | Some p ->
        let j = ref (p + String.length key) in
        if !j >= n || not (Source_text.is_ident_char text.[!j] || text.[!j] = '.') then begin
          while !j < n && (text.[!j] = ' ' || text.[!j] = '\n' || text.[!j] = '\t' || text.[!j] = '\r') do incr j done;
          if !j < n && text.[!j] = '"' then
            match String.index_from_opt text (!j + 1) '"' with
            | Some e -> go (e + 1) (String.sub text (!j + 1) (e - !j - 1) :: acc)
            | None -> List.rev acc
          else go (p + 2) acc
        end
        else go (p + 2) acc
  in
  go 0 []

let sheet src file =
  let path = Filename.concat (Filename.dirname src) file in
  match read path with
  | text -> (
      match Css_scan.sheet ~path:file text with Ok sheet -> sheet | Error m -> fail "%s: %s" src m)
  | exception Sys_error _ -> fail "%s: [%%yuka.css %S]: cannot read %s" src file path

let command =
  let dirs = ref [] in
  ( { Cli.name = "css";
      usage =
        "usage: yuka css --dir DIR [--dir DIR]...\n\
         Print the OCaml module with the sheets of every [%yuka.css \"file.css\"] in the sources under each DIR.";
      specs = [ ("--dir", Arg.String (fun d -> dirs := !dirs @ [ d ]), "DIR A source directory of a library that uses [%yuka.css]") ] },
    dirs )

let main argv =
  let c, dirs = command in
  Cli.parse c argv;
  if !dirs = [] then Cli.usage_error c "give at least one --dir";
  Cli.run c (fun () ->
      let sheets =
        List.concat_map sources !dirs
        |> List.concat_map (fun src -> List.map (sheet src) (declared src))
        |> List.fold_left
             (fun acc (s : Css_scan.sheet) ->
               if List.exists (fun (t : Css_scan.sheet) -> t.file = s.file) acc then acc else acc @ [ s ])
             []
      in
      print_string "let sheets = [\n";
      List.iter (fun (s : Css_scan.sheet) -> Printf.printf "  (%S, %S);\n" s.file s.text) sheets;
      print_string "]\n")
