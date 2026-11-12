open Demo_app
open Demo_shared

let has html needle =
  if not (Model.Issue.contains ~sub:needle html) then
    Alcotest.failf "missing %S in@.%s" needle html

let lacks html needle =
  if Model.Issue.contains ~sub:needle html then Alcotest.failf "unexpected %S" needle

let config =
  Yuka.Server.config
    ~assets:(Yuka.Server.modules ~dir:"js" ~entry:"demo/client/main.js" ~manifest:"{}" ~packages:[] ~digest:"")
    ~public:[ ("/static", "static") ]
    ~styles:[ "/static/style.css" ] ()

let handler = Dream.set_secret "test" @@ Dream.cookie_sessions @@ Yuka_dream.handler config Routes_server.app

let call ?(meth = `GET) ?(headers = []) ?(body = "") target =
  let response = Dream.test handler (Dream.request ~method_:meth ~target ~headers body) in
  (Dream.status_to_int (Dream.status response), response, Lwt_main.run (Dream.body response))

let get target =
  let status, _, body = call target in
  Alcotest.(check int) ("status of " ^ target) 200 status;
  body

let header response name = Dream.header response name

let index () =
  let status, response, html = call "/" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check (option string)) "rule header" (Some "nosniff")
    (header response "x-content-type-options");
  Alcotest.(check (option string)) "cache" (Some "no-store") (header response "cache-control");
  has html "<title>Issues</title>";
  has html "My issues";
  has html "<a class=\"nav-link\" href=\"/\" aria-current=\"page\">Issues</a>";
  has html "<yuka-island data-name=\"Demo_shared.Issue_list\" data-id=\"i";
  has html "<yuka-island data-name=\"Demo_shared.New_issue\"";
  has html "<yuka-island data-name=\"Demo_shared.Counter\"";
  has html "<script type=\"module\" async src=\"/_yuka/app/demo/client/main.js\"></script>";
  has html "data-start=\"idle\"";
  lacks html "data-start=\"interaction\"";
  has html "\"id\":\"YUK-1\"";
  has html "\"status\":\"In_progress\"";
  has html "Hydration mismatch on nested holes";
  has html "Clicks: <!--[-->0<!--]-->";
  has html "<a class=\"row-title\" href=\"/issue/YUK-1\">"

let my_issues () =
  let html = get "/my" in
  has html "<a class=\"nav-link\" href=\"/my\" aria-current=\"page\">My issues</a>";
  has html "YUK-1";
  lacks html "YUK-6\""

let issue_page () =
  let html = get "/issue/YUK-1" in
  has html "<title>YUK-1</title>";
  has html "Hydration mismatch on nested holes";
  has html "Maya Chen";
  has html "Urgent";
  has html "<yuka-island data-name=\"Demo_shared.Comments\"";
  has html "Please add a test with an empty filter result.";
  has html "\"issue_id\":\"YUK-1\"";
  has html "<yuka-island data-name=\"Demo_shared.Related\"";
  has html "<yuka-island data-name=\"Demo_shared.Issue_props\"";
  has html "data-start=\"interaction\"";
  has html "data-start=\"visible\"";
  has html "\"$async\":\"a"

let streaming () =
  let html = get "/issue/YUK-1" in
  let index_of needle =
    let n = String.length needle in
    let rec go i =
      if i + n > String.length html then Alcotest.failf "no %S" needle
      else if String.sub html i n = needle then i
      else go (i + 1)
    in
    go 0
  in
  let shell = index_of "<div class=\"skeleton\">" in
  let fill = index_of "data-yuka-fill=\"s1\"" in
  let related = index_of "data-yuka-async=\"a1\"" in
  Alcotest.(check bool) "shell first" true (shell < fill);
  Alcotest.(check bool) "comments before related" true (fill < related);
  Alcotest.(check bool) "fill script" true (index_of "__yukaFill" < shell)

let navigation () =
  let _, response, html = call ~headers:[ ("Yuka-Navigate", "1") ] "/issue/YUK-1" in
  Alcotest.(check (option string)) "vary" (Some "Yuka-Navigate") (header response "vary");
  has html "Please add a test with an empty filter result.";
  lacks html "skeleton";
  lacks html "__yukaFill"

let not_found () =
  let status, response, html = call "/issue/NOPE" in
  Alcotest.(check int) "status" 404 status;
  Alcotest.(check (option string)) "no-store" (Some "no-store") (header response "cache-control");
  has html "Issue not found";
  has html "There is no issue NOPE.";
  let _, _, html = call "/issue/a%20b" in
  has html "There is no issue a b.";
  has html "class=\"sidebar\"";
  let status, _, html = call "/nowhere" in
  Alcotest.(check int) "status" 404 status;
  has html "Page not found"

let about () =
  let html = get "/about" in
  has html "<title>About</title>";
  lacks html "<script type=\"module\"";
  lacks html "__yukaFill";
  lacks html "modulepreload"

let form_post () =
  let headers = [ ("Content-Type", "application/x-www-form-urlencoded"); ("Origin", "http://demo.test"); ("Host", "demo.test") ] in
  let status, _, html =
    call ~meth:`POST ~headers ~body:"_yuka_action=create_issue&title=&description=kept+text&status=done&priority=high" "/new"
  in
  Alcotest.(check int) "422" 422 status;
  has html "Title is required";
  has html "kept text";
  has html {|<option value="done" selected="">|};
  let status, response, _ =
    call ~meth:`POST ~headers ~body:"_yuka_action=create_issue&title=From+a+form&description=&status=todo&priority=low" "/new"
  in
  Alcotest.(check int) "303" 303 status;
  let location = Option.value (header response "location") ~default:"" in
  Alcotest.(check bool) "to the new issue" true (String.length location > 11 && String.sub location 0 11 = "/issue/YUK-");
  has (get location) "From a form"

let prerendered () =
  let out = Filename.temp_dir "yuka_demo" "" in
  Lwt_main.run (Yuka_dream.prerender ~out (Yuka.Server.config ()) Routes_server.app);
  let handler = Yuka_dream.handler (Yuka.Server.config ~prerendered:out ()) Routes_server.app
  in
  let call meth =
    let response = Dream.test handler (Dream.request ~method_:meth ~target:"/about" "") in
    (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))
  in
  let status, body = call `GET in
  Alcotest.(check int) "GET" 200 status;
  has body "<title>About</title>";
  let status, body = call `HEAD in
  Alcotest.(check int) "HEAD" 200 status;
  Alcotest.(check string) "HEAD body" "" body

let rules () =
  let status, response, _ = call "/issues?x=1" in
  Alcotest.(check int) "redirect" 308 status;
  Alcotest.(check (option string)) "location" (Some "/?x=1") (header response "location");
  let status, response, _ = call ~meth:`POST "/issues.json" in
  Alcotest.(check int) "405" 405 status;
  Alcotest.(check (option string)) "allow" (Some "GET, HEAD, OPTIONS") (header response "allow");
  let status, response, body = call ~meth:`HEAD "/issues.json" in
  Alcotest.(check int) "HEAD" 200 status;
  Alcotest.(check string) "HEAD body" "" body;
  Alcotest.(check (option string)) "endpoint cache" (Some "public, max-age=60")
    (header response "cache-control");
  let body = get "/issues.json" in
  has body "\"id\":\"YUK-1\"";
  let status, _, _ = call "/static/x/../style.css" in
  Alcotest.(check int) "dot segment" 404 status

let action_route () =
  let status, _, body =
    call ~meth:`POST ~headers:[ ("Content-Type", "application/json"); ("Origin", "http://demo.test"); ("Host", "demo.test") ]
      ~body:{|{"issue_id":"YUK-2","body":"From the test"}|} "/_yuka/action/add_comment"
  in
  Alcotest.(check int) "status" 200 status;
  has body "From the test";
  let status, _, _ = call "/_yuka/action/add_comment" in
  Alcotest.(check int) "GET" 405 status

let fst3 (a, _, _) = a

module Yojson_like = struct
  let id text =
    match Yuka.Json.of_string text with
    | Ok (`Assoc f) -> ( match List.assoc_opt "id" f with Some (`Int i) -> Some i | _ -> None)
    | _ -> None
end

let settle async =
  Lwt_main.run (Lwt.pause ());
  match Yuka.Async.status async with
  | Yuka.Async.Done v -> Ok v
  | Failed m -> Error m
  | Pending -> Error "pending"

let actions () =
  (match
     settle
       (Yuka.Action.call Actions.update_issue
          { Actions.id = "YUK-4"; status = Some Model.Issue.Done; priority = None })
   with
  | Ok (i : Model.Issue.t) ->
      Alcotest.(check bool) "status changed" true (i.status = Model.Issue.Done);
      Alcotest.(check bool) "stored" true
        ((Option.get (Store.find "YUK-4")).status = Model.Issue.Done)
  | Error m -> Alcotest.failf "update failed: %s" m);
  (match
     settle
       (Yuka.Action.call Actions.create_issue
          { Actions.title = " "; description = ""; status = Model.Issue.Todo; priority = Model.Issue.Low })
   with
  | Ok (Error [ (Some `Title, "Title is required") ]) -> ()
  | _ -> Alcotest.fail "expected Title is required");
  (match
     settle
       (Yuka.Action.call Actions.create_issue
          {
            Actions.title = String.make 81 'x';
            description = "";
            status = Model.Issue.Todo;
            priority = Model.Issue.Low;
          })
   with
  | Ok (Error [ (Some `Title, "Title is too long (at most 80 characters)") ]) -> ()
  | _ -> Alcotest.fail "expected Title is too long");
  (match
     settle
       (Yuka.Action.call Actions.create_issue
          {
            Actions.title = "write the release notes";
            description = "";
            status = Model.Issue.Todo;
            priority = Model.Issue.Low;
          })
   with
  | Ok (Error [ (Some `Title, "An issue with this title already exists: YUK-25") ]) -> ()
  | _ -> Alcotest.fail "expected a duplicate title");
  (match
     settle
       (Yuka.Action.call Actions.update_issue
          { Actions.id = "NOPE"; status = None; priority = None })
   with
  | Ok _ -> Alcotest.fail "expected failure"
  | Error _ -> ());
  (match
     settle
       (Yuka.Action.call Actions.create_issue
          {
            Actions.title = "Brand new";
            description = "d";
            status = Model.Issue.Todo;
            priority = Model.Issue.High;
          })
   with
  | Ok (Ok (i : Model.Issue.t)) ->
      Alcotest.(check bool) "id" true (String.length i.id > 4 && String.sub i.id 0 4 = "YUK-");
      has (get "/") "Brand new"
  | _ -> Alcotest.fail "create failed");
  match
    settle
      (Yuka.Action.call Actions.add_comment
         { Actions.issue_id = "YUK-3"; body = "Nice work" })
  with
  | Ok (c : Model.Comment.t) ->
      Alcotest.(check string) "author" "Maya Chen" c.author.name;
      Alcotest.(check int) "stored" 2 (List.length (Store.comments_of "YUK-3"))
  | Error m -> Alcotest.failf "comment failed: %s" m

let live_answers () =
  let html = get "/" in
  has html {|data-yuka-answer="l:issues &quot;All&quot;">{"ok":[{"id":"YUK-|};
  has html {|data-yuka-answer="l:csrf">{"ok":"|};
  has html "<a class=\"row-title\" href=\"/issue/YUK-1\">";
  let html = get "/issue/YUK-2" in
  has html {|data-yuka-answer="l:issue &quot;YUK-2&quot;">|};
  lacks (get "/about") "l:csrf"

let live_publish () =
  let out = ref [] in
  let connection =
    let pending = ref [ {|{"t":"hello","v":1,"csrf":""}|}; {|{"t":"sub","id":1,"topic":"issues","key":"All"}|};
                        {|{"t":"sub","id":2,"topic":"issues","key":"Mine"}|}; {|{"t":"sub","id":3,"topic":"issue","key":"YUK-5"}|} ] in
    Yuka.Server.Live.connection
      ~send:(fun t -> out := t :: !out; Yuka.Async.return ())
      ~receive:(fun () ->
        match !pending with
        | x :: rest ->
            pending := rest;
            Yuka.Async.return (Some x)
        | [] -> fst3 (Yuka.Async.make ()))
      ~close:(fun _ -> Yuka.Async.return ())
  in
  let _ =
    Yuka.Server.Testing.live_run ~sleep:(fun _ -> fst3 (Yuka.Async.make ()))
      (Yuka.Server.Testing.context ~session:"s" ())
      ~verify_csrf:(fun _ -> Yuka.Async.return true) ~token:(fun () -> "t") connection
  in
  out := [];
  (match
     settle
       (Yuka.Action.call Actions.update_issue
          { Actions.id = "YUK-5"; status = Some Model.Issue.Canceled; priority = None })
   with
  | Ok _ -> ()
  | Error m -> Alcotest.failf "update failed: %s" m);
  let ids =
    List.sort compare
      (List.filter_map
         (fun t ->
           match Yojson_like.id t with Some id when Model.Issue.contains ~sub:{|"t":"state"|} t -> Some id | _ -> None)
         !out)
  in
  Alcotest.(check (list int)) "published to both views and the issue" [ 1; 2; 3 ] ids;
  Alcotest.(check bool) "the new status" true
    (List.exists (fun t -> Yojson_like.id t = Some 3 && Model.Issue.contains ~sub:"Canceled" t) !out)

let () =
  Handlers.register ();
  Alcotest.run "demo"
    [
      ( "pages",
        [
          Alcotest.test_case "index" `Quick index;
          Alcotest.test_case "my issues" `Quick my_issues;
          Alcotest.test_case "issue page" `Quick issue_page;
          Alcotest.test_case "streaming order" `Quick streaming;
          Alcotest.test_case "navigation" `Quick navigation;
          Alcotest.test_case "not found" `Quick not_found;
          Alcotest.test_case "about has no JavaScript" `Quick about;
          Alcotest.test_case "redirect, 405, HEAD, endpoint, assets" `Quick rules;
          Alcotest.test_case "prerendered /about, GET and HEAD" `Quick prerendered;
          Alcotest.test_case "the new issue form posts with no JavaScript" `Quick form_post;
          Alcotest.test_case "action route" `Quick action_route;
        ] );
      ("actions", [ Alcotest.test_case "store through actions" `Quick actions ]);
      ( "live",
        [
          Alcotest.test_case "pages embed the live state and a token" `Quick live_answers;
          Alcotest.test_case "update_issue publishes to both views and the issue" `Quick live_publish;
        ] );
    ]
