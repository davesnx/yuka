let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

let late_script inner req =
  match Dream.header req "referer" with
  | Some referer
    when String.ends_with ~suffix:"/before-hydration" referer
         && String.ends_with ~suffix:"/main.js" (Dream.target req) ->
      Lwt.bind (Lwt_unix.sleep 3.) (fun () -> inner req)
  | _ -> inner req

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
  let second = ref 0 in
  let bus = ref "memory" in
  let secret =
    ref (Option.value (Sys.getenv_opt "YUKA_DEMO_SECRET") ~default:"yuka-demo-secret-for-development-only")
  in
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
      ("--secret", Arg.Set_string secret, "Secret of the session cookies (default: $YUKA_DEMO_SECRET)");
      ( "--second-node",
        Arg.Set_int second,
        "Also serve a second live node on this port, joined to the first by a bus (same store)" );
      ("--bus", Arg.Set_string bus, "With --second-node: memory (default) or pg:CONNINFO (yuka-live-pg)");
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
      ~styles:[ "/static/style.css" ] ~css:Demo_app.Yuka_css.sheets
      ~dev:(!prerender = "" && Sys.getenv_opt "YUKA_DEV" = Some "1")
      ()
  in
  Demo_app.Handlers.register ();
  let app = Demo_app.Routes_server.app in
  if !prerender <> "" then Lwt_main.run (Yuka_dream.prerender ~out:!prerender config app)
  else if !second = 0 then
    Dream.run ~port:!port @@ Dream.logger @@ late_script @@ Dream.set_secret !secret @@ Dream.cookie_sessions
    @@ Yuka_dream.handler config app
  else begin
    let make_bus =
      match String.index_opt !bus ':' with
      | Some colon when String.sub !bus 0 colon = "pg" ->
          let conninfo = String.sub !bus (colon + 1) (String.length !bus - colon - 1) in
          fun () -> Yuka_live_pg.bus ~conninfo ~channel:"yuka_demo" ()
      | _ when !bus = "memory" ->
          let memory = Yuka.Server.Live.memory () in
          fun () -> Yuka.Server.Live.memory_bus memory
      | _ -> failwith ("demo_server: unknown --bus " ^ !bus)
    in
    let other = Yuka.Server.Live.node () in
    let serve ?node port =
      Dream.serve ~port @@ Dream.logger @@ late_script @@ Dream.set_secret !secret @@ Dream.cookie_sessions
      @@ Yuka_dream.handler ?node config app
    in
    Lwt_main.run
      (let open Lwt.Syntax in
       let* () = Yuka_dream.to_lwt (Yuka.Server.Live.use_bus ~name:"first" (make_bus ())) in
       let* () = Yuka_dream.to_lwt (Yuka.Server.Live.use_bus ~node:other ~name:"second" (make_bus ())) in
       Lwt.join [ serve !port; serve ~node:other !second ])
  end
