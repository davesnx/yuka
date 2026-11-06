open Demo_shared

let styles = [ "/static/style.css" ]


let () =
  let here = Filename.dirname Sys.executable_name in
  let port = ref 8080 in
  let js_dir = ref (Filename.concat here "../client/out") in
  let static_dir = ref (Filename.concat here "../static") in
  let bundle = ref false in
  let bundle_dir = ref (Filename.concat here "../client/bundle") in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default 8080)");
      ("--js-dir", Arg.Set_string js_dir, "Melange output directory");
      ("--bundle", Arg.Set bundle, "Serve the esbuild bundle instead of the module tree");
      ("--bundle-dir", Arg.Set_string bundle_dir, "Directory of the bundle (see demo/bundle.sh)");
      ("--static-dir", Arg.Set_string static_dir, "Directory of style.css");
    ]
    (fun _ -> ())
    "demo_server [--port N] [--js-dir DIR] [--static-dir DIR]";
  let import_map, scripts =
    if !bundle then (None, [ "/static/bundle/main.js" ])
    else
      ( Some (Yuka_server.import_map ~url:"/static/js" ~dir:!js_dir),
        [ "/static/js/demo/client/main.js" ] )
  in
  let respond ?status ~request ~title view =
    Yuka_server.respond ?status ~request ~early:true ?import_map ~title ~styles ~scripts view
  in
  Demo_app.Handlers.register ();
  Dream.run ~port:!port
  @@ Dream.logger
  @@ Dream.router
       [
         Yuka_server.route;
         Dream.get "/static/style.css" (fun req ->
             Dream.from_filesystem !static_dir "style.css" req);
         Dream.get "/static/bundle/**" (Dream.static !bundle_dir);
         Dream.get "/static/js/**" (Dream.static !js_dir);
         Dream.get "/**"
           (Yuka_router_server.handler
              ~not_found:(fun request ->
                respond ~status:`Not_Found ~request ~title:"Not found" (fun () ->
                    Demo_app.Pages.not_found (Dream.target request)))
              [
                Yuka_router.case (Routes.index ()) (fun request ->
                    respond ~request ~title:"Issues" Demo_app.Pages.index);
                Yuka_router.case (Routes.my ()) (fun request ->
                    respond ~request ~title:"My issues" Demo_app.Pages.my_issues);
                Yuka_router.case (Routes.issue ()) (fun id request ->
                    match Demo_app.Store.find id with
                    | Some i -> respond ~request ~title:id (fun () -> Demo_app.Pages.issue i)
                    | None ->
                        respond ~status:`Not_Found ~request ~title:"Not found" (fun () ->
                            Demo_app.Pages.not_found id));
              ]);
       ]
