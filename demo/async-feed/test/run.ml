open Async_feed_app
open Async_feed_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/async-feed/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
    ()

let handler = Dream.set_secret "test" @@ Dream.cookie_sessions @@ Yuka_dream.handler config Yuka_routes.app

let call ?(meth = `GET) ?(headers = []) ?(body = "") target =
  let response = Dream.test handler (Dream.request ~method_:meth ~headers ~target body) in
  (Dream.status_to_int (Dream.status response), response, Lwt_main.run (Dream.body response))

let get target =
  let status, _, body = call target in
  (status, body)

let count html needle =
  let n = String.length needle in
  let rec go i found =
    if i + n > String.length html then found else go (i + 1) (if String.sub html i n = needle then found + 1 else found)
  in
  go 0 0

let contains html needle = count html needle > 0
let check_has html name needle = Alcotest.(check bool) name true (contains html needle)

let clock () =
  Alcotest.(check string) "epoch" "Jan 1, 1970, 00:00:00 UTC" (Clock.utc 0);
  Alcotest.(check string) "leap day" "Feb 29, 2000, 13:05:09 UTC" (Clock.utc 951829509);
  Alcotest.(check string) "iso" "2000-02-29T13:05:09Z" (Clock.iso 951829509);
  Alcotest.(check string) "newest" "Nov 20, 2026, 09:01:40 UTC" (Clock.utc 1795165300)

let feed () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check int) "one page of cards" 50 (count html {|<li class="card" |});
  check_has html "newest first" {|data-id="5000"|};
  check_has html "time in UTC"
    {|<time class="card-time" datetime="2026-11-20T09:01:40Z" title="2026-11-20T09:01:40Z" data-ts="1795165300">Nov 20, 2026, 09:01:40 UTC</time>|};
  check_has html "count" "50 of 5000 events";
  check_has html "filters" {|aria-label="Filters"|};
  check_has html "project filter" ">Project</span>";
  check_has html "team filter" ">Team</span>";
  check_has html "assignee filter" ">Assignee</span>";
  check_has html "simulate button" "Simulate events";
  check_has html "settings" {|aria-label="Settings"|};
  check_has html "theme toggle" {|aria-label="Toggle light and dark theme"|};
  check_has html "older link" {|href="/?before=|};
  List.iter
    (fun source -> check_has html ("logo " ^ Model.source_label source) ("logo-" ^ Model.source_slug source))
    [ Model.New_relic; Vercel; Figma; Reddit; Github ]

let filtered () =
  let status, html = get "/?project=Billing&team=Growth" in
  Alcotest.(check int) "status" 200 status;
  let cards = count html {|<li class="card" |} in
  Alcotest.(check bool) "some cards" true (cards > 0);
  Alcotest.(check int) "each card has the project" cards (count html {|<span class="tag">Billing</span>|});
  Alcotest.(check int) "each card has the team" cards (count html {|<span class="tag">Growth</span>|});
  check_has html "chosen project in the button" ">Billing</span>";
  check_has html "older link keeps filters" {|href="/?project=Billing&amp;team=Growth&amp;before=|}

let before () =
  let _, html = get "/?before=1795165300" in
  Alcotest.(check bool) "newest left out" false (contains html {|data-id="5000"|});
  check_has html "next one first" {|data-id="4999"|};
  check_has html "back to latest" "Back to latest"

let simulated () =
  let event = Store.add ~now:0 in
  Alcotest.(check int) "next id" 5001 event.id;
  Alcotest.(check int) "after the newest" 1795165301 event.time;
  let _, html = get "/" in
  check_has html "new event on top" {|data-id="5001"|};
  Alcotest.(check bool) "in the live state" true (List.exists (fun (e : Model.event) -> e.id = 5001) (Store.recent ()))

let post_comment item text =
  let status, _, body =
    call ~meth:`POST
      ~headers:[ ("Content-Type", "application/json"); ("Origin", "http://feed.test"); ("Host", "feed.test") ]
      ~body:(Yuka.Json.to_string (`Assoc [ ("item", `Int item); ("text", `String text) ]))
      "/_yuka/action/async_feed_comment"
  in
  (status, body)

let comment_buttons () =
  let _, html = get "/" in
  Alcotest.(check int) "a comment link on each card" 50 (count html {|<a class="comment-button" href="/item/|});
  check_has html "count of a card with no comments" {|href="/item/5000" aria-label="0 comments"|};
  check_has html "count of a card with seeded comments" {|href="/item/4999" aria-label="2 comments"|}

let item_page () =
  let status, html = get "/item/4999" in
  Alcotest.(check int) "status" 200 status;
  check_has html "the panel" {|<aside class="sheet-panel" role="dialog" aria-modal="true"|};
  check_has html "over the feed" {|data-id="4998"|};
  check_has html "the source link opens a new tab" {|target="_blank" rel="noopener"|};
  check_has html "a source-specific field" "<dt>Subreddit</dt>";
  check_has html "the seeded comments" {|class="comment-text"|};
  check_has html "the exact time in UTC before the zone script" {|class="detail-time" datetime=|};
  check_has html "the form" {|id="overlay-comment-text"|};
  let status, _ = get "/item/99999" in
  Alcotest.(check int) "an unknown item" 404 status;
  let status, html = get "/item/10" in
  Alcotest.(check int) "a New Relic item" 200 status;
  check_has html "New Relic fields" "<dt>Severity</dt>"

let item_overlay () =
  let _, response, html = call ~headers:[ ("Yuka-Navigate", "L0"); ("Yuka-Overlay", "1") ] "/item/4999" in
  Alcotest.(check (option string)) "an overlay answer" (Some "overlay") (Dream.header response "yuka-layer");
  check_has html "the panel" {|class="sheet-panel"|};
  Alcotest.(check bool) "no feed under it" false (contains html {|<li class="card"|});
  Alcotest.(check bool) "no header" false (contains html {|class="header"|})

let add_comment () =
  let before = List.length (Store.thread (Option.get (Store.find 4999))) in
  let status, body = post_comment 4999 "  Shipped the fix, please verify.  " in
  Alcotest.(check int) "status" 200 status;
  check_has body "the new comment is in the thread" {|"text":"Shipped the fix, please verify."|};
  let _, html = get "/" in
  check_has html "the card count"
    (Printf.sprintf {|href="/item/4999" aria-label="%d comments"|} (before + 1));
  let _, html = get "/item/4999" in
  check_has html "the thread after a reload" "Shipped the fix, please verify.";
  List.iter
    (fun (name, item, text) ->
      let status, body = post_comment item text in
      Alcotest.(check int) (name ^ " status") 400 status;
      Alcotest.(check bool) (name ^ " not added") false (contains body {|"author"|}))
    [
      ("empty", 4999, "   \n ");
      ("too long", 4999, String.make (Feed.max_comment + 1) 'a');
      ("unknown item", 99999, "Hello");
    ];
  let status, _ = post_comment 4999 (String.concat "" (List.init Feed.max_comment (fun _ -> "\u{e9}"))) in
  Alcotest.(check int) "the limit counts characters, not bytes" 200 status;
  Alcotest.(check int) "only the valid comments were kept" (before + 2) (List.length (Store.thread (Option.get (Store.find 4999))))

let () =
  Handlers.register ();
  Alcotest.run "async feed"
    [
      ("clock", [ Alcotest.test_case "UTC text" `Quick clock ]);
      ( "pages",
        [
          Alcotest.test_case "feed" `Quick feed;
          Alcotest.test_case "filters" `Quick filtered;
          Alcotest.test_case "before" `Quick before;
          Alcotest.test_case "simulated event" `Quick simulated;
        ] );
      ( "comments",
        [
          Alcotest.test_case "comment links" `Quick comment_buttons;
          Alcotest.test_case "item page" `Quick item_page;
          Alcotest.test_case "item overlay" `Quick item_overlay;
          Alcotest.test_case "add a comment" `Quick add_comment;
        ] );
    ]
