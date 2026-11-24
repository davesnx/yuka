open Infinite_scroll_app

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/infinite-scroll/client/main.js" ~manifest:"{}" ~packages:[]
            ~digest:""))
    ()

let handler = Yuka_dream.handler config Yuka_routes.app

let get target =
  let response = Dream.test handler (Dream.request ~target "") in
  (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

let count html needle =
  let n = String.length needle in
  let rec go i found =
    if i + n > String.length html then found else go (i + 1) (if String.sub html i n = needle then found + 1 else found)
  in
  go 0 0

let check_count html name expected needle = Alcotest.(check int) name expected (count html needle)

let first_page () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_count html "one page of palettes" 24 {|<article class="card">|};
  check_count html "skeleton cards" 8 {|class="card skeleton"|};
  check_count html "the watched skeleton" 1 {|<article id="next-page"|};
  check_count html "the island" 1 {|data-name="Infinite_scroll_shared.Load_more"|};
  check_count html "the next page" 1 {|"next":"/?pages=2"|}

let later_page () =
  let _, html = get "/?pages=2" in
  check_count html "two pages of palettes" 48 {|<article class="card">|};
  check_count html "the next page" 1 {|"next":"/?pages=3"|}

let last_page () =
  let _, html = get "/?pages=40" in
  check_count html "every palette" 960 {|<article class="card">|};
  check_count html "no skeleton" 0 {|class="card skeleton"|};
  check_count html "no next page" 1 {|"next":null|}

let () =
  Alcotest.run "infinite scroll"
    [
      ( "gallery",
        [
          Alcotest.test_case "first page" `Quick first_page;
          Alcotest.test_case "later page" `Quick later_page;
          Alcotest.test_case "last page" `Quick last_page;
        ] );
    ]
