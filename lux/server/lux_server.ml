let read_file path = In_channel.with_open_bin path In_channel.input_all

let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

let stop message =
  prerr_endline ("lux_server: " ^ message);
  exit 1

let () =
  let here = Filename.dirname Sys.executable_name in
  let port = ref 8080 in
  let interface = ref "localhost" in
  let js_dir = ref (Filename.concat here "../client/out") in
  let static_dir = ref (Filename.concat here "../static") in
  let manifest = ref (Filename.concat here "../client/yuka_islands.json") in
  let metafile = ref (Filename.concat here "../client/meta.json") in
  let bundle = ref false in
  let base = ref "" in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default 8080)");
      ("--interface", Arg.Set_string interface, "Network interface to listen on (default localhost)");
      ("--js-dir", Arg.Set_string js_dir, "Melange output directory");
      ("--bundle", Arg.Set bundle, "Serve the esbuild bundle instead of the module tree");
      ("--static-dir", Arg.Set_string static_dir, "Directory of style.css");
      ("--manifest", Arg.Set_string manifest, "Island manifest (yuka_islands.json)");
      ("--metafile", Arg.Set_string metafile, "esbuild metafile, with --bundle");
      ("--base", Arg.Set_string base, "Serve the app under this path prefix, as /demo/lux (default: none)");
    ]
    (fun _ -> ())
    "lux_server [--port N] [--interface ADDRESS] [--bundle] [--base PREFIX]";
  let manifest = read_file !manifest in
  let assets =
    match
      if !bundle then
        Yuka.Server.bundle ~dir:(Filename.concat !js_dir "lux/client") ~entry:"bundle/main.js" ~manifest
          ~metafile:(read_file !metafile)
      else
        Yuka.Server.modules ~dir:!js_dir ~entry:"lux/client/main.js" ~manifest ~packages:(packages !js_dir)
          ~digest:(Yuka.Server.tree_digest !js_dir)
    with
    | Ok assets -> assets
    | Error message -> stop message
  in
  let base = !base in
  let config =
    match
      Yuka.Server.config ~base ~assets
        ~public:[ ("/static", !static_dir) ]
        ~head:{|<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" href="data:,">|}
        ~styles:[ base ^ "/static/style.css" ] ()
    with
    | config -> config
    | exception Invalid_argument message -> stop message
  in
  Dream.run ~interface:!interface ~port:!port @@ Dream.logger @@ Yuka_dream.handler config Yuka_routes.app
