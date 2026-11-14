open Yuka

let check = Cases.check
let ints = string_of_int

let num : int Context.t = Context.make ~name:"num" ()
let other : int Context.t = Context.make ~name:"other" ()
let show c = match Context.get c with Some n -> ints n | None -> "none"
let later c = hole (fun () -> text (show c))
let shown = Dom_cases.text_content

let render tree =
  let c = Dom_cases.container "" in
  let dispose = Private.render (Dom_cases.as_element c) tree in
  (c, dispose)

let raises f =
  match f () with
  | _ -> "no exception"
  | exception Invalid_argument m -> m

let root_render () =
  let c, dispose =
    render (fun () ->
        Dom_cases.div []
          [ Context.provide num 1 (fun () ->
                element "p"
                  [ hole_attr "title" (fun () -> Some (show num)) ]
                  [ text ("f" ^ show num); later num ]);
            element "b" [ hole_attr "title" (fun () -> Some (show num)) ] [ text ("f" ^ show num); later num ] ])
  in
  check "inside: function, hole, attribute" "f11 1"
    (shown (Dom_cases.query c "p") ^ " " ^ Option.value ~default:"null" (Dom_cases.get_attribute (Dom_cases.query c "p") "title"));
  check "outside: function and hole" "fnonenone" (shown (Dom_cases.query c "b"));
  check "outside: attribute" "none"
    (Option.value ~default:"null" (Dom_cases.get_attribute (Dom_cases.query c "b") "title"));
  dispose ()

let hole_again () =
  let s = State.make 0 and st = State.make 10 and comp = ref 0 in
  let sc : int State.t Context.t = Context.make ~name:"state" () in
  let child () =
    incr comp;
    let v = Context.get_exn sc in
    Dom_cases.div []
      [ element "i" [] [ hole (fun () -> text (ints (State.get s) ^ ":" ^ show num)) ];
        element "b" [] [ hole (fun () -> text (ints (State.get v))) ] ]
  in
  let c, dispose =
    render (fun () -> Context.provide num 1 (fun () -> Context.provide sc st (fun () -> child ())))
  in
  let b = Dom_cases.query c "b" in
  State.set s 1;
  State.set s 2;
  check "a hole that runs again reads the value" "2:1" (shown (Dom_cases.query c "i"));
  State.set st 11;
  State.set st 12;
  check "a State in the context updates its hole" "12" (shown (Dom_cases.query c "b"));
  Dom_cases.same "the element around the hole is kept" b (Dom_cases.query c "b");
  check "the component function ran once" "1" (ints !comp);
  dispose ()

let row_later () =
  let items = State.make [| "a" |] in
  let row k =
    let body () = element "i" [] [ text (k ^ show num); hole (fun () -> text (show num)) ] in
    if k = "c" then Context.provide num 9 body else body ()
  in
  let c, dispose =
    render (fun () ->
        Context.provide num 1 (fun () -> Dom_cases.div [] [ each ~key:Fun.id (fun () -> State.get items) row ]))
  in
  check "first row" "a11" (Dom_cases.texts c "i");
  State.set items [| "a"; "b"; "c" |];
  check "a row added later reads the value; a row with its own provide reads its own" "a11,b11,c99"
    (Dom_cases.texts c "i");
  dispose ()

let catch_reset () =
  let fail = ref true and outer_builds = ref 0 and inner_builds = ref 0 in
  let fallback ~error:_ ~reset =
    element "p" [ on "click" (fun _ -> reset ()) ] [ text ("fallback" ^ show num) ]
  in
  let children () =
    incr outer_builds;
    if !fail then failwith "boom";
    Dom_cases.div []
      [ element "i" [] [ text (show num); later num ];
        Context.provide other 2 (fun () ->
            incr inner_builds;
            element "b" [] [ text (show other); later other; later num ]) ]
  in
  let c, dispose =
    render (fun () -> Context.provide num 1 (fun () -> Catch.make ~fallback ~children ()))
  in
  check "the fallback shows and reads the value" "fallback1" (shown c);
  fail := false;
  Dom_cases.click (Dom_cases.query c "p");
  check "after reset the children read the value" "11" (shown (Dom_cases.query c "i"));
  check "a provider inside the children reads its value" "221" (shown (Dom_cases.query c "b"));
  check "children built again" "2" (ints !outer_builds);
  check "inner provider built once, after reset" "1" (ints !inner_builds);
  dispose ()

let click_handler () =
  let seen = ref [] in
  let button id = element "button" [ attr "id" id; on "click" (fun _ -> seen := (id ^ "=" ^ show num) :: !seen) ] [] in
  let c, dispose =
    render (fun () -> Dom_cases.div [] [ Context.provide num 1 (fun () -> button "in"); button "out" ])
  in
  Dom_cases.click (Dom_cases.query c "#in");
  Dom_cases.click (Dom_cases.query c "#out");
  check "a handler reads at click time" "in=1 out=none" (String.concat " " (List.rev !seen));
  check "no value after the click" "none" (show num);
  dispose ()

let async_callback () =
  let a, resolve, _ = Async.make () in
  let seen = ref [] in
  let c, dispose =
    render (fun () ->
        Context.provide num 1 (fun () ->
            Async.on_settled a (fun _ -> seen := show num :: !seen);
            later num))
  in
  resolve ();
  check "the render reads the value" "1" (shown c);
  check "an Async callback after the render reads None" "none" (String.concat " " !seen);
  dispose ()

let set_timeout : (unit -> unit) -> unit = [%mel.raw "function (f) { setTimeout(function () { f() }, 0) }"]

let timer_after finish =
  let seen = ref "unset" in
  let c, dispose =
    render (fun () ->
        Context.provide num 1 (fun () ->
            set_timeout (fun () -> seen := show num);
            later num))
  in
  set_timeout (fun () ->
      finish (fun () ->
          check "the render reads the value" "1" (shown c);
          check "a timer after the render reads None" "none" !seen;
          dispose ()))

let hydrate_tree s () =
  Dom_cases.div []
    [ Context.provide num 1 (fun () ->
          element "p"
            [ hole_attr "title" (fun () -> Some (show num)) ]
            [ text (show num); hole (fun () -> text (ints (State.get s) ^ ":" ^ show num)) ]);
      element "b" [] [ later num ] ]

let hydration () =
  let s = State.make 0 in
  let html = Dom_cases.server (hydrate_tree s ()) in
  check "server html" {|<div><!--[--><p title="1">1<!--[-->0:1<!--]--></p><!--]--><b>none</b></div>|} html;
  let island = Dom_cases.create (Dom_cases.document ()) "yuka-island" in
  Dom_cases.append (Dom_cases.body ()) island;
  Dom_cases.set_html island html;
  let p = Dom_cases.query island "p" in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element island) (hydrate_tree s) in
  check "no mismatch" "" (Dom_cases.warnings ());
  Dom_cases.same "the element is adopted" p (Dom_cases.query island "p");
  check "html unchanged" html (Dom_cases.html island);
  State.set s 1;
  check "a State change after hydration" "11:1" (shown (Dom_cases.query island "p"));
  check "outside" "none" (shown (Dom_cases.query island "b"));
  dispose ()

let island_message = ref ""

let island_view slot =
  island_message := raises (fun () -> Context.get_exn num);
  element "div" []
    [ element "i" [] [ text (show num) ];
      Context.provide num 3 (fun () -> element "b" [] [ later num ]);
      runtime_slot slot ]

let island_entry = runtime_entry ~name:"Ctx" (fun _ -> Ok (fun () -> island_view None))

let island_page () =
  Island_cases.page
    [ Context.provide num 1 (fun () ->
          runtime_island ~name:"Ctx" ~props:`Null (fun () ->
              island_view (Some (Private.element (Private.hole (fun () -> Private.node (element "u" [] [ text (show num) ])))))))
    ]

let island_start () =
  let c = Island_cases.setup_page (island_page ()) in
  check "server html" "none 3 1" (String.concat " " [ Dom_cases.texts c "i"; Dom_cases.texts c "b"; Dom_cases.texts c "u" ]);
  island_message := "";
  Dom_cases.capture_warnings ();
  Island_cases.start_islands [ island_entry ];
  ignore (Dom_cases.warnings ());
  check "inside the island get is None" "none" (Dom_cases.texts c "i");
  check "get_exn raises with the name of the context" "Yuka.Context.get_exn: no value for num" !island_message;
  check "a provide inside the island" "3" (Dom_cases.texts c "b");
  check "the page's children keep the page value" "1" (Dom_cases.texts c "u");
  Island_cases.reset_body ()

let island_start_in_scope () =
  let c = Island_cases.setup_page (island_page ()) in
  island_message := "";
  Dom_cases.capture_warnings ();
  Private.with_context [ Context.bind num 5 ] (fun () -> Island_cases.start_islands [ island_entry ]);
  ignore (Dom_cases.warnings ());
  check "the island ran in the browser" "Yuka.Context.get_exn: no value for num" !island_message;
  check "an island started inside a scope reads None" "none" (Dom_cases.texts c "i");
  check "its provide still works" "3" (Dom_cases.texts c "b");
  Island_cases.reset_body ()

let provide_all () =
  let both () = text (show num ^ show other) in
  let c, dispose =
    render (fun () ->
        Dom_cases.div []
          [ Context.provide_all
              [ Context.bind num 1; Context.bind other 2; Context.bind num 3 ]
              (fun () -> element "p" [] [ both (); hole both ]);
            element "b" [] [ both (); hole both ] ])
  in
  check "both contexts, the last duplicate wins" "3232" (shown (Dom_cases.query c "p"));
  check "outside" "nonenonenonenone" (shown (Dom_cases.query c "b"));
  dispose ()

let all =
  [ ("context: root render", root_render);
    ("context: a hole that runs again, a State in the value", hole_again);
    ("context: a row added after the mount", row_later);
    ("context: Catch then reset", catch_reset);
    ("context: a click handler inside and outside", click_handler);
    ("context: an Async callback after the render", async_callback);
    ("context: hydration of server HTML", hydration);
    ("context: an island started on a page with a provide", island_start);
    ("context: an island started inside a scope", island_start_in_scope);
    ("context: provide_all with two contexts", provide_all) ]

let async = [ ("context: a timer after the render", timer_after) ]
