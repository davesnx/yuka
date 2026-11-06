open Ppx_compile

let fails = ref 0

let check name cond =
  if not cond then (
    incr fails;
    Printf.printf "FAIL %s\n" name)

let issue : Model.issue =
  { id = 7; title = "x"; note = Some "n"; tags = [ "a"; "b" ]; status = Closed;
    priority = Custom ("c", true); at = (3, 0.5); scores = [| 1.; 2.5 |] }

let roundtrip codec v =
  match Yuka.Codec.decode codec (Yuka.Codec.encode codec v) with
  | Ok v' -> v = v'
  | Error _ -> false

let () =
  check "issue" (roundtrip Model.issue_codec issue);
  check "issue none" (roundtrip Model.issue_codec { issue with note = None });
  List.iter
    (fun p -> check "priority" (roundtrip Model.priority_codec p))
    [ Low; Level 3; Custom ("a", false); Range { lo = 1; hi = 9 } ];
  check "status json"
    (Yuka.Codec.encode Model.status_codec Open = `String "Open");
  check "level json"
    (Yuka.Codec.encode Model.priority_codec (Level 3)
    = `List [ `String "Level"; `Int 3 ]);
  check "range json"
    (Yuka.Codec.encode Model.priority_codec (Range { lo = 1; hi = 2 })
    = `List [ `String "Range"; `Assoc [ ("lo", `Int 1); ("hi", `Int 2) ] ]);
  check "alias" (roundtrip Model.id_codec 4);
  let json =
    match Yuka.Codec.encode Model.issue_codec issue with
    | `Assoc l -> `Assoc (List.filter (fun (k, _) -> k <> "note") l)
    | j -> j
  in
  (match Yuka.Codec.decode Model.issue_codec json with
   | Ok i -> check "missing option" (i.note = None)
   | Error e -> check ("missing option: " ^ e) false);
  (match Yuka.Codec.decode Model.issue_codec (`Assoc []) with
   | Error "missing field id" -> ()
   | _ -> check "missing field" false);
  (match Yuka.Codec.decode Model.status_codec (`String "Nope") with
   | Error _ -> ()
   | Ok _ -> check "bad constructor" false);
  check "name" (Yuka.Internal.entry_name Counter.register = "Ppx_compile.Counter");
  let props =
    `Assoc
      [ ("label", `String "L"); ("step", `Int 2);
        ("issue", Yuka.Codec.encode Model.issue_codec issue) ]
  in
  (match Yuka.Internal.entry_decode Counter.register props with
   | Ok build ->
       let html = Yuka.Internal.to_html (build ()) in
       check ("register html: " ^ html) (String.length html > 0)
   | Error e -> check ("register: " ^ e) false);
  (match
     Yuka.Internal.entry_decode Counter.register
       (`Assoc [ ("issue", Yuka.Codec.encode Model.issue_codec issue); ("label", `String "L") ])
   with
   | Ok _ -> ()
   | Error e -> check ("register without step: " ^ e) false);
  (match Yuka.Internal.entry_decode Counter.register (`Assoc [ ("label", `String "L") ]) with
   | Error _ -> ()
   | Ok _ -> check "register missing issue" false);
  let page = Yuka.Internal.to_html (Yuka.Internal.node Page.view) in
  check ("page has island: " ^ page)
    (let sub = "yuka-island" in
     let n = String.length sub in
     let rec go i = i + n <= String.length page && (String.sub page i n = sub || go (i + 1)) in
     go 0);
  let items = Yuka.Async.resolved [ 1; 2 ] in
  let direct = Yuka.Codec.encode (Yuka.Codec.async (Yuka.Codec.list Yuka.Codec.int)) items in
  check "async direct" (direct <> `Null);
  (match Yuka.Codec.encode Model.loaded_codec { items; other = Yuka.Async.resolved "x" } with
   | `Assoc [ ("items", j); _ ] -> check "async field" (j = direct)
   | _ -> check "async field shape" false);
  let island_html = Yuka.Internal.to_html (Yuka.Internal.node (Lazy_list.island ~items ())) in
  let contains s sub =
    let n = String.length sub in
    let rec go i = i + n <= String.length s && (String.sub s i n = sub || go (i + 1)) in
    go 0
  in
  check ("island async prop: " ^ island_html)
    (contains island_html (Yuka.Json.to_string direct));
  let rec chain n : int Model.tree =
    if n = 0 then Leaf else Node (chain (n - 1), n, Leaf)
  in
  let deep = chain 5000 in
  check "deep tree" (roundtrip (Model.tree_codec Yuka.Codec.int) deep);
  let rec rose n : Model.rose = { label = string_of_int n; kids = (if n = 0 then [] else [ rose (n - 1); rose (n - 1) ]) } in
  check "rose" (roundtrip Model.rose_codec (rose 8));
  let e : Model.expr = Block [ Do (Num 1); Let { name = "x"; value = Block [ Do (Num 2) ] } ] in
  check "mutual" (roundtrip Model.expr_codec e);
  check "mutual json"
    (Yuka.Codec.encode Model.stmts_codec [ Do (Num 1) ]
    = `List [ `List [ `String "Do"; `List [ `String "Num"; `Int 1 ] ] ]);
  check "pair" (roundtrip Model.pair_codec (chain 3, Node (Leaf, "a", Leaf)));
  check "either" (roundtrip (Model.either_codec Yuka.Codec.int Yuka.Codec.string) (Right "r"));
  check "either json"
    (Yuka.Codec.encode (Model.either_codec Yuka.Codec.int Yuka.Codec.string) (Left 1)
    = `List [ `String "Left"; `Int 1 ]);
  check "nested" (roundtrip Model.nested_codec (Some (Node (Leaf, [ 1 ], Leaf))));
  List.iter
    (fun sub -> check ("page contains " ^ sub) (contains page sub))
    [ "style=\"display:contents\"";
      "data-start=\"visible\"";
      "<!--[$--><p>server content</p><yuka-island";
      "</yuka-island><script type=\"application/json\" data-yuka-props=\"i3\">";
      "<!--]--></section>";
      "\"children\":null" ];
  check "no data-start for Load"
    (contains page "data-id=\"i1\" style=\"display:contents\"><button>");
  check "island name" (Counter.name = "Ppx_compile.Counter");
  List.iter
    (fun r -> check "result" (roundtrip (Model.outcome3_codec) r))
    [ [ Ok 1; Error "e" ] ];
  check "result json"
    (Yuka.Codec.encode Model.outcome2_codec (Error Open) = `Assoc [ ("error", `String "Open") ]);
  let is_template (e : _ Yuka.element) =
    match Yuka.Internal.node e with Yuka.Internal.Template _ -> true | _ -> false
  in
  check "static is a template" (is_template Templated.static_tree);
  check "fixed is a template" (is_template Templated.fixed);
  check "by hand is not" (not (is_template Templated.static_by_hand));
  check "not fixed is not" (not (is_template (Templated.not_fixed "x")));
  check "static html same"
    (Yuka.Internal.to_html (Yuka.Internal.node Templated.static_tree)
    = Yuka.Internal.to_html (Yuka.Internal.node Templated.static_by_hand));
  check "fixed html same"
    (Yuka.Internal.to_html (Yuka.Internal.node Templated.fixed)
    = Yuka.Internal.to_html (Yuka.Internal.node Templated.by_hand));
  (match Yuka.Internal.node Templated.static_tree with
   | Yuka.Internal.Template { node; id } ->
       check ("template id " ^ id) (id = "ppx_compile/templated:16:2");
       check "skeleton"
         (Yuka.Internal.skeleton_html node
         = Yuka.Internal.to_html node)
   | _ -> ());
  let settled = Yuka.Async.resolved [ "a"; "b" ] in
  let await_html = Yuka.Internal.to_html (Yuka.Internal.node (Awaiting.view settled)) in
  check ("await settled: " ^ await_html) (contains await_html "<ul><li>a</li><li>b</li></ul>");
  check "await not loading" (not (contains await_html "loading"));
  let failed_html =
    Yuka.Internal.to_html
      (Yuka.Internal.node (Awaiting.with_failed (Yuka.Async.failed "boom")))
  in
  check ("await failed: " ^ failed_html) (contains failed_html "<p>boom</p>");
  if !fails > 0 then exit 1 else print_endline "ok"
