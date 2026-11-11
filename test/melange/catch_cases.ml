open Yuka
module D = Dom_cases
module I = Island_cases

let check = Cases.check
let ints = string_of_int

let fallback ~error ~reset =
  lower "p" [ attr "class" "fallback"; on "click" (fun _ -> reset ()) ] [ text ("caught " ^ error) ]

let shown c = D.text_content c

let render tree =
  let c = D.container "" in
  let dispose = Private.render (D.as_element c) tree in
  (c, dispose)

let boundary children = Catch.make ~fallback ~children ()

let catch_first_effect () =
  let c, dispose =
    render (fun () ->
        D.div []
          [ text "a";
            boundary (fun () ->
                Effect.run (fun () -> failwith "first");
                D.span [ text "x" ]);
            text "b" ])
  in
  check "an error in the first run of an effect" {|acaught Failure(first)b|} (shown c);
  dispose ()

let flush_tree s ~wrap =
  D.div []
    [ wrap (fun () ->
          Effect.run (fun () -> State.set s 1);
          D.span [ text "ok" ]) ]

let render_error tree =
  let c = D.container "" in
  match Private.render (D.as_element c) tree with
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
        D.div [] [ text "a"; boundary (fun () -> D.span [ text "x"; failwith "render" ]); text "b" ])
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
    D.span [ text "ok" ]
  in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
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
    D.span [ text "ok" ]
  in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
  State.set n 1;
  check "an error in a cleanup" {|caught Failure(cleanup)|} (shown c);
  dispose ()

let catch_memo () =
  let n = State.make 0 in
  let child () =
    let m = State.memo (fun () -> if State.get n > 0 then failwith "memo" else 7) in
    D.span [ hole (fun () -> text (ints (State.get m))) ]
  in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
  check "memo value" "7" (shown c);
  State.set n 1;
  check "an error in a memo" {|caught Failure(memo)|} (shown c);
  dispose ()

let catch_hole () =
  let n = State.make 0 in
  let child () =
    D.span [ hole (fun () -> if State.get n > 0 then failwith "hole" else text "ok") ]
  in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
  State.set n 1;
  check "an error in a hole that runs again" {|caught Failure(hole)|} (shown c);
  dispose ()

let catch_each_row () =
  let items = State.make [| "a" |] in
  let child () =
    D.div []
      [ each ~key:Fun.id (fun () -> State.get items)
          (fun s -> if s = "bad" then failwith "row" else D.span [ text s ]) ]
  in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
  State.set items [| "a"; "bad" |];
  check "an error in a new row" {|caught Failure(row)|} (shown c);
  dispose ()

let catch_each_duplicate_key () =
  let items = State.make [| "a"; "b" |] in
  let c, dispose =
    render (fun () ->
        D.div [] [ boundary (fun () -> D.div [] [ each ~key:Fun.id (fun () -> State.get items) text ]) ])
  in
  State.set items [| "b"; "a"; "b" |];
  check "a duplicate key in an update" {|caught Failure(Yuka.each: duplicate key b)|} (shown c);
  dispose ()

let catch_click () =
  let n = State.make 0 in
  let child () =
    D.div []
      [ D.span [ hole (fun () -> text (ints (State.get n))) ];
        lower "button" [ on "click" (fun _ -> State.update n succ; failwith "click") ] [] ]
  in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
  D.click (D.query c "button");
  check "an error in an event handler" {|caught Failure(click)|} (shown c);
  dispose ()

let catch_focus () =
  let child () = lower "input" [ on "focus" (fun _ -> failwith "focus") ] [] in
  let c, dispose = render (fun () -> D.div [] [ boundary child ]) in
  D.dispatch (D.query c "input") (D.nonbubbling "focus");
  check "an error in a non-bubbling handler" {|caught Failure(focus)|} (shown c);
  dispose ()

let catch_reset () =
  let parent = State.make 5 and fail = ref true in
  let child () =
    let n = State.make 0 in
    D.div []
      [ lower "button" [ attr "id" "inc"; on "click" (fun _ -> State.update n succ) ] [];
        lower "i" [] [ hole (fun () -> text (ints (State.get n))) ];
        lower "button"
          [ attr "id" "bad"; on "click" (fun _ -> if !fail then failwith "bad") ]
          [] ]
  in
  let c, dispose =
    render (fun () ->
        D.div []
          [ lower "b" [] [ hole (fun () -> text (ints (State.get parent))) ]; boundary child ])
  in
  D.click (D.query c "#inc");
  D.click (D.query c "#inc");
  check "child state" "52" (shown c);
  State.set parent 6;
  D.click (D.query c "#bad");
  check "fallback" {|6caught Failure(bad)|} (shown c);
  fail := false;
  D.click (D.query c ".fallback");
  check "reset: the children start from their first state, the parent keeps its value"
    "60" (shown c);
  D.click (D.query c "#inc");
  check "the new children work" "61" (shown c);
  dispose ()

let catch_nested () =
  let n = State.make 0 in
  let c, dispose =
    render (fun () ->
        D.div []
          [ Catch.make
              ~fallback:(fun ~error ~reset:_ -> text ("outer " ^ error))
              ~children:(fun () ->
                D.div []
                  [ D.span [ text "o" ];
                    boundary (fun () ->
                        D.span [ hole (fun () -> if State.get n = 1 then failwith "inner" else text "i") ]) ])
              () ])
  in
  State.set n 1;
  check "the nearest boundary catches" {|ocaught Failure(inner)|} (shown c);
  dispose ()

let catch_fallback_error () =
  let c, dispose =
    render (fun () ->
        D.div []
          [ boundary (fun () ->
                D.div []
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
  D.div []
    [ boundary (fun () -> if !server_fails then failwith "server only" else D.span [ text "ok" ]) ]

let catch_hydrate_fallback () =
  server_fails := true;
  let html, logged = Cases.logged (fun () -> D.server (hydratable ())) in
  check "server log" "Yuka.Catch: Failure(server only)" (String.concat "|" logged);
  check "server html" "<div><!--[!--><p class=\"fallback\">caught server error</p><!--]--></div>" html;
  server_fails := false;
  let island = D.create (D.document ()) "yuka-island" in
  D.append (D.body ()) island;
  D.set_html island html;
  let p = D.query island "p" in
  D.capture_warnings ();
  let dispose = Client.hydrate (D.as_element island) hydratable in
  check "no mismatch" "" (D.warnings ());
  D.same "the fallback is adopted" p (D.query island "p");
  D.click p;
  check "reset renders the children on the client" "<div><!--[!--><span>ok</span><!--]--></div>"
    (D.html island);
  dispose ()

let catch_hydrate_children () =
  let html = D.server (hydratable ()) in
  let island = D.create (D.document ()) "yuka-island" in
  D.append (D.body ()) island;
  D.set_html island html;
  let span = D.query island "span" in
  D.capture_warnings ();
  let dispose = Client.hydrate (D.as_element island) hydratable in
  check "no mismatch" "" (D.warnings ());
  D.same "the children are adopted" span (D.query island "span");
  dispose ()

let show_view status =
  Show.make ~status
    ~loading:(text "loading")
    ~failed:(fun e -> text ("failed " ^ Status.error_to_string e))
    ~children:(fun d -> lower "b" [] [ text d ])
    ()

let show_client () =
  let st = State.make Status.Idle in
  let c, dispose = render (fun () -> show_view (fun () -> State.get st)) in
  check "idle" "loading" (shown c);
  State.set st (Status.Loading None);
  check "loading" "loading" (shown c);
  State.set st (Status.Ready { data = "a"; stale = false });
  check "ready" "a" (shown c);
  let b = D.query c "b" in
  State.set st (Status.Loading (Some "a"));
  check "loading keeps the data" "a" (shown c);
  D.same "same data, same node" b (D.query c "b");
  State.set st (Status.Ready { data = "b"; stale = false });
  check "new data" "b" (shown c);
  State.set st (Status.Failed { error = Status.Network "down"; last = Some "b" });
  check "failed" "failed network error: down" (shown c);
  dispose ()

let show_hydrate () =
  List.iter
    (fun (name, st) ->
      let tree () = D.div [] [ show_view (fun () -> st) ] in
      let logged, _ = D.hydrate_logged (D.server (tree ())) tree in
      check ("hydrate " ^ name) "" logged)
    [ ("idle", Status.Idle);
      ("loading", Status.Loading None);
      ("loading with data", Status.Loading (Some "d"));
      ("ready", Status.Ready { data = "d"; stale = false });
      ("failed", Status.Failed { error = Status.Server; last = None }) ]

let effect_view () =
  let n = State.make 0 in
  Effect.run (fun () -> if State.get n = 2 then failwith "effect");
  lower "div" []
    [ lower "span" [] [ hole (fun () -> text (ints (State.get n))) ];
      lower "button" [ on "click" (fun _ -> State.update n succ) ] [ text "+" ] ]

let click_view () =
  let n = State.make 0 in
  lower "div" []
    [ lower "span" [] [ hole (fun () -> text (ints (State.get n))) ];
      lower "button" [ on "click" (fun _ -> State.update n succ; failwith "click") ] [ text "!" ] ]

let without_boundary view expected =
  let c =
    I.setup_page
      (I.page [ Client.island ~name:"Bad" ~props:(`Int 0) view; I.counter_island 10 ])
  in
  I.capture_errors ();
  let reported = ref [] in
  Yuka.render
    ~islands:(Client.registry [ Client.entry ~name:"Bad" (fun _ -> Ok view); I.counter_entry ])
    ~navigation:false
    ~on_error:(fun m -> reported := m :: !reported)
    ();
  let button i = (D.query_all c "button").(i) in
  D.click (button 0);
  D.click (button 0);
  let after = I.spans c in
  D.click (button 0);
  check "the island is stopped" after (I.spans c);
  D.click (button 1);
  check "the other island works" (String.sub after 0 1 ^ ",11") (I.spans c);
  let logged = I.errors () in
  check "console.error" ("yuka island i1 (Bad): " ^ expected) logged;
  check "on_error" logged (String.concat "|" (List.rev !reported));
  after

let island_without_boundary_effect () =
  check "the DOM stays" "2,10" (without_boundary effect_view {|Failure(effect)|})

let island_without_boundary_click () =
  check "the DOM stays" "1,10" (without_boundary click_view {|Failure(click)|})

let island_boot_error () =
  let entry = Client.entry ~name:"Bad" (fun _ -> Ok (fun () -> failwith "boot")) in
  let c =
    I.setup_page (I.page [ Client.island ~name:"Bad" ~props:(`Int 0) (fun () -> D.span [ text "server" ]) ])
  in
  I.capture_errors ();
  I.start_islands [ entry ];
  check "logged" {|yuka island i1 (Bad): Failure(boot)|} (I.errors ());
  check "server html kept" "server" (I.spans c)

let bad_rows () =
  D.div [] [ each ~key:Fun.id (fun () -> [| "a"; "bad" |])
               (fun s -> if s = "bad" then failwith "row" else D.span [ text s ]) ]

let catch_each_first_render () =
  let c, dispose = render (fun () -> D.div [] [ text "a"; boundary bad_rows; text "b" ]) in
  check "a row that raises at first render" {|acaught Failure(row)b|} (shown c);
  dispose ()

let catch_each_first_hydrate () =
  let ok = ref true in
  let tree () = D.div [] [ boundary (fun () -> if !ok then D.span [ text "ok" ] else bad_rows ()) ] in
  let html = D.server (tree ()) in
  ok := false;
  let island = D.create (D.document ()) "yuka-island" in
  D.append (D.body ()) island;
  D.set_html island html;
  D.capture_warnings ();
  let dispose = Client.hydrate (D.as_element island) tree in
  ignore (D.warnings ());
  check "a row that raises during hydration"
    "<div><!--[--><p class=\"fallback\">caught Failure(row)</p><!--]--></div>" (D.html island);
  dispose ()

let show_untracks_children () =
  let st = State.make (Status.Ready { data = "a"; stale = false }) and other = State.make "x" in
  let c, dispose =
    render (fun () ->
        Show.make
          ~status:(fun () -> State.get st)
          ~loading:(text "loading")
          ~children:(fun d -> lower "b" [] [ text (d ^ State.get other) ])
          ())
  in
  let b = D.query c "b" in
  State.set other "y";
  D.same "a read in the children does not render Show again" b (D.query c "b");
  check "text" "ax" (shown c);
  dispose ()

let handler_error_stops_event () =
  let outer = ref 0 in
  let c, dispose =
    render (fun () ->
        lower "div"
          [ on "click" (fun _ -> incr outer) ]
          [ boundary (fun () -> lower "button" [ on "click" (fun _ -> failwith "click") ] []) ])
  in
  batch (fun () -> D.click (D.query c "button"));
  check "fallback" {|caught Failure(click)|} (shown c);
  check "ancestor handlers do not run" "0" (ints !outer);
  dispose ()

let cleanup_on_dispose () =
  let items = State.make [| "a" |] and cleaned = ref 0 in
  let row _ =
    Effect.run ~cleanup:(fun () -> incr cleaned) ignore;
    Effect.run ~cleanup:(fun () -> failwith "cleanup") ignore;
    D.span [ text "r" ]
  in
  let c, dispose =
    render (fun () ->
        D.div [] [ boundary (fun () -> D.div [] [ each ~key:Fun.id (fun () -> State.get items) row ]) ])
  in
  State.set items [||];
  check "fallback" {|caught Failure(cleanup)|} (shown c);
  check "the other cleanups of the owner ran" "1" (ints !cleaned);
  dispose ()

let on_error_raises () =
  let c =
    I.setup_page
      (I.page [ Client.island ~name:"Bad" ~props:(`Int 0) click_view; I.counter_island 10 ])
  in
  I.capture_errors ();
  Yuka.render
    ~islands:(Client.registry [ Client.entry ~name:"Bad" (fun _ -> Ok click_view); I.counter_entry ])
    ~navigation:false
    ~on_error:(fun _ -> failwith "reporter down")
    ();
  let button i = (D.query_all c "button").(i) in
  D.click (button 0);
  D.click (button 0);
  ignore (I.errors ());
  check "the island stopped although on_error raised" "1,10" (I.spans c);
  D.click (button 1);
  check "the other island works" "1,11" (I.spans c)

let cleanup_raises_view () =
  let n = State.make 0 in
  Effect.run ~cleanup:(fun () -> failwith "cleanup") ignore;
  Effect.run (fun () -> if State.get n = 1 then failwith "effect");
  lower "div" []
    [ lower "span" [] [ hole (fun () -> text (ints (State.get n))) ];
      lower "button" [ on "click" (fun _ -> State.update n succ) ] [ text "+" ] ]

let island_dispose_raises () =
  check "the DOM stays" "1,10"
    (without_boundary cleanup_raises_view
       {|Failure(effect)|yuka island i1 (Bad): Failure(cleanup)|})

let island_start_dispose_raises () =
  let view () =
    Effect.run ~cleanup:(fun () -> failwith "cleanup") ignore;
    Effect.run (fun () -> failwith "first");
    D.span [ text "x" ]
  in
  let c = I.setup_page (I.page [ Client.island ~name:"Bad" ~props:(`Int 0) view; I.counter_island 10 ]) in
  I.capture_errors ();
  I.start_islands [ Client.entry ~name:"Bad" (fun _ -> Ok view); I.counter_entry ];
  check "both errors logged"
    {|yuka island i1 (Bad): Failure(first)|yuka island i1 (Bad): Failure(cleanup)|} (I.errors ());
  D.click (D.query_all c "button").(0);
  check "the other island started" "x,11" (I.spans c)

let all =
  [
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
