let ( let* ) = Lwt.bind

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

let check_true msg b = Alcotest.(check bool) msg true b
let bound = 30.

let bounded what p =
  Lwt.pick
    [
      p;
      Lwt.bind (Lwt_unix.sleep bound) (fun () -> Lwt.fail (Failure (Printf.sprintf "%s: nothing after %.0f s" what bound)));
    ]

let rec poll f = if f () then Lwt.return_unit else Lwt.bind (Lwt_unix.sleep 0.01) (fun () -> poll f)
let wait_for what f = bounded what (poll f)

let write_all fd text =
  let rec from off =
    if off = String.length text then Lwt.return_unit
    else Lwt.bind (Lwt_unix.write_string fd text off (String.length text - off)) (fun n -> from (off + n))
  in
  Lwt.catch (fun () -> from 0) (function
    | Unix.Unix_error ((Unix.EPIPE | Unix.ECONNRESET), _, _) -> Lwt.return_unit
    | e -> Lwt.fail e)

let read_all fd =
  let buffer = Buffer.create 4096 and chunk = Bytes.create 65536 in
  let rec next () =
    Lwt.bind (Lwt_unix.read fd chunk 0 (Bytes.length chunk)) (function
      | 0 -> Lwt.return (Buffer.contents buffer)
      | n ->
          Buffer.add_subbytes buffer chunk 0 n;
          next ())
  in
  Lwt.catch next (function
    | Unix.Unix_error (Unix.ECONNRESET, _, _) -> Lwt.return (Buffer.contents buffer)
    | e -> Lwt.fail e)

let pair handler =
  let client, server = Lwt_unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  (client, Yuka_server.connection handler (Unix.ADDR_UNIX "") server)

let read_until fd buffer part =
  let chunk = Bytes.create 65536 in
  let rec next () =
    if contains (Buffer.contents buffer) part then Lwt.return_unit
    else
      Lwt.bind (Lwt_unix.read fd chunk 0 (Bytes.length chunk)) (function
        | 0 -> Lwt.fail (Failure (Printf.sprintf "the connection ended before %S: %S" part (Buffer.contents buffer)))
        | n ->
            Buffer.add_subbytes buffer chunk 0 n;
            next ())
  in
  bounded ("waiting for " ^ part) (next ())

let read_at_least fd n =
  let chunk = Bytes.create 65536 in
  let rec next got =
    if got >= n then Lwt.return_unit
    else
      Lwt.bind (Lwt_unix.read fd chunk 0 (Bytes.length chunk)) (function
        | 0 -> Lwt.fail (Failure "the connection ended")
        | k -> next (got + k))
  in
  bounded "the first bytes" (next 0)

let open_fds () = Array.length (Sys.readdir "/dev/fd")

let within seconds what p =
  Lwt.pick
    [
      p;
      Lwt.bind (Lwt_unix.sleep seconds) (fun () -> Lwt.fail (Failure (Printf.sprintf "%s: nothing after %.1f s" what seconds)));
    ]

let exchange ?(ended = true) handler text =
  let client, served = pair handler in
  let sent = write_all client text in
  let* output = bounded "the answer" (read_all client) in
  let* () = bounded "the request" sent in
  (* The client closes once it has the whole answer: ache waits for that before
     it closes its own end (lingering close, RFC 9112 9.6). *)
  let* () = Lwt_unix.close client in
  let* () = if ended then bounded "the end of the connection" served else Lwt.return_unit in
  Lwt.return output

type response = { status : int; headers : (string * string) list; body : string }

let header name r = List.assoc_opt name r.headers
let headers name r = List.filter_map (fun (n, v) -> if n = name then Some v else None) r.headers

let find text part from =
  let n = String.length part in
  let rec at i = if i + n > String.length text then None else if String.sub text i n = part then Some i else at (i + 1) in
  at from

let dechunk text pos =
  let rec chunks pos acc =
    match find text "\r\n" pos with
    | None -> Alcotest.failf "no chunk size at %d in %S" pos text
    | Some eol ->
        let size = int_of_string ("0x" ^ String.sub text pos (eol - pos)) in
        if size = 0 then begin
          Alcotest.(check string) "the end of the chunks" "\r\n" (String.sub text (eol + 2) 2);
          (String.concat "" (List.rev acc), eol + 4)
        end
        else begin
          if eol + 2 + size + 2 > String.length text then Alcotest.failf "a chunk cut at %d in %S" pos text;
          Alcotest.(check string) "the end of a chunk" "\r\n" (String.sub text (eol + 2 + size) 2);
          chunks (eol + 2 + size + 2) (String.sub text (eol + 2) size :: acc)
        end
  in
  chunks pos []

let parse_one ~head text pos =
  match find text "\r\n\r\n" pos with
  | None -> Alcotest.failf "no response head at %d in %S" pos text
  | Some stop -> (
      let lines =
        String.split_on_char '\n' (String.sub text pos (stop - pos))
        |> List.map (fun l -> if String.ends_with ~suffix:"\r" l then String.sub l 0 (String.length l - 1) else l)
      in
      let status_line, header_lines = (List.hd lines, List.tl lines) in
      if not (String.starts_with ~prefix:"HTTP/1.1 " status_line) then
        Alcotest.failf "not a status line at %d: %S" pos status_line;
      let status = int_of_string (String.sub status_line 9 3) in
      let headers =
        List.map
          (fun line ->
            let colon = String.index line ':' in
            ( String.lowercase_ascii (String.sub line 0 colon),
              String.trim (String.sub line (colon + 1) (String.length line - colon - 1)) ))
          header_lines
      in
      let start = stop + 4 in
      let r = { status; headers; body = "" } in
      if List.mem_assoc "transfer-encoding" headers && List.mem_assoc "content-length" headers then
        Alcotest.failf "both transfer-encoding and content-length at %d: %S" pos status_line;
      if head || status < 200 || status = 204 || status = 304 then (r, start)
      else
        match (List.assoc_opt "transfer-encoding" headers, List.assoc_opt "content-length" headers) with
        | Some "chunked", _ ->
            let body, next = dechunk text start in
            ({ r with body }, next)
        | None, Some n ->
            let n = int_of_string n in
            ({ r with body = String.sub text start n }, start + n)
        | _ -> ({ r with body = String.sub text start (String.length text - start) }, String.length text))

let responses ~heads text =
  let rec go pos heads acc =
    match heads with
    | [] ->
        if pos <> String.length text then
          Alcotest.failf "bytes after the last response: %S" (String.sub text pos (String.length text - pos));
        List.rev acc
    | head :: heads ->
        let r, next = parse_one ~head text pos in
        go next heads (r :: acc)
  in
  go 0 heads []

let one ~head output = match responses ~heads:[ head ] output with [ r ] -> r | _ -> Alcotest.fail "not one response"

let request_text ?(meth = "GET") ?(version = "HTTP/1.1") ?(headers = []) ?(body = "") target =
  String.concat ""
    ((meth ^ " " ^ target ^ " " ^ version ^ "\r\n") :: List.map (fun (n, v) -> n ^ ": " ^ v ^ "\r\n") headers)
  ^ "\r\n" ^ body

let chunked body = Printf.sprintf "%x\r\n%s\r\n0\r\n\r\n" (String.length body) body

let call ?(meth = "GET") ?(headers = []) ?(body = "") ?length ?(chunks = false) ?framing handler target =
  let framing, body =
    match (framing, length, chunks) with
    | Some framing, _, _ -> (framing, body)
    | None, _, true -> ([ ("Transfer-Encoding", "chunked") ], chunked body)
    | None, Some n, false -> ([ ("Content-Length", string_of_int n) ], body)
    | None, None, false -> ((if body = "" then [] else [ ("Content-Length", string_of_int (String.length body)) ]), body)
  in
  let host = if List.mem_assoc "Host" headers then [] else [ ("Host", "app.test") ] in
  let text = request_text ~meth ~headers:(host @ headers @ framing @ [ ("Connection", "close") ]) ~body target in
  one ~head:(meth = "HEAD") (Lwt_main.run (exchange handler text))

let same_origin = [ ("Origin", "http://app.test"); ("Host", "app.test") ]

let static =
  let dir = Filename.temp_dir "yuka_static" "" in
  let write name text = Out_channel.with_open_bin (Filename.concat dir name) (fun oc -> output_string oc text) in
  write "s.css" "body{}";
  write "a.js" "export {}";
  write "c.html" "<p>c</p>";
  write "big.bin" (String.init (200 * 1024) (fun i -> Char.chr ((i * 7 + i / 251) land 255)));
  Out_channel.with_open_bin (Filename.concat (Filename.dirname dir) (Filename.basename dir ^ "-outside.txt")) (fun oc ->
      output_string oc "outside");
  dir

let secret = "0123456789abcdef0123456789abcdef-test"
let sessions = Yuka_server.sessions ~secret ()
let config = Yuka.Server.config ~public:[ ("/static", static) ] ()
let quiet config = Yuka_server.handler ~sessions ~log_requests:false config Yuka_routes.app
let make = quiet

let with_stderr f =
  let file = Filename.temp_file "yuka_stderr" "" in
  let saved = Unix.dup Unix.stderr in
  let fd = Unix.openfile file [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  Unix.dup2 fd Unix.stderr;
  Fun.protect
    ~finally:(fun () ->
      Unix.dup2 saved Unix.stderr;
      Unix.close saved;
      Unix.close fd)
    f;
  In_channel.with_open_bin file In_channel.input_all

let serve () =
  let out = Filename.temp_dir "yuka_out" "" in
  Sys.mkdir (Filename.concat out "docs") 0o755;
  Out_channel.with_open_bin (Filename.concat out "docs/index.html") (fun oc -> output_string oc "from disk");
  let handler = make (Yuka.Server.config ~prerendered:out ()) in
  let r = call handler "/docs" in
  Alcotest.(check string) "file" "from disk" r.body;
  Alcotest.(check (option string)) "rule header" (Some "test") (header "x-site" r);
  Alcotest.(check (list string)) "a repeated rule header, both values" [ "a"; "b" ] (headers "x-twice" r);
  Alcotest.(check (option string)) "type" (Some "text/html; charset=utf-8") (header "content-type" r);
  Alcotest.(check (option string)) "length" (Some "9") (header "content-length" r);
  check_true "a query renders" (contains (call handler "/docs?x=1").body "<p>docs</p>");
  check_true "not prerendered" (contains (call handler "/secret").body "secret");
  let r = call handler "/post/nope" in
  Alcotest.(check int) "missing file renders" 404 r.status;
  check_true "not found" (contains r.body "missing /post/nope")

let head () =
  let handler = make config in
  List.iter
    (fun target ->
      let get = call handler target and head = call ~meth:"HEAD" handler target in
      Alcotest.(check (pair int int)) (target ^ ": status of GET and HEAD") (200, 200) (get.status, head.status);
      Alcotest.(check string) (target ^ ": no body") "" head.body;
      List.iter
        (fun name -> Alcotest.(check (option string)) (target ^ ": " ^ name) (header name get) (header name head))
        (if target = "/static/s.css" then [ "transfer-encoding" ] else [ "transfer-encoding"; "content-type" ]);
      match header "content-length" head with
      | None -> ()
      | length -> Alcotest.(check (option string)) (target ^ ": a length is the GET length") (header "content-length" get) length)
    [ "/feed.xml"; "/docs"; "/slow"; "/static/s.css" ];
  Alcotest.(check (option string)) "a string answer has its length" (Some "6")
    (header "content-length" (call ~meth:"HEAD" handler "/feed.xml"))

let one_connection () =
  let handler = make config in
  let run text heads = responses ~heads (Lwt_main.run (exchange handler text)) in
  (match
     run "HEAD /slow HTTP/1.1\r\nHost: x\r\n\r\nGET /docs HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n" [ true; false ]
   with
  | [ h; g ] ->
      Alcotest.(check (pair int int)) "HEAD then GET" (200, 200) (h.status, g.status);
      Alcotest.(check (option string)) "the HEAD of a stream" (Some "chunked") (header "transfer-encoding" h);
      check_true "the GET body" (contains g.body "<p>docs</p>")
  | _ -> assert false);
  match
    run "GET /docs HTTP/1.1\r\nHost: x\r\n\r\nGET /feed.xml HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n" [ false; false ]
  with
  | [ a; b ] ->
      check_true "the first GET" (a.status = 200 && contains a.body "<p>docs</p>");
      Alcotest.(check (pair int string)) "the second GET" (200, "<rss/>") (b.status, b.body)
  | _ -> assert false

let patch () =
  let r = call ~meth:"PATCH" ~headers:same_origin (make config) "/patched" in
  Alcotest.(check (pair int string)) "a PATCH endpoint" (200, "patched") (r.status, r.body)

let dev_env_ignored () =
  Unix.putenv "YUKA_DEV" "1";
  let config = Fun.protect ~finally:(fun () -> Unix.putenv "YUKA_DEV" "") (fun () -> Yuka.Server.config ()) in
  let handler = make config in
  let index = (call handler "/").body in
  check_true "a page" (contains index "<title>Home</title>");
  check_true "no dev script" (not (contains index "EventSource"));
  Alcotest.(check int) "no dev events" 404 (call handler "/_yuka/dev").status

let streamed () =
  let gate, open_gate, _ = Yuka.Async.make () in
  App.gate := gate;
  let shell, output =
    Lwt_main.run
      (let client, served = pair (make config) in
       let* () = write_all client "GET /gated HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n" in
       let seen = Buffer.create 4096 in
       let* () = read_until client seen "loading" in
       let shell = Buffer.contents seen in
       open_gate ();
       let* rest = bounded "the rest" (read_all client) in
       let* () = Lwt_unix.close client in
       let* () = bounded "the end of the connection" served in
       Lwt.return (shell, shell ^ rest))
  in
  check_true "the shell arrives before the await settles" (not (contains shell "gated data"));
  let r = one ~head:false output in
  Alcotest.(check int) "status" 200 r.status;
  check_true "the shell" (contains r.body "before");
  check_true "the fill" (contains r.body "<p>gated data</p>");
  check_true "the end" (String.ends_with ~suffix:"</body></html>" r.body)

let http_1_0 () =
  let r =
    one ~head:false
      (Lwt_main.run (exchange (make config) (request_text ~version:"HTTP/1.0" ~headers:[ ("Host", "app.test") ] "/slow")))
  in
  Alcotest.(check int) "status" 200 r.status;
  Alcotest.(check (option string)) "not chunked" None (header "transfer-encoding" r);
  Alcotest.(check (option string)) "closed" (Some "close") (header "connection" r);
  check_true "the fill" (contains r.body "<p>slow data</p>");
  check_true "the end" (String.ends_with ~suffix:"</body></html>" r.body)

let timeout () =
  let start = Unix.gettimeofday () in
  let r = call (make (Yuka.Server.config ~timeout:0.05 ())) "/stuck" in
  check_true "ends with the timeout" (Unix.gettimeofday () -. start < 1.);
  Alcotest.(check int) "status" 200 r.status;
  check_true "the failed fill after the timeout" (contains r.body "failed");
  check_true "the end" (contains r.body "</body></html>")

let leave_ticks handler =
  let left, leave, _ = Yuka.Async.make () in
  App.client_left := left;
  App.second_write := None;
  Lwt_main.run
    (let client, _ = pair handler in
     let* () = write_all client "GET /ticks HTTP/1.1\r\nHost: app.test\r\n\r\n" in
     let* () = read_until client (Buffer.create 256) "first" in
     let* () = Lwt_unix.close client in
     leave ();
     wait_for "the second write" (fun () -> !App.second_write <> None))

let client_leaves () =
  leave_ticks (make config);
  match !App.second_write with
  | Some (Error _) -> ()
  | Some (Ok ()) -> Alcotest.fail "the write after the client left succeeded"
  | None -> assert false

let ache_request () =
  let r = call ~headers:[ ("x-user", "bob") ] (make config) "/whoami?a=1" in
  Alcotest.(check string) "inside an ache request" "/whoami?a=1 bob" r.body;
  check_true "a Testing request" (Option.is_none (Yuka_server.request (Yuka.Server.Testing.request ())))

let handler_reads_the_request () =
  let headers = (("Content-Type", "application/json") :: same_origin) @ [ ("Cookie", "a=1; theme=dark") ] in
  let r = call ~meth:"POST" ~headers ~body:"[1,2,3]" (make config) "/sum?tag=t" in
  Alcotest.(check (pair int string)) "JSON body, query param and cookie" (201, {|["6","t","dark"]|}) (r.status, r.body)

let files () =
  let handler = make config in
  let r = call handler "/static/s.css" in
  Alcotest.(check (pair int string)) "the file" (200, "body{}") (r.status, r.body);
  let r = call handler "/static/none.css" in
  Alcotest.(check (pair int (option string))) "a missing file" (404, Some "no-store") (r.status, header "cache-control" r);
  let r = call handler "/static/big.bin" in
  let big = In_channel.with_open_bin (Filename.concat static "big.bin") In_channel.input_all in
  Alcotest.(check int) "200 KiB" 204_800 (String.length big);
  Alcotest.(check (option string)) "its length" (Some "204800") (header "content-length" r);
  check_true "the whole file" (r.status = 200 && r.body = big);
  List.iter
    (fun (file, t) -> Alcotest.(check (option string)) file (Some t) (header "content-type" (call handler ("/static/" ^ file))))
    [
      ("a.js", "application/javascript");
      ("s.css", "text/css");
      ("c.html", "text/html; charset=utf-8");
      ("big.bin", "application/octet-stream");
    ]

let no_escape () =
  let handler = make config in
  let outside = Filename.basename static ^ "-outside.txt" in
  List.iter
    (fun target ->
      let r = call handler target in
      check_true (target ^ ": not the file outside") (not (contains r.body "outside")))
    [ "/static/../" ^ outside; "/static/%2e%2e/" ^ outside; "/static/..%2f" ^ outside; "/static/%2E%2E%2F" ^ outside ]

let echo = Yuka.Action.mutation ~name:"echo" ~input:Yuka.Codec.string ~output:Yuka.Codec.int
let () = Yuka.Server.Action.implement echo (fun _ s -> Yuka.Async.return (String.length s))
let quoted size = "\"" ^ String.make (size - 2) 'x' ^ "\""

let body_limit () =
  let handler = make config in
  let post ?length ?chunks body =
    let r =
      call ~meth:"POST" ~headers:(("Content-Type", "application/json") :: same_origin) ?length ?chunks ~body handler
        "/_yuka/action/echo"
    in
    (r.status, r.body)
  in
  Alcotest.(check int) "at the limit" 200 (fst (post ~chunks:true (quoted 1_048_576)));
  Alcotest.(check (pair int string)) "over the limit" (413, {|{"error":"request too large"}|}) (post ~chunks:true (quoted 1_048_577));
  Alcotest.(check int) "a declared length over the limit is refused before reading" 413 (fst (post ~length:2_000_000 (quoted 4)));
  Alcotest.(check (pair int string)) "a small declared length" (200, {|{"ok":2}|}) (post ~length:4 (quoted 4))

let expect_continue () =
  let handler = make config in
  let head = "POST /_yuka/action/echo HTTP/1.1\r\nHost: app.test\r\nOrigin: http://app.test\r\nContent-Type: application/json\r\nExpect: 100-continue\r\nConnection: close\r\n" in
  Lwt_main.run
    (let client, served = pair handler in
     let* () = write_all client (head ^ "Content-Length: 4\r\n\r\n") in
     let buffer = Buffer.create 256 in
     let* () = read_until client buffer "\r\n\r\n" in
     Alcotest.(check string) "100 Continue before the body" "HTTP/1.1 100 Continue\r\n\r\n" (Buffer.contents buffer);
     let* () = write_all client {|"ab"|} in
     let* rest = bounded "the answer" (read_all client) in
     let r = one ~head:false rest in
     Alcotest.(check (pair int string)) "then the answer" (200, {|{"ok":2}|}) (r.status, r.body);
     let* () = Lwt_unix.close client in
     bounded "the end of the connection" served);
  let refused = Lwt_main.run (exchange ~ended:false handler (head ^ "Content-Length: 2000000\r\n\r\n")) in
  check_true "no 100 Continue for a body that is refused" (not (contains refused "100 Continue"));
  Alcotest.(check int) "a body over the limit" 413 (one ~head:false refused).status

let smuggled = request_text ~headers:[ ("Host", "app.test") ] "/docs"

let refused_body_framing () =
  let output =
    Lwt_main.run
      (exchange (make config)
         (request_text ~meth:"POST"
            ~headers:(same_origin @ [ ("Content-Type", "text/plain"); ("Content-Length", string_of_int (String.length smuggled)) ])
            ~body:smuggled "/_yuka/action/echo"
         ^ request_text ~headers:[ ("Host", "app.test"); ("Connection", "close") ] "/feed.xml"))
  in
  match responses ~heads:[ false; false ] output with
  | [ refused; next ] ->
      Alcotest.(check int) "refused before reading" 415 refused.status;
      Alcotest.(check (pair int string)) "the next request" (200, "<rss/>") (next.status, next.body)
  | _ -> assert false

let unread_body () =
  let output =
    Lwt_main.run
      (let client, served = pair (make config) in
       let* () =
         write_all client
           (request_text ~meth:"POST"
              ~headers:(same_origin @ [ ("Content-Type", "application/json"); ("Content-Length", "2000000") ])
              ~body:smuggled "/_yuka/action/echo")
       in
       let seen = Buffer.create 256 in
       let* () = read_until client seen "request too large" in
       Lwt_unix.shutdown client Unix.SHUTDOWN_SEND;
       let* rest = bounded "the end of the connection" (read_all client) in
       let* () = bounded "the server ends the connection" served in
       let* () = Lwt_unix.close client in
       Lwt.return (Buffer.contents seen ^ rest))
  in
  let first, next = parse_one ~head:false output 0 in
  Alcotest.(check int) "the 413" 413 first.status;
  let rest = String.sub output next (String.length output - next) in
  check_true ("the body is not a next request: " ^ rest) (not (contains rest "HTTP/1.1 200" || contains rest "docs"))

let counted = Yuka.Action.mutation ~name:"counted" ~input:Yuka.Codec.string ~output:Yuka.Codec.int
let runs = ref 0

let () =
  Yuka.Server.Action.implement counted (fun _ s ->
      incr runs;
      Yuka.Async.return (String.length s))

let cut_chunked_body () =
  let before = !runs in
  let output =
    Lwt_main.run
      (exchange ~ended:false (make config)
         (request_text ~meth:"POST"
            ~headers:(same_origin @ [ ("Content-Type", "application/json"); ("Transfer-Encoding", "chunked") ])
            ~body:"4\r\n\"ab\"\r\nZZ\r\n" "/_yuka/action/counted"))
  in
  check_true ("a 400: " ^ output) (String.starts_with ~prefix:"HTTP/1.1 400" output);
  Alcotest.(check int) "the action did not run" before !runs;
  let output =
    Lwt_main.run
      (let client, served = pair (make config) in
       let* () =
         write_all client
           (request_text ~meth:"POST"
              ~headers:(same_origin @ [ ("Content-Type", "application/json"); ("Transfer-Encoding", "chunked") ])
              ~body:"4\r\n\"ab\"\r\n" "/_yuka/action/counted")
       in
       Lwt_unix.shutdown client Unix.SHUTDOWN_SEND;
       let* output = bounded "the answer" (read_all client) in
       let* () = bounded "the end of the connection" served in
       let* () = Lwt_unix.close client in
       Lwt.return output)
  in
  check_true ("no 200 for a body cut by the end of input: " ^ output) (not (String.starts_with ~prefix:"HTTP/1.1 200" output));
  Alcotest.(check int) "the action did not run on a cut body" before !runs

let smuggling () =
  let handler = make config in
  List.iter
    (fun (label, framing, body) ->
      let before = !runs in
      let r =
        call ~meth:"POST" ~headers:(("Content-Type", "application/json") :: same_origin) ~framing ~body handler
          "/_yuka/action/counted"
      in
      Alcotest.(check int) (label ^ ": 400") 400 r.status;
      Alcotest.(check (option string)) (label ^ ": closed") (Some "close") (header "connection" r);
      Alcotest.(check int) (label ^ ": the action did not run") before !runs)
    [
      ("chunked and a length", [ ("Transfer-Encoding", "chunked"); ("Content-Length", "4") ], chunked {|"ab"|});
      ("a hexadecimal length", [ ("Content-Length", "0x4") ], {|"ab"|});
      ("a signed length", [ ("Content-Length", "+4") ], {|"ab"|});
      ("an underscore in the length", [ ("Content-Length", "1_0") ], {|"abcdefgh"|});
      ("two lengths", [ ("Content-Length", "4"); ("Content-Length", "5") ], {|"ab"|});
    ]

let doubled_host () =
  let before = !runs in
  let r =
    call ~meth:"POST"
      ~headers:[ ("Content-Type", "application/json"); ("Origin", "http://app.test"); ("Host", "app.test"); ("Host", "evil.test") ]
      ~body:{|"ab"|} (make config) "/_yuka/action/counted"
  in
  Alcotest.(check int) "two Host fields: 400" 400 r.status;
  Alcotest.(check int) "the action did not run" before !runs

let long_header () =
  let handler = make config in
  let r = call ~headers:[ ("Cookie", "a=" ^ String.make 10_000 'c') ] handler "/feed.xml" in
  Alcotest.(check (pair int string)) "a 10 KB cookie" (200, "<rss/>") (r.status, r.body);
  let r =
    one ~head:false
      (Lwt_main.run
         (exchange handler (request_text ~headers:[ ("Host", "app.test"); ("Cookie", "a=" ^ String.make 40_000 'c') ] "/feed.xml")))
  in
  Alcotest.(check int) "a 40 KB cookie" 431 r.status

let framed query handler =
  responses ~heads:[ false; false ]
    (Lwt_main.run
       (exchange handler
          ("GET /framing?case=" ^ query
         ^ " HTTP/1.1\r\nHost: app.test\r\n\r\nGET /feed.xml HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n")))

let bodyless () =
  let handler = make config in
  List.iter
    (fun (query, status) ->
      match framed query handler with
      | [ a; b ] ->
          Alcotest.(check int) (query ^ ": status") status a.status;
          Alcotest.(check (pair int string)) (query ^ ": the next answer") (200, "<rss/>") (b.status, b.body)
      | _ -> assert false)
    [ ("204", 204); ("304", 304); ("204-stream", 204); ("304-stream", 304) ];
  let output = Lwt_main.run (exchange (fun _ _ -> failwith "broken") "HEAD / HTTP/1.1\r\nHost: app.test\r\n\r\n") in
  Alcotest.(check int) "the error answer to HEAD has no body" 500 (one ~head:true output).status;
  let output =
    Lwt_main.run
      (exchange handler "HEAD /feed.xml HTTP/1.1\r\nHost: app.test\r\n\r\nGET /feed.xml HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n")
  in
  match responses ~heads:[ true; false ] output with
  | [ h; g ] ->
      Alcotest.(check (option string)) "HEAD keeps the length" (Some "6") (header "content-length" h);
      Alcotest.(check (pair int string)) "the GET right after the HEAD head" (200, "<rss/>") (g.status, g.body)
  | _ -> assert false

let framing_headers () =
  let handler = make config in
  List.iter
    (fun query ->
      match framed query handler with
      | [ a; b ] ->
          Alcotest.(check (pair int string)) (query ^ ": the answer") (200, "hello") (a.status, a.body);
          Alcotest.(check (pair int string)) (query ^ ": the next answer") (200, "<rss/>") (b.status, b.body)
      | _ -> assert false)
    [ "length"; "chunked-string"; "stream-te"; "stream-length" ]

let invalid_answers () =
  let got = ref [] in
  let handler = make (Yuka.Server.config ~log:(fun level m -> got := (level, m) :: !got) ()) in
  List.iter
    (fun query ->
      got := [];
      match framed query handler with
      | [ a; b ] ->
          Alcotest.(check (pair int string)) (query ^ ": a plain 500") (500, "Internal Server Error") (a.status, a.body);
          Alcotest.(check (pair int string)) (query ^ ": the next answer") (200, "<rss/>") (b.status, b.body);
          check_true (query ^ ": logged") (List.exists (fun (level, m) -> level = `Error && contains m "answered 500") !got)
      | _ -> assert false)
    [ "status-99"; "status-1000"; "bad-name" ]

let log () =
  let output = with_stderr (fun () -> ignore (call (make (Yuka.Server.config ())) "/warned")) in
  check_true ("the default sink: " ^ output) (contains output "yuka: warn warned page");
  let kept = ref [] in
  let output = with_stderr (fun () -> ignore (call (make (Yuka.Server.config ~log:(fun _ m -> kept := m :: !kept) ())) "/warned")) in
  Alcotest.(check (list string)) "a config log is kept" [ "warned page" ] !kept;
  check_true "not on stderr" (not (contains output "warned page"))

let request_log () =
  let got = ref [] in
  let config = Yuka.Server.config ~public:[ ("/static", static) ] ~log:(fun level m -> got := (level, m) :: !got) () in
  let handler = Yuka_server.handler ~sessions config Yuka_routes.app in
  ignore (call handler "/docs?secret=1");
  ignore (call handler "/slow");
  ignore (call handler "/static/s.css");
  ignore (call handler "/post/nope");
  let lines = List.rev_map snd (List.filter (fun (level, _) -> level = `Info) !got) in
  let line_for prefix = List.find_opt (fun l -> String.starts_with ~prefix l) lines in
  List.iter
    (fun prefix ->
      match line_for prefix with
      | Some l -> check_true (l ^ ": a time") (String.ends_with ~suffix:"ms" l)
      | None -> Alcotest.failf "no line %S in %s" prefix (String.concat " | " lines))
    [ "GET /docs 200 "; "GET /slow 200 "; "GET /static/s.css 200 "; "GET /post/nope 404 " ];
  Alcotest.(check int) "one line per request" 4 (List.length lines);
  check_true "no query in the line" (not (List.exists (fun l -> contains l "secret") lines));
  got := [];
  ignore (call (quiet config) "/docs");
  Alcotest.(check int) "log_requests:false" 0 (List.length (List.filter (fun (level, _) -> level = `Info) !got))

let with_temp_dir prefix f =
  let dir = Filename.temp_dir prefix "" in
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun name -> Sys.remove (Filename.concat dir name)) (Sys.readdir dir);
      Sys.rmdir dir)
    (fun () -> f dir)

let failure_logs () =
  with_temp_dir "yuka_shrink" @@ fun shrink ->
  let got = ref [] in
  let file = Filename.concat shrink "s.bin" in
  Out_channel.with_open_bin file (fun oc -> output_string oc (String.make (16 * 1024 * 1024) 's'));
  let handler = make (Yuka.Server.config ~public:[ ("/shrink", shrink) ] ~log:(fun level m -> got := (level, m) :: !got) ()) in
  let logged part = List.exists (fun (level, m) -> level = `Error && contains m part) !got in
  ignore (Lwt_main.run (exchange ~ended:false handler "GET /framing?case=fail HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n"));
  check_true "a failed producer" (logged "producer broke");
  ignore (Lwt_main.run (exchange ~ended:false handler "GET /framing?case=raise HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n"));
  check_true "a raising producer" (logged "producer raised");
  Lwt_main.run
    (let client, _ = pair handler in
     let* () = write_all client "GET /shrink/s.bin HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n" in
     let* () = read_at_least client 65536 in
     Unix.truncate file 0;
     let* _ = bounded "the end of the answer" (read_all client) in
     Lwt_unix.close client);
  check_true "a file that changed size" (logged "before its size");
  got := [];
  leave_ticks handler;
  Alcotest.(check (list string)) "a client that left is not an error" []
    (List.filter_map (fun (level, m) -> if level = `Error then Some m else None) !got)

let no_query_in_error_logs () =
  let got = ref [] in
  let handler = make (Yuka.Server.config ~log:(fun level m -> got := (level, m) :: !got) ()) in
  List.iter
    (fun case ->
      ignore
        (Lwt_main.run
           (exchange ~ended:false handler
              (Printf.sprintf "GET /framing?case=%s&token=SECRET HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n" case))))
    [ "fail"; "raise"; "status-99" ];
  let errors = List.filter_map (fun (level, m) -> if level = `Error then Some m else None) !got in
  Alcotest.(check int) "three error lines" 3 (List.length errors);
  List.iter (fun m -> check_true ("no query in " ^ m) (not (contains m "SECRET"))) errors

let default_sink level message =
  if level <> `Debug then
    prerr_endline
      ("yuka: " ^ (match level with `Error -> "error" | `Warn -> "warn" | `Info -> "info" | `Debug -> "debug") ^ " " ^ message)

let raising_log () =
  Yuka.Server.set_default_log (fun _ _ -> failwith "the log broke");
  let bad, page =
    Fun.protect
      ~finally:(fun () -> Yuka.Server.set_default_log default_sink)
      (fun () ->
        let bad = Lwt_main.run (exchange ~ended:false (make config) "GET / HTTP/1.1\r\nbad header\r\n\r\n") in
        let raising = Yuka_server.handler ~sessions (Yuka.Server.config ~log:(fun _ _ -> failwith "the log broke") ()) Yuka_routes.app in
        (bad, call raising "/docs"))
  in
  Alcotest.(check int) "the error answer" 400 (one ~head:false bad).status;
  Alcotest.(check int) "a page with a request log that raises" 200 page.status

let set_cookies r = headers "set-cookie" r

let cookie_of r =
  match set_cookies r with
  | [ c ] -> (
      match String.split_on_char ';' c with
      | pair :: _ -> (
          match String.index_opt pair '=' with
          | Some i -> (String.sub pair 0 i, String.sub pair (i + 1) (String.length pair - i - 1))
          | None -> Alcotest.failf "no value in %S" c)
      | [] -> assert false)
  | cs -> Alcotest.failf "not one set-cookie: %s" (String.concat " | " cs)

let csrf_of r =
  let prefix = {|{"csrf":"|} in
  if String.starts_with ~prefix r.body then String.sub r.body (String.length prefix) (String.length r.body - String.length prefix - 2)
  else Alcotest.failf "no token in %S" r.body

let with_cookie (name, value) = [ ("Cookie", name ^ "=" ^ value) ]

let csrf_cookies () =
  let handler = make config in
  let r = call ~headers:same_origin handler "/_yuka/csrf" in
  Alcotest.(check int) "status" 200 r.status;
  ignore (csrf_of r);
  let name, value = cookie_of r in
  Alcotest.(check string) "the cookie name" "yuka-session" name;
  let attributes = List.map String.trim (List.tl (String.split_on_char ';' (List.hd (set_cookies r)))) in
  Alcotest.(check (list string)) "attributes" [ "Path=/"; "Max-Age=1209600"; "HttpOnly"; "SameSite=Lax" ] attributes;
  let again = call ~headers:(with_cookie (name, value) @ same_origin) handler "/_yuka/csrf" in
  Alcotest.(check (list string)) "a valid cookie gets no new cookie" [] (set_cookies again);
  let id = (call ~headers:(with_cookie (name, value)) handler "/session").body in
  Alcotest.(check string) "the same session" id (call ~headers:(with_cookie (name, value)) handler "/session").body;
  Alcotest.(check (list string)) "a page that asks for no session sets no cookie" [] (set_cookies (call handler "/docs"));
  Alcotest.(check (list string)) "a file sets no cookie" [] (set_cookies (call handler "/static/s.css"))

let session_id handler cookie =
  let r = call ~headers:cookie handler "/session" in
  (r.body, set_cookies r)

let bad_cookies () =
  let handler = make config in
  let r = call handler "/session" in
  let name, value = cookie_of r in
  let id = r.body in
  let flip c = if c = '0' then '1' else '0' in
  let changed_mac = String.mapi (fun i c -> if i = String.length value - 1 then flip c else c) value in
  let changed_id = String.mapi (fun i c -> if i = 3 then flip c else c) value in
  List.iter
    (fun (label, cookie) ->
      let got, cookies = session_id handler cookie in
      check_true (label ^ ": a new session") (got <> id && got <> "none");
      Alcotest.(check int) (label ^ ": a new cookie") 1 (List.length cookies))
    [
      ("a changed MAC of the same length", with_cookie (name, changed_mac));
      ("a changed id", with_cookie (name, changed_id));
      ("an empty value", with_cookie (name, ""));
      ("not a cookie of ours", with_cookie (name, "a b;c"));
      ("another secret", with_cookie (cookie_of (call (Yuka_server.handler ~sessions:(Yuka_server.sessions ~secret:(String.make 40 'z') ()) config Yuka_routes.app) "/session")));
    ];
  let got, cookies = session_id handler [ ("Cookie", name ^ "=junk; " ^ name ^ "=" ^ value) ] in
  Alcotest.(check (pair string (list string))) "a planted cookie before the valid one" (id, []) (got, cookies)

let no_sessions () =
  let logged = ref [] in
  let handler = Yuka_server.handler ~log_requests:false (Yuka.Server.config ~log:(fun _ m -> logged := m :: !logged) ()) Yuka_routes.app in
  let r = call ~headers:same_origin handler "/_yuka/csrf" in
  Alcotest.(check int) "csrf without sessions" 500 r.status;
  Alcotest.(check (list string)) "no cookie" [] (set_cookies r);
  let r = call ~headers:(("Upgrade", "websocket") :: same_origin) handler "/_yuka/live" in
  Alcotest.(check int) "live without sessions" 500 r.status;
  Alcotest.(check string) "no session" "none" (call handler "/session").body;
  Alcotest.(check int) "two log lines" 2 (List.length !logged)

let secure () =
  let handler = Yuka_server.handler ~sessions:(Yuka_server.sessions ~secure:true ~secret ()) ~log_requests:false config Yuka_routes.app in
  let r = call handler "/session" in
  let name, _ = cookie_of r in
  Alcotest.(check string) "the name" "__Host-yuka-session" name;
  check_true "Secure" (List.mem "Secure" (List.map String.trim (String.split_on_char ';' (List.hd (set_cookies r)))));
  let plain = call ~headers:(with_cookie ("yuka-session", snd (cookie_of (call (make config) "/session")))) handler "/session" in
  Alcotest.(check int) "the plain cookie name is not read" 1 (List.length (set_cookies plain))

let signed_cookies () =
  let request cookie = Yuka.Server.Testing.request ~header:(function "cookie" -> Some cookie | _ -> None) () in
  let pair = function
    | Ok (_, header) -> List.hd (String.split_on_char ';' header)
    | Error message -> Alcotest.fail message
  in
  let read ?(sessions = sessions) ?(name = "pref") cookie = Yuka_server.Signed_cookie.get sessions (request cookie) name in
  let value = {js|dark; é.1|js} in
  let written = Yuka_server.Signed_cookie.set sessions "pref" value in
  let header = match written with Ok (_, h) -> h | Error m -> Alcotest.fail m in
  Alcotest.(check (list string)) "the attributes of Server.Cookie.set" [ "Path=/"; "HttpOnly"; "SameSite=Lax" ]
    (List.tl (List.map String.trim (String.split_on_char ';' header)));
  Alcotest.(check (option string)) "valid" (Some value) (read (pair written));
  Alcotest.(check (option string)) "valid among other cookies" (Some value) (read ("a=1; " ^ pair written ^ "; b=2"));
  let encoded = String.sub (pair written) 5 (String.length (pair written) - 5) in
  let dot = String.rindex encoded '.' in
  let data = String.sub encoded 0 dot and mac = String.sub encoded (dot + 1) (String.length encoded - dot - 1) in
  let flip c = if c = '0' then '1' else '0' in
  List.iter
    (fun (label, cookie) -> Alcotest.(check (option string)) label None (read cookie))
    [
      ("a tampered value", "pref=" ^ String.map (fun c -> if c = 'd' then 'l' else c) data ^ "." ^ mac);
      ("a tampered signature", "pref=" ^ data ^ "." ^ String.mapi (fun i c -> if i = 0 then flip c else c) mac);
      ("no signature", "pref=" ^ data);
      ("an empty signature", "pref=" ^ data ^ ".");
      ("a value that does not decode", "pref=%ZZ." ^ mac);
      ("no cookie", "other=1");
    ];
  Alcotest.(check (option string)) "the value of another name" None
    (read ~name:"other" ("other=" ^ encoded));
  let other = Yuka_server.sessions ~secret:(String.make 40 'z') () in
  Alcotest.(check (option string)) "another secret" None (read ~sessions:other (pair written));
  Alcotest.(check (option string)) "valid with its own secret" (Some value)
    (read ~sessions:other (pair (Yuka_server.Signed_cookie.set other "pref" value)));
  let session_name, session_value = cookie_of (call (make config) "/session") in
  let fields = String.split_on_char '.' session_value in
  let session_mac = List.nth fields 4 in
  let forged = String.concat "\n" [ List.nth fields 1; List.nth fields 2; List.nth fields 3 ] ^ "." ^ session_mac in
  Alcotest.(check (option string)) "a MAC of the session cookie, with the session label" None
    (read ~name:session_name (session_name ^ "=" ^ Option.get (Yuka.Url.encode_uri_component forged)));
  Alcotest.(check bool) "an invalid name is an Error" true
    (Result.is_error (Yuka_server.Signed_cookie.set sessions "a b" "v"))

let short_secret () =
  Alcotest.check_raises "31 bytes" (Invalid_argument "Yuka_server.sessions: the secret must have at least 32 bytes") (fun () ->
      ignore (Yuka_server.sessions ~secret:(String.make 31 's') ()));
  List.iter
    (fun lifetime ->
      match Yuka_server.sessions ~lifetime ~secret () with
      | _ -> Alcotest.failf "lifetime %f accepted" lifetime
      | exception Invalid_argument _ -> ())
    [ 0.; 0.5; -1.; Float.nan; Float.infinity; 1e14 ]


let session_and_token handler =
  let r = call ~headers:same_origin handler "/_yuka/csrf" in
  (cookie_of r, csrf_of r)

let hello token = Printf.sprintf {|{"t":"hello","v":1,"csrf":"%s"}|} token
let cookie_text (name, value) = Some (name ^ "=" ^ value)

let expect_text what ws =
  let* f = bounded what (Ws.receive ws) in
  match f with Ws.Text t -> Lwt.return t | f -> Alcotest.failf "%s: %s" what (Ws.show f)

let live_hello handler ~cookie token =
  Lwt_main.run
    (let client, served = pair handler in
     let* ws, status = bounded "the handshake" (Ws.connect client ~host:"app.test" ~cookie) in
     Alcotest.(check string) "101" "HTTP/1.1 101 Switching Protocols" status;
     let* () = Ws.send ws (hello token) in
     let* f = bounded "the answer to hello" (Ws.receive ws) in
     let* () = Lwt.catch (fun () -> Ws.close ws 1000) (fun _ -> Lwt.return_unit) in
     let* () = bounded "the server closes" served in
     let* () = Lwt_unix.close client in
     Lwt.return f)

let live_round_trip () =
  let handler = make config in
  let cookie, token = session_and_token handler in
  Lwt_main.run
    (let client, served = pair handler in
     let* ws, status = bounded "the handshake" (Ws.connect client ~host:"app.test" ~cookie:(cookie_text cookie)) in
     Alcotest.(check string) "101" "HTTP/1.1 101 Switching Protocols" status;
     let* () = Ws.send ws (hello token) in
     let* text = expect_text "hello" ws in
     check_true ("hello back: " ^ text) (contains text {|"t":"hello"|});
     let rec pings n =
       if n = 0 then Lwt.return_unit
       else
         let* () = Ws.send ws {|{"t":"ping"}|} in
         let* text = expect_text "pong" ws in
         check_true ("pong: " ^ text) (contains text {|"t":"pong"|});
         pings (n - 1)
     in
     let* () = pings 3 in
     let* () = Ws.ping ws "abc" in
     let* f = bounded "a WebSocket pong" (Ws.receive ws) in
     Alcotest.(check string) "a WebSocket ping gets its pong" "pong abc" (Ws.show f);
     let* () = Ws.close ws 1000 in
     let* f = bounded "the close echo" (Ws.receive ws) in
     Alcotest.(check string) "the close echo" "close 1000" (Ws.show f);
     let* () = bounded "the server closes" served in
     Lwt_unix.close client)

let flip_last s = String.mapi (fun i c -> if i = String.length s - 1 then if c = '0' then '1' else '0' else c) s

let live_refused () =
  let handler = make config in
  let cookie_a, token_a = session_and_token handler and cookie_b, _ = session_and_token handler in
  List.iter
    (fun (label, cookie, token) ->
      Alcotest.(check string) label "close 4403" (Ws.show (live_hello handler ~cookie:(cookie_text cookie) token)))
    [
      ("a bad token", cookie_a, "bad");
      ("a changed MAC", cookie_a, flip_last token_a);
      ("the token of another session", cookie_b, token_a);
      ("no cookie", ("x", "y"), token_a);
    ];
  match live_hello handler ~cookie:(cookie_text cookie_a) token_a with
  | Ws.Text t -> check_true "the right token" (contains t {|"t":"hello"|})
  | f -> Alcotest.failf "the right token: %s" (Ws.show f)

let live_limit () =
  let handler = make config in
  let cookie, token = session_and_token handler in
  Lwt_main.run
    (let client, served = pair handler in
     let* ws, _ = bounded "the handshake" (Ws.connect client ~host:"app.test" ~cookie:(cookie_text cookie)) in
     let* () = Ws.send ws (hello token) in
     let* _ = expect_text "hello" ws in
     let* () = Ws.send ws (String.make (100 * 1024) 'x') in
     let* f = bounded "the close" (Ws.receive ws) in
     Alcotest.(check string) "a message over 64 KiB" "close 1009" (Ws.show f);
     let* () = bounded "the server closes" served in
     Lwt_unix.close client)

let live_client_stops_reading () =
  let handler = make config in
  let cookie, token = session_and_token handler in
  let baseline = open_fds () in
  let elapsed =
    Lwt_main.run
      (let client, server = Lwt_unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
       Lwt_unix.setsockopt_int server Unix.SO_SNDBUF 4096;
       Lwt_unix.setsockopt_int client Unix.SO_RCVBUF 4096;
       let served = Yuka_server.connection handler (Unix.ADDR_UNIX "") server in
       let* ws, _ = bounded "the handshake" (Ws.connect client ~host:"app.test" ~cookie:(cookie_text cookie)) in
       let* () = Ws.send ws (hello token) in
       let* _ = expect_text "hello" ws in
       let start = Unix.gettimeofday () in
       let rec flood n = if n = 0 then Lwt.return_unit else Lwt.bind (Ws.send ws {|{"t":"ping"}|}) (fun () -> flood (n - 1)) in
       let flood = Lwt.catch (fun () -> flood 5000) (function Unix.Unix_error (Unix.EPIPE, _, _) -> Lwt.return_unit | e -> Lwt.fail e) in
       let* () = bounded "the flood or the end of the connection" (Lwt.pick [ flood; Lwt.protected served ]) in
       let* () = bounded "the server closes a client that stopped reading" served in
       let elapsed = Unix.gettimeofday () -. start in
       let* () = Lwt_unix.close client in
       Lwt.return elapsed)
  in
  check_true (Printf.sprintf "closed after %.1f s" elapsed) (elapsed < 15.);
  Lwt_main.run (wait_for "the server socket is closed" (fun () -> open_fds () <= baseline))

let small_buffers client server =
  Lwt_unix.setsockopt_int server Unix.SO_SNDBUF 4096;
  Lwt_unix.setsockopt_int client Unix.SO_RCVBUF 4096

let stalled_pair ?(write_timeout = 0.2) handler =
  let client, server = Lwt_unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  small_buffers client server;
  (client, Yuka_server.connection ~write_timeout handler (Unix.ADDR_UNIX "") server)

let never_reads () =
  let handler = make config in
  App.flood_result := None;
  let baseline = open_fds () in
  Lwt_main.run
    (let leave_unread target =
       let client, served = stalled_pair handler in
       let* () = write_all client ("GET " ^ target ^ " HTTP/1.1\r\nHost: app.test\r\n\r\n") in
       let* () = within 3. ("the server closes a client that does not read " ^ target) served in
       Lwt_unix.close client
     in
     let* () = leave_unread "/static/big.bin" in
     let* () = leave_unread "/flood" in
     let* () = wait_for "the stream producer sees the failed write" (fun () -> !App.flood_result <> None) in
     wait_for "the file and the sockets are closed" (fun () -> open_fds () <= baseline))

let slow_reader () =
  let body, elapsed =
    Lwt_main.run
      (let client, served = stalled_pair ~write_timeout:1. (make config) in
       let* () = write_all client "GET /static/big.bin HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n" in
       let buffer = Buffer.create 4096 and chunk = Bytes.create 16384 in
       let started = Unix.gettimeofday () in
       let rec next () =
         let* n = Lwt_unix.read client chunk 0 (Bytes.length chunk) in
         if n = 0 then Lwt.return_unit
         else begin
           Buffer.add_subbytes buffer chunk 0 n;
           let* () = Lwt_unix.sleep 0.1 in
           next ()
         end
       in
       let* () = bounded "the slow download" (next ()) in
       let elapsed = Unix.gettimeofday () -. started in
       let* () = Lwt_unix.close client in
       let* () = bounded "the end of the connection" served in
       Lwt.return (Buffer.contents buffer, elapsed))
  in
  check_true (Printf.sprintf "longer than the write timeout (%.1f s)" elapsed) (elapsed > 1.2);
  let r = one ~head:false body in
  let big = In_channel.with_open_bin (Filename.concat static "big.bin") In_channel.input_all in
  check_true "a slow reader gets the whole file" (r.status = 200 && r.body = big)

let live_silent () =
  let handler = make config in
  let cookie, token = session_and_token handler in
  let baseline = open_fds () in
  let elapsed =
    Lwt_main.run
      (let client, server = Lwt_unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
       let served = Yuka_server.connection ~live_timeout:0.6 handler (Unix.ADDR_UNIX "") server in
       let* ws, _ = bounded "the handshake" (Ws.connect client ~host:"app.test" ~cookie:(cookie_text cookie)) in
       let* () = Ws.send ws (hello token) in
       let* _ = expect_text "hello" ws in
       let last_sent = ref 0. in
       let rec pings n =
         if n = 0 then Lwt.return_unit
         else
           let* () = Lwt_unix.sleep 0.1 in
           last_sent := Unix.gettimeofday ();
           let* () = Ws.send ws {|{"t":"ping"}|} in
           let* _ = expect_text "pong" ws in
           pings (n - 1)
       in
       let* () = pings 8 in
       check_true "a client that sends stays open" (Lwt.is_sleeping served);
       let started = !last_sent in
       let* () = within 3. "the server closes a silent live socket" served in
       let elapsed = Unix.gettimeofday () -. started in
       let* () = Lwt_unix.close client in
       Lwt.return elapsed)
  in
  check_true (Printf.sprintf "closed after the live timeout (%.2f s)" elapsed) (elapsed >= 0.55);
  Lwt_main.run (wait_for "the server socket is closed" (fun () -> open_fds () <= baseline))

let lifetime () =
  let handler = Yuka_server.handler ~sessions:(Yuka_server.sessions ~lifetime:2. ~secret ()) ~log_requests:false config Yuka_routes.app in
  Unix.sleepf (1.05 -. Float.rem (Unix.gettimeofday ()) 1.);
  let cookie, token = session_and_token handler in
  let id, _ = session_id handler (with_cookie cookie) in
  let got, cookies = session_id handler (with_cookie cookie) in
  Alcotest.(check (pair string int)) "fresh: kept, no new cookie" (id, 0) (got, List.length cookies);
  Unix.sleepf 1.3;
  let r = call ~headers:(with_cookie cookie) handler "/session" in
  let renewed = cookie_of r in
  Alcotest.(check string) "under half its life: the same id" id r.body;
  check_true "under half its life: a new cookie" (renewed <> cookie);
  (match live_hello handler ~cookie:(cookie_text renewed) token with
  | Ws.Text t -> check_true "the token is valid with the renewed cookie" (contains t {|"t":"hello"|})
  | f -> Alcotest.failf "the token with the renewed cookie: %s" (Ws.show f));
  Unix.sleepf 1.3;
  Alcotest.(check string) "an expired token" "close 4403" (Ws.show (live_hello handler ~cookie:(cookie_text renewed) token));
  Alcotest.(check string) "the renewed cookie keeps the session" id (fst (session_id handler (with_cookie renewed)));
  let got, cookies = session_id handler (with_cookie cookie) in
  check_true "an expired cookie: a new session" (got <> id && List.length cookies = 1)

let absolute_limit () =
  let handler =
    Yuka_server.handler ~sessions:(Yuka_server.sessions ~lifetime:2. ~max_lifetime:3. ~secret ()) ~log_requests:false config
      Yuka_routes.app
  in
  Unix.sleepf (1.05 -. Float.rem (Unix.gettimeofday ()) 1.);
  let started = Unix.gettimeofday () in
  let r = call handler "/session" in
  let id = r.body in
  let rec use cookie =
    Unix.sleepf 0.6;
    let at = Unix.gettimeofday () -. started in
    let r = call ~headers:(with_cookie cookie) handler "/session" in
    if r.body <> id then (at, r)
    else if at > 4.5 then Alcotest.failf "the session %s is still valid after %.1f seconds" id at
    else use (match set_cookies r with [] -> cookie | _ -> cookie_of r)
  in
  let at, r = use (cookie_of r) in
  check_true (Printf.sprintf "a new session after the absolute limit, not before (%.1f s)" at) (at >= 2.9);
  check_true (Printf.sprintf "a new session at the first request after the limit (%.1f s)" at) (at < 4.);
  Alcotest.(check string) "the new session is kept" r.body (fst (session_id handler (with_cookie (cookie_of r))))

let error_handler () =
  let bad = one ~head:false (Lwt_main.run (exchange (make config) "GET / HTTP/1.1\r\nbad header\r\n\r\n")) in
  Alcotest.(check (pair int string)) "not HTTP" (400, "Bad Request") (bad.status, bad.body);
  Alcotest.(check (option string)) "closed" (Some "close") (header "connection" bad);
  let secret = "secret detail 4711" in
  let output = ref "" in
  let log =
    with_stderr (fun () ->
        output := Lwt_main.run (exchange (fun _ _ -> failwith secret) "GET / HTTP/1.1\r\nHost: app.test\r\n\r\n"))
  in
  let r = one ~head:false !output in
  Alcotest.(check (pair int string)) "a leaked exception" (500, "Internal Server Error") (r.status, r.body);
  Alcotest.(check (option string)) "closed" (Some "close") (header "connection" r);
  check_true "no exception text sent" (not (contains !output secret));
  check_true ("the exception in the log: " ^ log) (contains log secret);
  let _ = Yuka.Server.config ~base:"/demo" () in
  ignore (Lwt_main.run (exchange (make config) "GET / HTTP/1.1\r\nbad header\r\n\r\n"));
  let url = Yuka.Router.url "/x" in
  ignore (Yuka.Server.config ());
  Alcotest.(check string) "a logged error keeps the base of the last config" "/demo/x" url

let connect port =
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let* () = bounded "connect" (Lwt_unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port))) in
  Lwt.return socket

let tcp port text =
  let* socket = connect port in
  let* () = write_all socket text in
  let* output = bounded "the answer" (read_all socket) in
  let* () = Lwt_unix.close socket in
  Lwt.return output

let get_over_tcp port target = tcp port ("GET " ^ target ^ " HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n")

let serve_port_0 () =
  Lwt_main.run
    (let stop, stopping = Lwt.wait () and ready, listening = Lwt.wait () in
     let server = Yuka_server.serve ~stop ~listening:(Lwt.wakeup listening) ~port:0 (make config) in
     let* port = bounded "listening" ready in
     check_true "a real port" (port > 0);
     let* output = get_over_tcp port "/feed.xml" in
     Alcotest.(check (pair int string)) "over TCP" (200, "<rss/>") (let r = one ~head:false output in (r.status, r.body));
     let host = "127.0.0.1:" ^ string_of_int port in
     let* output =
       tcp port
         (request_text ~meth:"POST"
            ~headers:
              [
                ("Host", host);
                ("Origin", "http://" ^ host);
                ("Content-Type", "application/json");
                ("Cookie", "theme=dark");
                ("Content-Length", "7");
                ("Connection", "close");
              ]
            ~body:"[1,2,3]" "/sum?tag=t")
     in
     Alcotest.(check (pair int string)) "a POST over TCP" (201, {|["6","t","dark"]|}) (let r = one ~head:false output in (r.status, r.body));
     Lwt.wakeup stopping ();
     let* () = bounded "the end of serve" server in
     let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
     let* refused =
       Lwt.catch
         (fun () -> Lwt.map (fun () -> false) (bounded "connect" (Lwt_unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port)))))
         (function Unix.Unix_error (Unix.ECONNREFUSED, _, _) -> Lwt.return true | e -> Lwt.fail e)
     in
     let* () = Lwt_unix.close socket in
     check_true "stop closes the listening socket" refused;
     Lwt.return_unit)

let bad_arguments () =
  List.iter
    (fun (label, f) ->
      match f () with
      | _ -> Alcotest.failf "%s accepted" label
      | exception Invalid_argument _ -> ())
    [
      ("a host name", fun () -> ignore (Yuka_server.serve ~interface:"localhost" (make config)));
      ("port 65536", fun () -> ignore (Yuka_server.serve ~port:65536 (make config)));
      ("port -1", fun () -> ignore (Yuka_server.serve ~port:(-1) (make config)));
      ("a write timeout of 0", fun () -> ignore (Yuka_server.serve ~write_timeout:0. (make config)));
      ("a live timeout of nan", fun () -> ignore (Yuka_server.serve ~live_timeout:Float.nan (make config)));
      ("a negative drain timeout", fun () -> ignore (Yuka_server.serve ~drain_timeout:(-1.) (make config)));
      ("no connection", fun () -> ignore (Yuka_server.serve ~max_connections:0 (make config)));
      ("no worker", fun () -> Yuka_server.run ~workers:0 config Yuka_routes.app);
      ( "a connection with a write timeout of 0",
        fun () ->
          let a, b = Lwt_unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
          Fun.protect
            ~finally:(fun () -> Unix.close (Lwt_unix.unix_file_descr a); Unix.close (Lwt_unix.unix_file_descr b))
            (fun () -> ignore (Yuka_server.connection ~write_timeout:0. (make config) (Unix.ADDR_UNIX "") b)) );
    ]

let with_server ?(handler = make config) ?max_connections f =
  Lwt_main.run
    (let stop, stopping = Lwt.wait () and ready, listening = Lwt.wait () in
     let server = Yuka_server.serve ~stop ~listening:(Lwt.wakeup listening) ~port:0 ?max_connections handler in
     let* port = bounded "listening" ready in
     Lwt.finalize
       (fun () -> f port)
       (fun () ->
         Lwt.wakeup stopping ();
         bounded "the end of serve" server))

let reset socket =
  Lwt_unix.setsockopt_optint socket Unix.SO_LINGER (Some 0);
  Lwt_unix.close socket

let reset_mid_answer () =
  with_temp_dir "yuka_huge" @@ fun dir ->
  Out_channel.with_open_bin (Filename.concat dir "huge.bin") (fun oc -> output_string oc (String.make (16 * 1024 * 1024) 'h'));
  let handler = make (Yuka.Server.config ~public:[ ("/huge", dir) ] ()) in
  App.flood_result := None;
  with_server ~handler (fun port ->
      let baseline = open_fds () in
      let reset_after target =
        let* socket = connect port in
        let* () = write_all socket ("GET " ^ target ^ " HTTP/1.1\r\nHost: app.test\r\n\r\n") in
        let* () = read_at_least socket 65536 in
        reset socket
      in
      let* () = reset_after "/huge/huge.bin" in
      let* () = reset_after "/flood" in
      let* () = wait_for "the stream producer sees the failed write" (fun () -> !App.flood_result <> None) in
      let* () = wait_for "the file and the sockets are closed" (fun () -> open_fds () <= baseline) in
      let* output = get_over_tcp port "/feed.xml" in
      check_true "still answers" (String.starts_with ~prefix:"HTTP/1.1 200" output);
      Lwt.return_unit)

let gone = Yuka.Topic.declare ~name:"gone" ~key:Yuka.Codec.string ~state:Yuka.Codec.int
let () = Yuka.Server.Live.implement gone (fun _ -> Yuka.Async.return 0)

(* Dream 1.0.0 spins at 100% CPU when it writes to a WebSocket whose client
   is gone (camlworks/dream#467). Here a client subscribes, leaves in each
   way, and the server publishes to it many times. *)
let live_publish_after_client_left () =
  let handler = make config in
  let cookie, token = session_and_token handler in
  with_server ~handler (fun port ->
      let baseline = open_fds () in
      let leave how =
        let* socket = connect port in
        let* ws, _ = bounded "the handshake" (Ws.connect socket ~host:"app.test" ~cookie:(cookie_text cookie)) in
        let* () = Ws.send ws (hello token) in
        let* _ = expect_text "hello" ws in
        let* () = Ws.send ws {|{"t":"sub","id":1,"topic":"gone","key":"k"}|} in
        let* _ = expect_text "state" ws in
        Yuka.Server.Live.publish gone "k" 1000;
        let* text = expect_text "1000" ws in
        check_true ("subscribed: " ^ text) (contains text "1000");
        (* No yield between leaving and the first publish: the server has not
           seen the client leave when it writes. *)
        let* () =
          match how with
          | `Reset ->
              let fd = Lwt_unix.unix_file_descr socket in
              Unix.setsockopt_optint fd Unix.SO_LINGER (Some 0);
              Lwt.return (Unix.close fd)
          | `Half_close -> Lwt.return (Lwt_unix.shutdown socket Unix.SHUTDOWN_SEND)
          | `Close -> Lwt.return (Unix.close (Lwt_unix.unix_file_descr socket))
        in
        let rec publish n =
          if n = 0 then Lwt.return_unit
          else begin
            Yuka.Server.Live.publish gone "k" n;
            let* () = Lwt.pause () in
            publish (n - 1)
          end
        in
        let* () = publish 500 in
        let* output = within 2. "an answer after the publishes" (get_over_tcp port "/feed.xml") in
        check_true "still answers" (String.starts_with ~prefix:"HTTP/1.1 200" output);
        match how with `Half_close -> Lwt_unix.close socket | `Reset | `Close -> Lwt.return_unit
      in
      let* () = leave `Reset in
      let* () = leave `Half_close in
      let* () = leave `Close in
      wait_for "the server closes the live sockets" (fun () -> open_fds () <= baseline))

let client_closes_first () =
  with_server (fun port ->
      let baseline = open_fds () in
      let rec many n =
        if n = 0 then Lwt.return_unit
        else
          let* socket = connect port in
          let* () =
            match n mod 3 with
            | 0 ->
                let* () = write_all socket "GET /feed.xml HTTP/1.1\r\nHost: app.test\r\n\r\n" in
                read_until socket (Buffer.create 256) "<rss/>"
            | 1 -> write_all socket "GET /feed.xml HTTP/1.1\r\nHo"
            | _ -> Lwt.return_unit
          in
          let* () = Lwt_unix.close socket in
          many (n - 1)
      in
      let* () = many 99 in
      let* () = wait_for "the server closes the sockets" (fun () -> open_fds () <= baseline) in
      let* output = get_over_tcp port "/feed.xml" in
      check_true "still answers" (String.starts_with ~prefix:"HTTP/1.1 200" output);
      Lwt.return_unit)

let connection_limit () =
  with_server ~max_connections:2 (fun port ->
      let* a = connect port in
      let* b = connect port in
      let* () = write_all b "GET /feed.xml HTTP/1.1\r\nHost: app.test\r\n\r\n" in
      let* () = read_until b (Buffer.create 256) "<rss/>" in
      let* c = connect port in
      let* () = write_all c "GET /feed.xml HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n" in
      let answer = read_all c in
      let* () = Lwt_unix.sleep 0.3 in
      check_true "no answer over the limit" (Lwt.is_sleeping answer);
      let* () = Lwt_unix.close a in
      let* output = bounded "the answer after a connection closed" answer in
      check_true "answered when a connection closed" (String.starts_with ~prefix:"HTTP/1.1 200" output);
      let* () = Lwt_unix.close b in
      Lwt_unix.close c)

let refused port =
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let* refused =
    Lwt.catch
      (fun () -> Lwt.map (fun () -> false) (bounded "connect" (Lwt_unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port)))))
      (function Unix.Unix_error (Unix.ECONNREFUSED, _, _) -> Lwt.return true | e -> Lwt.fail e)
  in
  let* () = Lwt_unix.close socket in
  Lwt.return refused

let start_gated port =
  let* busy = connect port in
  let* () = write_all busy "GET /gated HTTP/1.1\r\nHost: app.test\r\n\r\n" in
  let seen = Buffer.create 4096 in
  let* () = read_until busy seen "loading" in
  Lwt.return (busy, seen)

exception Stop_failed

let drain () =
  let gate, open_gate, _ = Yuka.Async.make () in
  App.gate := gate;
  let handler = make config in
  let cookie, token = session_and_token handler in
  Lwt_main.run
    (let stop, stopping = Lwt.wait () and ready, listening = Lwt.wait () in
     let server = Yuka_server.serve ~stop ~listening:(Lwt.wakeup listening) ~port:0 ~drain_timeout:10. handler in
     let* port = bounded "listening" ready in
     let* busy, seen = start_gated port in
     let* idle = connect port in
     let* () = write_all idle "GET /feed.xml HTTP/1.1\r\nHost: app.test\r\n\r\n" in
     let* () = read_until idle (Buffer.create 256) "<rss/>" in
     let* live = connect port in
     let* ws, _ = bounded "the handshake" (Ws.connect live ~host:"app.test" ~cookie:(cookie_text cookie)) in
     let* () = Ws.send ws (hello token) in
     let* _ = expect_text "hello" ws in
     Lwt.wakeup stopping ();
     let* f = within 3. "the close of the live socket" (Ws.receive ws) in
     Alcotest.(check string) "a live socket gets 1001" "close 1001" (Ws.show f);
     let* () = Ws.close ws 1001 in
     let* rest = within 3. "the end of an idle connection" (read_all idle) in
     Alcotest.(check string) "an idle connection is closed with no bytes" "" rest;
     let* refused = refused port in
     check_true "no new connection" refused;
     check_true "serve waits for the answer in progress" (Lwt.is_sleeping server);
     open_gate ();
     let* rest = within 3. "the end of the answer in progress" (read_all busy) in
     let r = one ~head:false (Buffer.contents seen ^ rest) in
     check_true "the answer in progress ends whole" (r.status = 200 && contains r.body "<p>gated data</p>" && String.ends_with ~suffix:"</body></html>" r.body);
     (* The clients close: each connection waits for that after its last answer. *)
     let* () = Lwt_list.iter_s Lwt_unix.close [ busy; idle; live ] in
     within 3. "the end of serve" server)

let drain_failed_stop () =
  Lwt_main.run
    (let stop, stopping = Lwt.wait () and ready, listening = Lwt.wait () in
     let server = Yuka_server.serve ~stop ~listening:(Lwt.wakeup listening) ~port:0 ~drain_timeout:10. (make config) in
     let* port = bounded "listening" ready in
     let* idle = connect port in
     let* () = write_all idle "GET /feed.xml HTTP/1.1\r\nHost: app.test\r\n\r\n" in
     let* () = read_until idle (Buffer.create 256) "<rss/>" in
     Lwt.wakeup_exn stopping Stop_failed;
     let* rest = within 3. "the end of an idle connection after a failed stop" (read_all idle) in
     Alcotest.(check string) "an idle connection is closed with no bytes" "" rest;
     let* outcome = within 3. "the end of serve" (Lwt.catch (fun () -> Lwt.map (fun () -> None) server) (fun e -> Lwt.return (Some e))) in
     check_true "serve fails with the exception of stop" (outcome = Some Stop_failed);
     Lwt_unix.close idle)

let drain_limit () =
  let gate, _, _ = Yuka.Async.make () in
  App.gate := gate;
  let elapsed =
    Lwt_main.run
      (let stop, stopping = Lwt.wait () and ready, listening = Lwt.wait () in
       let server = Yuka_server.serve ~stop ~listening:(Lwt.wakeup listening) ~port:0 ~drain_timeout:0.3 (make config) in
       let* port = bounded "listening" ready in
       let* busy, _ = start_gated port in
       let started = Unix.gettimeofday () in
       Lwt.wakeup stopping ();
       let* () = within 3. "the end of serve after the drain timeout" server in
       let elapsed = Unix.gettimeofday () -. started in
       let* _ = within 3. "the end of the answer cut by the drain timeout" (read_all busy) in
       let* () = Lwt_unix.close busy in
       Lwt.return elapsed)
  in
  App.gate := Yuka.Async.return ();
  check_true (Printf.sprintf "serve ends at the drain timeout (%.2f s)" elapsed) (elapsed >= 0.25 && elapsed < 2.)

let emfile_child () =
  let ok =
    Lwt_main.run
      (let ready, listening = Lwt.wait () in
       let _server = Yuka_server.serve ~listening:(Lwt.wakeup listening) ~port:0 (make config) in
       let* port = bounded "listening" ready in
       let rec fill acc =
         match Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 with
         | fd -> fill (fd :: acc)
         | exception Unix.Unix_error (Unix.EMFILE, _, _) -> acc
       in
       let spare = fill [] in
       Unix.close (List.hd spare);
       let* socket = connect port in
       let* () = Lwt_unix.sleep 0.5 in
       List.iter Unix.close (List.tl spare);
       let request = "GET /feed.xml HTTP/1.1\r\nHost: app.test\r\nConnection: close\r\n\r\n" in
       let* () = write_all socket request in
       let* output = bounded "the answer" (read_all socket) in
       (* Linux keeps the connection that accept could not take, and the server answers it
          once descriptors are free. macOS closes it in the failed accept, so there the
          server must answer the next connection. *)
       let* output = if output = "" then tcp port request else Lwt.return output in
       Lwt.return (String.starts_with ~prefix:"HTTP/1.1 200" output))
  in
  exit (if ok then 0 else 1)

(* A blocking waitpid that goes on after EINTR: Lwt_main.run installs a SIGCHLD
   handler, and on macOS the end of the child interrupts the waitpid. *)
let rec reap pid = match Unix.waitpid [] pid with _ -> () | exception Unix.Unix_error (Unix.EINTR, _, _) -> reap pid

let wait_child pid =
  let deadline = Unix.gettimeofday () +. bound in
  let rec wait () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.05;
        wait ()
    | 0, _ ->
        Unix.kill pid Sys.sigkill;
        reap pid;
        Alcotest.fail "the server process did not end"
    | _, status -> status
  in
  wait ()

let exited_0 = function
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n -> Alcotest.failf "the server process exited with %d" n
  | Unix.WSIGNALED n | Unix.WSTOPPED n -> Alcotest.failf "the server process got signal %d" n

let out_of_descriptors () =
  let pid =
    Unix.create_process "/bin/sh"
      [| "/bin/sh"; "-c"; "ulimit -n 64 && exec \"$0\" emfile-child"; Sys.executable_name |]
      Unix.stdin Unix.stdout Unix.stderr
  in
  exited_0 (wait_child pid)

let free_port () =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port = match Unix.getsockname s with Unix.ADDR_INET (_, port) -> port | _ -> assert false in
  Unix.close s;
  port

let connect_child port =
  let rec connect_to tries =
    let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    Unix.setsockopt_float s Unix.SO_RCVTIMEO bound;
    Unix.setsockopt_float s Unix.SO_SNDTIMEO bound;
    match Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) with
    | () -> s
    | exception Unix.Unix_error (Unix.ECONNREFUSED, _, _) when tries > 0 ->
        Unix.close s;
        Unix.sleepf 0.05;
        connect_to (tries - 1)
  in
  connect_to

let with_child pid f =
  Fun.protect
    ~finally:(fun () ->
      match Unix.waitpid [ Unix.WNOHANG ] pid with
      | 0, _ ->
          Unix.kill pid Sys.sigkill;
          reap pid
      | _ -> ()
      | exception Unix.Unix_error (Unix.ECHILD, _, _) -> ())
    f

let run_child port =
  Sys.set_signal Sys.sigpipe Sys.Signal_default;
  Yuka_server.run ~port ~sessions (Yuka.Server.config ()) Yuka_routes.app;
  exit 0

let run_stops () =
  let port = free_port () in
  let pid =
    Unix.create_process Sys.executable_name [| Sys.executable_name; "run-child"; string_of_int port |] Unix.stdin Unix.stdout
      (Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0)
  in
  let connect_to = connect_child port in
  with_child pid @@ fun () ->
  let s = connect_to 200 in
  let request = "GET /flood HTTP/1.1\r\nHost: x\r\n\r\n" in
  ignore (Unix.write_substring s request 0 (String.length request));
  let chunk = Bytes.create 4096 in
  ignore (Unix.read s chunk 0 4096);
  Unix.setsockopt_optint s Unix.SO_LINGER (Some 0);
  Unix.close s;
  Unix.sleepf 0.3;
  (match Unix.waitpid [ Unix.WNOHANG ] pid with
  | 0, _ -> ()
  | _, status -> exited_0 status; Alcotest.fail "the server ended after a client left");
  let s = connect_to 10 in
  let request = "GET /feed.xml HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n" in
  ignore (Unix.write_substring s request 0 (String.length request));
  let n = Unix.read s chunk 0 4096 in
  Unix.close s;
  check_true "still answers" (String.starts_with ~prefix:"HTTP/1.1 200" (Bytes.sub_string chunk 0 n));
  Unix.kill pid Sys.sigterm;
  exited_0 (wait_child pid)

let second_signal () =
  let port = free_port () in
  let pid =
    Unix.create_process Sys.executable_name [| Sys.executable_name; "run-child"; string_of_int port |] Unix.stdin Unix.stdout
      (Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0)
  in
  let connect_to = connect_child port in
  with_child pid @@ fun () ->
  let s = connect_to 200 in
  let request = "GET /stuck HTTP/1.1\r\nHost: x\r\n\r\n" in
  ignore (Unix.write_substring s request 0 (String.length request));
  let chunk = Bytes.create 4096 in
  ignore (Unix.read s chunk 0 4096);
  Unix.kill pid Sys.sigterm;
  Unix.sleepf 0.3;
  (match Unix.waitpid [ Unix.WNOHANG ] pid with
  | 0, _ -> ()
  | _ -> Alcotest.fail "the server ended at the first signal with a request in progress");
  let started = Unix.gettimeofday () in
  Unix.kill pid Sys.sigterm;
  let status = wait_child pid in
  Unix.close s;
  let elapsed = Unix.gettimeofday () -. started in
  check_true (Printf.sprintf "the second signal ends the process at once (%.2f s)" elapsed) (elapsed < 2.);
  match status with
  | Unix.WEXITED 1 -> ()
  | Unix.WEXITED n -> Alcotest.failf "the server process exited with %d, not 1" n
  | Unix.WSIGNALED n | Unix.WSTOPPED n -> Alcotest.failf "the server process got signal %d" n

let workers_child () =
  Sys.set_signal Sys.sigpipe Sys.Signal_default;
  Yuka_server.run ~workers:2 ~port:0
    ~listening:(fun port ->
      print_endline (string_of_int port);
      flush stdout)
    ~sessions (Yuka.Server.config ()) Yuka_routes.app;
  exit 0

let children pid =
  let file = Printf.sprintf "/proc/%d/task/%d/children" pid pid in
  if not (Sys.file_exists file) then None
  else
    let ic = open_in file in
    let line = Fun.protect ~finally:(fun () -> close_in ic) (fun () -> try input_line ic with End_of_file -> "") in
    Some (List.filter_map int_of_string_opt (String.split_on_char ' ' line))

let workers () =
  let out, into = Unix.pipe ~cloexec:true () in
  let pid =
    Unix.create_process Sys.executable_name [| Sys.executable_name; "workers-child" |] Unix.stdin into
      (Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0)
  in
  Unix.close into;
  let ic = Unix.in_channel_of_descr out in
  Fun.protect ~finally:(fun () -> close_in ic) @@ fun () ->
  with_child pid @@ fun () ->
  let port = int_of_string (input_line ic) in
  check_true "a real port" (port > 0);
  let get () =
    let s = connect_child port 0 in
    let request = "GET /feed.xml HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n" in
    ignore (Unix.write_substring s request 0 (String.length request));
    let chunk = Bytes.create 4096 in
    let n = Unix.read s chunk 0 4096 in
    Unix.close s;
    String.starts_with ~prefix:"HTTP/1.1 200" (Bytes.sub_string chunk 0 n)
  in
  check_true "every worker answers once listening is called" (List.for_all Fun.id (List.init 20 (fun _ -> get ())));
  let gone worker = match Unix.kill worker 0 with () -> false | exception Unix.Unix_error (Unix.ESRCH, _, _) -> true in
  let all_workers =
    match children pid with
    | None -> []
    | Some first ->
        Alcotest.(check int) "two worker processes" 2 (List.length first);
        Unix.sleepf 1.1;
        let killed = List.hd first in
        Unix.kill killed Sys.sigkill;
        let deadline = Unix.gettimeofday () +. bound in
        let rec replaced () =
          match children pid with
          | Some now when List.length now = 2 && not (List.mem killed now) -> now
          | _ when Unix.gettimeofday () < deadline ->
              Unix.sleepf 0.05;
              replaced ()
          | _ -> Alcotest.fail "a killed worker is not replaced"
        in
        let now = replaced () in
        check_true "the workers answer after a replacement" (List.for_all Fun.id (List.init 10 (fun _ -> get ())));
        now
  in
  Unix.kill pid Sys.sigterm;
  exited_0 (wait_child pid);
  check_true "every worker ended with the parent" (List.for_all gone all_workers)

let workers_orphaned () =
  let out, into = Unix.pipe ~cloexec:true () in
  let pid =
    Unix.create_process Sys.executable_name [| Sys.executable_name; "workers-child" |] Unix.stdin into
      (Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0)
  in
  Unix.close into;
  let ic = Unix.in_channel_of_descr out in
  Fun.protect ~finally:(fun () -> close_in ic) @@ fun () ->
  with_child pid @@ fun () ->
  ignore (int_of_string (input_line ic));
  match children pid with
  | None -> ()
  | Some workers ->
      Alcotest.(check int) "two worker processes" 2 (List.length workers);
      Unix.kill pid Sys.sigkill;
      reap pid;
      let gone worker = match Unix.kill worker 0 with () -> false | exception Unix.Unix_error (Unix.ESRCH, _, _) -> true in
      let deadline = Unix.gettimeofday () +. 5. in
      let rec wait () =
        if List.for_all gone workers then ()
        else if Unix.gettimeofday () < deadline then begin
          Unix.sleepf 0.05;
          wait ()
        end
        else begin
          List.iter (fun w -> try Unix.kill w Sys.sigkill with Unix.Unix_error _ -> ()) workers;
          Alcotest.fail "the workers serve on after their parent was killed"
        end
      in
      wait ()

let serve_failures () =
  Lwt_main.run
    (let taken = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
     let* () = Lwt_unix.bind taken (Unix.ADDR_INET (Unix.inet_addr_loopback, 0)) in
     Lwt_unix.listen taken 1;
     let port = match Lwt_unix.getsockname taken with Unix.ADDR_INET (_, p) -> p | _ -> assert false in
     let before = open_fds () in
     let* result =
       Lwt.catch
         (fun () -> Lwt.map (fun () -> None) (bounded "serve" (Yuka_server.serve ~port (make config))))
         (fun e -> Lwt.return (Some e))
     in
     (match result with
     | Some (Unix.Unix_error (Unix.EADDRINUSE, _, _)) -> ()
     | Some e -> Alcotest.failf "serve on a taken port: %s" (Printexc.to_string e)
     | None -> Alcotest.fail "serve on a taken port returned");
     Alcotest.(check int) "a port in use leaves no descriptor" before (open_fds ());
     let* () = Lwt_unix.close taken in
     let before = open_fds () in
     let ready, listening = Lwt.wait () in
     let* result =
       Lwt.catch
         (fun () ->
           Lwt.map (fun () -> None)
             (bounded "serve" (Yuka_server.serve ~stop:(Lwt.fail Stop_failed) ~listening:(Lwt.wakeup listening) ~port:0 (make config))))
         (fun e -> Lwt.return (Some e))
     in
     (match result with
     | Some Stop_failed -> ()
     | Some e -> Alcotest.failf "a failed stop: %s" (Printexc.to_string e)
     | None -> Alcotest.fail "a failed stop: serve returned");
     let* port = ready in
     let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
     let* refused =
       Lwt.catch
         (fun () -> Lwt.map (fun () -> false) (bounded "connect" (Lwt_unix.connect socket (Unix.ADDR_INET (Unix.inet_addr_loopback, port)))))
         (function Unix.Unix_error (Unix.ECONNREFUSED, _, _) -> Lwt.return true | e -> Lwt.fail e)
     in
     let* () = Lwt_unix.close socket in
     check_true "a failed stop closes the listening socket" refused;
     Alcotest.(check int) "a failed stop leaves no descriptor" before (open_fds ());
     Lwt.return_unit)

let () =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  (match Array.to_list Sys.argv with
  | [ _; "emfile-child" ] -> emfile_child ()
  | [ _; "run-child"; port ] -> run_child (int_of_string port)
  | [ _; "workers-child" ] -> workers_child ()
  | _ -> ());
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "yuka-server"
    [
      ( "cycle",
        [
          case "prerendered files, a query, the 404 page" serve;
          case "HEAD" head;
          case "HEAD then GET, two GETs on one connection" one_connection;
          case "a PATCH endpoint" patch;
          case "YUKA_DEV=1 does not turn on dev mode" dev_env_ignored;
          case "the shell is sent before the await settles" streamed;
          case "a stream to HTTP/1.0" http_1_0;
          case "the timeout fills a stuck await" timeout;
          case "a client that leaves fails the next write" client_leaves;
          case "Yuka_server.request" ache_request;
          case "a handler reads the request" handler_reads_the_request;
        ] );
      ("files", [ case "public files" files; case "no path out of the directory" no_escape ]);
      ( "body",
        [
          case "the body limit" body_limit;
          case "Expect: 100-continue" expect_continue;
          case "a refused body is skipped by its framing" refused_body_framing;
          case "an unread body is not a next request" unread_body;
          case "a cut chunked body does not run the action" cut_chunked_body;
          case "ambiguous body lengths are refused" smuggling;
          case "two Host fields are refused" doubled_host;
          case "a long header" long_header;
        ] );
      ( "framing",
        [
          case "no body bytes for HEAD, 204 and 304" bodyless;
          case "the server sets the framing headers" framing_headers;
          case "an answer ache cannot send is a 500" invalid_answers;
        ] );
      ( "log",
        [
          case "Console reaches the log" log;
          case "one line per request" request_log;
          case "failures after the head reach the config log" failure_logs;
          case "error lines have no query" no_query_in_error_logs;
          case "a log that raises" raising_log;
        ] );
      ( "session",
        [
          case "the first answer sets the cookie, a valid cookie gets none" csrf_cookies;
          case "bad cookies give a new session" bad_cookies;
          case "no sessions" no_sessions;
          case "secure cookies" secure;
          case "signed cookies" signed_cookies;
          case "a short secret is refused" short_secret;
          case "renewal and expiry" lifetime;
          case "renewal stops at the absolute limit" absolute_limit;
        ] );
      ( "live",
        [
          case "hello, pings and close" live_round_trip;
          case "a token is bound to its session" live_refused;
          case "a message over the limit" live_limit;
          case "a client that stops reading is closed" live_client_stops_reading;
          case "a silent client is closed" live_silent;
        ] );
      ( "server",
        [
          case "the error handler sends no exception text" error_handler;
          case "serve over TCP on port 0" serve_port_0;
          case "bad arguments" bad_arguments;
          case "serve fails without leaks" serve_failures;
          case "out of file descriptors" out_of_descriptors;
          case "a reset during an answer" reset_mid_answer;
          case "clients that close first" client_closes_first;
          case "a publish to a client that left" live_publish_after_client_left;
          case "run until SIGTERM" run_stops;
          case "a second signal exits at once" second_signal;
          case "run with two workers on port 0" workers;
          case "the workers end when their parent is killed" workers_orphaned;
          case "a client that never reads is closed" never_reads;
          case "a slow reader gets the whole answer" slow_reader;
          case "the connection limit" connection_limit;
          case "the drain lets answers in progress end" drain;
          case "the drain stops at its timeout" drain_limit;
          case "a failed stop drains" drain_failed_stop;
        ] );
    ]
