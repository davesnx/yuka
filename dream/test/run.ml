let static =
  let dir = Filename.temp_dir "yuka_static" "" in
  Out_channel.with_open_bin (Filename.concat dir "s.css") (fun oc -> output_string oc "body{}");
  dir

let config = Yuka.Server.config ~public:[ ("/static", static) ] ~css:[ ("w-0a1b.css", ".w_0a1b{}") ] ()

let rec files dir prefix =
  Sys.readdir dir |> Array.to_list |> List.sort compare
  |> List.concat_map (fun name ->
         let path = Filename.concat dir name and rel = prefix ^ name in
         if Sys.is_directory path then files path (rel ^ "/")
         else [ (rel, In_channel.with_open_bin path In_channel.input_all) ])

let with_stderr f =
  let file = Filename.temp_file "yuka_stderr" "" in
  let saved = Unix.dup Unix.stderr in
  let fd = Unix.openfile file [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  Unix.dup2 fd Unix.stderr;
  Fun.protect
    ~finally:(fun () ->
      Unix.dup2 saved Unix.stderr;
      Unix.close fd)
    f;
  In_channel.with_open_bin file In_channel.input_all

let prerender out =
  match Lwt_main.run (Yuka_dream.prerender ~out config Yuka_routes.app) with
  | Ok () -> ()
  | Error m -> Alcotest.fail m

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

let check_true msg b = Alcotest.(check bool) msg true b

let pages () =
  let out = Filename.temp_dir "yuka_out" "" in
  let warnings = with_stderr (fun () -> prerender out) in
  let written = files out "" in
  Alcotest.(check (list string))
    "files"
    [
      "404.html";
      "_yuka/css/w-0a1b.css";
      "docs/index.html";
      "feed.xml";
      "guide/index.html";
      "index.html";
      "post/hello/index.html";
      "post/world/index.html";
      "static/s.css";
      "whoami.txt";
    ]
    (List.map fst written);
  let file name = List.assoc name written in
  check_true "home" (contains (file "index.html") "<title>Home</title>");
  check_true "crawled from a crawled page" (contains (file "post/world/index.html") "post world");
  check_true "rule header page" (contains (file "post/hello/index.html") "class=\"root\"");
  Alcotest.(check string) "endpoint" "<rss/>" (file "feed.xml");
  Alcotest.(check string) "the Dream request of a prerender" "/whoami.txt -" (file "whoami.txt");
  check_true "404 page" (contains (file "404.html") "missing /404.html");
  Alcotest.(check string) "static copied" "body{}" (file "static/s.css");
  Alcotest.(check string) "css sheet written" ".w_0a1b{}" (file "_yuka/css/w-0a1b.css");
  check_true "warning for the 404 link" (contains warnings "/post/missing answered 404");
  check_true "no warning for links that are not prerendered" (not (contains warnings "/secret"));
  check_true "files are not crawled" (not (contains warnings "/_yuka"));
  check_true "a path that cannot be a file name"
    (contains warnings "yuka-dream prerender: /a%2Fb answered 200 but cannot be a file name, not written");
  List.iter
    (fun (path, expected) ->
      Alcotest.(check bool) path expected (Yuka.Server.Prerender.prerenderable config Yuka_routes.app path))
    [ ("/guide", true); ("/static/s.css", false); ("/_yuka/app/main.js", false); ("/_yuka", false) ]

let based () =
  let out = Filename.temp_dir "yuka_out" "" in
  let config = Yuka.Server.config ~base:"/demo/x" ~public:[ ("/static", static) ] ~css:[ ("w-0a1b.css", ".w_0a1b{}") ] () in
  let warnings =
    with_stderr (fun () ->
        match Lwt_main.run (Yuka_dream.prerender ~out config Yuka_routes.app) with
        | Ok () -> ()
        | Error m -> Alcotest.fail m)
  in
  let written = files out "" in
  Alcotest.(check (list string))
    "files have no base"
    [
      "404.html";
      "_yuka/css/w-0a1b.css";
      "docs/index.html";
      "feed.xml";
      "guide/index.html";
      "index.html";
      "post/hello/index.html";
      "post/world/index.html";
      "static/s.css";
      "whoami.txt";
    ]
    (List.map fst written);
  let file name = List.assoc name written in
  check_true "links have the base" (contains (file "index.html") {|<a href="/demo/x/post/hello">|});
  check_true "crawled from a crawled page" (contains (file "post/world/index.html") "post world");
  Alcotest.(check string) "requested under the base" "/demo/x/whoami.txt -" (file "whoami.txt");
  check_true "404 page" (contains (file "404.html") "missing /404.html");
  check_true "warning names the path of the app" (contains warnings "/post/missing answered 404")

let twice () =
  let out = Filename.temp_dir "yuka_out" "" in
  ignore (with_stderr (fun () -> prerender out));
  let first = files out "" in
  ignore (with_stderr (fun () -> prerender out));
  Alcotest.(check (list (pair string string))) "same files" first (files out "")

let serve () =
  let out = Filename.temp_dir "yuka_out" "" in
  ignore (with_stderr (fun () -> prerender out));
  Out_channel.with_open_bin (Filename.concat out "docs/index.html") (fun oc ->
      output_string oc "from disk");
  let handler = Yuka_dream.handler (Yuka.Server.config ~prerendered:out ()) Yuka_routes.app in
  let call target =
    let response = Dream.test handler (Dream.request ~target "") in
    (response, Lwt_main.run (Dream.body response))
  in
  let response, body = call "/docs" in
  Alcotest.(check string) "file" "from disk" body;
  Alcotest.(check (option string)) "rule header" (Some "test") (Dream.header response "x-site");
  Alcotest.(check (list string)) "a repeated rule header, both values" [ "a"; "b" ] (Dream.headers response "x-twice");
  Alcotest.(check (option string)) "type" (Some "text/html; charset=utf-8")
    (Dream.header response "content-type");
  let _, body = call "/docs?x=1" in
  check_true "a query renders" (contains body "<p>docs</p>");
  let _, body = call "/secret" in
  check_true "not prerendered" (contains body "secret");
  let response, body = call "/post/nope" in
  Alcotest.(check int) "missing file renders" 404 (Dream.status_to_int (Dream.status response));
  check_true "not found" (contains body "missing /post/nope")

let dev_env_ignored () =
  Unix.putenv "YUKA_DEV" "1";
  let config = Fun.protect ~finally:(fun () -> Unix.putenv "YUKA_DEV" "") (fun () -> Yuka.Server.config ()) in
  let handler = Yuka_dream.handler config Yuka_routes.app in
  let response = Dream.test handler (Dream.request ~target:"/" "") in
  let index = Lwt_main.run (Dream.body response) in
  check_true "a page" (contains index "<title>Home</title>");
  check_true "no dev script" (not (contains index "EventSource"));
  let dev = Dream.test handler (Dream.request ~target:"/_yuka/dev" "") in
  Alcotest.(check int) "no dev events" 404 (Dream.status_to_int (Dream.status dev))

let prerender_dev_off () =
  Unix.putenv "YUKA_DEV_FILE" "/nonexistent/yuka-dev";
  let out = Filename.temp_dir "yuka_out" "" in
  ignore
    (with_stderr (fun () ->
         match Lwt_main.run (Yuka_dream.prerender ~out (Yuka.Server.config ~dev:true ()) Yuka_routes.app) with
         | Ok () -> ()
         | Error m -> Alcotest.fail m));
  let read name = In_channel.with_open_bin (Filename.concat out name) In_channel.input_all in
  check_true "a page" (contains (read "index.html") "<title>Home</title>");
  check_true "no dev script in a page" (not (contains (read "index.html") "EventSource"));
  check_true "no dev script in 404.html" (not (contains (read "404.html") "EventSource"))

let out_inside_a_served_dir () =
  let dir = Filename.temp_dir "yuka_static" "" in
  Out_channel.with_open_bin (Filename.concat dir "s.css") (fun oc -> output_string oc "x");
  let config = Yuka.Server.config ~public:[ ("/static", dir) ] () in
  List.iter
    (fun out ->
      match Lwt_main.run (Yuka_dream.prerender ~out config Yuka_routes.app) with
      | Ok () -> Alcotest.failf "%s accepted" out
      | Error m -> check_true "names the directory" (contains m dir))
    [ Filename.concat dir "site"; dir; Filename.concat dir "a/../site" ];
  Alcotest.(check (list string)) "nothing written" [ "s.css" ] (List.map fst (files dir ""))

let dream_log () =
  let get handler = ignore (Lwt_main.run (Dream.body (Dream.test handler (Dream.request ~target:"/warned" "")))) in
  let output = with_stderr (fun () -> get (Dream.logger (Yuka_dream.handler (Yuka.Server.config ()) Yuka_routes.app))) in
  (match List.find_opt (fun l -> contains l "warned page") (String.split_on_char '\n' output) with
  | None -> Alcotest.failf "not in the Dream log: %s" output
  | Some line ->
      check_true "the yuka sub-log" (contains line "yuka");
      check_true "a warning" (contains line "WARN");
      check_true "the request id" (contains line "REQ "));
  let got = ref [] in
  let output =
    with_stderr (fun () -> get (Yuka_dream.handler (Yuka.Server.config ~log:(fun _ m -> got := m :: !got) ()) Yuka_routes.app))
  in
  Alcotest.(check (list string)) "a config log is kept" [ "warned page" ] !got;
  check_true "not in the Dream log" (not (contains output "warned page"))

let echo = Yuka.Action.mutation ~name:"echo" ~input:Yuka.Codec.string ~output:Yuka.Codec.int
let () = Yuka.Server.Action.implement echo (fun _ s -> Yuka.Async.return (String.length s))

let body_limit () =
  let handler = Yuka_dream.handler config Yuka_routes.app in
  let post ?length body =
    let headers =
      [ ("Content-Type", "application/json"); ("Origin", "http://app.test"); ("Host", "app.test") ]
      @ match length with Some n -> [ ("Content-Length", string_of_int n) ] | None -> []
    in
    let response = Dream.test handler (Dream.request ~method_:`POST ~target:"/_yuka/action/echo" ~headers body) in
    (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))
  in
  let quoted size = "\"" ^ String.make (size - 2) 'x' ^ "\"" in
  Alcotest.(check int) "at the limit" 200 (fst (post (quoted 1_048_576)));
  Alcotest.(check (pair int string)) "over the limit"
    (413, {|{"error":"request too large"}|})
    (post (quoted 1_048_577));
  Alcotest.(check int) "a declared length over the limit is refused before reading" 413
    (fst (post ~length:2_000_000 (quoted 4)));
  Alcotest.(check (pair int string)) "a small declared length" (200, {|{"ok":2}|}) (post ~length:4 (quoted 4))

let no_sessions () =
  let got = ref [] in
  let handler = Yuka_dream.handler (Yuka.Server.config ~log:(fun _ m -> got := m :: !got) ()) Yuka_routes.app in
  let csrf handler =
    let headers = [ ("Origin", "http://app.test"); ("Host", "app.test") ] in
    let response = Dream.test handler (Dream.request ~target:"/_yuka/csrf" ~headers "") in
    (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))
  in
  let status = ref 0 in
  ignore (with_stderr (fun () -> status := fst (csrf handler)));
  Alcotest.(check int) "csrf without the middleware" 500 !status;
  check_true "the log names the path and the middleware"
    (match !got with [ m ] -> contains m "/_yuka/csrf" && contains m "session middleware" | _ -> false);
  got := [];
  let status, body = csrf (Dream.memory_sessions () handler) in
  Alcotest.(check int) "csrf with the middleware" 200 status;
  check_true "a token" (contains body {|{"csrf":"|});
  Alcotest.(check (list string)) "no log" [] !got

let dream_request () =
  let handler = Yuka_dream.handler config Yuka_routes.app in
  let response = Dream.test handler (Dream.request ~target:"/whoami.txt?a=1" ~headers:[ ("x-user", "bob") ] "") in
  Alcotest.(check string) "inside a Dream request" "/whoami.txt?a=1 bob" (Lwt_main.run (Dream.body response));
  check_true "a Testing request" (Option.is_none (Yuka_dream.request (Yuka.Server.Testing.request ())))

let handler_reads_the_request () =
  let handler = Yuka_dream.handler config Yuka_routes.app in
  let headers =
    [ ("Content-Type", "application/json"); ("Origin", "http://app.test"); ("Host", "app.test"); ("Cookie", "a=1; theme=dark") ]
  in
  let response = Dream.test handler (Dream.request ~method_:`POST ~target:"/sum?tag=t" ~headers "[1,2,3]") in
  Alcotest.(check (pair int string)) "JSON body, query param and cookie" (201, {|["6","t","dark"]|})
    (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

let free_port () =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port = match Unix.getsockname s with Unix.ADDR_INET (_, port) -> port | _ -> assert false in
  Unix.close s;
  port

let rec connect_to port tries =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  match Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) with
  | () -> s
  | exception Unix.Unix_error (Unix.ECONNREFUSED, _, _) when tries > 0 ->
      Unix.close s;
      Unix.sleepf 0.05;
      connect_to port (tries - 1)

let rec wait_child flags pid =
  match Unix.waitpid flags pid with
  | state -> state
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait_child flags pid

let client_leaves_during_a_stream () =
  let port = free_port () in
  match Lwt_unix.fork () with
  | 0 ->
      let handler = Yuka_dream.handler config Yuka_routes.app in
      let stream _ =
        Dream.stream (fun s ->
            let rec go n =
              if n = 0 then Dream.close s
              else Lwt.bind (Dream.write s "chunk\n") (fun () -> Lwt.bind (Dream.flush s) (fun () -> Lwt.bind (Lwt_unix.sleep 0.05) (fun () -> go (n - 1))))
            in
            go 40)
      in
      Lwt_main.run
        (Dream.serve ~interface:"127.0.0.1" ~port (fun request ->
             if Dream.target request = "/stream" then stream request else handler request));
      Stdlib.exit 0
  | child ->
      let s = connect_to port 100 in
      let request = "GET /stream HTTP/1.1\r\nHost: x\r\n\r\n" in
      ignore (Unix.write_substring s request 0 (String.length request));
      Unix.shutdown s Unix.SHUTDOWN_SEND;
      Unix.close s;
      Unix.sleepf 1.;
      let state = wait_child [ Unix.WNOHANG ] child in
      if fst state = 0 then begin
        Unix.kill child Sys.sigkill;
        ignore (wait_child [] child)
      end;
      Alcotest.(check string)
        "the server process is still running" "running"
        (match state with
        | 0, _ -> "running"
        | _, Unix.WSIGNALED n when n = Sys.sigpipe -> "killed by SIGPIPE"
        | _, Unix.WSIGNALED n -> Printf.sprintf "killed by signal %d" n
        | _, Unix.WEXITED n -> Printf.sprintf "exited %d" n
        | _, Unix.WSTOPPED n -> Printf.sprintf "stopped %d" n)

let () =
  Alcotest.run "yuka-dream"
    [
      ( "prerender",
        [
          Alcotest.test_case "seeds, crawled links, 404.html, assets" `Quick pages;
          Alcotest.test_case "twice gives the same files" `Quick twice;
          Alcotest.test_case "under a base: requests and links have it, file names do not" `Quick based;
          Alcotest.test_case "the handler serves prerendered files" `Quick serve;
          Alcotest.test_case "YUKA_DEV=1 does not turn on dev mode" `Quick dev_env_ignored;
          Alcotest.test_case "a prerender with ~dev:true writes no dev script" `Quick prerender_dev_off;
          Alcotest.test_case "out inside a served directory is refused" `Quick out_inside_a_served_dir;
        ] );
      ("body", [ Alcotest.test_case "the body limit" `Quick body_limit ]);
      ("log", [ Alcotest.test_case "Console reaches the Dream log" `Quick dream_log ]);
      ("session", [ Alcotest.test_case "no session middleware" `Quick no_sessions ]);
      ( "request",
        [
          Alcotest.test_case "Yuka_dream.request" `Quick dream_request;
          Alcotest.test_case "a handler reads the request" `Quick handler_reads_the_request;
        ] );
      ("serve", [ Alcotest.test_case "a client that leaves during a streamed answer" `Quick client_leaves_during_a_stream ]);
    ]
