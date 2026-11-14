let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

let check_true msg b = Alcotest.(check bool) msg true b

let call ?(meth = `GET) ?(headers = []) ?(body = "") handler target =
  let request =
    Tapak.Request.make ~meth ~headers:(Http.Header.of_list headers) ~body:(Bytesrw.Bytes.Reader.of_string body) target
  in
  let response = handler request in
  (response, Tapak.Body.to_string (Tapak.Response.body response))

let status response = Http.Status.to_int (Tapak.Response.status response)
let header name response = Tapak.Response.header name response
let same_origin = [ ("Origin", "http://app.test"); ("Host", "app.test") ]

let static =
  let dir = Filename.temp_dir "yuka_static" "" in
  Out_channel.with_open_bin (Filename.concat dir "s.css") (fun oc -> output_string oc "body{}");
  dir

let config = Yuka.Server.config ~public:[ ("/static", static) ] ()

let serve make () =
  let out = Filename.temp_dir "yuka_out" "" in
  Sys.mkdir (Filename.concat out "docs") 0o755;
  Out_channel.with_open_bin (Filename.concat out "docs/index.html") (fun oc -> output_string oc "from disk");
  let handler = make (Yuka.Server.config ~prerendered:out ()) in
  let response, body = call handler "/docs" in
  Alcotest.(check string) "file" "from disk" body;
  Alcotest.(check (option string)) "rule header" (Some "test") (header "x-site" response);
  Alcotest.(check (list string))
    "a repeated rule header, both values" [ "a"; "b" ]
    (Http.Header.get_multi (Tapak.Response.headers response) "x-twice");
  Alcotest.(check (option string)) "type" (Some "text/html; charset=utf-8") (header "content-type" response);
  let _, body = call handler "/docs?x=1" in
  check_true "a query renders" (contains body "<p>docs</p>");
  let _, body = call handler "/secret" in
  check_true "not prerendered" (contains body "secret");
  let response, body = call handler "/post/nope" in
  Alcotest.(check int) "missing file renders" 404 (status response);
  check_true "not found" (contains body "missing /post/nope")

let public_file make () =
  let handler = make config in
  let response, body = call handler "/static/s.css" in
  Alcotest.(check (pair int string)) "the file" (200, "body{}") (status response, body);
  let response, _ = call handler "/static/none.css" in
  Alcotest.(check (pair int (option string))) "a missing file" (404, Some "no-store")
    (status response, header "cache-control" response)

let dev_env_ignored make () =
  Unix.putenv "YUKA_DEV" "1";
  let config = Fun.protect ~finally:(fun () -> Unix.putenv "YUKA_DEV" "") (fun () -> Yuka.Server.config ()) in
  let handler = make config in
  let _, index = call handler "/" in
  check_true "a page" (contains index "<title>Home</title>");
  check_true "no dev script" (not (contains index "EventSource"));
  let dev, _ = call handler "/_yuka/dev" in
  Alcotest.(check int) "no dev events" 404 (status dev)

let tapak_log make () =
  let got = ref [] in
  let report src level ~over k msgf =
    msgf (fun ?header:_ ?tags:_ fmt ->
        Format.kasprintf
          (fun m ->
            got := (Logs.Src.name src, level, m) :: !got;
            over ();
            k ())
          fmt)
  in
  let saved = Logs.reporter () in
  Logs.set_reporter { Logs.report };
  Fun.protect
    ~finally:(fun () -> Logs.set_reporter saved)
    (fun () ->
      ignore (call (make (Yuka.Server.config ())) "/warned");
      check_true "a warning on the yuka source"
        (List.mem ("yuka", Logs.Warning, "warned page") !got);
      got := [];
      let kept = ref [] in
      ignore (call (make (Yuka.Server.config ~log:(fun _ m -> kept := m :: !kept) ())) "/warned");
      Alcotest.(check (list string)) "a config log is kept" [ "warned page" ] !kept;
      check_true "not in Logs" (not (List.exists (fun (_, _, m) -> m = "warned page") !got)))

let echo = Yuka.Action.mutation ~name:"echo" ~input:Yuka.Codec.string ~output:Yuka.Codec.int
let () = Yuka.Server.Action.make echo (fun _ s -> Yuka.Async.return (String.length s))

let body_limit make () =
  let handler = make config in
  let post ?length body =
    let headers =
      (("Content-Type", "application/json") :: same_origin)
      @ match length with Some n -> [ ("Content-Length", string_of_int n) ] | None -> []
    in
    let response, body = call ~meth:`POST ~headers ~body handler "/_yuka/action/echo" in
    (status response, body)
  in
  let quoted size = "\"" ^ String.make (size - 2) 'x' ^ "\"" in
  Alcotest.(check int) "at the limit" 200 (fst (post (quoted 1_048_576)));
  Alcotest.(check (pair int string)) "over the limit"
    (413, {|{"error":"request too large"}|})
    (post (quoted 1_048_577));
  Alcotest.(check int) "a declared length over the limit is refused before reading" 413
    (fst (post ~length:2_000_000 (quoted 4)));
  Alcotest.(check (pair int string)) "a small declared length" (200, {|{"ok":2}|}) (post ~length:4 (quoted 4))

let streamed make () =
  let response, body = call (make config) "/slow" in
  Alcotest.(check int) "status" 200 (status response);
  check_true "a stream body" (match Tapak.Response.body response with `Stream _ -> true | _ -> false);
  check_true "the shell" (contains body "before");
  check_true "the loading state first" (contains body "loading");
  check_true "the fill" (contains body "<p>slow data</p>");
  check_true "the end" (contains body "</body></html>")

let timeout make () =
  let start = Unix.gettimeofday () in
  let response, body = call (make (Yuka.Server.config ~timeout:0.05 ())) "/stuck" in
  check_true "ends with the timeout" (Unix.gettimeofday () -. start < 1.);
  Alcotest.(check int) "status" 200 (status response);
  check_true "the failed fill after the timeout" (contains body "failed");
  check_true "the end" (contains body "</body></html>")

let csrf_cookies make () =
  let response, body = call ~headers:same_origin (make config) "/_yuka/csrf" in
  Alcotest.(check int) "status" 200 (status response);
  check_true "a token" (contains body {|{"csrf":"|});
  let cookies = Http.Header.get_multi (Tapak.Response.headers response) "set-cookie" in
  check_true "a session cookie" (List.exists (fun c -> String.starts_with ~prefix:"yuka-session=" c) cookies);
  check_true "a csrf cookie" (List.exists (fun c -> String.starts_with ~prefix:"yuka-csrf=" c) cookies);
  let response, _ =
    call
      ~headers:(("Cookie", "yuka-session=" ^ String.make 32 's' ^ "; yuka-csrf=" ^ String.make 32 'c') :: same_origin)
      (make config) "/_yuka/csrf"
  in
  Alcotest.(check (list string)) "no new cookie" []
    (Http.Header.get_multi (Tapak.Response.headers response) "set-cookie")

let set_cookie name response =
  List.find_map
    (fun c ->
      match String.split_on_char ';' c with
      | pair :: _ when String.starts_with ~prefix:(name ^ "=") pair ->
          Some (String.sub pair (String.length name + 1) (String.length pair - String.length name - 1))
      | _ -> None)
    (Http.Header.get_multi (Tapak.Response.headers response) "set-cookie")

let bad_cookies make () =
  List.iter
    (fun (label, cookies) ->
      let response, body = call ~headers:(("Cookie", cookies) :: same_origin) (make config) "/_yuka/csrf" in
      Alcotest.(check int) (label ^ ": status") 200 (status response);
      match set_cookie "yuka-csrf" response with
      | None -> Alcotest.failf "%s: no new yuka-csrf cookie" label
      | Some secret ->
          let token = String.sub body 9 (String.length body - 11) in
          let request =
            Tapak.Request.make ~headers:(Http.Header.of_list [ ("cookie", "yuka-csrf=" ^ secret) ]) "/"
          in
          check_true (label ^ ": the token verifies") (Tapak.Csrf.verify_token ~cookie_name:"yuka-csrf" ~token request))
    [
      ("a character outside letters and digits", "yuka-session=" ^ String.make 32 's' ^ "; yuka-csrf=" ^ String.make 31 'c' ^ "-");
      ("a wrong length", "yuka-session=" ^ String.make 32 's' ^ "; yuka-csrf=abc");
    ];
  List.iter
    (fun (label, value) ->
      let response, _ =
        call
          ~headers:(("Cookie", "yuka-session=" ^ value ^ "; yuka-csrf=" ^ String.make 32 'c') :: same_origin)
          (make config) "/_yuka/csrf"
      in
      check_true (label ^ ": a new session") (set_cookie "yuka-session" response <> None))
    [ ("an empty session", ""); ("a malformed session", "a b;c") ]

let request_switch_ends ~fs () =
  let start = Unix.gettimeofday () in
  Eio.Switch.run (fun sw ->
      let response, body = call (Yuka_tapak.sessions (Yuka_tapak.handler ~sw ~fs config Yuka_routes.app)) "/lingering" in
      Alcotest.(check int) "status" 200 (status response);
      check_true "answered" (contains body "answered"));
  check_true "the fiber on the request switch ends with the response" (Unix.gettimeofday () -. start < 1.)

let no_sessions ~sw ~fs () =
  let logged = ref [] in
  let config = Yuka.Server.config ~log:(fun _ m -> logged := m :: !logged) () in
  let handler = Yuka_tapak.handler ~sw ~fs config Yuka_routes.app in
  let response, _ = call ~headers:same_origin handler "/_yuka/csrf" in
  Alcotest.(check int) "csrf without the middleware" 500 (status response);
  check_true "the csrf log names the path and the middleware"
    (match !logged with [ m ] -> contains m "/_yuka/csrf" && contains m "session middleware" | _ -> false);
  logged := [];
  let response, _ =
    call ~headers:(("Upgrade", "websocket") :: same_origin) handler "/_yuka/live"
  in
  Alcotest.(check int) "live without the middleware" 500 (status response);
  check_true "the live log names the middleware"
    (match !logged with [ m ] -> contains m "the live socket needs session middleware" | _ -> false)

let csrf_secret = String.make 32 'k'

let token () =
  let request =
    Tapak.Request.make ~headers:(Http.Header.of_list [ ("cookie", "yuka-csrf=" ^ csrf_secret) ]) "/"
  in
  fst (Tapak.Csrf.input ~cookie_name:"yuka-csrf" request)

let with_server ~net handler f =
  Eio.Switch.run @@ fun sw ->
  let socket = Eio.Net.listen ~sw ~backlog:16 ~reuse_addr:true net (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0)) in
  let port = match Eio.Net.listening_addr socket with `Tcp (_, p) -> p | `Unix _ -> Alcotest.fail "unix" in
  let stop, set_stop = Eio.Promise.create () in
  Eio.Fiber.fork ~sw (fun () -> Tapak.run ~stop ~on_error:raise socket handler);
  Fun.protect ~finally:(fun () -> Eio.Promise.resolve set_stop ()) (fun () -> f port)

let exchange ~sw ~net port text =
  let flow = Eio.Net.connect ~sw net (`Tcp (Eio.Net.Ipaddr.V4.loopback, port)) in
  Eio.Flow.copy_string text flow;
  Eio.Flow.shutdown flow `Send;
  Eio.Fiber.first
    (fun () -> Eio.Buf_read.(parse_exn take_all) ~max_size:10_000_000 flow)
    (fun () ->
      Eio_unix.sleep 5.;
      Alcotest.fail "the server did not close the connection")

let responses text =
  let rec count i n =
    if i + 9 > String.length text then n
    else count (i + 1) (if String.sub text i 9 = "HTTP/1.1 " then n + 1 else n)
  in
  count 0 0

let unread_body ~net make () =
  with_server ~net (make config) (fun port ->
      Eio.Switch.run @@ fun sw ->
      let host = "127.0.0.1:" ^ string_of_int port in
      let output =
        exchange ~sw ~net port
          (String.concat "\r\n"
             [
               "POST /_yuka/action/echo HTTP/1.1";
               "Host: " ^ host;
               "Origin: http://" ^ host;
               "Content-Type: application/json";
               "Content-Length: 2000000";
               "";
               "GET /docs HTTP/1.1";
               "Host: " ^ host;
               "";
               "";
             ])
      in
      Alcotest.(check int) ("one response in " ^ output) 1 (responses output);
      check_true "413" (String.starts_with ~prefix:"HTTP/1.1 413" output);
      check_true "connection: close" (contains (String.lowercase_ascii output) "connection: close"))

let head_then_get ~net make () =
  with_server ~net (make config) (fun port ->
      Eio.Switch.run @@ fun sw ->
      let output =
        exchange ~sw ~net port
          "HEAD /slow HTTP/1.1\r\nHost: x\r\n\r\nGET /docs HTTP/1.1\r\nHost: x\r\n\r\n"
      in
      let first_end =
        let rec find i = if String.sub output i 4 = "\r\n\r\n" then i + 4 else find (i + 1) in
        find 0
      in
      check_true "the HEAD response is 200" (String.starts_with ~prefix:"HTTP/1.1 200" output);
      Alcotest.(check string)
        "the GET response starts right after the HEAD headers" "HTTP/1.1 200"
        (String.sub output first_end 12);
      check_true "the GET body" (contains output "<p>docs</p>"))

let websocket ~sw ~net port f =
  let flow = Eio.Net.connect ~sw net (`Tcp (Eio.Net.Ipaddr.V4.loopback, port)) in
  let host = "127.0.0.1:" ^ string_of_int port in
  Eio.Flow.copy_string
    (String.concat "\r\n"
       [
         "GET /_yuka/live HTTP/1.1";
         "Host: " ^ host;
         "Origin: http://" ^ host;
         "Upgrade: websocket";
         "Connection: Upgrade";
         "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==";
         "Sec-WebSocket-Version: 13";
         "Cookie: yuka-session=one; yuka-csrf=" ^ csrf_secret;
         "";
         "";
       ])
    flow;
  let input = Eio.Buf_read.of_flow ~max_size:1_000_000 flow in
  let status = Eio.Buf_read.line input in
  let rec skip () = if Eio.Buf_read.line input <> "" then skip () in
  skip ();
  Eio.Buf_write.with_flow flow (fun output ->
      f status (Cows.make ~role:Client input output));
  Eio.Flow.close flow

let live ~sw ~net make () =
  with_server ~net (make config) (fun port ->
      websocket ~sw ~net port (fun status conn ->
          Alcotest.(check string) "101" "HTTP/1.1 101 Switching Protocols" status;
          Cows.send conn (`Text (Printf.sprintf {|{"t":"hello","v":1,"csrf":"%s"}|} (token ())));
          (match Cows.recv conn with
          | `Text text -> check_true "hello back" (contains text {|"t":"hello"|})
          | _ -> Alcotest.fail "not a text");
          for _ = 1 to 3 do
            Cows.send conn (`Text {|{"t":"ping"}|});
            match Cows.recv conn with
            | `Text text -> check_true "pong" (contains text {|"t":"pong"|})
            | _ -> Alcotest.fail "not a text"
          done;
          Cows.close conn;
          match Cows.recv conn with
          | `Close (code, _) -> Alcotest.(check int) "the close echo" 1000 code
          | _ -> Alcotest.fail "not a close");
      websocket ~sw ~net port (fun _ conn ->
          Cows.send conn (`Text {|{"t":"hello","v":1,"csrf":"bad"}|});
          match Cows.recv conn with
          | `Close (code, _) -> Alcotest.(check int) "a bad token" 4403 code
          | _ -> Alcotest.fail "not a close"))

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let fs = Eio.Stdenv.fs env and net = Eio.Stdenv.net env in
  let make config = Yuka_tapak.sessions (Yuka_tapak.handler ~sw ~fs config Yuka_routes.app) in
  Alcotest.run ~and_exit:false "yuka-tapak"
    [
      ( "cycle",
        [
          Alcotest.test_case "the handler serves prerendered files" `Quick (serve make);
          Alcotest.test_case "a public file" `Quick (public_file make);
          Alcotest.test_case "YUKA_DEV=1 does not turn on dev mode" `Quick (dev_env_ignored make);
          Alcotest.test_case "a streamed await" `Quick (streamed make);
          Alcotest.test_case "the timeout fills a stuck await" `Quick (timeout make);
        ] );
      ( "body",
        [
          Alcotest.test_case "the body limit" `Quick (body_limit make);
          Alcotest.test_case "an unread body is not a next request" `Quick (unread_body ~net make);
          Alcotest.test_case "HEAD then GET on one connection" `Quick (head_then_get ~net make);
        ] );
      ("log", [ Alcotest.test_case "Console reaches Logs" `Quick (tapak_log make) ]);
      ( "session",
        [
          Alcotest.test_case "sessions gives the cookies" `Quick (csrf_cookies make);
          Alcotest.test_case "no sessions middleware" `Quick (no_sessions ~sw ~fs);
          Alcotest.test_case "malformed cookies are replaced" `Quick (bad_cookies make);
          Alcotest.test_case "the request switch ends with the response" `Quick (request_switch_ends ~fs);
        ] );
      ("live", [ Alcotest.test_case "hello, ping and close over a socket" `Quick (live ~sw ~net make) ]);
    ]
