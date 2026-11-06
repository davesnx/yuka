open Alcotest
module R = Yuka_router

let opt_string = option string

let href_cases =
  let issue = R.(s "issue" / string) in
  let t name f = test_case name `Quick f in
  [
    t "root" (fun () -> check string "root" "/" (R.href R.root));
    t "fixed" (fun () ->
        check string "fixed" "/a/b" (R.href R.(s "a" / s "b")));
    t "string" (fun () -> check string "string" "/issue/abc" (R.href issue "abc"));
    t "int" (fun () ->
        check string "int" "/n/-5" (R.href R.(s "n" / int) (-5)));
    t "two params" (fun () ->
        check string "two" "/p/x/7"
          (R.href R.(s "p" / string / int) "x" 7));
    t "encodes" (fun () ->
        check string "encoded" "/issue/a%2Fb%20c%3F%23%C3%A9"
          (R.href issue "a/b c?#\xc3\xa9"));
    t "query" (fun () ->
        check string "query" "/issue/1?q=a%20b%26c&x=%3D"
          (R.href ~query:[ ("q", "a b&c"); ("x", "=") ] issue "1"));
    t "bad segment" (fun () ->
        check bool "raises" true
          (match R.s "a/b" with exception Invalid_argument _ -> true | _ -> false);
        check bool "raises empty" true
          (match R.s "" with exception Invalid_argument _ -> true | _ -> false));
  ]

let parse_cases =
  let t name f = test_case name `Quick f in
  let issue = R.(s "issue" / string) in
  let show = Printf.sprintf in
  [
    t "root" (fun () ->
        check opt_string "root" (Some "root") (R.parse R.root "root" "/");
        check opt_string "empty" (Some "root") (R.parse R.root "root" "");
        check opt_string "other" None (R.parse R.root "root" "/a"));
    t "string param" (fun () ->
        check opt_string "match" (Some "id=abc")
          (R.parse issue (show "id=%s") "/issue/abc"));
    t "trailing slash" (fun () ->
        check opt_string "slash" (Some "id=abc")
          (R.parse issue (show "id=%s") "/issue/abc/"));
    t "query and fragment ignored" (fun () ->
        check opt_string "q" (Some "id=abc")
          (R.parse issue (show "id=%s") "/issue/abc?x=1&y=2#top"));
    t "decodes" (fun () ->
        check opt_string "decoded" (Some "id=a/b c\xc3\xa9")
          (R.parse issue (show "id=%s") "/issue/a%2Fb%20c%C3%A9"));
    t "bad percent kept" (fun () ->
        check opt_string "kept" (Some "id=100%")
          (R.parse issue (show "id=%s") "/issue/100%"));
    t "int param" (fun () ->
        let p = R.(s "n" / int) in
        check opt_string "int" (Some "7") (R.parse p string_of_int "/n/7");
        check opt_string "negative" (Some "-7") (R.parse p string_of_int "/n/-7");
        check opt_string "letters" None (R.parse p string_of_int "/n/x");
        check opt_string "hex" None (R.parse p string_of_int "/n/0x10");
        check opt_string "underscore" None (R.parse p string_of_int "/n/1_0");
        check opt_string "sign only" None (R.parse p string_of_int "/n/-");
        check opt_string "empty" None (R.parse p string_of_int "/n/"));
    t "two params in order" (fun () ->
        check opt_string "both" (Some "x:7")
          (R.parse R.(s "p" / string / int) (fun a b -> show "%s:%d" a b) "/p/x/7"));
    t "no match" (fun () ->
        check opt_string "wrong literal" None (R.parse issue (show "%s") "/ticket/1");
        check opt_string "too short" None (R.parse issue (show "%s") "/issue");
        check opt_string "too long" None (R.parse issue (show "%s") "/issue/1/2");
        check opt_string "prefix" None (R.parse R.(s "a") "x" "/a/b"));
    t "href then parse" (fun () ->
        let p = R.(s "p" / string / int) in
        let url = R.href p "a b/c" 3 in
        check opt_string "round trip" (Some "a b/c:3")
          (R.parse p (fun a b -> show "%s:%d" a b) url));
    t "query pairs" (fun () ->
        check
          (list (pair string string))
          "pairs"
          [ ("q", "a b"); ("x", ""); ("y", "1+2") ]
          (R.query "/a?q=a+b&x&y=1%2B2#f");
        check (list (pair string string)) "none" [] (R.query "/a");
        check (list (pair string string)) "empty" [] (R.query "/a?"));
  ]

let dispatch_cases =
  let t name f = test_case name `Quick f in
  let cases =
    [
      R.case R.(s "a" / s "new") "new";
      R.case R.(s "a" / string) (fun id -> "id " ^ id);
      R.case R.root "home";
    ]
  in
  [
    t "first match wins" (fun () ->
        check opt_string "new" (Some "new") (R.dispatch cases "/a/new");
        check opt_string "id" (Some "id 5") (R.dispatch cases "/a/5?x=1");
        check opt_string "root" (Some "home") (R.dispatch cases "/"));
    t "no case" (fun () ->
        check opt_string "none" None (R.dispatch cases "/b"));
  ]

let get target = Dream.request ~method_:`GET ~target ""

let body_of res = Lwt_main.run (Dream.body res)
let status_of res = Dream.status_to_int (Dream.status res)

let server_cases =
  let t name f = test_case name `Quick f in
  let handler =
    Yuka_router_server.handler
      ~not_found:(fun _ -> Dream.respond ~status:`Not_Found "custom 404")
      [
        R.case R.root (fun _ -> Dream.respond "home");
        R.case R.(s "issue" / int) (fun id req ->
            Dream.respond (Printf.sprintf "issue %d at %s" id (Dream.target req)));
        R.case R.(s "user" / string) (fun name _ -> Dream.respond ("user " ^ name));
      ]
  in
  let run target = Dream.test handler (get target) in
  [
    t "root" (fun () -> check string "body" "home" (body_of (run "/")));
    t "typed int and the request" (fun () ->
        check string "body" "issue 12 at /issue/12/?a=b"
          (body_of (run "/issue/12/?a=b")));
    t "decoded string" (fun () ->
        check string "body" "user a b" (body_of (run "/user/a%20b")));
    t "unknown path uses the caller 404" (fun () ->
        let res = run "/nothing" in
        check int "status" 404 (status_of res);
        check string "body" "custom 404" (body_of res));
    t "bad int is a 404" (fun () ->
        check int "status" 404 (status_of (run "/issue/x")));
    t "default 404" (fun () ->
        let res =
          Dream.test (Yuka_router_server.handler []) (get "/x")
        in
        check int "status" 404 (status_of res));
  ]

let () =
  run "router"
    [
      ("href", href_cases);
      ("parse", parse_cases);
      ("dispatch", dispatch_cases);
      ("server", server_cases);
    ]
