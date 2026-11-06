let page_cases =
  let open Alcotest in
  let page () =
    let html =
      Yuka_server.page ~title:"A & B" ~styles:[ "/a.css" ] ~scripts:[ "/m.js" ]
        (fun () -> Yuka.lower "p" [] [ Yuka.text "hi" ])
    in
    check string "document"
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>A &amp; B</title><link rel=\"stylesheet\" href=\"/a.css\"><script type=\"module\" src=\"/m.js\"></script></head><body><p>hi</p></body></html>"
      html
  in
  let to_string () =
    check string "element" "<p>a<!---->b</p>"
      (Yuka_server.to_string
         (fun () -> Yuka.lower "p" [] [ Yuka.text "a"; Yuka.text "b" ]))
  in
  let respond () =
    let res =
      Lwt_main.run
        (Yuka_server.respond ~status:`Not_Found (fun () -> Yuka.text "x"))
    in
    check int "status" 404 (Dream.status_to_int (Dream.status res));
    check string "body"
      ("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title></title>"
      ^ Yuka_server.fill_script ^ "</head><body>x</body></html>")
      (Lwt_main.run (Dream.body res))
  in
  let component_effect () =
    let runs = ref 0 in
    let component () =
      Yuka.Effect.run (fun () -> incr runs);
      Yuka.lower "p" [] []
    in
    check string "html" "<p></p>" (Yuka_server.to_string component);
    check int "effect not run" 0 !runs
  in
  [ test_case "component effect" `Quick component_effect; test_case "page" `Quick page; test_case "to_string" `Quick to_string;
    test_case "respond" `Quick respond ]

type issue = { title : string; n : int }

let issue_codec : issue Yuka.Codec.t =
  {
    encode =
      (fun i -> `Assoc [ ("title", `String i.title); ("n", `Int i.n) ]);
    decode =
      (function
      | `Assoc [ ("title", `String title); ("n", `Int n) ] -> Ok { title; n }
      | _ -> Error "bad issue");
  }

let create =
  Yuka.Action.declare ~name:"create" ~input:issue_codec ~output:issue_codec

let broken =
  Yuka.Action.declare ~name:"broken" ~input:Yuka.Codec.int
    ~output:Yuka.Codec.int

let failing =
  Yuka.Action.declare ~name:"failing" ~input:Yuka.Codec.int
    ~output:Yuka.Codec.int

let () =
  Yuka_server.Action.implement create (fun i ->
      Lwt.return { i with n = i.n + 1 });
  Yuka_server.Action.implement broken (fun _ -> failwith "secret detail");
  Yuka_server.Action.implement failing (fun _ -> Lwt.fail_with "secret promise")

let handler = Dream.router [ Yuka_server.route ]

let post ?(headers = [ ("Content-Type", "application/json"); ("Host", "x.test") ])
    name body =
  let req =
    Dream.request ~method_:`POST ~target:("/_yuka/action/" ^ name) ~headers body
  in
  let res = Dream.test handler req in
  (Dream.status_to_int (Dream.status res), Lwt_main.run (Dream.body res))

let action_cases =
  let open Alcotest in
  let reply = pair int string in
  let happy () =
    check reply "ok" (200, "{\"ok\":{\"title\":\"a\",\"n\":2}}")
      (post "create" "{\"title\":\"a\",\"n\":1}")
  in
  let bad_json () =
    let status, body = post "create" "{oops" in
    check int "status" 400 status;
    check bool "says JSON" true (String.length body > 0 && String.sub body 0 18 = "{\"error\":\"invalid ")
  in
  let bad_input () =
    let status, body = post "create" "{\"title\":1}" in
    check int "status" 400 status;
    check string "message" "{\"error\":\"invalid input: bad issue\"}" body
  in
  let unknown () =
    check reply "404" (404, "{\"error\":\"unknown action nope\"}") (post "nope" "1")
  in
  let content_type () =
    let status, _ = post ~headers:[ ("Content-Type", "text/plain") ] "broken" "1" in
    check int "415" 415 status;
    let status, _ = post ~headers:[] "broken" "1" in
    check int "415 without header" 415 status;
    let status, _ =
      post ~headers:[ ("Content-Type", "Application/JSON; charset=utf-8") ] "create"
        "{\"title\":\"a\",\"n\":1}"
    in
    check int "parameters allowed" 200 status
  in
  let origin () =
    let h origin =
      [ ("Content-Type", "application/json"); ("Host", "x.test"); ("Origin", origin) ]
    in
    let json = "{\"title\":\"a\",\"n\":1}" in
    check int "other site" 403 (fst (post ~headers:(h "https://evil.test") "create" json));
    check int "other port" 403 (fst (post ~headers:(h "http://x.test:81") "create" json));
    check int "same" 200 (fst (post ~headers:(h "https://x.test") "create" json));
    check int "no host" 403
      (fst
         (post
            ~headers:[ ("Content-Type", "application/json"); ("Origin", "https://x.test") ]
            "create" json))
  in
  let generic_500 () =
    check reply "raised" (500, "{\"error\":\"action failed\"}") (post "broken" "1");
    check reply "failed promise" (500, "{\"error\":\"action failed\"}") (post "failing" "1")
  in
  let twice () =
    check bool "raises" true
      (match Yuka_server.Action.implement create (fun i -> Lwt.return i) with
      | () -> false
      | exception Invalid_argument _ -> true)
  in
  let direct_call () =
    let status = Yuka.Async.status (Yuka.Action.call create { title = "t"; n = 5 }) in
    check string "resolved" "t 6"
      (match status with
      | Yuka.Async.Done i -> i.title ^ " " ^ string_of_int i.n
      | _ -> "other");
    check string "implementation failure" "failed"
      (match Yuka.Async.status (Yuka.Action.call broken 1) with
      | Yuka.Async.Failed _ -> "failed"
      | _ -> "other");
    let late = Yuka.Action.declare ~name:"late" ~input:Yuka.Codec.int ~output:Yuka.Codec.int in
    Yuka_server.Action.implement late (fun n -> Lwt.map (fun () -> n) (Lwt.pause ()));
    let async = Yuka.Action.call late 3 in
    check string "pending" "pending"
      (match Yuka.Async.status async with Pending -> "pending" | _ -> "other");
    Lwt_main.run (Lwt.pause ());
    check string "settles" "3"
      (match Yuka.Async.status async with Done n -> string_of_int n | _ -> "other")
  in
  [ test_case "happy path" `Quick happy; test_case "bad JSON" `Quick bad_json;
    test_case "bad input" `Quick bad_input; test_case "unknown action" `Quick unknown;
    test_case "content type" `Quick content_type; test_case "origin" `Quick origin;
    test_case "generic 500" `Quick generic_500;
    test_case "implement twice" `Quick twice;
    test_case "server-side call" `Quick direct_call ]

let contains text part =
  let n = String.length part in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = part || at (i + 1))
  in
  at 0

let recorder () =
  let chunks = ref [] in
  ((fun c -> chunks := c :: !chunks; Lwt.return_unit), fun () -> List.rev !chunks)

let pause () = Lwt_main.run (Lwt.pause ())

let text_await ?failed a name =
  Yuka.await ?failed a ~loading:(Yuka.text ("L" ^ name)) (fun n ->
      Yuka.text (name ^ string_of_int n))

let fill id html =
  Printf.sprintf
    "<template data-yuka-fill=\"%s\">%s</template><script>__yukaFill(\"%s\")</script>"
    id html id

let stream_cases =
  let open Alcotest in
  let list_of = list string in
  let state p = match Lwt.state p with Lwt.Sleep -> "running" | _ -> "done" in
  let shell_and_order () =
    let a, resolve_a, _ = Yuka.Async.make () in
    let b, resolve_b, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka_server.stream ~title:"T"
        (fun () ->
          Yuka.lower "div" [] [ text_await a "a"; text_await b "b" ])
        write
    in
    pause ();
    (match chunks () with
    | [ head; shell ] ->
        check bool "head" true
          (String.length head > 15
          && String.sub head 0 15 = "<!DOCTYPE html>"
          && contains head Yuka_server.fill_script);
        check string "shell"
          "<div><!--[s1-->La<!--]--><!--[s2-->Lb<!--]--></div>" shell
    | l -> failf "expected 2 chunks, got %d" (List.length l));
    check string "running" "running" (state p);
    resolve_b 2;
    pause ();
    check int "one fill" 3 (List.length (chunks ()));
    check string "still running" "running" (state p);
    resolve_a 1;
    Lwt_main.run p;
    check list_of "fills in settle order"
      [ fill "s2" "b2"; fill "s1" "a1"; "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()))
  in
  let settled_inline () =
    let write, chunks = recorder () in
    Lwt_main.run
      (Yuka_server.stream
         (fun () -> text_await (Yuka.Async.resolved 7) "a")
         write);
    check list_of "no fill"
      [ "<!--[-->a7<!--]-->"; "</body></html>" ]
      (List.tl (chunks ()))
  in
  let nested () =
    let outer, resolve_outer, _ = Yuka.Async.make () in
    let inner, resolve_inner, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka_server.stream
        (fun () ->
          Yuka.await outer ~loading:(Yuka.text "Lo") (fun n ->
              Yuka.lower "p" []
                [ Yuka.text (string_of_int n); text_await inner "i" ]))
        write
    in
    pause ();
    resolve_outer 1;
    pause ();
    check string "still running" "running" (state p);
    resolve_inner 2;
    Lwt_main.run p;
    check list_of "chunks"
      [ "<!--[s1-->Lo<!--]-->";
        fill "s1" "<p>1<!--[s2-->Li<!--]--></p>";
        fill "s2" "i2";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let failure () =
    let a, _, fail_a = Yuka.Async.make () in
    let b, _, fail_b = Yuka.Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka_server.stream
        (fun () ->
          Yuka.fragment
            [ text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) a "a";
              text_await b "b" ])
        write
    in
    fail_b "x";
    fail_a "boom";
    Lwt_main.run p;
    check list_of "failure chunks"
      [ "<!--[s1-->La<!--]--><!--[s2-->Lb<!--]-->";
        fill "s2" "";
        fill "s1" "E:boom";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let island a =
    Yuka.Client.island ~name:"I"
      ~props:(Yuka.Codec.encode (Yuka.Codec.async Yuka.Codec.int) a)
      (fun () -> Yuka.text "")
  in
  let async_prop () =
    let a, resolve, _ = Yuka.Async.make () in
    let b, _, fail_b = Yuka.Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka_server.stream
        (fun () ->
          let ia = island a in
          let ib = island b in
          Yuka.fragment [ ia; ib ])
        write
    in
    pause ();
    check string "shell"
      "<yuka-island data-name=\"I\" data-id=\"i1\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"i1\">{\"$async\":\"a1\"}</script><yuka-island data-name=\"I\" data-id=\"i2\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"i2\">{\"$async\":\"a2\"}</script>"
      (List.nth (chunks ()) 1);
    fail_b "no";
    resolve 5;
    Lwt_main.run p;
    check list_of "values"
      [ "<script type=\"application/json\" data-yuka-async=\"a2\">{\"error\":\"no\"}</script>";
        "<script type=\"application/json\" data-yuka-async=\"a1\">{\"ok\":5}</script>";
        "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()))
  in
  let async_in_fill () =
    let outer, resolve_outer, _ = Yuka.Async.make () in
    let value, resolve_value, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka_server.stream
        (fun () ->
          Yuka.await outer ~loading:Yuka.empty (fun _ -> island value))
        write
    in
    resolve_outer 0;
    pause ();
    resolve_value 9;
    Lwt_main.run p;
    check list_of "async registered in a fill"
      [ fill "s1"
          "<yuka-island data-name=\"I\" data-id=\"i1\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"i1\">{\"$async\":\"a1\"}</script>";
        "<script type=\"application/json\" data-yuka-async=\"a1\">{\"ok\":9}</script>";
        "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()))
  in
  let to_string_sync () =
    let pending, _, _ = Yuka.Async.make () in
    check string "pending prints loading" "<!--[-->La<!--]-->"
      (Yuka_server.to_string (fun () -> text_await pending "a"));
    check string "settled prints value" "<!--[-->a1<!--]-->"
      (Yuka_server.to_string (fun () -> text_await (Yuka.Async.resolved 1) "a"));
    check string "failed prints nothing" "<!--[--><!--]-->"
      (Yuka_server.to_string (fun () ->
           text_await (Yuka.Async.failed "x") "a"));
    let props el = Yuka_server.to_string el in
    check bool "settled prop inline" true
      (contains (props (fun () -> island (Yuka.Async.resolved 3)))
         "{\"$async\":\"a1\",\"ok\":3}");
    check bool "pending prop is an error" true
      (contains (props (fun () -> island pending))
         "{\"$async\":\"a1\",\"error\":\"pending at render\"}")
  in
  let await_node_kinds () =
    check string "await in page" "<!--[-->L<!--]-->"
      (Yuka_server.to_string (fun () ->
           let a, _, _ = Yuka.Async.make () in
           Yuka.await a ~loading:(Yuka.text "L") (fun () -> Yuka.text "x")))
  in
  let codec_async () =
    let codec = Yuka.Codec.async Yuka.Codec.int in
    let decode j = match Yuka.Codec.decode codec j with Ok a -> Yuka.Async.status a | Error m -> Yuka.Async.Failed ("decode:" ^ m) in
    let show = function Yuka.Async.Done n -> "done " ^ string_of_int n | Failed m -> "failed " ^ m | Pending -> "pending" in
    check string "ok" "done 4"
      (show (decode (`Assoc [ ("$async", `String "a1"); ("ok", `Int 4) ])));
    check string "error" "failed e"
      (show (decode (`Assoc [ ("$async", `String "a1"); ("error", `String "e") ])));
    check string "bad ok" "failed expected int, got \"x\""
      (show (decode (`Assoc [ ("$async", `String "a1"); ("ok", `String "x") ])));
    check string "not a reference" "failed decode:expected async reference, got 1"
      (show (decode (`Int 1)));
    let saved = !Yuka.Internal.async_source in
    let a, resolve, _ = Yuka.Async.make () in
    Yuka.Internal.async_source := (fun id -> if id = "a9" then Yuka.Async.map (fun n -> `Int n) a else Yuka.Async.failed "unknown");
    let r = decode (`Assoc [ ("$async", `String "a9") ]) in
    check string "bare reference waits" "pending" (show r);
    resolve 4;
    check string "bare reference resolves" "done 4" (show (Yuka.Async.status (match Yuka.Codec.decode codec (`Assoc [ ("$async", `String "a9") ]) with Ok a -> a | Error _ -> Yuka.Async.failed "x")));
    Yuka.Internal.async_source := saved
  in
  let respond_streams () =
    let a, resolve, _ = Yuka.Async.make () in
    let res = Lwt_main.run (Yuka_server.respond (fun () -> text_await a "a")) in
    ignore (Lwt.async (fun () -> Lwt.map (fun () -> resolve 1) (Lwt.pause ())));
    let body = Lwt_main.run (Dream.body res) in
    check bool "has the fill" true (contains body (fill "s1" "a1"));
    check bool "ends" true (contains body "</body></html>")
  in
  [ test_case "shell then fills in settle order" `Quick shell_and_order;
    test_case "settled value is inline" `Quick settled_inline;
    test_case "nested await" `Quick nested;
    test_case "failure" `Quick failure;
    test_case "async props" `Quick async_prop;
    test_case "async prop inside a fill" `Quick async_in_fill;
    test_case "to_string" `Quick to_string_sync;
    test_case "await prints a hole" `Quick await_node_kinds;
    test_case "Codec.async decode" `Quick codec_async;
    test_case "respond streams" `Quick respond_streams ]

let body_limit_cases =
  let open Alcotest in
  let limit = 1_048_576 in
  let json_body size = Printf.sprintf "{\"title\":\"%s\",\"n\":1}" (String.make (size - 18) 'x') in
  let headers = [ ("Content-Type", "application/json"); ("Host", "x.test") ] in
  let at_limit () =
    check int "exactly the limit" 200 (fst (post ~headers "create" (json_body limit)))
  in
  let over_without_length () =
    check
      (pair int string)
      "over the limit" (413, "{\"error\":\"request too large\"}")
      (post ~headers "create" (json_body (limit + 1)))
  in
  let over_with_length () =
    check
      (pair int string)
      "declared length" (413, "{\"error\":\"request too large\"}")
      (post
         ~headers:(("Content-Length", string_of_int (limit + 1)) :: headers)
         "create" "{}")
  in
  [ test_case "at the limit" `Quick at_limit;
    test_case "over the limit" `Quick over_without_length;
    test_case "over the limit by Content-Length" `Quick over_with_length ]

let page_extra_cases =
  let open Alcotest in
  let page_head () =
    let html =
      Yuka_server.page ~head:"<meta name=\"x\" content=\"y\">"
        ~import_map:[ ("yuka/", "/js/node_modules/yuka/"); ("m<", "/m") ]
        ~title:"T" ~styles:[ "/a.css" ] ~scripts:[ "/m.js" ]
        (fun () -> Yuka.text "x")
    in
    check string "head content"
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>T</title><script type=\"importmap\">{\"imports\":{\"yuka/\":\"/js/node_modules/yuka/\",\"m\\u003c\":\"/m\"}}</script><meta name=\"x\" content=\"y\"><link rel=\"stylesheet\" href=\"/a.css\"><script type=\"module\" src=\"/m.js\"></script></head><body>x</body></html>"
      html
  in
  let no_import_map () =
    check bool "no importmap by default" false
      (contains (Yuka_server.page (fun () -> Yuka.text "x")) "importmap")
  in
  let stream_head () =
    let write, chunks = recorder () in
    Lwt_main.run
      (Yuka_server.stream ~head:"<b></b>" ~import_map:[ ("p/", "/p/") ]
         ~scripts:[ "/m.js" ]
         (fun () -> Yuka.text "x")
         write);
    let head = List.hd (chunks ()) in
    let index part =
      let n = String.length part in
      let rec at i =
        if i + n > String.length head then -1
        else if String.sub head i n = part then i
        else at (i + 1)
      in
      at 0
    in
    check bool "import map first" true
      (index "importmap" >= 0
      && index "importmap" < index "__yukaFill"
      && index "importmap" < index "<b></b>"
      && index "importmap" < index "type=\"module\"");
    check bool "raw head kept" true (index "<b></b>" >= 0)
  in
  let respond_head () =
    let res =
      Lwt_main.run
        (Yuka_server.respond ~head:"<i></i>" ~import_map:[ ("p/", "/p/") ]
           (fun () -> Yuka.text "x"))
    in
    let body = Lwt_main.run (Dream.body res) in
    check bool "head and map" true
      (contains body "<i></i>" && contains body "\"p/\":\"/p/\"")
  in
  let map_of_dir () =
    let root = Filename.temp_file "yuka" "" in
    Sys.remove root;
    Sys.mkdir root 0o755;
    let nm = Filename.concat root "node_modules" in
    Sys.mkdir nm 0o755;
    List.iter (fun d -> Sys.mkdir (Filename.concat nm d) 0o755)
      [ "yuka.client"; "melange"; ".bin"; "@scope" ];
    Sys.mkdir (Filename.concat (Filename.concat nm "@scope") "pkg") 0o755;
    close_out (open_out (Filename.concat nm "file.txt"));
    check (list (pair string string)) "packages"
      [ ("@scope/pkg/", "/static/js/node_modules/@scope/pkg/");
        ("melange/", "/static/js/node_modules/melange/");
        ("yuka.client/", "/static/js/node_modules/yuka.client/") ]
      (Yuka_server.import_map ~url:"/static/js/" ~dir:root);
    check (list (pair string string)) "missing dir" []
      (Yuka_server.import_map ~url:"/x" ~dir:(Filename.concat root "nope"))
  in
  [ test_case "page head and import map" `Quick page_head;
    test_case "no import map by default" `Quick no_import_map;
    test_case "stream head order" `Quick stream_head;
    test_case "respond head" `Quick respond_head;
    test_case "import_map of a directory" `Quick map_of_dir ]

let reject_cases =
  let open Alcotest in
  let rejecting =
    Yuka.Action.declare ~name:"rejecting" ~input:Yuka.Codec.int
      ~output:Yuka.Codec.int
  in
  let rejecting_late =
    Yuka.Action.declare ~name:"rejecting_late" ~input:Yuka.Codec.int
      ~output:Yuka.Codec.int
  in
  Yuka_server.Action.implement rejecting (fun _ ->
      Yuka_server.Action.reject "title is empty");
  Yuka_server.Action.implement rejecting_late (fun _ ->
      Lwt.bind (Lwt.pause ()) (fun () -> Yuka_server.Action.reject "too late"));
  let route () =
    check (pair int string) "400 with the message"
      (400, "{\"error\":\"title is empty\"}")
      (post "rejecting" "1");
    check (pair int string) "after a wait"
      (400, "{\"error\":\"too late\"}")
      (post "rejecting_late" "1")
  in
  let ordinary () =
    let status, body = post "broken" "1" in
    check int "500" 500 status;
    check bool "message not sent" false (contains body "secret detail");
    let _, body = post "rejecting" "1" in
    check bool "reject message sent" true (contains body "title is empty")
  in
  let direct () =
    let show = function
      | Yuka.Async.Failed m -> "failed " ^ m
      | _ -> "other"
    in
    check string "server-side call" "failed title is empty"
      (show (Yuka.Async.status (Yuka.Action.call rejecting 1)))
  in
  [ test_case "route answers 400" `Quick route;
    test_case "ordinary exceptions stay 500" `Quick ordinary;
    test_case "server-side call fails" `Quick direct ]

let timeout_cases =
  let open Alcotest in
  let list_of = list string in
  let island a =
    Yuka.Client.island ~name:"I"
      ~props:(Yuka.Codec.encode (Yuka.Codec.async Yuka.Codec.int) a)
      (fun () -> Yuka.text "")
  in
  let never_settles () =
    let a, _, _ = Yuka.Async.make () in
    let b, _, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    Lwt_main.run
      (Yuka_server.stream ~timeout:0.05
         (fun () ->
           let prop = island b in
           Yuka.fragment
             [ prop;
               text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) a "a" ])
         write);
    check list_of "timeout chunks"
      [ "<yuka-island data-name=\"I\" data-id=\"i1\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"i1\">{\"$async\":\"a1\"}</script><!--[s1-->La<!--]-->";
        "<script type=\"application/json\" data-yuka-async=\"a1\">{\"error\":\"timeout\"}</script>";
        fill "s1" "E:timeout";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let nested_after_timeout () =
    let outer, resolve, _ = Yuka.Async.make () in
    let inner, _, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    Lwt_main.run
      (let p =
         Yuka_server.stream ~timeout:0.05
           (fun () ->
             Yuka.await outer ~loading:(Yuka.text "Lo") (fun _ ->
                 text_await inner "i"))
           write
       in
       resolve 1;
       p);
    check list_of "inner times out too"
      [ "<!--[s1-->Lo<!--]-->";
        fill "s1" "<!--[s2-->Li<!--]-->";
        fill "s2" "";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let failed_element_has_await () =
    let outer, _, _ = Yuka.Async.make () in
    let inner, _, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    Lwt_main.run
      (Yuka_server.stream ~timeout:0.05
         (fun () ->
           Yuka.await outer
             ~failed:(fun _ -> text_await inner "i")
             ~loading:(Yuka.text "Lo")
             (fun _ -> Yuka.empty))
         write);
    check list_of "await in the failed element is timed out too"
      [ "<!--[s1-->Lo<!--]-->";
        fill "s1" "<!--[s2-->Li<!--]-->";
        fill "s2" "";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let late_value_ignored () =
    let a, resolve, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    Lwt_main.run
      (Yuka_server.stream ~timeout:0.02 (fun () -> text_await a "a") write);
    resolve 1;
    pause ();
    check int "nothing after the end" 4 (List.length (chunks ()))
  in
  let settled_in_time () =
    let a, resolve, _ = Yuka.Async.make () in
    let write, chunks = recorder () in
    let p = Yuka_server.stream ~timeout:5. (fun () -> text_await a "a") write in
    resolve 1;
    Lwt_main.run p;
    check list_of "no timeout fill"
      [ "<!--[s1-->La<!--]-->"; fill "s1" "a1"; "</body></html>" ]
      (List.tl (chunks ()))
  in
  let script_in_core () =
    check string "same script" Yuka.Internal.fill_script Yuka_server.fill_script;
    check bool "is a script" true
      (contains Yuka.Internal.fill_script "window.__yukaFill=")
  in
  [ test_case "never-settling values time out" `Quick never_settles;
    test_case "nested await after a timeout" `Quick nested_after_timeout;
    test_case "await in a failed element" `Quick failed_element_has_await;
    test_case "late value is ignored" `Quick late_value_ignored;
    test_case "value in time" `Quick settled_in_time;
    test_case "fill script lives in the core" `Quick script_in_core ]

let of_lwt_cases =
  let open Alcotest in
  let show = function
    | Yuka.Async.Pending -> "pending"
    | Yuka.Async.Done n -> "done " ^ string_of_int n
    | Yuka.Async.Failed m -> "failed " ^ m
  in
  let captured f =
    let messages = ref [] in
    let reporter =
      {
        Logs.report =
          (fun _ _ ~over k msgf ->
            msgf (fun ?header:_ ?tags:_ fmt ->
                Format.kasprintf
                  (fun m ->
                    messages := m :: !messages;
                    over ();
                    k ())
                  fmt));
      }
    in
    let saved = Logs.reporter () in
    Logs.set_reporter reporter;
    let result = (try f () with e -> Logs.set_reporter saved; raise e) in
    Logs.set_reporter saved;
    (result, List.rev !messages)
  in
  let resolved () =
    check string "done" "done 3"
      (show (Yuka.Async.status (Yuka_server.Async.of_lwt (Lwt.return 3))))
  in
  let later () =
    let promise, wake = Lwt.wait () in
    let a = Yuka_server.Async.of_lwt promise in
    check string "pending" "pending" (show (Yuka.Async.status a));
    Lwt.wakeup wake 4;
    check string "done" "done 4" (show (Yuka.Async.status a))
  in
  let rejected () =
    let status, messages =
      captured (fun () ->
          let promise, wake = Lwt.wait () in
          let a = Yuka_server.Async.of_lwt promise in
          Lwt.wakeup_exn wake (Failure "secret detail");
          Yuka.Async.status a)
    in
    check string "generic message" "failed failed" (show status);
    check bool "logged with the detail" true
      (List.exists (fun m -> contains m "secret detail") messages);
    let status, _ = captured (fun () -> Yuka.Async.status (Yuka_server.Async.of_lwt (Lwt.fail_with "other secret"))) in
    check string "already rejected" "failed failed" (show status)
  in
  [ test_case "resolved" `Quick resolved;
    test_case "resolved later" `Quick later;
    test_case "rejected" `Quick rejected ]

let settled_cases =
  let open Alcotest in
  let later resolve v =
    Lwt.async (fun () -> Lwt.map (fun () -> resolve v) (Lwt.pause ()))
  in
  let simple () =
    let a, resolve_a, _ = Yuka.Async.make () in
    let b, resolve_b, _ = Yuka.Async.make () in
    later resolve_b 2;
    later resolve_a 1;
    check string "values in place"
      "<div><!--[-->a1<!--]--><!--[-->b2<!--]--></div>"
      (Lwt_main.run
         (Yuka_server.render_settled (fun () ->
              Yuka.lower "div" [] [ text_await a "a"; text_await b "b" ])))
  in
  let nested () =
    let outer, resolve_outer, _ = Yuka.Async.make () in
    let inner, resolve_inner, _ = Yuka.Async.make () in
    later resolve_outer 1;
    later resolve_inner 2;
    check string "nested in place"
      "<!--[--><p>1<!--[-->i2<!--]--></p><!--]-->"
      (Lwt_main.run
         (Yuka_server.render_settled (fun () ->
              Yuka.await outer ~loading:(Yuka.text "Lo") (fun n ->
                  Yuka.lower "p" []
                    [ Yuka.text (string_of_int n); text_await inner "i" ]))))
  in
  let loading_has_markers () =
    let outer, resolve_outer, _ = Yuka.Async.make () in
    let inner, _, _ = Yuka.Async.make () in
    later resolve_outer 1;
    check string "markers inside the replaced part are skipped" "<!--[-->o1<!--]-->"
      (Lwt_main.run
         (Yuka_server.render_settled ~timeout:0.1 (fun () ->
              Yuka.await outer
                ~loading:(Yuka.fragment [ text_await inner "i"; Yuka.text "x" ])
                (fun n -> Yuka.text ("o" ^ string_of_int n)))))
  in
  let async_prop () =
    let value, resolve, _ = Yuka.Async.make () in
    let failing, _, fail = Yuka.Async.make () in
    later resolve 5;
    later fail "no";
    let island a =
      Yuka.Client.island ~name:"I"
        ~props:(Yuka.Codec.encode (Yuka.Codec.async Yuka.Codec.int) a)
        (fun () -> Yuka.text "")
    in
    check string "values after the document"
      ("<yuka-island data-name=\"I\" data-id=\"i1\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"i1\">{\"$async\":\"a1\"}</script>"
      ^ "<yuka-island data-name=\"I\" data-id=\"i2\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"i2\">{\"$async\":\"a2\"}</script>"
      ^ "<script type=\"application/json\" data-yuka-async=\"a1\">{\"ok\":5}</script>"
      ^ "<script type=\"application/json\" data-yuka-async=\"a2\">{\"error\":\"no\"}</script>")
      (Lwt_main.run
         (Yuka_server.render_settled (fun () ->
              let first = island value in
              let second = island failing in
              Yuka.fragment [ first; second ])))
  in
  let nothing_pending () =
    check string "same as to_string" "<p>x</p>"
      (Lwt_main.run
         (Yuka_server.render_settled (fun () ->
              Yuka.lower "p" [] [ Yuka.text "x" ])))
  in
  let failure_and_timeout () =
    let a, _, fail_a = Yuka.Async.make () in
    let never, _, _ = Yuka.Async.make () in
    later fail_a "x";
    check string "failed and timed out"
      "<!--[-->E:x<!--]--><!--[-->E:timeout<!--]-->"
      (Lwt_main.run
         (Yuka_server.render_settled ~timeout:0.05 (fun () ->
              let first = text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) a "a" in
              let second = text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) never "b" in
              Yuka.fragment [ first; second ])))
  in
  let text_inside_hole () =
    let a, resolve, _ = Yuka.Async.make () in
    later resolve 1;
    check string "text neighbours keep their separators"
      "<p>t<!--[-->a1<!--]-->u</p>"
      (Lwt_main.run
         (Yuka_server.render_settled (fun () ->
              Yuka.lower "p" []
                [ Yuka.text "t"; text_await a "a"; Yuka.text "u" ])))
  in
  [ test_case "values in place" `Quick simple;
    test_case "nested values" `Quick nested;
    test_case "markers in the loading part" `Quick loading_has_markers;
    test_case "async props" `Quick async_prop;
    test_case "nothing pending" `Quick nothing_pending;
    test_case "failure and timeout" `Quick failure_and_timeout;
    test_case "text neighbours" `Quick text_inside_hole ]

let early_and_navigation_cases =
  let open Alcotest in
  let early_head () =
    let html =
      Yuka_server.page ~early:true ~scripts:[ "/a.js"; "/b.js" ]
        (fun () -> Yuka.text "x")
    in
    check bool "async module scripts" true
      (contains html
         "<script type=\"module\" async src=\"/a.js\"></script><script type=\"module\" async src=\"/b.js\"></script>");
    let plain = Yuka_server.page ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x") in
    check bool "not async by default" true
      (contains plain "<script type=\"module\" src=\"/a.js\"></script>");
    check bool "early false" false
      (contains (Yuka_server.page ~early:false ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x")) "async");
    let write, chunks = recorder () in
    Lwt_main.run
      (Yuka_server.stream ~early:true ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x") write);
    check bool "stream head" true
      (contains (List.hd (chunks ())) "<script type=\"module\" async src=\"/a.js\"></script>");
    let res =
      Lwt_main.run
        (Yuka_server.respond ~early:true ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x"))
    in
    check bool "respond head" true
      (contains (Lwt_main.run (Dream.body res)) "async src=\"/a.js\"")
  in
  let request ?(headers = []) () = Dream.request ~method_:`GET ~target:"/" ~headers ""
  in
  let async_island a =
    Yuka.Client.island ~name:"I"
      ~props:(Yuka.Codec.encode (Yuka.Codec.async Yuka.Codec.int) a)
      (fun () -> Yuka.text "")
  in
  let build resolve_later () =
    let a, resolve, _ = Yuka.Async.make () in
    let v, resolve_v, _ = Yuka.Async.make () in
    resolve_later resolve resolve_v;
    let island = async_island v in
    Yuka.lower "main" [] [ text_await a "a"; island ]
  in
  let later resolve resolve_v =
    Lwt.async (fun () ->
        Lwt.map (fun () -> resolve 1; resolve_v 5) (Lwt.pause ()))
  in
  let navigation () =
    let req = request ~headers:[ ("Yuka-Navigate", "1") ] () in
    let res =
      Lwt_main.run
        (Yuka_server.respond ~request:req ~title:"T" ~scripts:[ "/m.js" ] (build later))
    in
    check int "status" 200 (Dream.status_to_int (Dream.status res));
    check (option string) "vary" (Some "Yuka-Navigate") (Dream.header res "Vary");
    let body = Lwt_main.run (Dream.body res) in
    let settled =
      Lwt_main.run (Yuka_server.render_settled (build later))
    in
    check string "document"
      ("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>T</title><script type=\"module\" src=\"/m.js\"></script></head><body>"
      ^ settled ^ "</body></html>")
      body;
    check bool "values included" true (contains body "data-yuka-async=\"a1\">{\"ok\":5}</script>");
    check bool "values filled in place" true (contains body "<main><!--[-->a1<!--]-->");
    check bool "no fill script or template" false
      (contains body "__yukaFill" || contains body "<template")
  in
  let normal_request () =
    let res =
      Lwt_main.run
        (Yuka_server.respond ~request:(request ()) (build later))
    in
    check (option string) "vary on normal pages too" (Some "Yuka-Navigate")
      (Dream.header res "Vary");
    let body = Lwt_main.run (Dream.body res) in
    check bool "streamed with fills" true (contains body "<template data-yuka-fill=\"s1\">");
    let other = request ~headers:[ ("Yuka-Navigate", "0") ] () in
    let res = Lwt_main.run (Yuka_server.respond ~request:other (build later)) in
    check bool "only 1 navigates" true
      (contains (Lwt_main.run (Dream.body res)) "<template data-yuka-fill=")
  in
  let navigation_failure () =
    let req = request ~headers:[ ("Yuka-Navigate", "1") ] () in
    let started = Unix.gettimeofday () in
    let res =
      Lwt_main.run
        (Yuka_server.respond ~request:req ~status:`Not_Found ~timeout:0.05
           (fun () ->
             let never, _, _ = Yuka.Async.make () in
             text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) never "a"))
    in
    check bool "the given timeout is used" true (Unix.gettimeofday () -. started < 3.);
    check int "status kept" 404 (Dream.status_to_int (Dream.status res));
    check bool "timeout applies" true
      (contains (Lwt_main.run (Dream.body res)) "<!--[-->E:timeout<!--]-->")
  in
  [ test_case "early scripts" `Quick early_head;
    test_case "navigation request is settled" `Quick navigation;
    test_case "normal request streams" `Quick normal_request;
    test_case "navigation keeps status and timeout" `Quick navigation_failure ]

let () =
  Alcotest.run "yuka"
    [
      ( "core",
        List.map
          (fun (name, case) -> Alcotest.test_case name `Quick case)
          Cases.all );
      ("server", page_cases);
      ("actions", action_cases);
      ("body limit", body_limit_cases);
      ("streaming", stream_cases);
      ("page extras", page_extra_cases);
      ("reject", reject_cases);
      ("timeout", timeout_cases);
      ("of_lwt", of_lwt_cases);
      ("render_settled", settled_cases);
      ("early and navigation", early_and_navigation_cases);
    ]
