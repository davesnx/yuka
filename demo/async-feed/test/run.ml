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

let find html needle =
  let n = String.length needle in
  let rec go i = if i + n > String.length html then None else if String.sub html i n = needle then Some i else go (i + 1) in
  go 0

let check_has html name needle = Alcotest.(check bool) name true (contains html needle)

let clock () =
  Alcotest.(check string) "epoch" "Jan 1, 1970, 00:00:00 UTC" (Clock.utc 0);
  Alcotest.(check string) "leap day" "Feb 29, 2000, 13:05:09 UTC" (Clock.utc 951829509);
  Alcotest.(check string) "iso" "2000-02-29T13:05:09Z" (Clock.iso 951829509);
  Alcotest.(check string) "newest" "Nov 20, 2026, 09:01:40 UTC" (Clock.utc 1795165300)

let outlet_key html =
  let start = String.length {|<yuka-outlet data-k="|} + Option.get (find html {|<yuka-outlet data-k="|}) in
  String.sub html start (String.index_from html start '"' - start)

let with_cookie cookie target =
  let _, _, body = call ~headers:[ ("Cookie", cookie) ] target in
  body

let theme () =
  let toggle theme pressed =
    Printf.sprintf {|<button id="theme" class="icon-button theme-toggle" type="button" aria-label="Dark theme" title="Toggle theme" data-theme="%s" aria-pressed="%s">|}
      theme pressed
  in
  check_has (snd (get "/")) "no cookie follows the system" (toggle "system" "false");
  check_has (with_cookie "async-feed-theme=dark" "/") "the dark cookie" (toggle "dark" "true");
  check_has (with_cookie "async-feed-theme=light" "/item/4999") "the light cookie" (toggle "light" "false");
  check_has (with_cookie "async-feed-theme=blue" "/") "an unknown value follows the system" (toggle "system" "false")

let zone () =
  let script zone = Printf.sprintf {|data-name="zone">%s</script>|} zone in
  check_has (snd (get "/")) "no zone cookie" (script "null");
  check_has (with_cookie "async-feed-zone=America%2FNew_York" "/") "the zone cookie, decoded" (script {|"America/New_York"|});
  check_has (with_cookie "async-feed-zone=%3Cscript%3E" "/") "a zone with other characters is dropped" (script "null")

let kept_layout () =
  let key = outlet_key (snd (get "/")) in
  let _, response, html = call ~headers:[ ("Yuka-Navigate", key) ] "/?project=Billing" in
  Alcotest.(check (option string)) "a filter navigation keeps the layout" (Some key) (Dream.header response "yuka-outlet");
  Alcotest.(check bool) "no header" false (contains html {|class="header"|});
  let _, response, _ = call ~headers:[ ("Yuka-Navigate", key); ("Cookie", "async-feed-theme=dark") ] "/?project=Billing" in
  Alcotest.(check (option string)) "another theme renders the layout again" None (Dream.header response "yuka-outlet")

let local_time () =
  let _, html = get "/" in
  check_has html "the server prints the UTC time"
    {|<time class="card-time" datetime="2026-11-20T09:01:40Z" title="2026-11-20T09:01:40Z">Nov 20, 2026, 09:01:40 UTC</time>|};
  check_has html "as an island" {|<yuka-island data-name="Async_feed_shared.Local_time"|};
  check_has html "with the instant as a prop" {|{"time":1795165300,"class_":"card-time"}|}

let live_part () =
  let _, html = get "/" in
  check_has html "the latest page has the live feed" "Async_feed_shared.Live_feed";
  let _, html = get "/?before=1795165300" in
  Alcotest.(check bool) "an older page has no live feed" false (contains html "Async_feed_shared.Live_feed")

let feed () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check int) "one page of cards" 50 (count html {|<li class="card" |});
  check_has html "oldest of the page" {|data-id="4951"|};
  check_has html "newest of the page" {|data-id="5000"|};
  let pos_oldest = Option.get (find html {|data-id="4951"|}) in
  let pos_newest = Option.get (find html {|data-id="5000"|}) in
  Alcotest.(check bool) "sorted top to bottom (newest at bottom)" true (pos_oldest < pos_newest);
  Alcotest.(check bool) "no Notifications heading" false (contains html "Notifications");
  Alcotest.(check bool) "no 50 of 5000 events count" false (contains html "of 5000 events");
  Alcotest.(check bool) "description hidden on feed" false (contains html {|class="card-text"|});
  Alcotest.(check int) "a time island on each card" 50 (count html {|{"time":|});
  check_has html "sidebar filters" {|class="sidebar"|};
  check_has html "filters nav" {|aria-label="Filters"|};
  check_has html "project dropdown" {|id="project-button"|};
  check_has html "team dropdown" {|id="team-button"|};
  check_has html "assignee is a list, not a dropdown" {|class="assignee-list"|};
  Alcotest.(check bool) "no assignee dropdown" false (contains html {|id="assignee-button"|});
  check_has html "timezone directly in header" {|id="header-zone"|};
  check_has html "date directly in header" {|id="header-date"|};
  Alcotest.(check bool) "no settings popover button" false (contains html {|id="settings-button"|});
  check_has html "simulate button" "Simulate events";
  check_has html "theme toggle" {|aria-label="Dark theme"|};
  check_has html "older link" {|href="/?before=|};
  check_has html "fake user avatars rendered" {|class="user-avatar"|};
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
  check_has html "next one included" {|data-id="4999"|};
  check_has html "back to latest" "Back to latest"

let simulated () =
  let event = Store.add ~now:0 in
  Alcotest.(check int) "next id" 5001 event.id;
  Alcotest.(check int) "after the newest" 1795165301 event.time;
  let _, html = get "/" in
  check_has html "new event in feed" {|data-id="5001"|};
  let pos_5000 = Option.get (find html {|data-id="5000"|}) in
  let pos_5001 = Option.get (find html {|data-id="5001"|}) in
  Alcotest.(check bool) "new event is at the bottom" true (pos_5000 < pos_5001);
  Alcotest.(check bool) "in the live state" true (List.exists (fun (e : Model.event) -> e.id = 5001) (Store.recent ()))

let live_kept () =
  for _ = 1 to Feed.kept + 10 do
    ignore (Store.add ~now:0)
  done;
  let recent = Store.recent () in
  Alcotest.(check int) "the live state keeps 500 events" 500 (List.length recent);
  Alcotest.(check int) "the newest first" (Store.newest_id ()) (List.hd recent).id

let post_comment item text =
  let status, _, body =
    call ~meth:`POST
      ~headers:[ ("Content-Type", "application/json"); ("Origin", "http://feed.test"); ("Host", "feed.test") ]
      ~body:(Yuka.Json.to_string (`Assoc [ ("item", `Int item); ("text", `String text) ]))
      "/_yuka/action/async_feed_comment"
  in
  (status, body)

let comment_cards () =
  let _, html = get "/" in
  Alcotest.(check int) "entire card is a link" 50 (count html {|<a class="card-link" href="/item/|});
  Alcotest.(check bool) "no separate comment-button icon link" false (contains html {|class="comment-button"|});
  check_has html "count of a card with no comments" {|>0 comments</span>|};
  check_has html "count of a card with seeded comments" {|>2 comments</span>|}

let item_page () =
  let status, html = get "/item/4999" in
  Alcotest.(check int) "status" 200 status;
  check_has html "the panel" {|<aside class="sheet-panel" role="dialog" aria-modal="true"|};
  check_has html "split layout" {|class="sheet-split"|};
  check_has html "main pane" {|class="sheet-main"|};
  check_has html "metadata pane" {|class="sheet-meta"|};
  check_has html "over the feed" {|data-id="4998"|};
  check_has html "the source link opens a new tab" {|target="_blank" rel="noopener"|};
  check_has html "a source-specific field" "<dt>Subreddit</dt>";
  check_has html "reddit iframe embed" {|<iframe class="embed-frame embed-reddit" src="/embed/4999"|};
  check_has html "upvote velocity chart" "Upvote velocity";
  check_has html "the seeded comments" {|class="comment-text"|};
  check_has html "the detail time island" {|"class_":"detail-time"|};
  check_has html "the comment time island" {|"class_":"comment-time"|};
  check_has html "the form" {|id="overlay-comment-text"|};
  let status, embed_html = get "/embed/4999" in
  Alcotest.(check int) "reddit embed route" 200 status;
  check_has embed_html "reddit OG card" {|class="og-card"|};
  let status, _ = get "/item/99999" in
  Alcotest.(check int) "an unknown item" 404 status;
  let status, html = get "/item/10" in
  Alcotest.(check int) "a New Relic item" 200 status;
  check_has html "New Relic fields" "<dt>Severity</dt>";
  check_has html "New Relic uptime graph" {|class="uptime-bars"|};
  let status, html = get "/item/4" in
  Alcotest.(check int) "a Figma item" 200 status;
  check_has html "Figma iframe embed" {|<iframe class="embed-frame embed-figma" src="/embed/4"|};
  let status, figma_embed = get "/embed/4" in
  Alcotest.(check int) "figma embed route" 200 status;
  check_has figma_embed "figma canvas" {|class="figma-canvas"|};
  let status, html = get "/item/2" in
  Alcotest.(check int) "a Vercel item" 200 status;
  check_has html "Vercel build waterfall" {|class="waterfall"|};
  let status, html = get "/item/3" in
  Alcotest.(check int) "a GitHub item" 200 status;
  check_has html "GitHub CI checks" {|class="checks-strip"|}

let item_overlay () =
  let key = outlet_key (snd (get "/")) in
  let _, response, html = call ~headers:[ ("Yuka-Navigate", key); ("Yuka-Overlay", "1") ] "/item/4999" in
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
    (Printf.sprintf {|data-count="%d">%d comments</span>|} (before + 1) (before + 1));
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
          Alcotest.test_case "local time" `Quick local_time;
          Alcotest.test_case "theme cookie" `Quick theme;
          Alcotest.test_case "zone cookie" `Quick zone;
          Alcotest.test_case "kept layout" `Quick kept_layout;
          Alcotest.test_case "live part" `Quick live_part;
          Alcotest.test_case "filters" `Quick filtered;
          Alcotest.test_case "before" `Quick before;
          Alcotest.test_case "simulated event" `Quick simulated;
        ] );
      ( "comments",
        [
          Alcotest.test_case "card links" `Quick comment_cards;
          Alcotest.test_case "item page" `Quick item_page;
          Alcotest.test_case "item overlay" `Quick item_overlay;
          Alcotest.test_case "add a comment" `Quick add_comment;
        ] );
      ("live", [ Alcotest.test_case "kept events" `Quick live_kept ]);
    ]
