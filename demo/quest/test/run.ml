open Quest_app

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/quest/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
    ()

let handler = Yuka_dream.handler config Yuka_routes.app

let get target =
  let response = Dream.test handler (Dream.request ~target "") in
  (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

let contains html needle =
  let n = String.length needle in
  let rec go i = i + n <= String.length html && (String.sub html i n = needle || go (i + 1)) in
  go 0

let check_contains html name needle = Alcotest.(check bool) name true (contains html needle)
let link (scene : Story.scene) = Printf.sprintf {|href="/scene/%s"|} scene.id

(* The scenes on the way through: the next one is the child that is not a leaf. *)
let rec spine (scene : Story.scene) =
  match List.filter (fun (child : Story.scene) -> child.children <> []) scene.children with
  | [ next ] -> scene :: spine next
  | _ -> [ scene ]

let riddles () = List.filter (fun (scene : Story.scene) -> match scene.view with Riddle _ -> true | _ -> false) (spine Story.root)

let opening () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_contains html "title" "<title>Ashfall</title>";
  check_contains html "the first exit" (link (List.hd Story.root.children));
  check_contains html "the HUD island" {|data-name="Quest_shared.Hud"|};
  check_contains html "the hotkeys island" {|data-name="Quest_shared.Hotkeys"|};
  check_contains html "the panel" {|class="panel"|}

let tree () =
  let riddles = riddles () in
  Alcotest.(check int) "five acts of five riddles" 25 (List.length riddles);
  List.iter
    (fun (riddle : Story.scene) ->
      Alcotest.(check int) "three answers" 3 (List.length riddle.children);
      Alcotest.(check int) "two deaths"
        2
        (List.length (List.filter (fun (child : Story.scene) -> child.children = []) riddle.children)))
    riddles;
  let last = List.rev (spine Story.root) |> List.hd in
  Alcotest.(check bool) "the way ends at the duel" true (match last.view with Duel _ -> true | _ -> false);
  Alcotest.(check bool)
    "ids are 12 hex digits" true
    (Hashtbl.fold
       (fun id _ ok -> ok && String.length id = 12 && String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) id)
       Story.scenes true)

let riddle_pages () =
  List.iter
    (fun (riddle : Story.scene) ->
      let status, html = get ("/scene/" ^ riddle.id) in
      Alcotest.(check int) "status" 200 status;
      List.iter (fun child -> check_contains html "a link to each answer" (link child)) riddle.children;
      match riddle.view with
      | Riddle { act; number } ->
          let { Story.prompt; _ } = List.nth Story.acts.(act).riddles number in
          check_contains html "the prompt" prompt
      | _ -> ())
    (riddles ())

let death () =
  let riddle = List.hd (riddles ()) in
  let death = List.find (fun (child : Story.scene) -> child.children = []) riddle.children in
  let status, html = get ("/scene/" ^ death.id) in
  Alcotest.(check int) "status" 200 status;
  check_contains html "the heading" "You have died";
  check_contains html "back to the riddle" (link riddle);
  check_contains html "the empty life globe" {|class="globe empty life"|}

(* The cell taken at each turn: a corner, the opposite corner, the block, then the fork
   wins. *)
let duel () =
  let duel = List.rev (spine Story.root) |> List.hd in
  let play (scene : Story.scene) cell =
    let exit = List.find (fun (exit : Story.exit) -> exit.label = Int.to_string cell) scene.exits in
    Option.get (Story.find exit.target)
  in
  let ending = List.fold_left play duel [ 0; 8; 6; 3 ] in
  Alcotest.(check bool) "the fork wins" true (match ending.view with Ending { outcome = Won; _ } -> true | _ -> false);
  let status, html = get ("/scene/" ^ ending.id) in
  Alcotest.(check int) "status" 200 status;
  check_contains html "the heading" "Victory";
  check_contains html "the winning line" "cell frost win"

let lost () =
  let status, _ = get "/scene/000000000000" in
  Alcotest.(check int) "an unknown scene" 404 status

let () =
  Pages.step := 0.;
  Alcotest.run "quest"
    [
      ( "story",
        [
          Alcotest.test_case "opening" `Quick opening;
          Alcotest.test_case "tree" `Quick tree;
          Alcotest.test_case "riddle pages" `Quick riddle_pages;
          Alcotest.test_case "death" `Quick death;
          Alcotest.test_case "duel" `Quick duel;
          Alcotest.test_case "unknown scene" `Quick lost;
        ] );
    ]
