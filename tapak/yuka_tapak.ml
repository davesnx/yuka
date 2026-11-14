type current = { sw : Eio.Switch.t; mutable read : bool }

let current : current Eio.Fiber.key = Eio.Fiber.create_key ()

exception Request_ended

let switch () =
  match Eio.Fiber.get current with
  | Some c -> c.sw
  | None -> invalid_arg "Yuka_tapak.switch: not inside a request of Yuka_tapak.handler"

let await async =
  match Yuka.Async.status async with
  | Yuka.Async.Done v -> v
  | Yuka.Async.Failed m -> failwith m
  | Yuka.Async.Pending -> (
      let p, r = Eio.Promise.create () in
      Yuka.Async.on_result async (Eio.Promise.resolve r);
      match Eio.Promise.await p with Ok v -> v | Error m -> failwith m)

let async ~sw f =
  let a, ok, fail = Yuka.Async.make () in
  Eio.Fiber.fork ~sw (fun () ->
      match f () with
      | v -> ok v
      | exception (Eio.Cancel.Cancelled _ as e) -> raise e
      | exception e -> fail (Printexc.to_string e));
  a

let guard f =
  match f () with
  | v -> Yuka.Async.return v
  | exception (Eio.Cancel.Cancelled _ as e) -> raise e
  | exception e -> Yuka.Async.failed (Printexc.to_string e)

let session_cookie = "yuka-session"
let csrf_cookie = "yuka-csrf"
let cookie request name = List.assoc_opt name (Tapak.Cookies.Cookie.parse (Tapak.Request.headers request))

let well_formed value =
  String.length value = 32
  && String.for_all (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true | _ -> false) value

let sessions next request =
  let fresh =
    List.filter_map
      (fun name ->
        match cookie request name with
        | Some value when well_formed value -> None
        | _ -> Some (name, Tapak.Csrf.generate_secret ()))
      [ session_cookie; csrf_cookie ]
  in
  let request =
    if fresh = [] then request
    else
      let kept =
        List.filter
          (fun (name, _) -> not (List.mem_assoc name fresh))
          (Tapak.Cookies.Cookie.parse (Tapak.Request.headers request))
      in
      Tapak.Request.remove_header "cookie" request
      |> Tapak.Request.add_header "cookie"
           (String.concat "; " (List.map (fun (name, value) -> name ^ "=" ^ value) (kept @ fresh)))
  in
  List.fold_left
    (fun response pair ->
      let name, value =
        Tapak.Cookies.Set_cookie.(
          serialize (make ~path:"/" ~same_site:`Lax ~secure:false ~http_only:true pair))
      in
      Tapak.Response.add_header name value response)
    (next request) fresh

module Base = struct
  type request = Tapak.Request.t
  type reply = Tapak.Response.t

  let meth request : Yuka.Router.meth =
    match Tapak.Request.meth request with
    | (`GET | `HEAD | `POST | `PUT | `PATCH | `DELETE | `OPTIONS) as m -> m
    | `CONNECT -> `Other "CONNECT"
    | `TRACE -> `Other "TRACE"
    | `Other m -> `Other m

  let target = Tapak.Request.target
  let header request name = Tapak.Request.header name request

  let body request ~limit =
    match Option.bind (header request "content-length") int_of_string_opt with
    | Some n when n > limit -> Yuka.Async.return None
    | _ ->
        guard (fun () ->
            let over = ref false in
            let text =
              Tapak.Request.body request
              |> Bytesrw.Bytes.Reader.limit ~action:(fun _ _ -> over := true) limit
              |> Bytesrw.Bytes.Reader.to_string
            in
            if !over then None
            else begin
              Option.iter (fun c -> c.read <- true) (Eio.Fiber.get current);
              Some text
            end)

  let session request = cookie request session_cookie

  let csrf_token request =
    Option.map (fun _ -> fst (Tapak.Csrf.input ~cookie_name:csrf_cookie request)) (cookie request csrf_cookie)

  let verify_csrf request token =
    Yuka.Async.return (Tapak.Csrf.verify_token ~cookie_name:csrf_cookie ~token request)

  let respond ({ status; headers; body } : Yuka.Server.response) =
    let headers = Http.Header.of_list headers and status = Http.Status.of_int status in
    Yuka.Async.return
      (match body with
      | Yuka.Server.String text -> Tapak.Response.of_string ~headers ~status text
      | Yuka.Server.Stream f ->
          Tapak.Response.stream ~headers ~status (fun write flush ->
              await
                (f (fun text ->
                     guard (fun () ->
                         write text;
                         flush ())))))

  let exists ~root ~path =
    let file = Filename.concat root path in
    Sys.file_exists file && not (Sys.is_directory file)

  let receive conn =
    let rec next () =
      match Cows.recv conn with
      | `Text text | `Binary text -> Some text
      | `Ping data ->
          Cows.send conn (`Pong data);
          next ()
      | `Pong _ -> next ()
      | `Close _ ->
          (try Cows.close conn with Cows.Connection_closed | Eio.Io _ -> ());
          None
      | exception (Cows.Connection_closed | End_of_file | Eio.Io _) -> None
    in
    next ()

  let upgrade request run =
    Yuka.Async.return
      (Tapak.Response.websocket
         (fun conn ->
           let closed, closing = Eio.Promise.create () in
           let connection =
             Yuka.Server.Live.connection
               ~send:(fun text -> guard (fun () -> Cows.send conn (`Text text)))
               ~receive:(fun () -> guard (fun () -> receive conn))
               ~close:(fun code ->
                 guard (fun () ->
                     Fun.protect
                       ~finally:(fun () -> ignore (Eio.Promise.try_resolve closing ()))
                       (fun () -> try Cows.close ~code conn with Cows.Connection_closed -> ())))
           in
           Eio.Fiber.first (fun () -> Eio.Promise.await closed) (fun () -> await (run connection)))
         request)

  let sleep seconds =
    match Eio.Fiber.get current with
    | None -> Yuka.Async.failed "Yuka_tapak: sleep outside a request"
    | Some { sw; _ } ->
        let a, ok, _ = Yuka.Async.make () in
        Eio.Fiber.fork_daemon ~sw (fun () ->
            Eio_unix.sleep seconds;
            ok ();
            `Stop_daemon);
        a
end

let src = Logs.Src.create "yuka"

let log level message =
  match level with
  | `Error -> Logs.err ~src (fun m -> m "%s" message)
  | `Warn -> Logs.warn ~src (fun m -> m "%s" message)
  | `Info -> Logs.info ~src (fun m -> m "%s" message)
  | `Debug -> Logs.debug ~src (fun m -> m "%s" message)

let has_body request =
  Tapak.Request.header "transfer-encoding" request <> None
  || Option.fold ~none:false ~some:(fun n -> n > 0)
       (Option.bind (Tapak.Request.header "content-length" request) int_of_string_opt)

let drain request =
  let reader = Tapak.Request.body request in
  let rec read () = if not (Bytesrw.Bytes.Slice.is_eod (Bytesrw.Bytes.Reader.read reader)) then read () in
  try read () with Eio.Cancel.Cancelled _ as e -> raise e | _ -> ()

let handler ~sw ~fs ?node config app =
  let module Cycle = Yuka.Server.Adapter.Make (struct
    include Base

    let file _ ~root ~path ~headers =
      Yuka.Async.return
        (if exists ~root ~path then
           Tapak.Response.file ~headers:(Http.Header.of_list headers) Eio.Path.(fs / root / path)
         else
           Tapak.Response.of_string ~status:`Not_found
             ~headers:(Http.Header.of_list [ ("cache-control", "no-store") ])
             "Not Found")
  end) in
  let config = Yuka.Server.Adapter.default_log log config in
  fun request ->
    let opened, open_ = Eio.Promise.create () and closed, close = Eio.Promise.create () in
    Eio.Fiber.fork ~sw (fun () ->
        try
          Eio.Switch.run (fun rsw ->
              Eio.Promise.resolve open_ rsw;
              Eio.Promise.await closed;
              raise Request_ended)
        with
        | Request_ended -> ()
        | Eio.Cancel.Cancelled _ as e -> raise e
        | e -> Logs.err ~src (fun m -> m "request switch failed: %s" (Printexc.to_string e)));
    let state = { sw = Eio.Promise.await opened; read = false } in
    let close () = ignore (Eio.Promise.try_resolve close ()) in
    let bound run = Eio.Fiber.with_binding current state run in
    let later run = Fun.protect ~finally:close (fun () -> bound run) in
    match bound (fun () -> await (Cycle.handler ?node config app request)) with
    | exception e ->
        close ();
        raise e
    | response -> (
        let unread = has_body request && not state.read in
        let drain () = if unread then drain request in
        let response =
          if unread then Tapak.Response.add_header_or_replace "connection" "close" response else response
        in
        let body = Tapak.Response.body response in
        match (Tapak.Request.meth request, body) with
        | _, `Raw f -> Tapak.Response.with_ ~body:(`Raw (fun i o -> later (fun () -> f i o))) response
        | `HEAD, (`Stream _ | `String _ | `Empty) when unread || Tapak.Body.length body = None ->
            close ();
            let response =
              if Tapak.Body.length body = None then
                Tapak.Response.add_header_unless_exists "transfer-encoding" "chunked" response
              else response
            in
            Tapak.Response.with_ ~body:(`Raw (fun _ _ -> drain ())) response
        | _, `Stream (length, f) ->
            Tapak.Response.with_
              ~body:(`Stream (length, fun w flush -> later (fun () -> f w flush; drain ())))
              response
        | _, (`String _ | `Empty) when unread ->
            close ();
            let text = Tapak.Body.to_string body in
            Tapak.Response.with_
              ~body:
                (Tapak.Body.stream ~length:(Int64.of_int (String.length text)) (fun write flush ->
                     write text;
                     flush ();
                     drain ()))
              response
        | _ ->
            close ();
            response)
