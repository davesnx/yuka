open Demo_app
open Demo_shared

let has html needle =
  if not (Model.Issue.contains ~sub:needle html) then
    Alcotest.failf "missing %S in@.%s" needle html

let lacks html needle =
  if Model.Issue.contains ~sub:needle html then Alcotest.failf "unexpected %S" needle

let render = Yuka.Server.to_string

let index () =
  let html = render Pages.index in
  has html "My issues";
  has html "<yuka-island data-name=\"Demo_shared.Issue_list\" data-id=\"i";
  has html "<yuka-island data-name=\"Demo_shared.New_issue\"";
  has html "<yuka-island data-name=\"Demo_shared.Counter\"";
  has html "data-start=\"idle\"";
  lacks html "data-start=\"interaction\"";
  has html "data-yuka-props=\"i";
  has html "\"id\":\"YUK-1\"";
  has html "\"status\":\"In_progress\"";
  has html "Hydration mismatch on nested holes";
  has html "In Progress";
  has html "Clicks: <!--[-->0<!--]-->";
  has html "<a class=\"row-title\" href=\"/issue/YUK-1\">"

let my_issues () =
  let html = render Pages.my_issues in
  has html "YUK-1";
  lacks html "YUK-6\""

let issue_page () =
  let i = Option.get (Store.find "YUK-1") in
  let html = Lwt_main.run
      (Yuka_dream.to_lwt
         (Yuka.Server.render_settled ~sleep:Yuka_dream.sleep (fun () -> Pages.issue i))) in
  has html "Hydration mismatch on nested holes";
  has html "Maya Chen";
  has html "Urgent";
  has html "<yuka-island data-name=\"Demo_shared.Comments\"";
  has html "Please add a test with an empty filter result.";
  has html "\"issue_id\":\"YUK-1\"";
  has html "<yuka-island data-name=\"Demo_shared.Related\"";
  has html "<yuka-island data-name=\"Demo_shared.Issue_props\"";
  has html "data-start=\"interaction\"";
  has html "<!--[$-->";
  has html "data-start=\"visible\"";
  has html "\"$async\":\"a";
  lacks html "skeleton"

let pending_page () =
  let i = Option.get (Store.find "YUK-1") in
  let html = render (fun () -> Pages.issue ~delay:5. i) in
  has html "<div class=\"skeleton\">";
  lacks html "Please add a test with an empty filter result."

let streaming () =
  let i = Option.get (Store.find "YUK-1") in
  let chunks = ref [] in
  Lwt_main.run
    (Yuka_dream.to_lwt
       (Yuka.Server.stream ~sleep:Yuka_dream.sleep
          ~write:(fun c ->
            chunks := c :: !chunks;
            Yuka.Async.resolved ())
          (fun () -> Pages.issue ~delay:0.05 i)));
  let chunks = List.rev !chunks in
  let index_of needle =
    let rec go n = function
      | [] -> Alcotest.failf "no chunk with %S" needle
      | c :: rest -> if Model.Issue.contains ~sub:needle c then n else go (n + 1) rest
    in
    go 0 chunks
  in
  let shell = index_of "<div class=\"skeleton\">" in
  let fill = index_of "data-yuka-fill=\"s1\"" in
  let related = index_of "data-yuka-async=\"a1\"" in
  Alcotest.(check bool) "shell first" true (shell < fill);
  Alcotest.(check bool) "comments before related" true (fill < related);
  has (List.nth chunks fill) "Please add a test with an empty filter result."

let not_found () =
  let html = render (fun () -> Pages.not_found "YUK-999") in
  has html "Issue not found";
  has html "YUK-999"

let settle async =
  Lwt_main.run (Lwt.pause ());
  match Yuka.Async.status async with
  | Yuka.Async.Done v -> Ok v
  | Failed m -> Error m
  | Pending -> Error "pending"

let actions () =
  Handlers.register ();
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
  | Ok (Error Actions.Empty_title) -> ()
  | _ -> Alcotest.fail "expected Empty_title");
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
  | Ok (Error (Actions.Title_too_long 80)) -> ()
  | _ -> Alcotest.fail "expected Title_too_long");
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
  | Ok (Error (Actions.Duplicate_title "YUK-25")) -> ()
  | _ -> Alcotest.fail "expected Duplicate_title");
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
      Alcotest.(check string) "id" "YUK-26" i.id;
      has (render Pages.index) "Brand new"
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

let () =
  Alcotest.run "demo"
    [
      ( "pages",
        [
          Alcotest.test_case "index" `Quick index;
          Alcotest.test_case "my issues" `Quick my_issues;
          Alcotest.test_case "issue page" `Quick issue_page;
          Alcotest.test_case "pending page" `Quick pending_page;
          Alcotest.test_case "streaming order" `Quick streaming;
          Alcotest.test_case "not found" `Quick not_found;
        ] );
      ("actions", [ Alcotest.test_case "store through actions" `Quick actions ]);
    ]
