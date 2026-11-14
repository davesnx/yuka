let time _request = Tapak.json (Printf.sprintf {|{"from":"tapak router","time":%.0f}|} (Unix.gettimeofday ()))

let () =
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some Logs.Info);
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let port =
    match Sys.getenv_opt "PORT" with
    | None -> 8080
    | Some p -> (
        match int_of_string_opt p with
        | Some port -> port
        | None ->
            prerr_endline ("PORT is not a number: " ^ p);
            exit 1)
  in
  let socket =
    Eio.Net.listen ~reuse_addr:true ~backlog:128 ~sw (Eio.Stdenv.net env) (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  let yuka = Yuka_tapak.handler ~sw ~fs:(Eio.Stdenv.fs env) (Yuka.Server.config ()) Yuka_routes.app in
  let app =
    Tapak.Router.(of_list ~not_found:yuka [ get (s "api" / s "time") |> handle_request time ])
    |> Tapak.pipe ~through:[ Yuka_tapak.sessions ]
  in
  Tapak.run ~on_error:(fun e -> Logs.err (fun m -> m "%s" (Printexc.to_string e))) socket app
