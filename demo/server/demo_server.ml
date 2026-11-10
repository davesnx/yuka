let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

let read_file path = In_channel.with_open_bin path In_channel.input_all

let () =
  let here = Filename.dirname Sys.executable_name in
  let port = ref 8080 in
  let js_dir = ref (Filename.concat here "../client/out") in
  let static_dir = ref (Filename.concat here "../static") in
  let manifest = ref (Filename.concat here "../client/yuka_islands.json") in
  let metafile = ref (Filename.concat here "../client/meta.json") in
  let bundle = ref false in
  let prerender = ref "" in
  let prerendered = ref "" in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default 8080)");
      ("--js-dir", Arg.Set_string js_dir, "Melange output directory");
      ("--bundle", Arg.Set bundle, "Serve the esbuild bundle instead of the module tree");
      ("--manifest", Arg.Set_string manifest, "Island manifest (yuka_islands.json)");
      ("--metafile", Arg.Set_string metafile, "esbuild metafile, with --bundle");
      ("--static-dir", Arg.Set_string static_dir, "Directory of style.css");
      ("--prerender", Arg.Set_string prerender, "Write the prerendered pages to DIR and exit");
      ("--prerendered", Arg.Set_string prerendered, "Serve the prerendered pages of DIR");
    ]
    (fun _ -> ())
    "demo_server [--port N] [--bundle] [--prerender DIR] [--prerendered DIR]";
  let manifest = read_file !manifest in
  let client = Filename.concat !js_dir "demo/client" in
  let assets =
    if !bundle then
      Yuka.Server.bundle ~dir:client ~entry:"bundle/main.js" ~manifest
        ~metafile:(read_file !metafile)
    else
      Yuka.Server.modules ~dir:!js_dir ~entry:"demo/client/main.js" ~manifest
        ~packages:(packages !js_dir) ~digest:(Yuka_dream.tree_digest !js_dir)
  in
  let config =
    Yuka.Server.config ~assets
      ~public:[ ("/static", !static_dir) ]
      ?prerendered:(if !prerendered = "" then None else Some !prerendered)
      ~styles:[ "/static/style.css" ] ~css:Demo_app.Yuka_css.sheets ()
  in
  Demo_app.Handlers.register ();
  let app = Demo_app.Routes_server.app in
  if !prerender <> "" then Lwt_main.run (Yuka_dream.prerender ~out:!prerender config app)
  else Dream.run ~port:!port @@ Dream.logger @@ Yuka_dream.handler config app
