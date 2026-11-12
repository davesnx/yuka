open Yuka

let check = Cases.check
let ints = string_of_int

let fallback ~error ~reset =
  element "p" [ attr "class" "fallback"; on "click" (fun _ -> reset ()) ] [ text ("caught " ^ error) ]

let shown c = Dom_cases.text_content c

let render tree =
  let c = Dom_cases.container "" in
  let dispose = Private.render (Dom_cases.as_element c) tree in
  (c, dispose)

let boundary children = Catch.make ~fallback ~children ()

let catch_first_effect () =
  let c, dispose =
    render (fun () ->
        Dom_cases.div []
          [ text "a";
            boundary (fun () ->
                Effect.run (fun () -> failwith "first");
                Dom_cases.span [ text "x" ]);
            text "b" ])
  in
  check "an error in the first run of an effect" {|acaught Failure(first)b|} (shown c);
  dispose ()

let flush_tree s ~wrap =
  Dom_cases.div []
    [ wrap (fun () ->
          Effect.run (fun () -> State.set s 1);
          Dom_cases.span [ text "ok" ]) ]

let render_error tree =
  let c = Dom_cases.container "" in
  match Private.render (Dom_cases.as_element c) tree with
  | dispose ->
      dispose ();
      ("no error", shown c)
  | exception Failure m -> ("Failure(" ^ m ^ ")", shown c)

let catch_other_effect_error () =
  let run ~wrap =
    let s = State.make 0 in
    let (), stop_b = owner (fun () -> Effect.run (fun () -> if State.get s = 1 then failwith "B")) in
    let result = render_error (fun () -> flush_tree s ~wrap) in
    stop_b ();
    result
  in
  let plain_error, _ = run ~wrap:(fun f -> f ()) in
  let error, dom = run ~wrap:boundary in
  check "without a boundary, B's error leaves render" "Failure(B)" plain_error;
  check "with a boundary, B's error leaves render the same way" plain_error error;
  check "the boundary did not show B's error" "false"
    (string_of_bool (String.length dom >= 6 && String.sub dom 0 6 = "caught"))

let catch_render () =
  let c, dispose =
    render (fun () ->
        Dom_cases.div [] [ text "a"; boundary (fun () -> Dom_cases.span [ text "x"; failwith "render" ]); text "b" ])
  in
  check "fallback replaces the children" {|acaught Failure(render)b|} (shown c);
  dispose ()

let catch_effect () =
  let n = State.make 0 and cleaned = ref 0 and runs = ref 0 in
  let child () =
    Effect.run ~cleanup:(fun () -> incr cleaned) (fun () -> ignore (State.get n));
    Effect.run (fun () ->
        incr runs;
        if State.get n = 1 then failwith "effect");
    Dom_cases.span [ text "ok" ]
  in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  check "children" "ok" (shown c);
  State.set n 1;
  check "fallback" {|caught Failure(effect)|} (shown c);
  check "the cleanup of a sibling effect ran" "2" (ints !cleaned);
  State.set n 2;
  check "the effects of the children stopped" "2" (ints !runs);
  dispose ()

let catch_cleanup () =
  let n = State.make 0 in
  let child () =
    Effect.run
      ~cleanup:(fun () -> if State.peek n > 0 then failwith "cleanup")
      (fun () -> ignore (State.get n));
    Dom_cases.span [ text "ok" ]
  in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  State.set n 1;
  check "an error in a cleanup" {|caught Failure(cleanup)|} (shown c);
  dispose ()

let catch_memo () =
  let n = State.make 0 in
  let child () =
    let m = State.memo (fun () -> if State.get n > 0 then failwith "memo" else 7) in
    Dom_cases.span [ hole (fun () -> text (ints (State.get m))) ]
  in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  check "memo value" "7" (shown c);
  State.set n 1;
  check "an error in a memo" {|caught Failure(memo)|} (shown c);
  dispose ()

let catch_hole () =
  let n = State.make 0 in
  let child () =
    Dom_cases.span [ hole (fun () -> if State.get n > 0 then failwith "hole" else text "ok") ]
  in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  State.set n 1;
  check "an error in a hole that runs again" {|caught Failure(hole)|} (shown c);
  dispose ()

let catch_each_row () =
  let items = State.make [| "a" |] in
  let child () =
    Dom_cases.div []
      [ each ~key:Fun.id (fun () -> State.get items)
          (fun s -> if s = "bad" then failwith "row" else Dom_cases.span [ text s ]) ]
  in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  State.set items [| "a"; "bad" |];
  check "an error in a new row" {|caught Failure(row)|} (shown c);
  dispose ()

let catch_each_duplicate_key () =
  let items = State.make [| "a"; "b" |] in
  let c, dispose =
    render (fun () ->
        Dom_cases.div [] [ boundary (fun () -> Dom_cases.div [] [ each ~key:Fun.id (fun () -> State.get items) text ]) ])
  in
  State.set items [| "b"; "a"; "b" |];
  check "a duplicate key in an update" {|caught Failure(Yuka.each: duplicate key b)|} (shown c);
  dispose ()

let catch_click () =
  let n = State.make 0 in
  let child () =
    Dom_cases.div []
      [ Dom_cases.span [ hole (fun () -> text (ints (State.get n))) ];
        element "button" [ on "click" (fun _ -> State.update n succ; failwith "click") ] [] ]
  in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  Dom_cases.click (Dom_cases.query c "button");
  check "an error in an event handler" {|caught Failure(click)|} (shown c);
  dispose ()

let catch_focus () =
  let child () = element "input" [ on "focus" (fun _ -> failwith "focus") ] [] in
  let c, dispose = render (fun () -> Dom_cases.div [] [ boundary child ]) in
  Dom_cases.dispatch (Dom_cases.query c "input") (Dom_cases.nonbubbling "focus");
  check "an error in a non-bubbling handler" {|caught Failure(focus)|} (shown c);
  dispose ()

let catch_reset () =
  let parent = State.make 5 and fail = ref true in
  let child () =
    let n = State.make 0 in
    Dom_cases.div []
      [ element "button" [ attr "id" "inc"; on "click" (fun _ -> State.update n succ) ] [];
        element "i" [] [ hole (fun () -> text (ints (State.get n))) ];
        element "button"
          [ attr "id" "bad"; on "click" (fun _ -> if !fail then failwith "bad") ]
          [] ]
  in
  let c, dispose =
    render (fun () ->
        Dom_cases.div []
          [ element "b" [] [ hole (fun () -> text (ints (State.get parent))) ]; boundary child ])
  in
  Dom_cases.click (Dom_cases.query c "#inc");
  Dom_cases.click (Dom_cases.query c "#inc");
  check "child state" "52" (shown c);
  State.set parent 6;
  Dom_cases.click (Dom_cases.query c "#bad");
  check "fallback" {|6caught Failure(bad)|} (shown c);
  fail := false;
  Dom_cases.click (Dom_cases.query c ".fallback");
  check "reset: the children start from their first state, the parent keeps its value"
    "60" (shown c);
  Dom_cases.click (Dom_cases.query c "#inc");
  check "the new children work" "61" (shown c);
  dispose ()

let catch_nested () =
  let n = State.make 0 in
  let c, dispose =
    render (fun () ->
        Dom_cases.div []
          [ Catch.make
              ~fallback:(fun ~error ~reset:_ -> text ("outer " ^ error))
              ~children:(fun () ->
                Dom_cases.div []
                  [ Dom_cases.span [ text "o" ];
                    boundary (fun () ->
                        Dom_cases.span [ hole (fun () -> if State.get n = 1 then failwith "inner" else text "i") ]) ])
              () ])
  in
  State.set n 1;
  check "the nearest boundary catches" {|ocaught Failure(inner)|} (shown c);
  dispose ()

let catch_fallback_error () =
  let c, dispose =
    render (fun () ->
        Dom_cases.div []
          [ boundary (fun () ->
                Dom_cases.div []
                  [ text "o";
                    Catch.make
                      ~fallback:(fun ~error:_ ~reset:_ -> failwith "fallback")
                      ~children:(fun () -> failwith "inner")
                      () ]) ])
  in
  check "an error in the fallback goes to the boundary above" {|caught Failure(fallback)|}
    (shown c);
  dispose ()

let server_fails = ref false

let hydratable () =
  Dom_cases.div []
    [ boundary (fun () -> if !server_fails then failwith "server only" else Dom_cases.span [ text "ok" ]) ]

let catch_hydrate_fallback () =
  server_fails := true;
  let html, logged = Cases.logged (fun () -> Dom_cases.server (hydratable ())) in
  check "server log" "Yuka.Catch: Failure(server only)" (String.concat "|" logged);
  check "server html" "<div><!--[!--><p class=\"fallback\">caught server error</p><!--]--></div>" html;
  server_fails := false;
  let island = Dom_cases.create (Dom_cases.document ()) "yuka-island" in
  Dom_cases.append (Dom_cases.body ()) island;
  Dom_cases.set_html island html;
  let p = Dom_cases.query island "p" in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element island) hydratable in
  check "no mismatch" "" (Dom_cases.warnings ());
  Dom_cases.same "the fallback is adopted" p (Dom_cases.query island "p");
  Dom_cases.click p;
  check "reset renders the children on the client" "<div><!--[!--><span>ok</span><!--]--></div>"
    (Dom_cases.html island);
  dispose ()

let catch_hydrate_children () =
  let html = Dom_cases.server (hydratable ()) in
  let island = Dom_cases.create (Dom_cases.document ()) "yuka-island" in
  Dom_cases.append (Dom_cases.body ()) island;
  Dom_cases.set_html island html;
  let span = Dom_cases.query island "span" in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element island) hydratable in
  check "no mismatch" "" (Dom_cases.warnings ());
  Dom_cases.same "the children are adopted" span (Dom_cases.query island "span");
  dispose ()

let show_view status =
  Show.make ~status
    ~loading:(text "loading")
    ~failed:(fun e -> text ("failed " ^ Status.error_to_string e))
    ~children:(fun d -> element "b" [] [ text d ])
    ()

let show_client () =
  let st = State.make Status.Idle in
  let c, dispose = render (fun () -> show_view (fun () -> State.get st)) in
  check "idle" "loading" (shown c);
  State.set st (Status.Loading None);
  check "loading" "loading" (shown c);
  State.set st (Status.Ready { data = "a"; stale = false });
  check "ready" "a" (shown c);
  let b = Dom_cases.query c "b" in
  State.set st (Status.Loading (Some "a"));
  check "loading keeps the data" "a" (shown c);
  Dom_cases.same "same data, same node" b (Dom_cases.query c "b");
  State.set st (Status.Ready { data = "b"; stale = false });
  check "new data" "b" (shown c);
  State.set st (Status.Failed { error = Status.Network "down"; last = Some "b" });
  check "failed" "failed network error: down" (shown c);
  dispose ()

let show_hydrate () =
  List.iter
    (fun (name, st) ->
      let tree () = Dom_cases.div [] [ show_view (fun () -> st) ] in
      let logged, _ = Dom_cases.hydrate_logged (Dom_cases.server (tree ())) tree in
      check ("hydrate " ^ name) "" logged)
    [ ("idle", Status.Idle);
      ("loading", Status.Loading None);
      ("loading with data", Status.Loading (Some "d"));
      ("ready", Status.Ready { data = "d"; stale = false });
      ("failed", Status.Failed { error = Status.Server; last = None }) ]

let effect_view () =
  let n = State.make 0 in
  Effect.run (fun () -> if State.get n = 2 then failwith "effect");
  element "div" []
    [ element "span" [] [ hole (fun () -> text (ints (State.get n))) ];
      element "button" [ on "click" (fun _ -> State.update n succ) ] [ text "+" ] ]

let click_view () =
  let n = State.make 0 in
  element "div" []
    [ element "span" [] [ hole (fun () -> text (ints (State.get n))) ];
      element "button" [ on "click" (fun _ -> State.update n succ; failwith "click") ] [ text "!" ] ]

let without_boundary view expected =
  let c =
    Island_cases.setup_page
      (Island_cases.page [ runtime_island ~name:"Bad" ~props:(`Int 0) view; Island_cases.counter_island 10 ])
  in
  Island_cases.capture_errors ();
  let reported = ref [] in
  Yuka.render
    ~islands:(runtime_registry [ runtime_entry ~name:"Bad" (fun _ -> Ok view); Island_cases.counter_entry ])
    ~navigation:false
    ~on_error:(fun m -> reported := m :: !reported)
    ();
  let button i = (Dom_cases.query_all c "button").(i) in
  Dom_cases.click (button 0);
  Dom_cases.click (button 0);
  let after = Island_cases.spans c in
  Dom_cases.click (button 0);
  check "the island is stopped" after (Island_cases.spans c);
  Dom_cases.click (button 1);
  check "the other island works" (String.sub after 0 1 ^ ",11") (Island_cases.spans c);
  let logged = Island_cases.errors () in
  check "console.error" ("yuka island i1 (Bad): " ^ expected) logged;
  check "on_error" logged (String.concat "|" (List.rev !reported));
  after

let island_without_boundary_effect () =
  check "the DOM stays" "2,10" (without_boundary effect_view {|Failure(effect)|})

let island_without_boundary_click () =
  check "the DOM stays" "1,10" (without_boundary click_view {|Failure(click)|})

let island_boot_error () =
  let entry = runtime_entry ~name:"Bad" (fun _ -> Ok (fun () -> failwith "boot")) in
  let c =
    Island_cases.setup_page (Island_cases.page [ runtime_island ~name:"Bad" ~props:(`Int 0) (fun () -> Dom_cases.span [ text "server" ]) ])
  in
  Island_cases.capture_errors ();
  Island_cases.start_islands [ entry ];
  check "logged" {|yuka island i1 (Bad): Failure(boot)|} (Island_cases.errors ());
  check "server html kept" "server" (Island_cases.spans c)

let bad_rows () =
  Dom_cases.div [] [ each ~key:Fun.id (fun () -> [| "a"; "bad" |])
               (fun s -> if s = "bad" then failwith "row" else Dom_cases.span [ text s ]) ]

let catch_each_first_render () =
  let c, dispose = render (fun () -> Dom_cases.div [] [ text "a"; boundary bad_rows; text "b" ]) in
  check "a row that raises at first render" {|acaught Failure(row)b|} (shown c);
  dispose ()

let catch_each_first_hydrate () =
  let ok = ref true in
  let tree () = Dom_cases.div [] [ boundary (fun () -> if !ok then Dom_cases.span [ text "ok" ] else bad_rows ()) ] in
  let html = Dom_cases.server (tree ()) in
  ok := false;
  let island = Dom_cases.create (Dom_cases.document ()) "yuka-island" in
  Dom_cases.append (Dom_cases.body ()) island;
  Dom_cases.set_html island html;
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element island) tree in
  ignore (Dom_cases.warnings ());
  check "a row that raises during hydration"
    "<div><!--[--><p class=\"fallback\">caught Failure(row)</p><!--]--></div>" (Dom_cases.html island);
  dispose ()

let show_untracks_children () =
  let st = State.make (Status.Ready { data = "a"; stale = false }) and other = State.make "x" in
  let c, dispose =
    render (fun () ->
        Show.make
          ~status:(fun () -> State.get st)
          ~loading:(text "loading")
          ~children:(fun d -> element "b" [] [ text (d ^ State.get other) ])
          ())
  in
  let b = Dom_cases.query c "b" in
  State.set other "y";
  Dom_cases.same "a read in the children does not render Show again" b (Dom_cases.query c "b");
  check "text" "ax" (shown c);
  dispose ()

let handler_error_stops_event () =
  let outer = ref 0 in
  let c, dispose =
    render (fun () ->
        element "div"
          [ on "click" (fun _ -> incr outer) ]
          [ boundary (fun () -> element "button" [ on "click" (fun _ -> failwith "click") ] []) ])
  in
  batch (fun () -> Dom_cases.click (Dom_cases.query c "button"));
  check "fallback" {|caught Failure(click)|} (shown c);
  check "ancestor handlers do not run" "0" (ints !outer);
  dispose ()

let cleanup_on_dispose () =
  let items = State.make [| "a" |] and cleaned = ref 0 in
  let row _ =
    Effect.run ~cleanup:(fun () -> incr cleaned) ignore;
    Effect.run ~cleanup:(fun () -> failwith "cleanup") ignore;
    Dom_cases.span [ text "r" ]
  in
  let c, dispose =
    render (fun () ->
        Dom_cases.div [] [ boundary (fun () -> Dom_cases.div [] [ each ~key:Fun.id (fun () -> State.get items) row ]) ])
  in
  State.set items [||];
  check "fallback" {|caught Failure(cleanup)|} (shown c);
  check "the other cleanups of the owner ran" "1" (ints !cleaned);
  dispose ()

let looping_view () =
  boundary (fun () ->
      let s = State.make 0 in
      Effect.run (fun () -> if State.get s > 0 then State.set s (State.peek s + 1));
      element "button" [ on "click" (fun _ -> State.set s 1; failwith "x") ] [ text "go" ])

let flush_error_reported () =
  let c = Island_cases.setup_page (Island_cases.page [ runtime_island ~name:"Loop" ~props:(`Int 0) looping_view ]) in
  Island_cases.capture_errors ();
  let reported = ref [] in
  Yuka.render
    ~islands:(runtime_registry [ runtime_entry ~name:"Loop" (fun _ -> Ok looping_view) ])
    ~navigation:false
    ~on_error:(fun m -> reported := m :: !reported)
    ();
  Dom_cases.click (Dom_cases.query c "button");
  ignore (Island_cases.errors ());
  let text = String.concat "|" !reported in
  let n = String.length "100 update rounds" in
  let rec go i = i + n <= String.length text && (String.sub text i n = "100 update rounds" || go (i + 1)) in
  check "the Catch shows the handler error" "caught Failure(x)" (shown (Dom_cases.query c "p"));
  check "the update error goes to the island" "true" (string_of_bool (go 0))

let on_error_raises () =
  let c =
    Island_cases.setup_page
      (Island_cases.page [ runtime_island ~name:"Bad" ~props:(`Int 0) click_view; Island_cases.counter_island 10 ])
  in
  Island_cases.capture_errors ();
  Yuka.render
    ~islands:(runtime_registry [ runtime_entry ~name:"Bad" (fun _ -> Ok click_view); Island_cases.counter_entry ])
    ~navigation:false
    ~on_error:(fun _ -> failwith "reporter down")
    ();
  let button i = (Dom_cases.query_all c "button").(i) in
  Dom_cases.click (button 0);
  Dom_cases.click (button 0);
  ignore (Island_cases.errors ());
  check "the island stopped although on_error raised" "1,10" (Island_cases.spans c);
  Dom_cases.click (button 1);
  check "the other island works" "1,11" (Island_cases.spans c)

let cleanup_raises_view () =
  let n = State.make 0 in
  Effect.run ~cleanup:(fun () -> failwith "cleanup") ignore;
  Effect.run (fun () -> if State.get n = 1 then failwith "effect");
  element "div" []
    [ element "span" [] [ hole (fun () -> text (ints (State.get n))) ];
      element "button" [ on "click" (fun _ -> State.update n succ) ] [ text "+" ] ]

let island_dispose_raises () =
  check "the DOM stays" "1,10"
    (without_boundary cleanup_raises_view
       {|Failure(effect)|yuka island i1 (Bad): Failure(cleanup)|})

let island_start_dispose_raises () =
  let view () =
    Effect.run ~cleanup:(fun () -> failwith "cleanup") ignore;
    Effect.run (fun () -> failwith "first");
    Dom_cases.span [ text "x" ]
  in
  let c = Island_cases.setup_page (Island_cases.page [ runtime_island ~name:"Bad" ~props:(`Int 0) view; Island_cases.counter_island 10 ]) in
  Island_cases.capture_errors ();
  Island_cases.start_islands [ runtime_entry ~name:"Bad" (fun _ -> Ok view); Island_cases.counter_entry ];
  check "both errors logged"
    {|yuka island i1 (Bad): Failure(first)|yuka island i1 (Bad): Failure(cleanup)|} (Island_cases.errors ());
  Dom_cases.click (Dom_cases.query_all c "button").(0);
  check "the other island started" "x,11" (Island_cases.spans c)

let all =
  [
    ("catch: the update error of a raising handler is reported", flush_error_reported);
    ("catch: render", catch_render);
    ("catch: an error of another effect in the first flush", catch_other_effect_error);
    ("catch: first run of an effect", catch_first_effect);
    ("catch: effect after mount", catch_effect);
    ("catch: effect cleanup", catch_cleanup);
    ("catch: memo", catch_memo);
    ("catch: hole that runs again", catch_hole);
    ("catch: each row", catch_each_row);
    ("catch: each duplicate key", catch_each_duplicate_key);
    ("catch: event handler", catch_click);
    ("catch: non-bubbling handler", catch_focus);
    ("catch: reset", catch_reset);
    ("catch: each row that raises at first render", catch_each_first_render);
    ("catch: each row that raises during hydration", catch_each_first_hydrate);
    ("show: children are untracked", show_untracks_children);
    ("catch: a handler error stops the event", handler_error_stops_event);
    ("catch: a cleanup that raises on dispose", cleanup_on_dispose);
    ("island: on_error that raises", on_error_raises);
    ("island: a cleanup that raises while the island stops", island_dispose_raises);
    ("island: a cleanup that raises while a failed start stops", island_start_dispose_raises);
    ("catch: nested", catch_nested);
    ("catch: error in the fallback", catch_fallback_error);
    ("catch: hydrate a server fallback", catch_hydrate_fallback);
    ("catch: hydrate the children", catch_hydrate_children);
    ("show: client states", show_client);
    ("show: hydration", show_hydrate);
    ("island without a boundary: effect", island_without_boundary_effect);
    ("island without a boundary: click", island_without_boundary_click);
    ("island: an error at start keeps the server HTML", island_boot_error);
  ]
