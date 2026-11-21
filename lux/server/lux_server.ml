let read_file path = In_channel.with_open_bin path In_channel.input_all

let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

let () =
  let here = Filename.dirname Sys.executable_name in
  let port = ref 8080 in
  let js_dir = ref (Filename.concat here "../client/out") in
  let static_dir = ref (Filename.concat here "../static") in
  let manifest = ref (Filename.concat here "../client/yuka_islands.json") in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default 8080)");
      ("--js-dir", Arg.Set_string js_dir, "Melange output directory");
      ("--static-dir", Arg.Set_string static_dir, "Directory of style.css");
      ("--manifest", Arg.Set_string manifest, "Island manifest (yuka_islands.json)");
    ]
    (fun _ -> ())
    "lux_server [--port N]";
  match
    Yuka.Server.modules ~dir:!js_dir ~entry:"lux/client/main.js" ~manifest:(read_file !manifest)
      ~packages:(packages !js_dir) ~digest:(Yuka.Server.tree_digest !js_dir)
  with
  | Error message ->
      prerr_endline ("lux_server: " ^ message);
      exit 1
  | Ok assets ->
      let config =
        Yuka.Server.config ~assets
          ~public:[ ("/static", !static_dir) ]
          ~head:{|<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" href="data:,">|}
          ~styles:[ "/static/style.css" ] ()
      in
      Dream.run ~port:!port @@ Dream.logger @@ Yuka_dream.handler config Yuka_routes.app
