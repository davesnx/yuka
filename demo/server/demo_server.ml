open Demo_shared

let styles = [ "/static/style.css" ]

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
      ( Some (Yuka.Server.import_map ~url:"/static/js" (packages !js_dir)),
        [ "/static/js/demo/client/main.js" ] )
  in
  let respond ?status ~request ~title view =
    Demo_app.Yuka_dream.respond ?status ?import_map ~styles ~scripts ~request ~title view
  in
  let pages =
    [
      Yuka.Router.case (Routes.index ()) (fun request ->
          respond ~request ~title:"Issues" Demo_app.Pages.index);
      Yuka.Router.case (Routes.my ()) (fun request ->
          respond ~request ~title:"My issues" Demo_app.Pages.my_issues);
      Yuka.Router.case (Routes.issue ()) (fun id request ->
          match Demo_app.Store.find id with
          | Some i -> respond ~request ~title:id (fun () -> Demo_app.Pages.issue i)
          | None ->
              respond ~status:`Not_Found ~request ~title:"Not found" (fun () ->
                  Demo_app.Pages.not_found id));
    ]
  in
  Demo_app.Handlers.register ();
  Dream.run ~port:!port
  @@ Dream.logger
  @@ Dream.router
       [
         Demo_app.Yuka_dream.action_route;
         Dream.get "/static/style.css" (fun req ->
             Dream.from_filesystem !static_dir "style.css" req);
         Dream.get "/static/bundle/**" (Dream.static !bundle_dir);
         Dream.get "/static/js/**" (Dream.static !js_dir);
         Dream.get "/**" (fun request ->
             match Yuka.Router.dispatch pages (Dream.target request) with
             | Some handler -> handler request
             | None ->
                 respond ~status:`Not_Found ~request ~title:"Not found" (fun () ->
                     Demo_app.Pages.not_found (Dream.target request)));
       ]
