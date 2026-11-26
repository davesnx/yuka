open Utop_demo_app
open Utop_demo_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/utop/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
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

let first_session () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_count html "the title" 1 "<title>lists.ml — utop</title>";
  check_count html "the island" 1 {|data-name="Utop_demo_shared.Terminal"|};
  check_count html "the phrases of lists.ml" 5 {|<section class="phrase" |};
  check_count html "the prompt" 1 {|<input id="utop-input"|};
  check_count html "the selected file" 1 {|<a class="row selected" href="/?file=lists.ml" aria-current="page">|};
  check_count html "the banner" 1 "Welcome to utop version 2.15.0 (using OCaml version 5.3.0)!";
  check_count html "a highlighted type" 1 {|<span class="tk type">int list</span>|}

let other_session () =
  let _, html = get "/?file=variants.ml" in
  check_count html "the title" 1 "<title>variants.ml — utop</title>";
  check_count html "the phrases of variants.ml" 4 {|<section class="phrase" |};
  check_count html "the warning" 1 {|<span class="tk warning">Warning 8|};
  let _, html = get "/?file=nope.ml" in
  check_count html "an unknown file shows lists.ml" 1 "<title>lists.ml — utop</title>"

let answers = Session.lists.entries @ Session.extra

let answer ?(env = []) phrase = (Repl.evaluate ~answers ~env phrase).output

let repl () =
  let check = Alcotest.(check string) in
  check "a phrase of the history" "- : int = 15" (answer "List.fold_left  ( + ) 0 xs ;;");
  check "arithmetic" "- : int = 7" (answer "1 + 2 * 3;;");
  check "precedence and mod" "- : int = -1" (answer "-(7 mod 4) + 2 * (3 - 2);;");
  check "let" "val x : int = 42" (answer "let x = 6 * 7;;");
  check "a name of the env" "- : int = 43" (answer ~env:[ ("x", 42) ] "x + 1;;");
  check "unbound" "Line 1, characters 4-5:\nError: Unbound value y" (answer "1 + y;;");
  check "unbound in a let" "Line 1, characters 8-9:\nError: Unbound value z" (answer "let a = z;;");
  check "division by zero" "Exception: Division_by_zero." (answer "1 / 0;;");
  check "unknown directive" "Unknown directive \"nope\"." (answer "#nope;;");
  Alcotest.(check bool) "#quit" true (Repl.evaluate ~answers ~env:[] "#quit;;").quit;
  Alcotest.(check bool) "a phrase without ;; is not complete" false (Repl.complete "1 +");
  Alcotest.(check (list string)) "completion in a module" [ "fold_left"; "fold_right" ] (Repl.candidates ~env:[] "List.fo");
  check "accept" "List.fold_left" (Repl.accept "List.fo" "fold_left")

let highlight () =
  let kinds tokens = List.map (fun (kind, text) -> Highlight.class_of kind ^ ":" ^ text) tokens in
  Alcotest.(check (list string))
    "val" [ "tk keyword:val "; "tk name:xs "; "tk operator:: "; "tk type:int list"; "tk operator: = "; "tk punctuation:["; "tk number:1"; "tk punctuation:]" ]
    (kinds (List.hd (Highlight.answer "val xs : int list = [1]")))

let () =
  Alcotest.run "utop"
    [
      ( "page",
        [ Alcotest.test_case "first session" `Quick first_session; Alcotest.test_case "other session" `Quick other_session ] );
      ("repl", [ Alcotest.test_case "evaluate" `Quick repl; Alcotest.test_case "highlight" `Quick highlight ]);
    ]
