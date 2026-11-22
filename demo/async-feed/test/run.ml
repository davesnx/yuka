open Async_feed_app
open Async_feed_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/async-feed/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
    ()

let handler = Dream.set_secret "test" @@ Dream.cookie_sessions @@ Yuka_dream.handler config Yuka_routes.app

let get target =
  let response = Dream.test handler (Dream.request ~target "") in
  (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

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
    ]
