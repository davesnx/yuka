(* Serves the infinite scroll example: make infinite-scroll-serve, then
   http://localhost:8080. *)

let read path = In_channel.with_open_bin path In_channel.input_all

let () =
  let here = Filename.dirname Sys.executable_name in
  let port = ref (match Option.bind (Sys.getenv_opt "PORT") int_of_string_opt with Some port -> port | None -> 8080) in
  Arg.parse [ ("--port", Arg.Set_int port, "Port to listen on (default: $PORT, or 8080)") ] (fun _ -> ()) "main [--port N]";
  let dir = Filename.concat here "../client/out" in
  let assets =
    match
      Yuka.Server.modules ~dir ~entry:"examples/infinite-scroll/client/main.js"
        ~manifest:(read (Filename.concat here "../client/yuka_islands.json"))
        ~packages:(List.sort compare (Array.to_list (Sys.readdir (Filename.concat dir "node_modules"))))
        ~digest:(Yuka.Server.tree_digest dir)
    with
    | Ok assets -> assets
    | Error message ->
        prerr_endline message;
        exit 1
  in
  let config =
    Yuka.Server.config ~assets
      ~public:[ ("/static", Filename.concat here "../static") ]
      ~styles:[ "/static/style.css" ]
      ~head:{|<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" type="image/svg+xml" href="/static/favicon.svg">|}
      ~dev:(Sys.getenv_opt "YUKA_DEV" = Some "1")
      ()
  in
  Dream.run ~port:!port @@ Dream.logger @@ Dream.set_secret "infinite-scroll-example" @@ Dream.cookie_sessions
  @@ Yuka_dream.handler config Yuka_routes.app
