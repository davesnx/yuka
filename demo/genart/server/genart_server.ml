let stop message =
  prerr_endline ("genart_server: " ^ message);
  exit 1

let () =
  let port =
    ref
      (match Sys.getenv_opt "PORT" with
      | None -> 8080
      | Some value -> ( match int_of_string_opt value with Some port -> port | None -> stop ("PORT is not a number: " ^ value)))
  in
  let interface = ref "localhost" in
  let dir = ref (Filename.concat (Filename.dirname Sys.executable_name) "..") in
  let bundle = ref false in
  let base = ref "" in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default: $PORT, or 8080)");
      ("--interface", Arg.Set_string interface, "Network interface to listen on (default localhost)");
      ("--dir", Arg.Set_string dir, "Directory of client/ and static/ (default: the parent of the executable directory)");
      ("--bundle", Arg.Set bundle, "Serve the esbuild bundle instead of the module tree");
      ("--base", Arg.Set_string base, "Serve the app under this path prefix, as /genart (default: none)");
    ]
    (fun _ -> ())
    "genart_server [--port N] [--interface ADDRESS] [--dir DIR] [--bundle] [--base PREFIX]";
  match
    Genart_app.Serve.make ~base:!base ~bundle:!bundle ~dev:(Sys.getenv_opt "YUKA_DEV" = Some "1") ~dir:!dir ()
  with
  | Error message -> stop message
  | Ok app -> Dream.run ~interface:!interface ~port:!port @@ Dream.logger @@ app.handler
