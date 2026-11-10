module Server = Yuka.Server
module Async = Yuka.Async

let contains text part =
  let n = String.length part in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = part || at (i + 1))
  in
  at 0

let get a =
  match Async.status a with
  | Async.Done v -> v
  | Async.Failed m -> failwith ("failed: " ^ m)
  | Async.Pending -> failwith "still pending"

let is_pending a = match Async.status a with Async.Pending -> true | _ -> false

let recorder () =
  let chunks = ref [] in
  ( (fun c ->
      chunks := c :: !chunks;
      Async.resolved ()),
    fun () -> List.rev !chunks )

let manual_sleep () =
  let timers = ref [] in
  let sleep seconds =
    let a, resolve, _ = Async.make () in
    timers := !timers @ [ (seconds, resolve) ];
    a
  in
  let fire () =
    let due = !timers in
    timers := [];
    List.iter (fun (_, resolve) -> resolve ()) due
  in
  (sleep, fire, fun () -> List.map fst !timers)

let never_sleep _ =
  let a, _, _ = Async.make () in
  a

let text_await ?failed a name =
  Yuka.Await.make ?failed ~async:a ~loading:(Yuka.text ("L" ^ name))
    ~children:(fun n -> Yuka.text (name ^ string_of_int n))
    ()

let fill id html =
  Printf.sprintf
    "<template data-yuka-fill=\"%s\">%s</template><script>__yukaFill(\"%s\")</script>"
    id html id

let island a =
  Yuka.Client.island ~name:"I"
    ~props:(Yuka.Codec.encode (Yuka.Codec.async Yuka.Codec.int) a)
    (fun () -> Yuka.text "")

let island_wrap id content =
  Printf.sprintf
    "<yuka-island data-name=\"I\" data-id=\"%s\" style=\"display:contents\">%s</yuka-island><script type=\"application/json\" data-yuka-props=\"%s\">null</script>"
    id content id

let island_html id props =
  Printf.sprintf
    "<yuka-island data-name=\"I\" data-id=\"%s\" style=\"display:contents\"></yuka-island><script type=\"application/json\" data-yuka-props=\"%s\">%s</script>"
    id id props

let value_script id json =
  Printf.sprintf
    "<script type=\"application/json\" data-yuka-async=\"%s\">%s</script>" id
    json

let stream ?head ?early ?import_map ?timeout ?(sleep = never_sleep) ?title
    ?styles ?scripts build write =
  Yuka.Private.stream ?head ?early ?import_map ?timeout ?title ?styles ?scripts
    ~sleep ~write build

let page_cases =
  let open Alcotest in
  let page () =
    let html =
      Server.document ~title:"A & B" ~styles:[ "/a.css" ] ~scripts:[ "/m.js" ]
        (fun () -> Yuka.lower "p" [] [ Yuka.text "hi" ])
    in
    check string "document"
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>A &amp; B</title><link rel=\"stylesheet\" href=\"/a.css\"><script type=\"module\" src=\"/m.js\"></script></head><body><p>hi</p></body></html>"
      html
  in
  let to_string () =
    check string "element" "<p>ab</p>"
      (Server.to_string (fun () ->
           Yuka.lower "p" [] [ Yuka.text "a"; Yuka.text "b" ]))
  in
  let markers_only_in_islands () =
    let pending, _, _ = Async.make () in
    let content () =
      Yuka.lower "p" []
        [ Yuka.text "a";
          Yuka.text "b";
          Yuka.hole (fun () -> Yuka.text "h");
          Yuka.each ~key:Fun.id (fun () -> [ "x"; "y" ]) Yuka.text;
          text_await (Async.resolved 1) "s";
          text_await pending "l" ]
    in
    let outside =
      Server.to_string (fun () ->
          Yuka.lower "p" []
            [ Yuka.text "a";
              Yuka.text "b";
              text_await (Async.resolved 1) "s";
              text_await pending "l" ])
    in
    check string "no markers outside an island" "<p>abs1Ll</p>" outside;
    check string "markers inside an island"
      (island_wrap
         "i1"
         "<p>a<!---->b<!--[-->h<!--]--><!--[--><!--[-->x<!--]--><!--[-->y<!--]--><!--]--><!--[-->s1<!--]--><!--[-->Ll<!--]--></p>")
      (Server.to_string (fun () ->
           Yuka.Client.island ~name:"I" ~props:`Null content))
  in
  let respond () =
    let write, chunks = recorder () in
    get
      (Yuka.Private.stream ~sleep:never_sleep ~write (fun () -> Yuka.text "x"));
    check string "body"
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title></title></head><body>x</body></html>"
      (String.concat "" (chunks ()))
  in
  let component_effect () =
    let runs = ref 0 in
    let component () =
      Yuka.Effect.run (fun () -> incr runs);
      Yuka.lower "p" [] []
    in
    check string "html" "<p></p>" (Server.to_string component);
    check int "effect not run" 0 !runs
  in
  [ test_case "component effect" `Quick component_effect;
    test_case "page" `Quick page;
    test_case "to_string" `Quick to_string;
    test_case "markers only in islands" `Quick markers_only_in_islands;
    test_case "respond" `Quick respond ]

type issue = { title : string; n : int }

let issue_codec : issue Yuka.Codec.t =
  {
    encode = (fun i -> `Assoc [ ("title", `String i.title); ("n", `Int i.n) ]);
    decode =
      (function
      | `Assoc [ ("title", `String title); ("n", `Int n) ] -> Ok { title; n }
      | _ -> Error "bad issue");
  }

let declare name = Yuka.Action.declare ~name ~input:Yuka.Codec.int ~output:Yuka.Codec.int
let create = Yuka.Action.declare ~name:"create" ~input:issue_codec ~output:issue_codec
let broken = declare "broken"
let failing = declare "failing"
let rejecting = declare "rejecting"
let rejecting_late = declare "rejecting_late"
let rejecting_chain = declare "rejecting_chain"
let late = declare "late"
let late_gate, late_open, _ = Async.make ()
let call_gate, call_open, _ = Async.make ()

let () =
  Server.Action.implement create (fun i ->
      Async.resolved { i with n = i.n + 1 });
  Server.Action.implement broken (fun _ -> failwith "secret detail");
  Server.Action.implement failing (fun _ -> Async.failed "secret failure");
  Server.Action.implement rejecting (fun _ -> Server.Action.reject "title is empty");
  Server.Action.implement rejecting_late (fun _ ->
      Async.bind late_gate (fun () -> Server.Action.rejected "too late"));
  Server.Action.implement rejecting_chain (fun _ ->
      Server.Action.rejected "from a chain");
  Server.Action.implement late (fun n -> Async.map (fun () -> n) call_gate)

let json_type = Some "application/json"

let post ?(content_type = json_type) ?(origin = None) ?(host = Some "x.test")
    name body =
  get (Yuka.Private.handle_action ~name ~content_type ~origin ~host ~body)

let logged f =
  let messages = ref [] in
  let saved = !Server.log_error in
  Server.log_error := (fun m -> messages := m :: !messages);
  let result = (try f () with e -> Server.log_error := saved; raise e) in
  Server.log_error := saved;
  (result, List.rev !messages)

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
    check bool "says JSON" true
      (String.length body > 18 && String.sub body 0 18 = "{\"error\":\"invalid ")
  in
  let bad_input () =
    let status, body = post "create" "{\"title\":1}" in
    check int "status" 400 status;
    check string "message" "{\"error\":\"invalid input: bad issue\"}" body
  in
  let unknown () =
    check reply "404" (404, "{\"error\":\"unknown action nope\"}")
      (post "nope" "1")
  in
  let content_type () =
    check int "415" 415
      (fst (post ~content_type:(Some "text/plain") "broken" "1"));
    check int "415 without header" 415 (fst (post ~content_type:None "broken" "1"));
    check int "parameters allowed" 200
      (fst
         (post
            ~content_type:(Some "Application/JSON; charset=utf-8")
            "create" "{\"title\":\"a\",\"n\":1}"))
  in
  let origin () =
    let json = "{\"title\":\"a\",\"n\":1}" in
    let with_origin o = fst (post ~origin:(Some o) "create" json) in
    check int "other site" 403 (with_origin "https://evil.test");
    check int "other port" 403 (with_origin "http://x.test:81");
    check int "same" 200 (with_origin "https://x.test");
    check int "no host" 403
      (fst (post ~origin:(Some "https://x.test") ~host:None "create" json))
  in
  let check_order () =
    check int "origin before name" 403
      (fst (post ~origin:(Some "https://evil.test") "nope" "1"));
    check int "name before content type" 404
      (fst (post ~content_type:None "nope" "1"));
    check int "content type before size" 415
      (fst (post ~content_type:None "create" (String.make 2_000_000 'x')))
  in
  let generic_500 () =
    let (raised, failed), messages =
      logged (fun () -> (post "broken" "1", post "failing" "1"))
    in
    check reply "raised" (500, "{\"error\":\"action failed\"}") raised;
    check reply "failed async" (500, "{\"error\":\"action failed\"}") failed;
    check bool "details are logged" true
      (List.exists (fun m -> contains m "secret detail") messages
      && List.exists (fun m -> contains m "secret failure") messages)
  in
  let twice () =
    check bool "raises" true
      (match Server.Action.implement create (fun i -> Async.resolved i) with
      | () -> false
      | exception Invalid_argument _ -> true)
  in
  let direct_call () =
    check string "resolved" "t 6"
      (let i = get (Yuka.Action.call create { title = "t"; n = 5 }) in
       i.title ^ " " ^ string_of_int i.n);
    check bool "implementation failure" true
      (match Async.status (Yuka.Action.call broken 1) with
      | Async.Failed _ -> true
      | _ -> false)
  in
  let late_call () =
    let call = Yuka.Action.call late 3 in
    check bool "pending" true (is_pending call);
    call_open ();
    check int "settles" 3 (get call)
  in
  [ test_case "happy path" `Quick happy;
    test_case "bad JSON" `Quick bad_json;
    test_case "bad input" `Quick bad_input;
    test_case "unknown action" `Quick unknown;
    test_case "content type" `Quick content_type;
    test_case "origin" `Quick origin;
    test_case "order of checks" `Quick check_order;
    test_case "generic 500" `Quick generic_500;
    test_case "implement twice" `Quick twice;
    test_case "server-side call" `Quick direct_call;
    test_case "late call settles" `Quick late_call ]

let body_limit_cases =
  let open Alcotest in
  let limit = 1_048_576 in
  let json_body size =
    Printf.sprintf "{\"title\":\"%s\",\"n\":1}" (String.make (size - 18) 'x')
  in
  let at_limit () =
    check int "exactly the limit" 200 (fst (post "create" (json_body limit)))
  in
  let over () =
    check (pair int string) "over the limit"
      (413, "{\"error\":\"request too large\"}")
      (post "create" (json_body (limit + 1)))
  in
  [ test_case "at the limit" `Quick at_limit;
    test_case "over the limit" `Quick over ]

let stream_cases =
  let open Alcotest in
  let list_of = list string in
  let shell_and_order () =
    let a, resolve_a, _ = Async.make () in
    let b, resolve_b, _ = Async.make () in
    let write, chunks = recorder () in
    let p =
      stream ~title:"T"
        (fun () -> Yuka.lower "div" [] [ text_await a "a"; text_await b "b" ])
        write
    in
    (match chunks () with
    | [ head; shell ] ->
        check bool "head" true
          (String.length head > 15
          && String.sub head 0 15 = "<!DOCTYPE html>"
          && contains head Server.fill_script);
        check string "shell"
          "<div><!--[s1-->La<!--]--><!--[s2-->Lb<!--]--></div>" shell
    | l -> failf "expected 2 chunks, got %d" (List.length l));
    check bool "running" true (is_pending p);
    resolve_b 2;
    check int "one fill" 3 (List.length (chunks ()));
    check bool "still running" true (is_pending p);
    resolve_a 1;
    get p;
    check list_of "fills in settle order"
      [ fill "s2" "b2"; fill "s1" "a1"; "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()))
  in
  let settled_inline () =
    let write, chunks = recorder () in
    get (stream (fun () -> text_await (Async.resolved 7) "a") write);
    check list_of "no fill"
      [ "a7"; "</body></html>" ]
      (List.tl (chunks ()))
  in
  let nested () =
    let outer, resolve_outer, _ = Async.make () in
    let inner, resolve_inner, _ = Async.make () in
    let write, chunks = recorder () in
    let p =
      stream
        (fun () ->
          Yuka.Await.make ~async:outer ~loading:(Yuka.text "Lo")
            ~children:(fun n ->
              Yuka.lower "p" []
                [ Yuka.text (string_of_int n); text_await inner "i" ])
            ())
        write
    in
    resolve_outer 1;
    check bool "still running" true (is_pending p);
    resolve_inner 2;
    get p;
    check list_of "chunks"
      [ "<!--[s1-->Lo<!--]-->";
        fill "s1" "<p>1<!--[s2-->Li<!--]--></p>";
        fill "s2" "i2";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let failure () =
    let a, _, fail_a = Async.make () in
    let b, _, fail_b = Async.make () in
    let write, chunks = recorder () in
    let p =
      stream
        (fun () ->
          Yuka.fragment
            [ text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) a "a";
              text_await b "b" ])
        write
    in
    fail_b "x";
    fail_a "boom";
    get p;
    check list_of "failure chunks"
      [ "<!--[s1-->La<!--]--><!--[s2-->Lb<!--]-->";
        fill "s2" "";
        fill "s1" "E:boom";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let async_prop () =
    let a, resolve, _ = Async.make () in
    let b, _, fail_b = Async.make () in
    let write, chunks = recorder () in
    let p =
      stream
        (fun () ->
          let ia = island a in
          let ib = island b in
          Yuka.fragment [ ia; ib ])
        write
    in
    check string "shell"
      (island_html "i1" "{\"$async\":\"a1\"}"
      ^ island_html "i2" "{\"$async\":\"a2\"}")
      (List.nth (chunks ()) 1);
    fail_b "no";
    resolve 5;
    get p;
    check list_of "values"
      [ value_script "a2" "{\"error\":\"failed\"}";
        value_script "a1" "{\"ok\":5}";
        "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()))
  in
  let async_errors () =
    let a, _, fail_a = Async.make () in
    let b, _, fail_b = Async.make () in
    let write, chunks = recorder () in
    let logged = ref [] in
    let saved = !Server.log_error in
    Server.log_error := (fun m -> logged := m :: !logged);
    let p = stream (fun () -> Yuka.fragment [ island a; island b ]) write in
    fail_a "db password wrong";
    fail_b "yuka.reject:title is empty";
    get p;
    Server.log_error := saved;
    check list_of "values"
      [ value_script "a2" "{\"error\":\"failed\"}";
        value_script "a1" "{\"error\":\"title is empty\"}";
        "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()));
    check list_of "log" [ "async value a2 failed: db password wrong" ] !logged
  in
  let async_errors_inline () =
    let logged = ref [] in
    let saved = !Server.log_error in
    Server.log_error := (fun m -> logged := m :: !logged);
    let html =
      Server.to_string (fun () ->
          Yuka.fragment
            [ island (Async.failed "db password wrong");
              island (Async.failed "yuka.reject:title is empty") ])
    in
    Server.log_error := saved;
    check string "inline values"
      (island_html "i1" "{\"$async\":\"a2\",\"error\":\"failed\"}"
      ^ island_html "i2" "{\"$async\":\"a1\",\"error\":\"title is empty\"}")
      html;
    check list_of "log" [ "async value a2 failed: db password wrong" ] !logged
  in
  let async_in_fill () =
    let outer, resolve_outer, _ = Async.make () in
    let value, resolve_value, _ = Async.make () in
    let write, chunks = recorder () in
    let p =
      stream
        (fun () ->
          Yuka.Await.make ~async:outer ~loading:Yuka.empty
            ~children:(fun _ -> island value)
            ())
        write
    in
    resolve_outer 0;
    resolve_value 9;
    get p;
    check list_of "async registered in a fill"
      [ fill "s1" (island_html "i1" "{\"$async\":\"a1\"}");
        value_script "a1" "{\"ok\":9}";
        "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (chunks ()))
  in
  let to_string_sync () =
    let pending, _, _ = Async.make () in
    check string "pending prints loading" "La"
      (Server.to_string (fun () -> text_await pending "a"));
    check string "settled prints value" "a1"
      (Server.to_string (fun () -> text_await (Async.resolved 1) "a"));
    check string "failed prints nothing" ""
      (Server.to_string (fun () -> text_await (Async.failed "x") "a"));
    check bool "settled prop inline" true
      (contains
         (Server.to_string (fun () -> island (Async.resolved 3)))
         "{\"$async\":\"a1\",\"ok\":3}");
    check bool "pending prop is an error" true
      (contains
         (Server.to_string (fun () -> island pending))
         "{\"$async\":\"a1\",\"error\":\"pending at render\"}")
  in
  let codec_async () =
    let codec = Yuka.Codec.async Yuka.Codec.int in
    let decode j =
      match Yuka.Codec.decode codec j with
      | Ok a -> Async.status a
      | Error m -> Async.Failed ("decode:" ^ m)
    in
    let show = function
      | Async.Done n -> "done " ^ string_of_int n
      | Async.Failed m -> "failed " ^ m
      | Async.Pending -> "pending"
    in
    check string "ok" "done 4"
      (show (decode (`Assoc [ ("$async", `String "a1"); ("ok", `Int 4) ])));
    check string "error" "failed e"
      (show (decode (`Assoc [ ("$async", `String "a1"); ("error", `String "e") ])));
    check string "bad ok" "failed expected int, got \"x\""
      (show (decode (`Assoc [ ("$async", `String "a1"); ("ok", `String "x") ])));
    check string "not a reference"
      "failed decode:expected async reference, got 1"
      (show (decode (`Int 1)));
    let saved = !Yuka.Private.async_source in
    let a, resolve, _ = Async.make () in
    Yuka.Private.async_source :=
      (fun id ->
        if id = "a9" then Async.map (fun n -> `Int n) a else Async.failed "unknown");
    let reference = `Assoc [ ("$async", `String "a9") ] in
    check string "bare reference waits" "pending" (show (decode reference));
    resolve 4;
    check string "bare reference resolves" "done 4" (show (decode reference));
    Yuka.Private.async_source := saved
  in
  let respond_streams () =
    let a, resolve, _ = Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka.Private.stream ~sleep:never_sleep ~write (fun () -> text_await a "a")
    in
    resolve 1;
    get p;
    let body = String.concat "" (chunks ()) in
    check bool "has the fill" true (contains body (fill "s1" "a1"));
    check bool "ends" true (contains body "</body></html>")
  in
  let write_order () =
    let gates = ref [] in
    let written = ref [] in
    let write chunk =
      let a, resolve, _ = Async.make () in
      gates := !gates @ [ resolve ];
      Async.map (fun () -> written := chunk :: !written) a
    in
    let x, resolve_x, _ = Async.make () in
    let y, resolve_y, _ = Async.make () in
    let p =
      stream
        (fun () -> Yuka.fragment [ text_await x "x"; text_await y "y" ])
        write
    in
    let release () =
      match !gates with
      | g :: rest ->
          gates := rest;
          g ()
      | [] -> failwith "no write waiting"
    in
    release ();
    release ();
    resolve_y 2;
    resolve_x 1;
    check int "second chunk waits for the first write" 2 (List.length !written);
    check int "one write in flight" 1 (List.length !gates);
    release ();
    release ();
    release ();
    get p;
    check list_of "written in order"
      [ fill "s2" "y2"; fill "s1" "x1"; "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (List.rev !written))
  in
  let write_failure () =
    let write chunk =
      if contains chunk "<template" then Async.failed "socket closed"
      else Async.resolved ()
    in
    let a, resolve, _ = Async.make () in
    let p = stream (fun () -> text_await a "a") write in
    resolve 1;
    check bool "the result fails although the last write works" true
      (match Async.status p with Async.Failed _ -> true | _ -> false)
  in
  [ test_case "shell then fills in settle order" `Quick shell_and_order;
    test_case "settled value is inline" `Quick settled_inline;
    test_case "nested await" `Quick nested;
    test_case "failure" `Quick failure;
    test_case "async props" `Quick async_prop;
    test_case "async errors stay on the server" `Quick async_errors;
    test_case "async errors at print time stay on the server" `Quick async_errors_inline;
    test_case "async prop inside a fill" `Quick async_in_fill;
    test_case "to_string" `Quick to_string_sync;
    test_case "Codec.async decode" `Quick codec_async;
    test_case "respond streams" `Quick respond_streams;
    test_case "writes are sequenced" `Quick write_order;
    test_case "a failed write fails the stream" `Quick write_failure ]

let page_extra_cases =
  let open Alcotest in
  let page_head () =
    let html =
      Server.document ~head:"<meta name=\"x\" content=\"y\">"
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
      (contains (Server.document (fun () -> Yuka.text "x")) "importmap")
  in
  let stream_head () =
    let write, chunks = recorder () in
    let a, resolve, _ = Async.make () in
    let p =
      stream ~head:"<b></b>" ~import_map:[ ("p/", "/p/") ]
        ~scripts:[ "/m.js" ]
        (fun () -> text_await a "a")
        write
    in
    resolve 1;
    get p;
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
    let write, chunks = recorder () in
    get
      (Yuka.Private.stream ~head:"<i></i>" ~import_map:[ ("p/", "/p/") ]
         ~sleep:never_sleep ~write
         (fun () -> Yuka.text "x"));
    let body = String.concat "" (chunks ()) in
    check bool "head and map" true
      (contains body "<i></i>" && contains body "\"p/\":\"/p/\"")
  in
  let map_of_packages () =
    check
      (list (pair string string))
      "packages"
      [ ("@scope/pkg/", "/static/js/node_modules/@scope/pkg/");
        ("melange/", "/static/js/node_modules/melange/");
        ("yuka-client/", "/static/js/node_modules/yuka-client/") ]
      (Yuka.Private.import_map ~url:"/static/js/"
         [ "@scope/pkg"; "melange"; "yuka-client" ]);
    check
      (list (pair string string))
      "no trailing slash on the url" [ ("a/", "/x/node_modules/a/") ]
      (Yuka.Private.import_map ~url:"/x" [ "a" ]);
    check
      (list (pair string string))
      "no packages" []
      (Yuka.Private.import_map ~url:"/x" [])
  in
  [ test_case "page head and import map" `Quick page_head;
    test_case "no import map by default" `Quick no_import_map;
    test_case "stream head order" `Quick stream_head;
    test_case "respond head" `Quick respond_head;
    test_case "import_map of a package list" `Quick map_of_packages ]

let reject_cases =
  let open Alcotest in
  let route () =
    check (pair int string) "400 with the message"
      (400, "{\"error\":\"title is empty\"}")
      (post "rejecting" "1");
    check (pair int string) "after rejected in a chain"
      (400, "{\"error\":\"from a chain\"}")
      (post "rejecting_chain" "1")
  in
  let after_a_wait () =
    let waiting =
      Yuka.Private.handle_action ~name:"rejecting_late" ~content_type:json_type
        ~origin:None ~host:(Some "x.test") ~body:"1"
    in
    check bool "pending" true (is_pending waiting);
    late_open ();
    check (pair int string) "400 after the wait"
      (400, "{\"error\":\"too late\"}")
      (get waiting)
  in
  let ordinary () =
    let (status, body), _ = logged (fun () -> post "broken" "1") in
    check int "500" 500 status;
    check bool "message not sent" false (contains body "secret detail");
    let _, body = post "rejecting" "1" in
    check bool "reject message sent" true (contains body "title is empty")
  in
  let rejection_is_not_logged () =
    let _, messages = logged (fun () -> post "rejecting" "1") in
    check int "nothing logged" 0 (List.length messages)
  in
  let direct () =
    let show = function
      | Async.Failed m -> "failed " ^ m
      | _ -> "other"
    in
    check string "server-side call" "failed title is empty"
      (show (Async.status (Yuka.Action.call rejecting 1)));
    check string "server-side call, chain" "failed from a chain"
      (show (Async.status (Yuka.Action.call rejecting_chain 1)))
  in
  [ test_case "route answers 400" `Quick route;
    test_case "rejection after a wait" `Quick after_a_wait;
    test_case "ordinary exceptions stay 500" `Quick ordinary;
    test_case "a rejection is not logged" `Quick rejection_is_not_logged;
    test_case "server-side call fails" `Quick direct ]

let timeout_cases =
  let open Alcotest in
  let list_of = list string in
  let never_settles () =
    let a, _, _ = Async.make () in
    let b, _, _ = Async.make () in
    let sleep, fire, requested = manual_sleep () in
    let write, chunks = recorder () in
    let p =
      stream ~timeout:0.05 ~sleep
        (fun () ->
          let prop = island b in
          Yuka.fragment
            [ prop; text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) a "a" ])
        write
    in
    check (list (float 0.)) "sleep asked for the timeout" [ 0.05 ] (requested ());
    check bool "waits for the timer" true (is_pending p);
    fire ();
    get p;
    check list_of "timeout chunks"
      [ island_html "i1" "{\"$async\":\"a1\"}" ^ "<!--[s1-->La<!--]-->";
        value_script "a1" "{\"error\":\"timeout\"}";
        fill "s1" "E:timeout";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let default_timeout () =
    let a, _, _ = Async.make () in
    let sleep, _, requested = manual_sleep () in
    let write, _ = recorder () in
    ignore (stream ~sleep (fun () -> text_await a "a") write);
    check (list (float 0.)) "ten seconds" [ 10. ] (requested ())
  in
  let no_timer_when_settled () =
    let sleep, _, requested = manual_sleep () in
    let write, _ = recorder () in
    get (stream ~sleep (fun () -> text_await (Async.resolved 1) "a") write);
    check int "no timer" 0 (List.length (requested ()))
  in
  let nested_after_timeout () =
    let outer, resolve, _ = Async.make () in
    let inner, _, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let write, chunks = recorder () in
    let p =
      stream ~sleep
        (fun () ->
          Yuka.Await.make ~async:outer ~loading:(Yuka.text "Lo")
            ~children:(fun _ -> text_await inner "i")
            ())
        write
    in
    resolve 1;
    fire ();
    get p;
    check list_of "inner times out too"
      [ "<!--[s1-->Lo<!--]-->";
        fill "s1" "<!--[s2-->Li<!--]-->";
        fill "s2" "";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let failed_element_has_await () =
    let outer, _, _ = Async.make () in
    let inner, _, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let write, chunks = recorder () in
    let p =
      stream ~sleep
        (fun () ->
          Yuka.Await.make ~async:outer
            ~failed:(fun _ -> text_await inner "i")
            ~loading:(Yuka.text "Lo")
            ~children:(fun _ -> Yuka.empty)
            ())
        write
    in
    fire ();
    get p;
    check list_of "await in the failed element is timed out too"
      [ "<!--[s1-->Lo<!--]-->";
        fill "s1" "<!--[s2-->Li<!--]-->";
        fill "s2" "";
        "</body></html>" ]
      (List.tl (chunks ()))
  in
  let late_value_ignored () =
    let a, resolve, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let write, chunks = recorder () in
    let p = stream ~sleep (fun () -> text_await a "a") write in
    fire ();
    get p;
    resolve 1;
    check int "nothing after the end" 4 (List.length (chunks ()))
  in
  let timer_after_end () =
    let a, resolve, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let write, chunks = recorder () in
    let p = stream ~sleep (fun () -> text_await a "a") write in
    resolve 1;
    get p;
    fire ();
    check list_of "the late timer does nothing"
      [ "<!--[s1-->La<!--]-->"; fill "s1" "a1"; "</body></html>" ]
      (List.tl (chunks ()))
  in
  [ test_case "never-settling values time out" `Quick never_settles;
    test_case "default timeout" `Quick default_timeout;
    test_case "no timer when nothing is pending" `Quick no_timer_when_settled;
    test_case "nested await after a timeout" `Quick nested_after_timeout;
    test_case "await in a failed element" `Quick failed_element_has_await;
    test_case "late value is ignored" `Quick late_value_ignored;
    test_case "timer after the end" `Quick timer_after_end;
    test_case "fill script lives in the core" `Quick (fun () ->
        check string "same script" Yuka.Private.fill_script Server.fill_script) ]

let settled_cases =
  let open Alcotest in
  let render ?timeout ?(sleep = never_sleep) build =
    Yuka.Private.settled ?timeout ~sleep build
  in
  let simple () =
    let a, resolve_a, _ = Async.make () in
    let b, resolve_b, _ = Async.make () in
    let p =
      render (fun () ->
          Yuka.lower "div" [] [ text_await a "a"; text_await b "b" ])
    in
    resolve_b 2;
    resolve_a 1;
    check string "values in place"
      "<div>a1b2</div>" (get p)
  in
  let inside_island () =
    let outer, resolve_outer, _ = Async.make () in
    let inner, _, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let p =
      render ~sleep (fun () ->
          Yuka.Client.island ~name:"I" ~props:`Null (fun () ->
              Yuka.lower "p" []
                [ Yuka.text "t";
                  Yuka.Await.make ~async:outer
                    ~loading:(Yuka.fragment [ text_await inner "i"; Yuka.text "x" ])
                    ~children:(fun n -> Yuka.text ("o" ^ string_of_int n))
                    ();
                  Yuka.text "u" ]))
    in
    resolve_outer 1;
    fire ();
    check string "a fill inside an island keeps its hole markers"
      (island_wrap "i1" "<p>t<!--[-->o1<!--]-->u</p>")
      (get p)
  in
  let nested () =
    let outer, resolve_outer, _ = Async.make () in
    let inner, resolve_inner, _ = Async.make () in
    let p =
      render (fun () ->
          Yuka.Await.make ~async:outer ~loading:(Yuka.text "Lo")
            ~children:(fun n ->
              Yuka.lower "p" []
                [ Yuka.text (string_of_int n); text_await inner "i" ])
            ())
    in
    resolve_outer 1;
    resolve_inner 2;
    check string "nested in place"
      "<p>1i2</p>" (get p)
  in
  let loading_has_markers () =
    let outer, resolve_outer, _ = Async.make () in
    let inner, _, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let p =
      render ~sleep (fun () ->
          Yuka.Await.make ~async:outer
            ~loading:(Yuka.fragment [ text_await inner "i"; Yuka.text "x" ])
            ~children:(fun n -> Yuka.text ("o" ^ string_of_int n))
            ())
    in
    resolve_outer 1;
    fire ();
    check string "markers inside the replaced part are skipped"
      "o1" (get p)
  in
  let async_prop () =
    let value, resolve, _ = Async.make () in
    let failing, _, fail = Async.make () in
    let p =
      render (fun () ->
          let first = island value in
          let second = island failing in
          Yuka.fragment [ first; second ])
    in
    resolve 5;
    fail "no";
    check string "values after the document"
      (island_html "i1" "{\"$async\":\"a1\"}"
      ^ island_html "i2" "{\"$async\":\"a2\"}"
      ^ value_script "a1" "{\"ok\":5}"
      ^ value_script "a2" "{\"error\":\"failed\"}")
      (get p)
  in
  let nothing_pending () =
    check string "same as to_string" "<p>x</p>"
      (get (render (fun () -> Yuka.lower "p" [] [ Yuka.text "x" ])))
  in
  let failure_and_timeout () =
    let a, _, fail_a = Async.make () in
    let never, _, _ = Async.make () in
    let sleep, fire, _ = manual_sleep () in
    let p =
      render ~sleep (fun () ->
          let first = text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) a "a" in
          let second =
            text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) never "b"
          in
          Yuka.fragment [ first; second ])
    in
    fail_a "x";
    fire ();
    check string "failed and timed out"
      "E:xE:timeout" (get p)
  in
  let text_inside_hole () =
    let a, resolve, _ = Async.make () in
    let p =
      render (fun () ->
          Yuka.lower "p" [] [ Yuka.text "t"; text_await a "a"; Yuka.text "u" ])
    in
    resolve 1;
    check string "text neighbours keep their separators"
      "<p>ta1u</p>" (get p)
  in
  [ test_case "values in place" `Quick simple;
    test_case "nested values" `Quick nested;
    test_case "fill inside an island" `Quick inside_island;
    test_case "markers in the loading part" `Quick loading_has_markers;
    test_case "async props" `Quick async_prop;
    test_case "nothing pending" `Quick nothing_pending;
    test_case "failure and timeout" `Quick failure_and_timeout;
    test_case "text neighbours" `Quick text_inside_hole ]

let navigation_cases =
  let open Alcotest in
  let mount_needs_ppx () =
    let raises_ppx f =
      match f () with
      | () -> false
      | exception Failure m -> contains m "yuka.ppx"
    in
    check bool "no registry" true (raises_ppx (fun () -> Yuka.mount ()));
    check bool "registry on native" true
      (raises_ppx (fun () -> Yuka.mount ~islands:(Yuka.Client.registry []) ()))
  in
  let early_head () =
    let html = Server.document ~early:true ~scripts:[ "/a.js"; "/b.js" ] (fun () -> Yuka.text "x") in
    check bool "async module scripts" true
      (contains html
         "<script type=\"module\" async src=\"/a.js\"></script><script type=\"module\" async src=\"/b.js\"></script>");
    check bool "not async by default" true
      (contains
         (Server.document ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x"))
         "<script type=\"module\" src=\"/a.js\"></script>");
    check bool "early false" false
      (contains
         (Server.document ~early:false ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x"))
         "async");
    let write, chunks = recorder () in
    get (stream ~early:true ~scripts:[ "/a.js" ] (fun () -> Yuka.text "x") write);
    check bool "stream head" true
      (contains (List.hd (chunks ()))
         "<script type=\"module\" async src=\"/a.js\"></script>");
  in
  let build () =
    let a, resolve, _ = Async.make () in
    let v, resolve_v, _ = Async.make () in
    ( (fun () ->
        let prop = island v in
        Yuka.lower "main" [] [ text_await a "a"; prop ]),
      fun () ->
        resolve 1;
        resolve_v 5 )
  in
  let navigation () =
    let view, release = build () in
    let p = Yuka.Private.settled ~sleep:never_sleep view in
    check bool "waits for the values" true (is_pending p);
    release ();
    let body = get p in
    check bool "values included" true
      (contains body "data-yuka-async=\"a1\">{\"ok\":5}</script>");
    check bool "values filled in place" true
      (contains body "<main>a1");
    check bool "no fill script or template" false
      (contains body "__yukaFill" || contains body "<template")
  in
  let normal_request () =
    let view, release = build () in
    let write, chunks = recorder () in
    let p = Yuka.Private.stream ~sleep:never_sleep ~write view in
    release ();
    get p;
    check bool "streamed with fills" true
      (contains (String.concat "" (chunks ())) "<template data-yuka-fill=\"s1\">");
    check bool "several writes" true (List.length (chunks ()) > 1)
  in
  let navigation_timeout () =
    let never, _, _ = Async.make () in
    let sleep, fire, requested = manual_sleep () in
    let p =
      Yuka.Private.settled ~timeout:0.05 ~sleep (fun () ->
          text_await ~failed:(fun m -> Yuka.text ("E:" ^ m)) never "a")
    in
    check (list (float 0.)) "the given timeout is used" [ 0.05 ] (requested ());
    fire ();
    check bool "timeout applies" true (contains (get p) "E:timeout")
  in
  [ test_case "early scripts" `Quick early_head;
    test_case "navigation request is settled" `Quick navigation;
    test_case "normal request streams" `Quick normal_request;
    test_case "navigation keeps the timeout" `Quick navigation_timeout;
    test_case "mount needs the ppx" `Quick mount_needs_ppx ]

let review_cases =
  let open Alcotest in
  let list_of = list string in
  let sync_settle_during_shell () =
    let a, resolve_a, _ = Async.make () in
    let b, resolve_b, _ = Async.make () in
    let written = ref [] in
    let write chunk =
      written := chunk :: !written;
      if contains chunk "<!--[s1-->" then resolve_a 1;
      Async.resolved ()
    in
    let p =
      stream
        (fun () -> Yuka.fragment [ text_await a "a"; text_await b "b" ])
        write
    in
    check bool "waits for the second value" true (is_pending p);
    resolve_b 2;
    get p;
    check list_of "both chunks are written"
      [ fill "s1" "a1"; fill "s2" "b2"; "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (List.rev !written))
  in
  let sync_async_prop () =
    let a, resolve_a, _ = Async.make () in
    let b, resolve_b, _ = Async.make () in
    let written = ref [] in
    let write chunk =
      written := chunk :: !written;
      if contains chunk "data-yuka-props=\"i1\"" then resolve_a 1;
      Async.resolved ()
    in
    let p =
      stream
        (fun () ->
          let first = island a in
          let second = island b in
          Yuka.fragment [ first; second ])
        write
    in
    resolve_b 2;
    get p;
    check list_of "both values are written"
      [ value_script "a1" "{\"ok\":1}"; value_script "a2" "{\"ok\":2}"; "</body></html>" ]
      (List.filteri (fun i _ -> i >= 2) (List.rev !written))
  in
  let timer_keeps_nothing () =
    let sleep, _, _ = manual_sleep () in
    let weak = Weak.create 1 in
    let finished = ref false in
    (let marker = Bytes.make 1000 'x' in
     Weak.set weak 0 (Some marker);
     let a, resolve, _ = Async.make () in
     let write chunk =
       ignore (Sys.opaque_identity (Bytes.length marker, chunk));
       Async.resolved ()
     in
     let p = stream ~sleep (fun () -> text_await a "a") write in
     resolve 1;
     get p;
     finished := true);
    check bool "finished" true !finished;
    Gc.full_major ();
    Gc.full_major ();
    check bool "the pending timer does not keep the render alive" false
      (Weak.check weak 0);
    ignore (Sys.opaque_identity (sleep 0.))
  in
  let deep_body () =
    let body = String.make 100000 '[' ^ String.make 100000 ']' in
    check int "400" 400 (fst (post "create" body));
    check bool "message" true
      (contains (snd (post "create" body)) "nesting too deep")
  in
  [ test_case "a value settling during registration" `Quick sync_settle_during_shell;
    test_case "an async prop settling during registration" `Quick sync_async_prop;
    test_case "the timer keeps nothing alive" `Quick timer_keeps_nothing;
    test_case "deeply nested action body" `Quick deep_body ]

let loading_cases =
  let open Alcotest in
  let isl ?loading name =
    Yuka.Client.island ?loading ~name ~props:(`Int 1) (fun () -> Yuka.text "")
  in
  let link url = Printf.sprintf "<link rel=\"modulepreload\" href=\"%s\">" url in
  let count text part =
    let n = String.length part in
    let rec go i acc =
      if i + n > String.length text then acc
      else go (i + 1) (if String.sub text i n = part then acc + 1 else acc)
    in
    go 0 0
  in
  let preload name = Some ("/js/" ^ name ^ ".js") in
  let shell ?preload build =
    let write, chunks = recorder () in
    get (Yuka.Private.stream ?preload ~sleep:never_sleep ~write build);
    List.nth (chunks ()) 1
  in
  let data_start () =
    let html loading = Yuka.Server.to_string (fun () -> isl ~loading "A") in
    check bool "lazy visible" true
      (contains (html (`Lazy `Visible)) "data-start=\"visible\"");
    check bool "lazy idle" true
      (contains (html (`Lazy `Idle)) "data-start=\"idle\"");
    check bool "lazy interaction" true
      (contains (html (`Lazy `Interaction)) "data-start=\"interaction\"");
    check bool "load has none" false (contains (html `Load) "data-start")
  in
  let once () =
    let out =
      shell ~preload (fun () ->
          Yuka.fragment [ isl "A"; isl ~loading:`Visible "A"; isl "B" ])
    in
    check int "A once" 1 (count out (link "/js/A.js"));
    check int "B once" 1 (count out (link "/js/B.js"));
    check bool "before the island" true
      (contains out (link "/js/A.js" ^ "<yuka-island data-name=\"A\""))
  in
  let lazy_none () =
    let out = shell ~preload (fun () -> isl ~loading:(`Lazy `Idle) "A") in
    check bool "no link" false (contains out "modulepreload");
    let out =
      shell ~preload (fun () ->
          Yuka.fragment [ isl ~loading:(`Lazy `Visible) "A"; isl "A" ])
    in
    check int "a later non-lazy use gets the link" 1
      (count out (link "/js/A.js"))
  in
  let catch_keeps_link () =
    let saved = !Yuka.Server.log_error in
    Yuka.Server.log_error := ignore;
    let out =
      shell ~preload (fun () ->
          Yuka.fragment
            [ Yuka.Catch.make
                ~fallback:(fun ~error:_ ~reset:_ -> Yuka.text "f")
                ~children:(fun () ->
                  Yuka.fragment
                    [ isl "A";
                      Yuka.Private.element (Yuka.Private.Hole (fun () -> failwith "x")) ])
                ();
              isl "A" ])
    in
    Yuka.Server.log_error := saved;
    check int "the link of a dropped island is printed again" 1 (count out (link "/js/A.js"))
  in
  let no_function () =
    check bool "no link" false
      (contains (shell (fun () -> isl "A")) "modulepreload")
  in
  let none_result () =
    let out = shell ~preload:(fun _ -> None) (fun () -> isl "A") in
    check bool "no url, no link" false (contains out "modulepreload")
  in
  let escaped () =
    let out =
      shell ~preload:(fun _ -> Some "/a\"b&c.js") (fun () -> isl "A")
    in
    check bool "escaped" true (contains out (link "/a&quot;b&amp;c.js"))
  in
  let streamed () =
    let a, resolve, _ = Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka.Private.stream ~preload ~sleep:never_sleep ~write (fun () ->
          Yuka.fragment
            [ isl "A";
              Yuka.Await.make ~async:a ~loading:Yuka.empty
                ~children:(fun _ -> Yuka.fragment [ isl "A"; isl "B" ])
                () ])
    in
    resolve 0;
    get p;
    let all = chunks () in
    let shell = List.nth all 1 and fills = String.concat "" (List.tl (List.tl all)) in
    check int "A in the shell" 1 (count shell (link "/js/A.js"));
    check int "A not repeated in the part" 0 (count fills (link "/js/A.js"));
    check int "B first appears in the part" 1 (count fills (link "/js/B.js"));
    check bool "B not in the shell" false (contains shell "/js/B.js")
  in
  let respond_navigating () =
    check int "link in the settled body" 1
      (count (get (Yuka.Private.settled ~preload ~sleep:never_sleep (fun () -> isl "A"))) (link "/js/A.js"))
  in
  let outer_open = "<yuka-island data-name=\"Outer\"" in
  let between out =
    let find part from =
      let n = String.length part in
      let rec at i =
        if i + n > String.length out then -1
        else if String.sub out i n = part then i
        else at (i + 1)
      in
      at from
    in
    let o = find outer_open 0 in
    let c = find "</yuka-island>" (find "data-name=\"Inner\"" o) in
    let c = find "</yuka-island>" (c + 1) in
    (String.sub out o (c - o), String.sub out c (String.length out - c))
  in
  let outer_with child =
    Yuka.Client.island ~name:"Outer" ~props:(`Int 1) (fun () -> child ())
  in
  let nested_in_render () =
    let out =
      shell ~preload (fun () ->
          outer_with (fun () ->
              Yuka.Private.element
                (Yuka.Private.node (isl "Inner"))))
    in
    let inside, after = between out in
    check bool "no link inside the outer island" false (contains inside "<link");
    check bool "link right after the outer close, then its props" true
      (contains after
         ("</yuka-island><script type=\"application/json\" data-yuka-props=\"i1\">1</script>"
         ^ link "/js/Inner.js"));
    check int "outer link before the outer island" 1 (count out (link "/js/Outer.js"));
    check int "inner link once" 1 (count out (link "/js/Inner.js"))
  in
  let nested_in_slot () =
    let out =
      shell ~preload (fun () ->
          let s = Yuka.Slot.make (isl "Inner") in
          Yuka.Client.island ~name:"Outer" ~props:(`Int 1) (fun () -> Yuka.slot s))
    in
    let inside, after = between out in
    check bool "no link inside the outer island" false (contains inside "<link");
    check bool "link after the outer close" true (contains after (link "/js/Inner.js"));
    check int "inner link once" 1 (count out (link "/js/Inner.js"))
  in
  let nested_in_failed_catch () =
    let saved = !Yuka.Server.log_error in
    Yuka.Server.log_error := ignore;
    let out =
      shell ~preload (fun () ->
          outer_with (fun () ->
              Yuka.Catch.make
                ~fallback:(fun ~error:_ ~reset:_ -> Yuka.text "f")
                ~children:(fun () ->
                  Yuka.fragment
                    [ Yuka.Private.element (Yuka.Private.node (isl "Inner"));
                      Yuka.Private.element (Yuka.Private.Hole (fun () -> failwith "x")) ])
                ()))
    in
    Yuka.Server.log_error := saved;
    check int "no link for the dropped inner island" 0 (count out (link "/js/Inner.js"))
  in
  let nested_dedup () =
    let out =
      shell ~preload (fun () ->
          Yuka.fragment
            [ outer_with (fun () ->
                  Yuka.Private.element (Yuka.Private.node (isl "Inner")));
              isl "Inner" ])
    in
    check int "once across nested and later use" 1 (count out (link "/js/Inner.js"))
  in
  let await_in_island () =
    let a, resolve, _ = Async.make () in
    let write, chunks = recorder () in
    let p =
      Yuka.Private.stream ~preload ~sleep:never_sleep ~write (fun () ->
          Yuka.Client.island ~name:"Outer" ~props:(`Int 1) (fun () ->
              Yuka.Private.element
                (Yuka.Private.node
                   (Yuka.Await.make ~async:a ~loading:Yuka.empty
                      ~children:(fun _ -> isl "Inner")
                      ()))))
    in
    resolve 0;
    get p;
    let all = chunks () in
    let fills = List.tl (List.tl all) in
    let joined = String.concat "" fills in
    check int "link once in the response" 1 (count joined (link "/js/Inner.js"));
    let template_start =
      let n = String.length "<template" in
      let rec at i = if String.sub joined i n = "<template" then i else at (i + 1) in
      at 0
    in
    let close = "</template>" in
    let rec find i = if String.sub joined i (String.length close) = close then i else find (i + 1) in
    let moved = String.sub joined template_start (find template_start - template_start) in
    check bool "no link in the moved content" false (contains moved "<link");
    check bool "link before the template" true
      (contains joined (link "/js/Inner.js" ^ "<template"))
  in
  let manifest = {|{"Demo_shared.A":"./islands/a.js","Demo_shared.B":"demo/shared/b.js"}|} in
  let urls () =
    let f = Yuka.Private.preload_urls ~manifest ~base:"/assets/" () in
    check (option string) "leading ./ removed" (Some "/assets/islands/a.js")
      (f "Demo_shared.A");
    check (option string) "plain path" (Some "/assets/demo/shared/b.js")
      (f "Demo_shared.B");
    check (option string) "unknown" None (f "Nope")
  in
  let metafile =
    {|{"inputs":{},"outputs":{"dist/a-3F2A.js":{"entryPoint":"islands/a.js","bytes":10},"dist/chunk-X.js":{"bytes":5},"dist/b-9.js":{"entryPoint":"app/demo/shared/b.js"}}}|}
  in
  let urls_metafile () =
    let f = Yuka.Private.preload_urls ~manifest ~base:"/" ~metafile () in
    check (option string) "exact" (Some "/dist/a-3F2A.js") (f "Demo_shared.A");
    check (option string) "suffix only is no match" None (f "Demo_shared.B");
    let g =
      Yuka.Private.preload_urls ~manifest:{|{"X":"other.js"}|} ~base:"/" ~metafile ()
    in
    check (option string) "no output" None (g "X")
  in
  let urls_exact_wins () =
    let metafile =
      {|{"outputs":{"o/long.js":{"entryPoint":"x/islands/a.js"},"o/exact.js":{"entryPoint":"./islands/a.js"}}}|}
    in
    let f = Yuka.Private.preload_urls ~manifest ~base:"" ~metafile () in
    check (option string) "exact first" (Some "o/exact.js") (f "Demo_shared.A")
  in
  let urls_bad () =
    let bad f = match f () with _ -> false | exception Invalid_argument _ -> true in
    check bool "bad manifest" true
      (bad (fun () -> Yuka.Private.preload_urls ~manifest:"{" ~base:"" ()));
    check bool "manifest not an object" true
      (bad (fun () -> Yuka.Private.preload_urls ~manifest:"[]" ~base:"" ()));
    check bool "bad metafile" true
      (bad (fun () -> Yuka.Private.preload_urls ~manifest ~base:"" ~metafile:"x" ()));
    check bool "metafile without outputs" true
      (bad (fun () -> Yuka.Private.preload_urls ~manifest ~base:"" ~metafile:"{}" ()))
  in
  [ test_case "data-start from the trigger" `Quick data_start;
    test_case "preload once per island name" `Quick once;
    test_case "a dropped island in a Catch keeps the preload link" `Quick catch_keeps_link;
    test_case "no preload for lazy" `Quick lazy_none;
    test_case "no preload without the function" `Quick no_function;
    test_case "no preload without a url" `Quick none_result;
    test_case "preload url is escaped" `Quick escaped;
    test_case "preload in a streamed part" `Quick streamed;
    test_case "no preload inside an island (render)" `Quick nested_in_render;
    test_case "no preload inside an island (slot)" `Quick nested_in_slot;
    test_case "nested preload once" `Quick nested_dedup;
    test_case "no queued link for an island dropped by a Catch" `Quick nested_in_failed_catch;
    test_case "no preload in a fill inside an island" `Quick await_in_island;
    test_case "preload when navigating" `Quick respond_navigating;
    test_case "preload_urls without metafile" `Quick urls;
    test_case "preload_urls with metafile" `Quick urls_metafile;
    test_case "preload_urls matches only equal paths" `Quick urls_exact_wins;
    test_case "preload_urls bad input" `Quick urls_bad ]

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
      ("render_settled", settled_cases);
      ("early and navigation", navigation_cases);
      ("review fixes", review_cases);
      ("island loading", loading_cases);
    ]
