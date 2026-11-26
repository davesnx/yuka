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
    (contains html {|<a class="card" href="/mini-linear" target="_blank" rel="noopener">|});
  Alcotest.(check bool) "Mini Linear name" true (contains html "<h2>Mini Linear</h2>");
  Alcotest.(check bool) "Async in a new tab" true
    (contains html {|<a class="card" href="/async-feed" target="_blank" rel="noopener">|});
  Alcotest.(check bool) "Async name" true (contains html "<h2>Async</h2>");
  Alcotest.(check bool) "Posters in a new tab" true
    (contains html {|<a class="card" href="/posters" target="_blank" rel="noopener">|});
  Alcotest.(check bool) "Posters name" true (contains html "<h2>Posters</h2>");
  Alcotest.(check bool) "Infinite scroll in a new tab" true
    (contains html {|<a class="card" href="/infinite-scroll" target="_blank" rel="noopener">|});
  Alcotest.(check bool) "Infinite scroll name" true (contains html "<h2>Infinite scroll</h2>");
  Alcotest.(check bool) "Genart in a new tab" true
    (contains html {|<a class="card" href="/genart" target="_blank" rel="noopener">|});
  Alcotest.(check bool) "Genart name" true (contains html "<h2>Genart</h2>");
  Alcotest.(check bool) "an illustration per card" true (contains html {|<svg class="art"|});
  Alcotest.(check bool) "no card number" false (contains html "/ Demo");
  Alcotest.(check bool) "no open link label" false (contains html "Open demo");
  Alcotest.(check bool) "no script" false (contains html "<script")

let () = Alcotest.run "demo index" [ ("pages", [ Alcotest.test_case "home lists the demos" `Quick home ]) ]
