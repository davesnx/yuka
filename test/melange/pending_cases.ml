open Yuka

let check = Cases.check

type call = { label : string; resolve : (int, Status.error) result -> unit }

let calls : call list ref = ref []

let call label =
  let a, resolve, _ = Async.make () in
  calls := { label; resolve } :: !calls;
  a

let find label =
  match List.find_opt (fun c -> String.equal c.label label) !calls with
  | Some c -> c
  | None -> raise (Cases.Failed ("no call " ^ label))

let resolve label v = (find label).resolve (Ok v)
let reject label m = (find label).resolve (Error (Status.Rejected m))

let show = function
  | Status.Ready { data; _ } -> string_of_int data
  | Status.Loading None -> "…"
  | Status.Loading (Some d) -> string_of_int d ^ "~"
  | Status.Failed { error; _ } -> "E(" ^ Status.error_to_string error ^ ")"
  | Status.Idle -> "idle"

let memo label input = Async.memo (fun () -> call (label ^ State.get input))
let view r = hole (fun () -> text (show (State.get r)))
let busy_mark b = hole (fun () -> text (if State.get b then "[busy]" else ""))
let fallback name = Pending.make ~fallback:(text name)

let render tree =
  calls := [];
  let c = Dom_cases.container "" in
  let dispose = Private.render (Dom_cases.as_element c) tree in
  let seen = ref [ Dom_cases.text_content c ] in
  let step () =
    let now = Dom_cases.text_content c in
    match !seen with last :: _ when String.equal last now -> () | _ -> seen := now :: !seen
  in
  let history () = String.concat " | " (List.rev !seen) in
  (c, step, history, dispose)

let three_sources_one_switch () =
  let filter = State.make "0" in
  let c, step, history, dispose =
    render (fun () ->
        fallback "fallback"
          ~children:(fun () ->
            let a = memo "a" filter and b = memo "b" filter and d = memo "c" filter in
            let busy = Pending.busy () in
            fragment [ view a; text ","; view b; text ","; view d; text " "; busy_mark busy ])
          ())
  in
  let settle l v =
    resolve l v;
    step ()
  in
  settle "b0" 20;
  settle "a0" 10;
  settle "c0" 30;
  State.set filter "1";
  step ();
  settle "c1" 31;
  settle "a1" 11;
  settle "b1" 21;
  State.set filter "2";
  step ();
  settle "a2" 12;
  reject "c2" "boom";
  step ();
  settle "b2" 22;
  check "T2: three refetches switch the view once, and a failure switches with the group"
    "fallback | 10,20,30  | 10,20,30 [busy] | 11,21,31  | 11,21,31 [busy] | 12,22,E(boom) " (history ());
  ignore c;
  dispose ()

let nested filter =
  fallback "outer fallback"
    ~children:(fun () ->
      let a = memo "A" filter in
      fragment
        [ text "A="; view a; text " / ";
          fallback "inner fallback" ~children:(fun () -> fragment [ text "B="; view (memo "B" filter) ]) () ])
    ()

let nested_inner_first () =
  let filter = State.make "1" in
  let _, step, history, dispose = render (fun () -> nested filter) in
  resolve "B1" 2;
  step ();
  resolve "A1" 1;
  step ();
  State.set filter "2";
  step ();
  resolve "A2" 11;
  step ();
  resolve "B2" 12;
  step ();
  check "T3a: the first load follows the outer boundary, then each boundary switches alone"
    "outer fallback | A=1 / B=2 | A=11 / B=2 | A=11 / B=12" (history ());
  dispose ()

let nested_outer_first () =
  let filter = State.make "1" in
  let _, step, history, dispose = render (fun () -> nested filter) in
  resolve "A1" 1;
  step ();
  resolve "B1" 2;
  step ();
  check "T3b: the outer boundary shows the inner fallback until the inner source settles"
    "outer fallback | A=1 / inner fallback | A=1 / B=2" (history ());
  dispose ()

let busy_nearest () =
  let fa = State.make "a" and fb = State.make "b" in
  let outside = ref None in
  Dom_cases.capture_console ();
  let c, _, _, dispose =
    render (fun () ->
        outside := Some (Pending.busy ());
        fallback "F"
          ~children:(fun () ->
            let a = memo "A" fa in
            let outer = Pending.busy () in
            fragment
              [ text "A="; view a; text " outer="; busy_mark outer;
                fallback "f"
                  ~children:(fun () ->
                    let inner = Pending.busy () in
                    fragment [ text " B="; view (memo "B" fb); text " inner="; busy_mark inner ])
                  () ])
          ())
  in
  let logged = Dom_cases.console_calls () in
  let outside = Option.get !outside in
  let line () =
    Dom_cases.text_content c ^ " outside=" ^ if State.peek outside then "[busy]" else ""
  in
  resolve "Aa" 1;
  resolve "Bb" 2;
  let both = line () in
  State.set fa "x";
  let outer_runs = line () in
  resolve "Ax" 11;
  let outer_done = line () in
  State.set fb "y";
  let inner_runs = line () in
  resolve "By" 12;
  let inner_done = line () in
  check "T6: busy () answers for the nearest boundary only"
    (String.concat "\n"
       [ "A=1 outer= B=2 inner= outside=";
         "A=1 outer=[busy] B=2 inner= outside=";
         "A=11 outer= B=2 inner= outside=";
         "A=11 outer= B=2 inner=[busy] outside=";
         "A=11 outer= B=12 inner= outside=" ])
    (String.concat "\n" [ both; outer_runs; outer_done; inner_runs; inner_done ]);
  check "T6: busy () with no boundary writes a console error"
    "error yuka: Pending.busy () found no Pending above it, so it stays false" logged;
  dispose ()

let held_hole () =
  let tab = State.make "list" in
  let c, step, history, dispose =
    render (fun () ->
        fallback "F"
          ~children:(fun () ->
            let busy = Pending.busy () in
            fragment
              [ text "tab="; hole (fun () -> text (State.get tab)); text " | ";
                hole (fun () ->
                    match State.get tab with
                    | "list" -> text "list=1"
                    | t -> fragment [ text (t ^ "="); view (Async.memo (fun () -> call t)) ]);
                text " "; busy_mark busy ])
          ())
  in
  ignore c;
  State.set tab "detail";
  step ();
  State.set tab "settings";
  step ();
  resolve "detail" 5;
  step ();
  resolve "settings" 7;
  step ();
  check "T5b: a hole that makes new sources keeps its old content until they settle; the latest content wins"
    "tab=list | list=1  | tab=detail | list=1 [busy] | tab=settings | list=1 [busy] | tab=settings | settings=7 "
    (history ());
  dispose ()

let source_in_a_hole () =
  let _, step, history, dispose =
    render (fun () ->
        fallback "F"
          ~children:(fun () ->
            fragment
              [ view (Async.memo (fun () -> call "made")); text "+";
                hole (fun () -> view (Async.memo (fun () -> call "mounted"))) ])
          ())
  in
  resolve "made" 1;
  step ();
  resolve "mounted" 2;
  step ();
  check "a source made when the children mount holds the fallback too" "F | 1+2" (history ());
  dispose ()

let await_without_loading () =
  let a, set, _ = Async.make () in
  let _, step, history, dispose =
    render (fun () ->
        fallback "F"
          ~children:(fun () ->
            fragment [ text "v="; Await.make ~async:a ~children:(fun n -> text (string_of_int n)) () ])
          ())
  in
  set 4;
  step ();
  check "an Await with no loading joins the boundary" "F | v=4" (history ());
  dispose ()

let await_without_boundary () =
  let a, set, _ = Async.make () in
  Dom_cases.capture_console ();
  let c, step, history, dispose =
    render (fun () -> fragment [ text "v="; Await.make ~async:a ~children:(fun n -> text (string_of_int n)) () ])
  in
  let logged = Dom_cases.console_calls () in
  ignore c;
  set 4;
  step ();
  check "an Await with no loading and no Pending shows nothing until the value settles" "v= | v=4" (history ());
  check "dev error"
    "error yuka: an Await with no loading has no Pending above it, so it shows nothing until its value is settled"
    logged;
  dispose ()

let disposed_while_pending () =
  let c, _, _, dispose =
    render (fun () -> fallback "F" ~children:(fun () -> view (Async.memo (fun () -> call "x"))) ())
  in
  dispose ();
  resolve "x" 1;
  check "a late answer after disposal changes nothing" "F" (Dom_cases.text_content c)

let island tree =
  let island = Dom_cases.create (Dom_cases.document ()) "yuka-island" in
  Dom_cases.append (Dom_cases.body ()) island;
  Dom_cases.set_html island tree;
  island

let hydrated_view a =
  Dom_cases.div []
    [ Pending.make ~fallback:(element "i" [] [ text "F" ])
        ~children:(fun () -> Await.make ~async:a ~children:(fun n -> element "b" [] [ text (string_of_int n) ]) ())
        () ]

let hydrate_ready () =
  let html = Dom_cases.server (hydrated_view (Async.return 5)) in
  check "server html, all settled" "<div><!--[--><!--[--><b>5</b><!--]--><!--]--></div>" html;
  let c = island html in
  let b = Dom_cases.query c "b" in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element c) (fun () -> hydrated_view (Async.return 5)) in
  check "no mismatch" "" (Dom_cases.warnings ());
  Dom_cases.same "every source has its value: the children adopt the server nodes" b (Dom_cases.query c "b");
  check "html unchanged" html (Dom_cases.html c);
  dispose ()

let hydrate_hold () =
  let html = Dom_cases.server (hydrated_view (Async.return 5)) in
  let c = island html in
  let b = Dom_cases.query c "b" in
  let a, set, _ = Async.make () in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element c) (fun () -> hydrated_view a) in
  let held = Dom_cases.html c in
  Dom_cases.same "H1: a source pending at hydration keeps the server nodes" b (Dom_cases.query c "b");
  check "H1: no loading, no change" html held;
  set 6;
  check "no mismatch" "" (Dom_cases.warnings ());
  check "H1: new nodes replace the server nodes one time" "<div><!--[--><!--[--><b>6</b><!--]--><!--]--></div>"
    (Dom_cases.html c);
  dispose ()

let hydrate_fallback () =
  let a, set, _ = Async.make () in
  let html = Dom_cases.server (hydrated_view a) in
  check "server html, pending, not streamed" "<div><!--[--><!--[?--><i>F</i><!--]--><!--]--></div>" html;
  let c = island html in
  let i = Dom_cases.query c "i" in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element c) (fun () -> hydrated_view a) in
  check "no mismatch" "" (Dom_cases.warnings ());
  Dom_cases.same "the fallback is adopted" i (Dom_cases.query c "i");
  set 3;
  check "the children replace the fallback" "<div><!--[--><!--[--><b>3</b><!--]--><!--]--></div>" (Dom_cases.html c);
  dispose ()

let inside_a_hole () =
  let filter = State.make "a" and builds = ref 0 in
  let c, step, history, dispose =
    render (fun () ->
        Dom_cases.div []
          [ hole (fun () ->
                fallback "F"
                  ~children:(fun () ->
                    incr builds;
                    let r = memo "x" filter in
                    let busy = Pending.busy () in
                    fragment [ view r; text " "; busy_mark busy ])
                  ()) ])
  in
  ignore c;
  resolve "xa" 1;
  step ();
  State.set filter "b";
  step ();
  resolve "xb" 2;
  step ();
  check "a Pending in a hole is built one time" "1" (string_of_int !builds);
  check "a Pending in a hole holds and shows busy" "F | 1  | 1 [busy] | 2 " (history ());
  dispose ()

let hydrate_then_change () =
  let filter = State.make "a" in
  calls := [];
  let tree () =
    Dom_cases.div []
      [ hole (fun () ->
            fallback "F"
              ~children:(fun () ->
                let r =
                  Async.memo (fun () ->
                      match State.get filter with "a" -> Async.return (Ok 1) | f -> call ("x" ^ f))
                in
                let busy = Pending.busy () in
                fragment [ view r; text " "; busy_mark busy ])
              ()) ]
  in
  let html = Dom_cases.server (tree ()) in
  let c = island html in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element c) tree in
  check "no mismatch" "" (Dom_cases.warnings ());
  let at_start = Dom_cases.text_content c in
  State.set filter "b";
  let running = Dom_cases.text_content c in
  resolve "xb" 2;
  check "after hydration, a change holds and shows busy" "1  | 1 [busy] | 2 "
    (String.concat " | " [ at_start; running; Dom_cases.text_content c ]);
  dispose ()

let held_view_stays_live () =
  let tab = State.make "list" and clicks = State.make 0 in
  let c, _, _, dispose =
    render (fun () ->
        fallback "F"
          ~children:(fun () ->
            hole (fun () ->
                match State.get tab with
                | "list" ->
                    element "button"
                      [ on "click" (fun _ -> State.set clicks (State.peek clicks + 1)) ]
                      [ hole (fun () -> text ("clicks=" ^ string_of_int (State.get clicks))) ]
                | t -> fragment [ text (t ^ "="); view (Async.memo (fun () -> call t)) ]))
          ())
  in
  State.set tab "detail";
  let held = Dom_cases.text_content c in
  Dom_cases.click (Dom_cases.query c "button");
  let clicked = Dom_cases.text_content c in
  resolve "detail" 5;
  check "the old view of a held hole updates and takes events until the switch"
    "clicks=0 | clicks=1 | detail=5" (String.concat " | " [ held; clicked; Dom_cases.text_content c ]);
  dispose ()

let all =
  [
    ("pending: T2 three refetches, one switch", three_sources_one_switch);
    ("pending: T3a nested, inner settles first", nested_inner_first);
    ("pending: T3b nested, outer settles first", nested_outer_first);
    ("pending: T6 busy () of the nearest boundary", busy_nearest);
    ("pending: T5b a held hole", held_hole);
    ("pending: the old view of a held hole stays live", held_view_stays_live);
    ("pending: a source made at mount holds the fallback", source_in_a_hole);
    ("pending: Await with no loading joins", await_without_loading);
    ("pending: Await with no loading and no boundary", await_without_boundary);
    ("pending: disposal with a run in flight", disposed_while_pending);
    ("pending: hydration adopts when all is settled", hydrate_ready);
    ("pending: H1 hydration keeps the server nodes", hydrate_hold);
    ("pending: inside a hole", inside_a_hole);
    ("pending: hydration, then a change", hydrate_then_change);
    ("pending: hydration of a server fallback", hydrate_fallback);
  ]
