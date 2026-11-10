let read path = In_channel.with_open_bin path In_channel.input_all

let files arg =
  if Sys.is_directory arg then
    Sys.readdir arg |> Array.to_list |> List.sort compare
    |> List.filter (fun f -> Filename.check_suffix f ".css")
    |> List.map (Filename.concat arg)
  else [ arg ]

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  if args = [] then begin
    prerr_endline "usage: yuka-css FILE.css|DIR ...";
    exit 2
  end;
  match
    List.concat_map files args
    |> List.map (fun path -> Css_scan.sheet ~path (read path))
  with
  | sheets ->
      print_string "let sheets = [\n";
      List.iter (fun (s : Css_scan.sheet) -> Printf.printf "  (%S, %S);\n" s.file s.text) sheets;
      print_string "]\n"
  | exception Css_scan.Error m ->
      prerr_endline ("yuka-css: " ^ m);
      exit 1
  | exception Sys_error m ->
      prerr_endline ("yuka-css: " ^ m);
      exit 1
