let handler = Yuka_dream.handler (Yuka.Server.config ~head:Demo_index.Pages.head ()) Demo_index.Yuka_routes.app

let get target =
  let response = Dream.test handler (Dream.request ~target "") in
  (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

let contains html needle =
  let n = String.length needle in
  let rec go i = i + n <= String.length html && (String.sub html i n = needle || go (i + 1)) in
  go 0

let home () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check bool) "title" true (contains html "<title>Yuka demos</title>");
  Alcotest.(check bool) "link in a new tab" true
    (contains html {|<a href="/mini-linear" target="_blank" rel="noopener">Mini Linear</a>|});
  Alcotest.(check bool) "no script" false (contains html "<script")

let () = Alcotest.run "demo index" [ ("pages", [ Alcotest.test_case "home lists the demos" `Quick home ]) ]
