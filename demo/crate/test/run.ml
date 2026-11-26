open Crate_app

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/crate/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
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

(* A page with two elements of one view transition name has no view transition at all. *)
let names_unique html =
  let marker = "view-transition-name:cover-" in
  let rec names i acc =
    match String.index_from_opt html i 'v' with
    | None -> acc
    | Some j when j + String.length marker <= String.length html && String.sub html j (String.length marker) = marker ->
        let k = ref (j + String.length marker) in
        while !k < String.length html && html.[!k] >= '0' && html.[!k] <= '9' do incr k done;
        names !k (String.sub html j (!k - j) :: acc)
    | Some j -> names (j + 1) acc
  in
  let all = names 0 [] in
  Alcotest.(check int) "unique cover names" (List.length all) (List.length (List.sort_uniq compare all));
  all

let shelf () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check int) "every record" 16 (List.length (names_unique html));
  check_count html "a link to an album" 1 {|href="/album/7"|};
  let _, jazz = get "/?genre=Jazz" in
  Alcotest.(check int) "the jazz records" 4 (List.length (names_unique jazz));
  let _, unknown = get "/?genre=Polka" in
  Alcotest.(check int) "an unknown genre shows all" 16 (List.length (names_unique unknown))

let album () =
  let status, html = get "/album/1" in
  Alcotest.(check int) "status" 200 status;
  Alcotest.(check (list string))
    "its cover and the covers of the records around it, the first one after the last"
    [ "view-transition-name:cover-1"; "view-transition-name:cover-16"; "view-transition-name:cover-2" ]
    (List.sort compare (names_unique html));
  check_count html "tracks change with no view transition" 5 {|data-yuka-transition="off"|};
  check_count html "the arrow keys" 1 {|"previous":"/album/16","next":"/album/2"|};
  let _, playing = get "/album/1?track=2" in
  check_count playing "the playing track" 1 "Now playing: Blue Hours";
  let missing, _ = get "/album/99" in
  Alcotest.(check int) "an album that is not there" 404 missing

let () =
  Alcotest.run "crate"
    [ ("pages", [ Alcotest.test_case "shelf" `Quick shelf; Alcotest.test_case "album" `Quick album ]) ]
