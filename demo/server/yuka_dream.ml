let to_async p =
  let async, resolve, fail = Yuka.Async.make () in
  Lwt.on_any p resolve (fun e -> fail (Printexc.to_string e));
  async

let to_lwt async =
  let p, w = Lwt.wait () in
  Yuka.Async.on_result async (function
    | Ok v -> Lwt.wakeup w v
    | Error m -> Lwt.wakeup_exn w (Failure m));
  p

let sleep d = to_async (Lwt_unix.sleep d)

let () =
  Yuka.Server.log_error := fun message -> Dream.error (fun log -> log "%s" message)

let respond ?status ?import_map ?scripts ?styles ~request ~title view =
  let navigating = Dream.header request "Yuka-Navigate" = Some "1" in
  Dream.stream ?status
    ~headers:[ ("Content-Type", "text/html; charset=utf-8"); ("Vary", "Yuka-Navigate") ]
    (fun stream ->
      let write s =
        to_async (Lwt.bind (Dream.write stream s) (fun () -> Dream.flush stream))
      in
      to_lwt
        (Yuka.Server.respond ~navigating ~early:true ?import_map ~title ?styles ?scripts
           ~sleep ~write view))

let action_route =
  Dream.post "/_yuka/action/:name" (fun request ->
      Lwt.bind (Dream.body request) (fun body ->
          let answer =
            Yuka.Server.handle_action ~name:(Dream.param request "name")
              ~content_type:(Dream.header request "Content-Type")
              ~origin:(Dream.header request "Origin")
              ~host:(Dream.header request "Host") ~body
          in
          Lwt.bind (to_lwt answer) (fun (status, json) ->
              Dream.respond ~status:(Dream.int_to_status status)
                ~headers:[ ("Content-Type", "application/json") ]
                json)))
