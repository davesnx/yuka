open Yuka

exception Failed of string

let check name expected actual =
  if expected <> actual then
    raise (Failed (Printf.sprintf "%s: expected %S, got %S" name expected actual))

let log () =
  let entries = ref [] in
  let add s = entries := s :: !entries in
  let read () = String.concat " " (List.rev !entries) in
  (add, read)

let first_run () =
  let add, read = log () in
  let count = State.make 0 in
  Effect.run (fun () -> add (string_of_int (State.get count)));
  check "runs once at creation" "0" (read ())

let rerun_on_change () =
  let add, read = log () in
  let count = State.make 0 in
  Effect.run (fun () -> add (string_of_int (State.get count)));
  State.set count 1;
  State.update count (fun c -> c + 1);
  check "runs again on each change" "0 1 2" (read ())

let no_rerun_on_equal_write () =
  let add, read = log () in
  let count = State.make 0 in
  let name = State.make ~equal:String.equal "a" in
  Effect.run (fun () -> add (string_of_int (State.get count)));
  Effect.run (fun () -> add (State.get name));
  State.set count 0;
  State.set name (String.make 1 'a');
  check "no run for an equal write" "0 a" (read ())

let cleanup_receives_previous_result () =
  let add, read = log () in
  let count = State.make 0 in
  Effect.run
    ~cleanup:(fun id -> add ("clear" ^ string_of_int id))
    (fun () ->
      let id = State.get count * 10 in
      add ("start" ^ string_of_int id);
      id);
  State.set count 1;
  State.set count 2;
  check "cleanup gets the previous result" "start0 clear0 start10 clear10 start20"
    (read ())

let nested_disposed_on_rerun () =
  let runs = ref 0 in
  let a = State.make 0 in
  let b = State.make 0 in
  Effect.run (fun () ->
      ignore (State.get a);
      Effect.run (fun () ->
          ignore (State.get b);
          incr runs));
  State.set a 1;
  State.set a 2;
  runs := 0;
  State.set b 1;
  check "one inner effect after two outer re-runs" "1" (string_of_int !runs)

let mount_dispose () =
  let add, read = log () in
  let count = State.make 0 in
  let (), dispose =
    owner (fun () ->
        Effect.run
          ~cleanup:(fun () -> add "outer-clean")
          (fun () ->
            ignore (State.get count);
            Effect.run
              ~cleanup:(fun () -> add "inner-clean")
              (fun () -> add ("inner" ^ string_of_int (State.get count)))))
  in
  dispose ();
  State.set count 1;
  check "dispose runs cleanups and stops effects" "inner0 inner-clean outer-clean"
    (read ())

let error_isolation () =
  let add, read = log () in
  let count = State.make 0 in
  Effect.run (fun () -> if State.get count = 1 then failwith "boom");
  Effect.run (fun () -> add (string_of_int (State.get count)));
  let raised = try State.set count 1; "no" with Failure m -> m in
  State.set count 2;
  check "other effect still runs" "0 1 2" (read ());
  check "first error raised after the flush" "boom" raised

let on_change_prev_next () =
  let add, read = log () in
  let count = State.make ~equal:Int.equal 0 in
  Effect.on_change count (fun ~prev ~next ->
      add (string_of_int prev ^ "->" ^ string_of_int next));
  State.set count 1;
  State.set count 1;
  State.set count 5;
  check "prev and next, not on the first run" "0->1 1->5" (read ())

let memo_recomputes_on_input_change () =
  let computes = ref 0 in
  let count = State.make 1 in
  let other = State.make 0 in
  let double =
    State.memo (fun () ->
        incr computes;
        State.get count * 2)
  in
  let r1 = State.get double in
  let r2 = State.get double in
  State.set other 1;
  let r3 = State.get double in
  State.set count 5;
  let r4 = State.get double in
  check "memo values" "2 2 2 10"
    (String.concat " " (List.map string_of_int [ r1; r2; r3; r4 ]));
  check "memo computes" "2" (string_of_int !computes)

let peek_does_not_track () =
  let runs = ref 0 in
  let count = State.make 0 in
  Effect.run (fun () ->
      ignore (State.peek count);
      incr runs);
  State.set count 1;
  check "peek is not a dependency" "1" (string_of_int !runs)

let outer_keeps_dependency_after_inner () =
  let outer = ref 0 in
  let count = State.make 0 in
  let other = State.make 0 in
  Effect.run (fun () ->
      ignore (State.get other);
      Effect.run (fun () -> ignore (State.get count));
      ignore (State.get count);
      incr outer);
  State.set count 1;
  State.set count 2;
  check "outer effect still reads count" "3" (string_of_int !outer)

let effect_sees_consistent_memo () =
  let add, read = log () in
  let count = State.make 1 in
  let double = State.memo (fun () -> State.get count * 2) in
  Effect.run (fun () ->
      add (Printf.sprintf "%d/%d" (State.get count) (State.get double)));
  State.set count 2;
  check "one run per write, no stale memo" "1/2 2/4" (read ())

let memo_equal_by_default () =
  let add, read = log () in
  let n = State.make 1 in
  let parity = State.memo (fun () -> State.get n mod 2) in
  Effect.run (fun () -> add (string_of_int (State.get parity)));
  State.set n 3;
  check "same memo value does not re-run effects" "1" (read ())

let effect_writing_own_state_settles () =
  let s = State.make 0 in
  Effect.run (fun () ->
      let v = State.get s in
      if v < 3 then State.set s (v + 1));
  check "a write that settles still works" "3" (string_of_int (State.peek s))

let contains text part =
  let n = String.length part in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = part || at (i + 1))
  in
  at 0

let effect_writing_own_state_stops () =
  let s = State.make 0 in
  let result =
    match
      Effect.run (fun () ->
          let v = State.get s in
          if v < 1000 then State.set s (v + 1))
    with
    | () -> "no error, value " ^ string_of_int (State.peek s)
    | exception Failure m when contains m "keeps changing a State it reads" ->
        "limit"
  in
  check "a write that does not settle stops with an error" "limit" result;
  let after = State.make 0 in
  let runs = ref 0 in
  Effect.run (fun () ->
      ignore (State.get after);
      incr runs);
  State.set after 1;
  check "effects still run after the limit" "2" (string_of_int !runs)

let html (el : server element) = Private.to_html (Private.node el)
let chtml (el : client element) = Private.to_html (Private.node el)

let html_escaping () =
  check "text" "<p>a &amp; b &lt;c&gt; \"d\"</p>"
    (html (lower "p" [] [ text "a & b <c> \"d\"" ]));
  check "attribute" "<a href=\"x&amp;y&quot;&lt;>\"></a>"
    (html (lower "a" [ attr "href" "x&y\"<>" ] []))

let html_adjacent_texts () =
  check "separator" "<p>a<!---->b<!---->c</p>"
    (html (lower "p" [] [ text "a"; text "b"; text "c" ]));
  check "across a fragment" "<p>a<!---->b</p>"
    (html (lower "p" [] [ text "a"; fragment [ text "b" ] ]));
  check "element between" "<p>a<b></b>b</p>"
    (html (lower "p" [] [ text "a"; lower "b" [] []; text "b" ]))

let html_empty_text () =
  check "nothing" "<p></p>" (html (lower "p" [] [ text "" ]));
  check "no separator for empty first" "<p>a</p>"
    (html (lower "p" [] [ text ""; text "a" ]))

let html_hole () =
  let runs = ref 0 in
  let s = State.make "x" in
  let el =
    lower "p" []
      [ hole (fun () -> incr runs; text (State.get s)); text "t" ]
  in
  check "markers" "<p><!--[-->x<!--]-->t</p>" (chtml el);
  check "function runs once" "1" (string_of_int !runs)

let html_each () =
  let el =
    lower "ul" []
      [
        each ~key:string_of_int
          (fun () -> [ 1; 2 ])
          (fun n -> lower "li" [] [ text (string_of_int n) ]);
      ]
  in
  check "items" "<ul><li>1</li><li>2</li></ul>"
    (chtml el);
  check "empty" "<!--[--><!--]-->"
    (chtml (each ~key:string_of_int (fun () -> []) (fun _ -> empty)));
  check "texts in items stay apart" "<!--[--><!--[-->a<!--]--><!--[-->b<!--]--><!--]-->"
    (chtml (each ~key:Fun.id (fun () -> [ "a"; "b" ]) text))

let html_dynamic_attribute () =
  let s = State.make (Some "v") in
  let el = lower "i" [ hole_attr "title" (fun () -> State.get s) ] [] in
  check "Some" "<i title=\"v\"></i>" (chtml el);
  State.set s None;
  check "None" "<i></i>" (chtml el)

let html_handler () =
  check "not written" "<button id=\"b\">go</button>"
    (chtml
       (lower "button"
          [ attr "id" "b"; on "click" (fun _ -> ()) ]
          [ text "go" ]))

let html_void () =
  check "void" "<p>a<br>b<input type=\"text\"></p>"
    (html
       (lower "p" []
          [ text "a"; lower "br" [] []; text "b";
            lower "input" [ attr "type" "text" ] [ text "ignored" ] ]))

let html_nested () =
  check "nested" "<div class=\"c\"><ul><li>1</li></ul></div>"
    (html
       (lower "div" [ attr "class" "c" ]
          [ lower "ul" [] [ lower "li" [] [ text "1" ] ] ]))

let html_effect_skipped () =
  let runs = ref 0 in
  let component () =
    Effect.run (fun () -> incr runs);
    lower "p" [] []
  in
  let in_hole = lower "div" [] [ hole (fun () -> component () |> fun e -> (Private.element (Private.node e) : client element)) ] in
  check "hole html" "<div><p></p></div>" (chtml in_hole);
  check "hole body effect not run" "0" (string_of_int !runs);
  check "build and print" "<p></p>"
    (Private.render_html (fun () -> Private.node (component ())));
  check "build effect not run" "0" (string_of_int !runs);
  check "flag restored" "false" (string_of_bool !Private.server_rendering);
  (try
     ignore
       (Private.to_html
          (Private.node (lower "p" [] [ hole (fun () -> failwith "x") ])))
   with Failure _ -> ());
  check "flag restored after exception" "false"
    (string_of_bool !Private.server_rendering);
  let (), dispose = owner (fun () -> ignore (component ())) in
  dispose ();
  check "runs in mount" "1" (string_of_int !runs)

let show_json = Json.to_string

let parse s =
  match Json.of_string s with Ok j -> show_json j | Error m -> "error: " ^ m

let is_error s = match Json.of_string s with Error _ -> "error" | Ok _ -> "ok"

let json_round_trip () =
  let values : Json.t list =
    [ `Null; `Bool true; `Bool false; `Int 0; `Int (-42); `Float 1.5;
      `Float 1.0; `Float (-0.25); `Float 1e100; `String ""; `String "a\"b\\c\n\t\r";
      `String "caf\xc3\xa9 \xe2\x82\xac \xf0\x9f\x98\x80"; `List [];
      `Assoc []; `List [ `Int 1; `List [ `Null; `Assoc [ ("k", `String "v") ] ] ];
      `Assoc [ ("a", `Int 1); ("b", `List [ `Float 2.5 ]) ] ]
  in
  List.iter
    (fun v ->
      match Json.of_string (show_json v) with
      | Ok v' -> if v <> v' then raise (Failed ("round trip: " ^ show_json v))
      | Error m -> raise (Failed ("round trip error: " ^ m)))
    values

let json_printing () =
  check "compact" "{\"a\":[1,2.5,null,true],\"b\":\"x\"}"
    (show_json (`Assoc [ ("a", `List [ `Int 1; `Float 2.5; `Null; `Bool true ]); ("b", `String "x") ]));
  check "float keeps a dot" "1.0" (show_json (`Float 1.0));
  check "a tie at 17 digits rounds to even" "1234567890123456.2"
    (show_json (`Float 1234567890123456.25));
  check "a tie at 17 digits rounds up to even" "1234567890123456.8"
    (show_json (`Float 1234567890123456.75));
  check "control chars" "\"\\u0001\\b\\f\\n\"" (show_json (`String "\001\b\012\n"));
  check "utf-8 kept" "\"caf\xc3\xa9\"" (show_json (`String "caf\xc3\xa9"));
  check "nan" "null" (show_json (`Float nan))

let json_script_safety () =
  let s = show_json (`String "</script><!--") in
  check "no less-than" "\"\\u003c/script>\\u003c!--\"" s;
  check "reads back" "</script><!--"
    (match Json.of_string s with Ok (`String x) -> x | _ -> "bad")

let json_parser () =
  check "escapes" "\"a\\n\\\"\\\\/\\b\""
    (parse "\"a\\n\\\"\\\\\\/\\b\"");
  check "unicode escape" "\"\xc3\xa9\xe2\x82\xac\"" (parse "\"\\u00e9\\u20AC\"");
  check "surrogate pair" "\"\xf0\x9f\x98\x80\"" (parse "\"\\ud83d\\ude00\"");
  check "whitespace" "{\"a\":[1,2]}" (parse " { \"a\" : [ 1 , 2 ] }\n");
  check "int" "`Int" (match Json.of_string "123" with Ok (`Int 123) -> "`Int" | _ -> "other");
  check "negative int" "`Int" (match Json.of_string "-7" with Ok (`Int (-7)) -> "`Int" | _ -> "other");
  check "float dot" "`Float" (match Json.of_string "1.0" with Ok (`Float _) -> "`Float" | _ -> "other");
  check "float exp" "`Float" (match Json.of_string "1e2" with Ok (`Float 100.) -> "`Float" | _ -> "other");
  check "float neg exp" "`Float" (match Json.of_string "-2.5E-1" with Ok (`Float (-0.25)) -> "`Float" | _ -> "other");
  check "empty containers" "[[],{}]" (parse "[[],{}]");
  check "nested" "{\"a\":{\"b\":[{\"c\":null}]}}" (parse "{\"a\":{\"b\":[{\"c\":null}]}}")

let json_invalid () =
  List.iter
    (fun s -> check ("invalid " ^ String.escaped s) "error" (is_error s))
    [ ""; " "; "["; "[1,]"; "{\"a\"}"; "{\"a\":1,}"; "{a:1}"; "tru"; "nul";
      "01"; "1."; ".5"; "-"; "1e"; "\"abc"; "\"\\x\""; "\"\\u12\""; "\"\\ud83d\"";
      "\"\\ude00\""; "\"\\ud83d\\u0041\""; "1 2"; "[1] x"; "'a'"; "\"a\nb\"" ]

let codec_ok c v = Codec.decode c (Codec.encode c v)

let codec_round_trip () =
  let open Codec in
  check "int" "Ok 5" (match codec_ok int 5 with Ok n -> "Ok " ^ string_of_int n | Error m -> m);
  check "string" "Ok a<b" (match codec_ok string "a<b" with Ok s -> "Ok " ^ s | Error m -> m);
  check "bool" "true" (match codec_ok bool true with Ok b -> string_of_bool b | Error m -> m);
  check "unit" "ok" (match codec_ok unit () with Ok () -> "ok" | Error m -> m);
  check "float" "2.5" (match codec_ok float 2.5 with Ok f -> string_of_float f | Error m -> m);
  check "list" "1,2,3"
    (match codec_ok (list int) [ 1; 2; 3 ] with
    | Ok l -> String.concat "," (List.map string_of_int l)
    | Error m -> m);
  check "array" "a,b"
    (match codec_ok (array string) [| "a"; "b" |] with
    | Ok a -> String.concat "," (Array.to_list a)
    | Error m -> m);
  check "option" "None Some 1"
    (match (codec_ok (option int) None, codec_ok (option int) (Some 1)) with
    | Ok None, Ok (Some 1) -> "None Some 1"
    | _ -> "bad");
  check "option encoding" "null" (show_json (Codec.encode (option int) None));
  check "nested" "[[1],[]]"
    (show_json (Codec.encode (list (list int)) [ [ 1 ]; [] ]))

let codec_errors () =
  let open Codec in
  let is_err = function Error _ -> "error" | Ok _ -> "ok" in
  check "int from string" "error" (is_err (decode int (`String "1")));
  check "int from float" "error" (is_err (decode int (`Float 1.5)));
  check "float from int" "ok" (is_err (decode float (`Int 1)));
  check "float value" "3." (match decode float (`Int 3) with Ok f -> Printf.sprintf "%g." f | Error m -> m);
  check "string from null" "error" (is_err (decode string `Null));
  check "list bad item" "error" (is_err (decode (list int) (`List [ `Int 1; `String "x" ])));
  check "list from int" "error" (is_err (decode (list int) (`Int 1)));
  check "option bad inner" "error" (is_err (decode (option int) (`String "x")));
  check "unit from int" "error" (is_err (decode unit (`Int 0)))

let status_text f = function
  | Async.Pending -> "pending"
  | Async.Done v -> "done " ^ f v
  | Async.Failed m -> "failed " ^ m

let async_settle_once () =
  let a, resolve, fail = Async.make () in
  check "pending" "pending" (status_text string_of_int (Async.status a));
  resolve 1;
  resolve 2;
  fail "late";
  check "first wins" "done 1" (status_text string_of_int (Async.status a));
  let b, resolve, fail = Async.make () in
  fail "boom";
  resolve 1;
  check "failure wins" "failed boom" (status_text string_of_int (Async.status b));
  check "resolved" "done 3" (status_text string_of_int (Async.status (Async.resolved 3)));
  check "failed" "failed no" (status_text string_of_int (Async.status (Async.failed "no")))

let async_on_settled () =
  let add, read = log () in
  let a, resolve, _ = Async.make () in
  Async.on_settled a (fun st -> add ("first:" ^ status_text string_of_int st));
  Async.on_settled a (fun st -> add ("second:" ^ status_text string_of_int st));
  check "nothing before" "" (read ());
  resolve 1;
  check "order" "first:done 1 second:done 1" (read ());
  Async.on_settled a (fun st -> add ("late:" ^ status_text string_of_int st));
  check "now when settled" "first:done 1 second:done 1 late:done 1" (read ());
  resolve 2;
  check "callbacks run once" "first:done 1 second:done 1 late:done 1" (read ())

let async_map_bind () =
  let a, resolve, _ = Async.make () in
  let m = Async.map (fun n -> n * 2) a in
  check "map pending" "pending" (status_text string_of_int (Async.status m));
  resolve 4;
  check "map done" "done 8" (status_text string_of_int (Async.status m));
  let inner, resolve_inner, _ = Async.make () in
  let b = Async.bind (Async.resolved 1) (fun _ -> inner) in
  check "bind waits for inner" "pending" (status_text string_of_int (Async.status b));
  resolve_inner 9;
  check "bind done" "done 9" (status_text string_of_int (Async.status b));
  let f = Async.map succ (Async.failed "e1") in
  check "map failure" "failed e1" (status_text string_of_int (Async.status f));
  let g = Async.bind (Async.resolved 1) (fun _ -> (Async.failed "e2" : int Async.t)) in
  check "bind inner failure" "failed e2" (status_text string_of_int (Async.status g));
  let called = ref false in
  let h = Async.bind (Async.failed "e3") (fun _ -> called := true; Async.resolved 1) in
  check "bind skips on failure" "failed e3 false"
    (status_text string_of_int (Async.status h) ^ " " ^ string_of_bool !called)

let async_watch () =
  let add, read = log () in
  let a, resolve, _ = Async.make () in
  let w = Async.watch a in
  Effect.run (fun () -> add (status_text string_of_int (State.get w)));
  resolve 7;
  check "effect sees the update" "pending done 7" (read ());
  let w2 = Async.watch (Async.resolved 1) in
  check "already settled" "done 1" (status_text string_of_int (State.peek w2))

let double =
  Action.declare ~name:"double" ~input:Codec.int ~output:Codec.int

let with_transport f body =
  let saved = !Private.call_action in
  Private.call_action := f;
  match body () with
  | v -> Private.call_action := saved; v
  | exception e -> Private.call_action := saved; raise e

let action_call () =
  check "name" "double" (Action.name double);
  let seen = ref "" in
  let result =
    with_transport
      (fun name input ->
        seen := name ^ " " ^ show_json input;
        match input with
        | `Int n -> Async.resolved (`Int (n * 2))
        | _ -> Async.failed "bad")
      (fun () -> Async.status (Action.call double 21))
  in
  check "transport got" "double 21" !seen;
  check "decoded output" "done 42" (status_text string_of_int result);
  let bad =
    with_transport
      (fun _ _ -> Async.resolved (`String "x"))
      (fun () -> Async.status (Action.call double 1))
  in
  check "decode error is Failed" "failed"
    (match bad with Async.Failed _ -> "failed" | _ -> "other");
  let failing =
    with_transport
      (fun _ _ -> Async.failed "server down")
      (fun () -> Async.status (Action.call double 1))
  in
  check "transport failure" "failed server down" (status_text string_of_int failing)

let html_island () =
  let item name =
    Client.island ~name
      ~props:(`Assoc [ ("t", `String "</script>") ])
      (fun () ->
        Effect.run (fun () -> failwith "effect ran on the server");
        lower "b" [] [ hole (fun () -> text "") ])
  in
  check "island"
    "<div><yuka-island data-name=\"A\" data-id=\"i1\" style=\"display:contents\"><b></b></yuka-island><script type=\"application/json\" data-yuka-props=\"i1\">{\"t\":\"\\u003c/script>\"}</script>t<yuka-island data-name=\"B\" data-id=\"i2\" style=\"display:contents\"><b></b></yuka-island><script type=\"application/json\" data-yuka-props=\"i2\">{\"t\":\"\\u003c/script>\"}</script></div>"
    (html (lower "div" [] [ item "A"; text "t"; item "B" ]));
  check "counter restarts" "i1"
    (let h = html (item "A") in
     let key = "data-id=\"" in
     let rec find i = if String.sub h i (String.length key) = key then i + String.length key else find (i + 1) in
     let start = find 0 in
     String.sub h start 2)

let island_entry () =
  let e =
    Client.entry ~name:"Counter" (fun props ->
        match Codec.decode Codec.int props with
        | Ok n -> Ok (fun () -> lower "i" [] [ text (string_of_int n) ])
        | Error m -> Error m)
  in
  check "name" "Counter" (Private.entry_name e);
  (match Private.entry_decode e (`Int 3) with
  | Ok build -> check "built" "<i>3</i>" (Private.to_html (build ()))
  | Error m -> raise (Failed m));
  check "decode error" "error"
    (match Private.entry_decode e (`String "x") with Error _ -> "error" | Ok _ -> "ok")

let untracked_no_dependency () =
  let runs = ref 0 in
  let s = State.make 0 in
  Effect.run (fun () ->
      ignore (Private.untracked (fun () -> State.get s));
      incr runs);
  State.set s 1;
  check "untracked read" "1" (string_of_int !runs)

let html_await () =
  let a, resolve, fail = Async.make () in
  let el =
    lower "p" []
      [ Await.make ~failed:(fun m -> text ("E" ^ m)) ~async:a ~loading:(text "L")
          ~children:(fun n -> text (string_of_int n)) () ]
  in
  check "pending" "<p><!--[-->L<!--]--></p>" (html el);
  resolve 3;
  check "settled" "<p><!--[-->3<!--]--></p>" (html el);
  let b, _, fail_b = Async.make () in
  let el_b = Await.make ~failed:(fun m -> text ("E" ^ m)) ~async:b ~loading:(text "L") ~children:(fun () -> text "x") () in
  fail_b "no";
  check "failed" "<!--[-->Eno<!--]-->" (html el_b);
  ignore fail;
  let c = Await.make ~async:(Async.failed "z") ~loading:(text "L") ~children:(fun () -> text "x") () in
  check "default failed is empty" "<!--[--><!--]-->" (html c)

let html_streaming_session () =
  let a, resolve, _ = Async.make () in
  let b, _, _ = Async.make () in
  let s = Private.session ~streaming:true ~islands_only:false in
  let first =
    Private.print s (fun () ->
        Private.node
          (lower "p" []
             [ Await.make ~async:a ~loading:(text "L") ~children:(fun n -> text (string_of_int n)) ();
               Await.make ~async:(Async.resolved 1) ~loading:(text "no") ~children:(fun n -> text (string_of_int n)) ();
               Await.make ~async:b ~loading:(text "M") ~children:(fun n -> text (string_of_int n)) () ]))
  in
  check "shell" "<p><!--[s1-->L<!--]--><!--[-->1<!--]--><!--[s2-->M<!--]--></p>" first;
  let pending = Private.take_pending s in
  check "pending ids in order" "s1 s2"
    (String.concat " "
       (List.map
          (function
          | Private.Pending_await { id; _ } | Private.Pending_async { id; _ } -> id
          | Private.Pending_answer { key; _ } -> key)
          pending));
  check "taken once" "0" (string_of_int (List.length (Private.take_pending s)));
  match pending with
  | Private.Pending_await { id; subscribe; fill; _ } :: _ ->
      check "id" "s1" id;
      let seen = ref false in
      subscribe (fun () -> seen := true);
      check "not yet" "false" (string_of_bool !seen);
      resolve 5;
      check "subscribe fires" "true" (string_of_bool !seen);
      check "fill" "5" (fill ())
  | _ -> raise (Failed "pending shape")

let codec_async_inline () =
  let codec = Codec.async Codec.int in
  let show = function
    | Ok a -> (match Async.status a with Async.Done n -> "done " ^ string_of_int n | Async.Failed m -> "failed " ^ m | Async.Pending -> "pending")
    | Error m -> "error " ^ m
  in
  check "ok" "done 4" (show (Codec.decode codec (`Assoc [ ("$async", `String "a1"); ("ok", `Int 4) ])));
  check "error" "failed e" (show (Codec.decode codec (`Assoc [ ("$async", `String "a1"); ("error", `String "e") ])));
  check "garbage" "error" (match Codec.decode codec (`Int 1) with Error _ -> "error" | Ok _ -> "ok");
  check "encode settled" "{\"$async\":\"a0\",\"ok\":2}"
    (show_json (Codec.encode codec (Async.resolved 2)))

let html_int_float_list () =
  check "ints are two texts" "<p>-3<!---->2</p>"
    (html (lower "p" [] [ int (-3); int 2 ]));
  check "float" "2.5" (html (float 2.5));
  check "whole float" "1.0" (html (float 1.0));
  check "list" "<ul><li>a</li><li>b</li></ul>"
    (html
       (lower "ul" []
          [ list [ lower "li" [] [ text "a" ]; lower "li" [] [ text "b" ] ] ]))

let with_platform p body =
  let saved = !Private.platform in
  Private.platform := p;
  match body () with
  | () -> Private.platform := saved
  | exception e ->
      Private.platform := saved;
      raise e

let platform_delegation () =
  let add, read = log () in
  let event : Event.t = Obj.magic 0 in
  let base = !Private.platform in
  with_platform
    {
      base with
      stop_propagation = (fun _ -> add "stop");
      target_tag = (fun _ -> "li");
      shift_key = (fun _ -> true);
      alt_key = (fun _ -> false);
      navigate = (fun url -> add ("go:" ^ url));
      focus = (fun id -> add ("focus:" ^ id));
      scroll_into_view = (fun id -> add ("scroll:" ^ id));
    }
    (fun () ->
      Event.stop_propagation event;
      add (Event.target_tag event);
      add (string_of_bool (Event.shift_key event));
      add (string_of_bool (Event.alt_key event));
      Browser.navigate "/a?b=1";
      Browser.focus "box";
      Browser.scroll_into_view "row-2");
  check "calls reach the platform"
    "stop li true false go:/a?b=1 focus:box scroll:row-2" (read ())

let async_on_result () =
  let add, read = log () in
  let show = function Ok n -> "ok " ^ string_of_int n | Error m -> "error " ^ m in
  let a, resolve, _ = Async.make () in
  Async.on_result a (fun r -> add (show r));
  Async.on_result a (fun r -> add ("again " ^ show r));
  check "nothing while pending" "" (read ());
  resolve 1;
  resolve 2;
  check "ok once, in order" "ok 1 again ok 1" (read ());
  let b, _, fail = Async.make () in
  Async.on_result b (fun r -> add (show r));
  fail "boom";
  Async.on_result (Async.resolved 5) (fun r -> add (show r));
  check "error and already settled" "ok 1 again ok 1 error boom ok 5" (read ())

let html_slot () =
  let content = Slot.make (lower "p" [] [ text "x" ]) in
  check "slot with content" "<div><!--[$--><p>x</p><!--]--></div>"
    (chtml (lower "div" [] [ slot content ]));
  let empty_slot = match Codec.decode Codec.slot `Null with Ok s -> s | Error m -> raise (Failed m) in
  check "empty slot" "<!--[$--><!--]-->" (chtml (slot empty_slot));
  check "text before and after" "<b>a<!--[$-->b<!--]-->c</b>"
    (chtml
       (lower "b" []
          [ text "a"; slot (Slot.make (text "b")); text "c" ]));
  check "slot codec encodes null" "null" (show_json (Codec.encode Codec.slot content));
  check "content" "some"
    (match Private.slot_content content with Some _ -> "some" | None -> "none");
  check "no content when decoded" "none"
    (match Private.slot_content empty_slot with Some _ -> "some" | None -> "none");
  check "dom empty at first" "0" (string_of_int (List.length !(Private.slot_dom content)));
  Private.slot_dom content := [ Obj.repr 1 ];
  check "dom is shared" "1" (string_of_int (List.length !(Private.slot_dom content)))

let html_island_loading () =
  let make loading =
    html (Client.island ?loading ~name:"A" ~props:`Null (fun () -> text ""))
  in
  let prefix = "<yuka-island data-name=\"A\" data-id=\"i1\" style=\"display:contents\"" in
  let start loading = String.sub (make loading) (String.length prefix) 18 in
  check "default" ("><" ^ "/yuka-island>") (String.sub (make None) (String.length prefix) 15);
  check "load" "></yuka-island>" (String.sub (make (Some `Load)) (String.length prefix) 15);
  check "idle" " data-start=\"idle\"" (String.sub (make (Some `Idle)) (String.length prefix) 18);
  check "visible" " data-start=\"visible\"" (String.sub (make (Some `Visible)) (String.length prefix) 21);
  check "interaction" " data-start=\"interaction\"" (String.sub (make (Some `Interaction)) (String.length prefix) 25);
  ignore start

type with_function = { f : int -> int; n : int }

let default_equality () =
  let runs name make set =
    let count = ref 0 in
    let s = State.make make in
    Effect.run (fun () -> ignore (State.get s); incr count);
    set s;
    ignore name;
    !count
  in
  check "equal string built at run time" "1"
    (string_of_int
       (runs "string" (String.make 2 'a') (fun s -> State.set s (String.make 2 'a'))));
  check "different string" "2"
    (string_of_int (runs "string" "a" (fun s -> State.set s "b")));
  check "equal float built at run time" "1"
    (string_of_int
       (runs "float" (float_of_int 3 /. 2.) (fun s -> State.set s (float_of_int 3 /. 2.))));
  check "equal list is a change" "2"
    (string_of_int
       (runs "list" [ 1; 2 ] (fun s -> State.set s (List.map succ [ 0; 1 ]))));
  let list = List.map succ [ 0; 1 ] in
  check "same list is not a change" "1"
    (string_of_int (runs "list" list (fun s -> State.set s list)));
  check "float nan is a change" "2"
    (string_of_int (runs "nan" Float.nan (fun s -> State.set s Float.nan)));
  check "same int is not a change" "1"
    (string_of_int (runs "int" 7 (fun s -> State.set s (3 + 4))));
  check "same constant constructor is not a change" "1"
    (string_of_int (runs "variant" `On (fun s -> State.set s `On)));
  let value = { f = (fun x -> x + 1); n = 1 } in
  check "same record with a function is equal" "1"
    (string_of_int (runs "fn" value (fun s -> State.set s value)));
  check "new record with the same function and fields is a change" "2"
    (string_of_int
       (runs "fn" value (fun s -> State.set s { f = value.f; n = 1 })));
  check "record with another function is a change" "2"
    (string_of_int
       (runs "fn" value (fun s -> State.set s { f = (fun x -> x * 2); n = 1 })));
  let memo_runs = ref 0 in
  let n = State.make 1 in
  let parity = State.memo (fun () -> [ State.get n mod 2 ]) in
  Effect.run (fun () -> ignore (State.get parity); incr memo_runs);
  State.set n 3;
  check "memo with a new list re-runs" "2" (string_of_int !memo_runs);
  let seen = ref 0 in
  let s = State.make "a" in
  Effect.on_change s (fun ~prev:_ ~next:_ -> incr seen);
  State.set s (String.make 1 'a');
  State.set s "b";
  check "on_change uses the same equality" "1" (string_of_int !seen)

let structural_equal_option () =
  let runs = ref 0 in
  let s = State.make ~equal:( = ) [ 1; 2 ] in
  Effect.run (fun () -> ignore (State.get s); incr runs);
  State.set s (List.map succ [ 0; 1 ]);
  check "~equal:( = ) skips an equal list" "1" (string_of_int !runs);
  State.set s [ 3 ];
  check "~equal:( = ) runs on a different list" "2" (string_of_int !runs);
  let memo_runs = ref 0 in
  let n = State.make 1 in
  let parity = State.memo ~equal:( = ) (fun () -> [ State.get n mod 2 ]) in
  Effect.run (fun () -> ignore (State.get parity); incr memo_runs);
  State.set n 3;
  check "memo ~equal:( = ) skips an equal list" "1" (string_of_int !memo_runs);
  let seen = ref 0 in
  let p = State.make (1, "a") in
  Effect.on_change ~equal:( = ) p (fun ~prev:_ ~next:_ -> incr seen);
  State.set p (1, String.make 1 'a');
  State.set p (2, "a");
  check "on_change ~equal:( = )" "1" (string_of_int !seen)

let closure_state () =
  let runs = ref 0 in
  let f = State.make (fun x -> x + 1) in
  Effect.run (fun () -> ignore (State.get f : int -> int); incr runs);
  let g = fun x -> x * 2 in
  State.set f g;
  State.set f g;
  check "a closure in a State compares by identity" "2" (string_of_int !runs);
  let pair = State.make ((fun x -> x), 1) in
  let pair_runs = ref 0 in
  Effect.run (fun () -> ignore (State.get pair : (int -> int) * int); incr pair_runs);
  State.set pair ((fun x -> x + 1), 1);
  check "a tuple with a closure does not raise" "2" (string_of_int !pair_runs);
  check "closure kept" "6" (string_of_int ((State.peek f) 3))

let batch_delays () =
  let add, read = log () in
  let a = State.make 0 in
  let b = State.make 0 in
  let double = State.memo (fun () -> State.get a * 2) in
  Effect.run (fun () ->
      add (Printf.sprintf "%d/%d" (State.get a) (State.get b)));
  let result =
    batch (fun () ->
        State.set a 1;
        State.set b 1;
        add ("memo" ^ string_of_int (State.peek double));
        "done")
  in
  check "one run after the batch" "0/0 memo2 1/1" (read ());
  check "batch returns the result" "done" result;
  State.set a 2;
  check "no batch after it ends" "0/0 memo2 1/1 2/1" (read ())

let batch_nests () =
  let add, read = log () in
  let a = State.make 0 in
  Effect.run (fun () -> add (string_of_int (State.get a)));
  batch (fun () ->
      State.set a 1;
      batch (fun () -> State.set a 2);
      add "inner-done";
      State.set a 3);
  check "inner batch does not flush" "0 inner-done 3" (read ());
  let trigger = State.make 0 in
  let inside = State.make 0 in
  let seen = ref [] in
  Effect.run (fun () ->
      if State.get trigger = 1 then
        batch (fun () -> State.set inside 1; State.set inside 2));
  Effect.run (fun () -> seen := State.get inside :: !seen);
  State.set trigger 1;
  check "batch inside an effect" "2,0" (String.concat "," (List.map string_of_int !seen))

let batch_raises () =
  let add, read = log () in
  let a = State.make 0 in
  Effect.run (fun () -> add (string_of_int (State.get a)));
  let raised =
    match
      batch (fun () ->
          State.set a 1;
          failwith "stop")
    with
    | () -> "no"
    | exception Failure m -> m
  in
  check "the exception of the batch" "stop" raised;
  check "pending effects ran" "0 1" (read ());
  State.set a 2;
  check "no batch left open" "0 1 2" (read ());
  let nested =
    match
      batch (fun () ->
          (try batch (fun () -> State.set a 3; failwith "inner")
           with Failure _ -> ());
          add "after-inner";
          State.set a 4)
    with
    | () -> "ok"
    | exception Failure m -> m
  in
  check "inner exception caught" "ok" nested;
  check "inner raise keeps the outer batch" "0 1 2 after-inner 4" (read ())

let disposal_order () =
  let add, read = log () in
  let (), dispose =
    owner (fun () ->
        Effect.run ~cleanup:(fun () -> add "first") (fun () -> ());
        Effect.run ~cleanup:(fun () -> add "second") (fun () -> ());
        Effect.run ~cleanup:(fun () -> add "third") (fun () -> ()))
  in
  dispose ();
  check "last created is cleaned first" "third second first" (read ())

let effect_run_order () =
  let add, read = log () in
  let count = State.make 0 in
  let double = State.memo (fun () -> State.get count * 2) in
  Effect.run (fun () -> add ("m" ^ string_of_int (State.get double)));
  Effect.run (fun () -> add ("a" ^ string_of_int (State.get count)));
  Effect.run (fun () -> add ("b" ^ string_of_int (State.get count)));
  State.set count 1;
  State.set count 2;
  check "lower level first, then the last created first"
    "m0 a0 b0 b1 a1 m2 b2 a2 m4" (read ())

let disposal_order_after_removal () =
  let add, read = log () in
  let (), dispose =
    owner (fun () ->
        Effect.run ~cleanup:(fun () -> add "a") (fun () -> ());
        let (), dispose_b =
          Private.owned (fun () ->
              Effect.run ~cleanup:(fun () -> add "b1") (fun () -> ());
              Effect.run ~cleanup:(fun () -> add "b2") (fun () -> ()))
        in
        Effect.run ~cleanup:(fun () -> add "c") (fun () -> ());
        let (), dispose_d =
          Private.owned (fun () -> Effect.run ~cleanup:(fun () -> add "d") (fun () -> ()))
        in
        Effect.run ~cleanup:(fun () -> add "e") (fun () -> ());
        dispose_d ();
        Effect.run
          ~cleanup:(fun () ->
            add "f";
            dispose_b ())
          (fun () -> ()))
  in
  dispose ();
  check "removed child first, then last created first; a cleanup that disposes a sibling"
    "d f b2 b1 e c a" (read ());
  dispose ();
  check "second dispose does nothing" "d f b2 b1 e c a" (read ())

let owned_removed_from_parent () =
  let add, read = log () in
  let (), dispose_parent =
    owner (fun () ->
        check "empty at first" "0" (string_of_int (Private.owner_size ()));
        for i = 1 to 200 do
          let (), dispose =
            Private.owned (fun () ->
                Effect.run ~cleanup:(fun () -> add ("gone" ^ string_of_int i)) (fun () -> ()))
          in
          dispose ()
        done;
        check "disposed children leave no disposer" "0"
          (string_of_int (Private.owner_size ()));
        let (), dispose_a =
          Private.owned (fun () ->
              Effect.run ~cleanup:(fun () -> add "a") (fun () -> ()))
        in
        let (), _dispose_b =
          Private.owned (fun () ->
              Effect.run ~cleanup:(fun () -> add "b") (fun () -> ()))
        in
        check "two live children" "2" (string_of_int (Private.owner_size ()));
        dispose_a ();
        dispose_a ();
        check "one live child" "1" (string_of_int (Private.owner_size ())))
  in
  let before = List.length (String.split_on_char ' ' (read ())) in
  check "each disposed child cleaned once" "201" (string_of_int before);
  dispose_parent ();
  let log_text = read () in
  let words = String.split_on_char ' ' log_text in
  check "parent dispose cleans only the live child" "202" (string_of_int (List.length words));
  check "the live one" "b" (List.nth words 201);
  check "a only once" "1"
    (string_of_int (List.length (List.filter (( = ) "a") words)))

let opt v = lower "option" [ attr "value" v ] [ text (String.uppercase_ascii v) ]

let html_select_value () =
  check "static value" "<select><option value=\"a\">A</option><option value=\"b\" selected=\"\">B</option></select>"
    (html (lower "select" [ attr "value" "b" ] [ opt "a"; opt "b" ]));
  let current = State.make (Some "a") in
  let dynamic = lower "select" [ hole_attr "value" (fun () -> State.get current) ] [ opt "a"; opt "b" ] in
  check "dynamic value" "<select><option value=\"a\" selected=\"\">A</option><option value=\"b\">B</option></select>"
    (chtml dynamic);
  State.set current None;
  check "no value, no selection" "<select><option value=\"a\">A</option><option value=\"b\">B</option></select>"
    (chtml dynamic);
  check "no value attribute on the select" "<select><option value=\"a\">A</option></select>"
    (html (lower "select" [] [ opt "a" ]));
  check "optgroup, fragment, hole and each"
    "<select><optgroup label=\"g\"><option value=\"b\" selected=\"\">B</option></optgroup><!--[--><option value=\"b\" selected=\"\">B</option><!--]--><!--[--><option value=\"b\" selected=\"\">B</option><!--]--><option value=\"c\">C</option></select>"
    (chtml
       (lower "select" [ attr "value" "b" ]
          [ lower "optgroup" [ attr "label" "g" ] [ fragment [ opt "b" ] ];
            hole (fun () -> opt "b");
            each ~key:Fun.id (fun () -> [ "b" ]) opt;
            opt "c" ]));
  check "escaped values compare unescaped" "<select><option value=\"a&quot;&amp;\" selected=\"\">A\"&amp;</option></select>"
    (html
       (lower "select" [ attr "value" "a\"&" ]
          [ lower "option" [ attr "value" "a\"&" ] [ text "A\"&" ] ]));
  check "option without value is not selected (text is not compared)"
    "<select><option>b</option></select>"
    (html (lower "select" [ attr "value" "b" ] [ lower "option" [] [ text "b" ] ]));
  check "own selected is not repeated" "<select><option value=\"b\" selected=\"\">B</option></select>"
    (html
       (lower "select" [ attr "value" "b" ]
          [ lower "option" [ attr "value" "b"; attr "selected" "" ] [ text "B" ] ]));
  check "an option outside a select is untouched" "<option value=\"b\">B</option>"
    (html (opt "b"));
  check "the selection ends with the select"
    "<div><select><option value=\"a\" selected=\"\">A</option></select><option value=\"a\">A</option></div>"
    (html (lower "div" [] [ lower "select" [ attr "value" "a" ] [ opt "a" ]; opt "a" ]));
  check "next select is independent"
    "<div><select><option value=\"a\" selected=\"\">A</option></select><select><option value=\"a\">A</option></select></div>"
    (html
       (lower "div" []
          [ lower "select" [ attr "value" "a" ] [ opt "a" ];
            lower "select" [] [ opt "a" ] ]))

let html_textarea_value () =
  check "static" "<textarea>a &amp; b &lt;c&gt;</textarea>"
    (html (lower "textarea" [ attr "value" "a & b <c>" ] []));
  check "children ignored" "<textarea>v</textarea>"
    (html (lower "textarea" [ attr "value" "v" ] [ text "ignored" ]));
  let v = State.make (Some "x") in
  let el = lower "textarea" [ attr "rows" "3"; hole_attr "value" (fun () -> State.get v) ] [] in
  check "dynamic keeps other attributes" "<textarea rows=\"3\">x</textarea>" (chtml el);
  State.set v None;
  check "dynamic none" "<textarea rows=\"3\"></textarea>" (chtml el);
  check "without value the children stay" "<textarea>kept</textarea>"
    (html (lower "textarea" [] [ text "kept" ]));
  check "leading newline survives" "<textarea>\n\nx</textarea>"
    (html (lower "textarea" [ attr "value" "\nx" ] []));
  check "input keeps its value attribute" "<input value=\"v\">"
    (html (lower "input" [ attr "value" "v" ] []))

let codec_result () =
  let c = Codec.result Codec.int Codec.string in
  check "ok" "{\"ok\":1}" (show_json (Codec.encode c (Ok 1)));
  check "error" "{\"error\":\"no\"}" (show_json (Codec.encode c (Error "no")));
  let show = function Ok (Ok n) -> "ok " ^ string_of_int n | Ok (Error m) -> "error " ^ m | Error m -> "decode:" ^ m in
  check "decode ok" "ok 2" (show (Codec.decode c (`Assoc [ ("ok", `Int 2) ])));
  check "decode error" "error x" (show (Codec.decode c (`Assoc [ ("error", `String "x") ])));
  check "ok payload type" "decode:expected int, got \"s\""
    (show (Codec.decode c (`Assoc [ ("ok", `String "s") ])));
  check "error payload type" "decode:expected string, got 1"
    (show (Codec.decode c (`Assoc [ ("error", `Int 1) ])));
  check "neither key" "decode:expected result, got {\"x\":1}"
    (show (Codec.decode c (`Assoc [ ("x", `Int 1) ])));
  check "both keys" "true"
    (string_of_bool
       (match Codec.decode c (`Assoc [ ("ok", `Int 1); ("error", `String "e") ]) with
       | Error _ -> true
       | Ok _ -> false));
  let nested = Codec.result (Codec.list Codec.int) (Codec.option Codec.string) in
  check "nested round trip" "ok 1,2"
    (match Codec.decode nested (Codec.encode nested (Ok [ 1; 2 ])) with
    | Ok (Ok l) -> "ok " ^ String.concat "," (List.map string_of_int l)
    | _ -> "bad")

let shape_html shape = Private.template_html (Private.template shape)

let html_template () =
  let p = Private.template Template.(element "p" [ fixed "class" "c" ] [ text "a" ]) in
  check "printed as its tree" "<p class=\"c\">a</p>" (chtml (Template.instance p [||]));
  check "no marker around nested" "<div><p class=\"c\">a</p></div>"
    (chtml (lower "div" [] [ Template.instance p [||] ]))

let template_parts_print () =
  let state = State.make "x" in
  let t =
    Private.template
      Template.(
        (element "div"
           [ fixed "id" "d"; part_attr 0; part_attr 1; part_attr 2 ]
           [ text "a"; part 3; element "span" [] [ part 4 ]; text "b" ]))
  in
  let parts : client Template.part array =
    Template.
      [|
        attribute (hole_attr "title" (fun () -> Some (State.get state)));
        attribute_option None;
        attribute (on "click" (fun _ -> ()));
        child (Yuka.text "t");
        child (hole (fun () -> Yuka.text (State.get state)));
      |]
  in
  let by_hand : client element =
    lower "div"
      [ attr "id" "d"; hole_attr "title" (fun () -> Some (State.get state)); on "click" (fun _ -> ()) ]
      [ text "a"; text "t"; lower "span" [] [ hole (fun () -> text (State.get state)) ]; text "b" ]
  in
  check "same html as lower" (chtml by_hand) (chtml (Template.instance t parts));
  check "html" "<div id=\"d\" title=\"x\">a<!---->t<span>x</span>b</div>"
    (chtml (Template.instance t parts))

let template_shape_html () =
  check "shape"
    "<div id=\"d\">a<!---->b<br><span>&amp;&lt;</span>c<!---->d<i></i>e</div>"
    (shape_html
       Template.(
         element "div" [ fixed "id" "d"; part_attr 0 ]
           [ text "a"; text "b"; element "br" [] []; part 1;
             element "span" [] [ text "&<" ]; text "c"; part 2; text "d";
             element "i" [] []; part 3; text "e" ]))

let template_values () =
  let opt v = Template.(element "option" [ fixed "value" v ] [ text v ]) in
  check "static select value"
    "<select><option value=\"a\">a</option><option value=\"b\" selected=\"\">b</option></select>"
    (shape_html Template.(element "select" [ fixed "value" "b" ] [ opt "a"; opt "b" ]));
  check "part select value is left out" "<select><option value=\"a\">a</option></select>"
    (shape_html Template.(element "select" [ part_attr 0 ] [ opt "a" ]));
  check "static textarea value" "<textarea>v &amp;</textarea>"
    (shape_html Template.(element "textarea" [ fixed "value" "v &" ] []));
  check "part textarea value is left out" "<textarea></textarea>"
    (shape_html Template.(element "textarea" [ part_attr 0 ] []))

let only_child_markers () =
  let s = State.make "x" in
  check "hole as the only child has no markers" "<p>x</p>"
    (chtml (lower "p" [] [ hole (fun () -> text (State.get s)) ]));
  check "hole with a sibling keeps markers" "<p><!--[-->x<!--]-->!</p>"
    (chtml (lower "p" [] [ hole (fun () -> text (State.get s)); text "!" ]));
  check "hole at the root keeps markers" "<!--[-->x<!--]-->"
    (chtml (hole (fun () -> text (State.get s))));
  check "hole inside a fragment keeps markers" "<p><!--[-->x<!--]--></p>"
    (chtml (lower "p" [] [ fragment [ hole (fun () -> text (State.get s)) ] ]));
  check "list as the only child, element rows: no markers"
    "<ul><li>a</li><li>b</li></ul>"
    (chtml (lower "ul" [] [ each ~key:Fun.id (fun () -> [ "a"; "b" ]) (fun v -> lower "li" [] [ text v ]) ]));
  check "list with a sibling, text rows: all markers"
    "<ul><!--[--><!--[-->a<!--]--><!--[-->b<!--]--><!--]--><li></li></ul>"
    (chtml
       (lower "ul" []
          [ each ~key:Fun.id (fun () -> [ "a"; "b" ]) text; lower "li" [] [] ]));
  check "template rows: no row markers" "<ul><!--[--><li>a</li><!--]--><i></i></ul>"
    (chtml
       (lower "ul" []
          [ each ~key:Fun.id (fun () -> [ "a" ])
              (fun v -> Template.instance (Private.template Template.(element "li" [] [ part 0 ])) Template.[| child (Yuka.text v) |]);
            lower "i" [] [] ]))

let await_component () =
  let a, resolve, fail = Async.make () in
  let el =
    lower "p" []
      [ Await.make ~async:a ~loading:(text "L")
          ~failed:(fun m -> text ("E" ^ m))
          ~children:(fun n -> text (string_of_int n))
          () ]
  in
  check "pending" "<p><!--[-->L<!--]--></p>" (html el);
  resolve 3;
  check "settled" "<p><!--[-->3<!--]--></p>" (html el);
  let b, _, fail_b = Async.make () in
  let el_b = Await.make ~async:b ~loading:(text "L") ~failed:(fun m -> text ("E" ^ m)) ~children:(fun () -> text "x") () in
  fail_b "no";
  check "failed element" "<!--[-->Eno<!--]-->" (html el_b);
  let c = Await.make ~async:(Async.failed "z") ~loading:(text "L") ~children:(fun () -> text "x") () in
  check "default failed is empty" "<!--[--><!--]-->" (html c);
  ignore fail

let mount_raises_disposes () =
  let add, read = log () in
  let result =
    match
      owner (fun () ->
          Effect.run ~cleanup:(fun () -> add "cleaned") (fun () -> add "ran");
          failwith "boom")
    with
    | _ -> "no error"
    | exception Failure m -> m
  in
  check "the exception is raised again" "boom" result;
  check "effects of a failed mount are disposed" "ran cleaned" (read ());
  let count = State.make 0 in
  let runs = ref 0 in
  (match
     owner (fun () ->
         Effect.run (fun () -> ignore (State.get count); incr runs);
         failwith "again")
   with
  | _ -> ()
  | exception Failure _ -> ());
  State.set count 1;
  check "a disposed effect does not run again" "1" (string_of_int !runs)

let owned_raises_disposes () =
  let add, read = log () in
  let (), dispose_parent =
    owner (fun () ->
        (match
           Private.owned (fun () ->
               Effect.run ~cleanup:(fun () -> add "cleaned") (fun () -> ());
               failwith "boom")
         with
        | _ -> ()
        | exception Failure _ -> ());
        check "the failed child leaves no disposer" "0"
          (string_of_int (Private.owner_size ())))
  in
  check "the child was disposed" "cleaned" (read ());
  dispose_parent ();
  check "not disposed twice" "cleaned" (read ())

let json_depth_limit () =
  let deep n = String.make n '[' ^ String.make n ']' in
  check "depth 100000 is an error" "error" (is_error (deep 100000));
  check "deep objects are an error" "error"
    (is_error (String.concat "" (List.init 100000 (fun _ -> "{\"a\":")) ^ "1"));
  check "depth 512 is fine" "ok" (is_error (deep 512));
  check "depth 513 is an error" "error" (is_error (deep 513));
  check "the message says why" "error: nesting too deep"
    (let m = parse (deep 513) in
     if String.length m >= 23 then String.sub m 0 23 else m)

let html_float_special () =
  check "nan" "NaN" (html (float nan));
  check "infinity" "Infinity" (html (float infinity));
  check "negative infinity" "-Infinity" (html (float neg_infinity));
  check "ordinary" "-0.5" (html (float (-0.5)));
  check "whole" "3.0" (html (float 3.0))

let html_array () =
  check "array" "a<!---->b" (html (array [| text "a"; text "b" |]));
  check "empty array" "" (html (array [||]))

let memo_lazy_without_readers () =
  let computes = ref 0 in
  let n = State.make 0 in
  let m =
    State.memo (fun () ->
        incr computes;
        State.get n + 1)
  in
  State.set n 1;
  State.set n 2;
  check "no recompute without a reader" "1" (string_of_int !computes);
  check "fresh on read" "3" (string_of_int (State.peek m));
  check "one recompute on read" "2" (string_of_int !computes)

let memo_diamond () =
  let add, read = log () in
  let n = State.make 1 in
  let a = State.memo (fun () -> State.get n * 2) in
  let b = State.memo (fun () -> State.get n * 3) in
  let sum = State.memo (fun () -> State.get a + State.get b) in
  let parity = State.memo (fun () -> State.get sum mod 2) in
  Effect.run (fun () ->
      add (Printf.sprintf "%d=%d+%d" (State.get sum) (State.get a) (State.get b)));
  Effect.run (fun () -> add ("p" ^ string_of_int (State.get parity)));
  State.set n 2;
  State.set n 4;
  check "one consistent run per write; an unchanged memo stops the update"
    "5=2+3 p1 10=4+6 p0 20=8+12" (read ())

let dynamic_dependencies () =
  let runs = ref 0 in
  let cond = State.make true in
  let a = State.make 0 in
  let b = State.make 0 in
  Effect.run (fun () ->
      incr runs;
      ignore (if State.get cond then State.get a else State.get b));
  State.set b 1;
  State.set cond false;
  State.set a 1;
  State.set b 2;
  check "only the States read in the last run" "3" (string_of_int !runs)

let dependency_order_changes () =
  let runs = ref 0 in
  let flip = State.make false in
  let a = State.make 0 in
  let b = State.make 0 in
  Effect.run (fun () ->
      incr runs;
      if State.get flip then (ignore (State.get b); ignore (State.get a))
      else (ignore (State.get a); ignore (State.get b)));
  State.set flip true;
  State.set b 1;
  State.set a 1;
  check "both States tracked after the read order changes" "4" (string_of_int !runs)

let memo_raises_reader_recovers () =
  let n = State.make 0 in
  let m =
    State.memo (fun () -> if State.get n = 1 then failwith "bad" else State.get n)
  in
  let seen = ref [] in
  Effect.run (fun () -> seen := State.get m :: !seen);
  (try State.set n 1 with Failure _ -> ());
  (try State.set n 2 with Failure _ -> ());
  check "the effect sees the memo again after it raised" "2,0"
    (String.concat "," (List.map string_of_int !seen))

let loop_limit_recovers () =
  let s = State.make 0 in
  let m = State.memo (fun () -> State.get s) in
  let loop = State.make false in
  let seen = ref 0 in
  Effect.run (fun () ->
      let v = State.get m in
      seen := v;
      if State.peek loop then State.set s (v + 1));
  State.set loop true;
  (try State.set s 1 with Failure _ -> ());
  State.set loop false;
  (try State.set s 1000 with Failure _ -> ());
  check "an effect dropped at the limit runs on a later write" "1000"
    (string_of_int !seen)

let raise_keeps_unread_dependencies () =
  let runs = ref 0 in
  let a = State.make 0 in
  let b = State.make 0 in
  Effect.run (fun () ->
      incr runs;
      if State.get a = 1 then failwith "stop";
      ignore (State.get b));
  (try State.set a 1 with Failure _ -> ());
  (try State.set b 5 with Failure _ -> ());
  check "a raising run keeps the States it did not read yet" "3"
    (string_of_int !runs)

let parent_runs_before_child () =
  let add, read = log () in
  let o = State.make (Some 1) in
  Effect.run (fun () ->
      match State.get o with
      | Some _ ->
          Effect.run (fun () -> add (string_of_int (Option.get (State.get o))))
      | None -> add "none");
  State.set o None;
  check "the parent re-runs and disposes the child first" "1 none" (read ())

let disposed_during_run () =
  let s = State.make 0 in
  let t = State.make 0 in
  let dispose = ref ignore in
  let (), d =
    owner (fun () ->
        Effect.run (fun () ->
            if State.get s = 1 then begin
              !dispose ();
              ignore (State.get t)
            end))
  in
  dispose := d;
  State.set s 1;
  check "an effect disposed during its run reads nothing more" "false false"
    (Printf.sprintf "%b %b" (Private.has_readers s) (Private.has_readers t))

let memo_first_compute_raises () =
  let n = State.make 0 in
  (try
     ignore
       (State.memo (fun () ->
            ignore (State.get n);
            failwith "bad"))
   with Failure _ -> ());
  check "a memo whose first compute raises leaves no reader" "false"
    (string_of_bool (Private.has_readers n))

let disposed_while_pending () =
  let add, read = log () in
  let s = State.make 0 in
  let (), dispose =
    owner (fun () -> Effect.run (fun () -> add ("b" ^ string_of_int (State.get s))))
  in
  Effect.run (fun () -> if State.get s = 1 then dispose ());
  State.set s 1;
  check "a pending effect disposed in the same flush does not run" "b0" (read ())

let memo_raises () =
  let n = State.make 0 in
  let m =
    State.memo (fun () -> if State.get n = 1 then failwith "bad" else State.get n)
  in
  let read () = try string_of_int (State.peek m) with Failure e -> e in
  State.set n 1;
  check "the read raises" "bad" (read ());
  check "the next read computes again" "bad" (read ());
  State.set n 2;
  check "a later change recovers" "2" (read ())

let batch_in_first_run () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.run (fun () -> add ("e" ^ string_of_int (State.get s)));
  Effect.run (fun () ->
      batch (fun () -> State.set s 1);
      add "end");
  check "a batch in an effect runs pending effects when the effect ends"
    "e0 end e1" (read ())

let all =
  [
    ("memo is lazy without readers", memo_lazy_without_readers);
    ("memo diamond", memo_diamond);
    ("dynamic dependencies", dynamic_dependencies);
    ("dependency order changes", dependency_order_changes);
    ("memo that raises, then its reader", memo_raises_reader_recovers);
    ("loop limit, then a later write", loop_limit_recovers);
    ("a raising run keeps unread dependencies", raise_keeps_unread_dependencies);
    ("parent effect before its child", parent_runs_before_child);
    ("an effect disposed during its run", disposed_during_run);
    ("a memo whose first compute raises", memo_first_compute_raises);
    ("disposed while pending", disposed_while_pending);
    ("memo that raises", memo_raises);
    ("batch in the first run of an effect", batch_in_first_run);
    ("first run", first_run);
    ("re-run on change", rerun_on_change);
    ("no re-run on an equal write", no_rerun_on_equal_write);
    ("cleanup receives the previous result", cleanup_receives_previous_result);
    ("nested effect disposed on owner re-run", nested_disposed_on_rerun);
    ("mount dispose runs inner cleanups", mount_dispose);
    ("error isolation", error_isolation);
    ("on_change prev and next", on_change_prev_next);
    ("memo recomputes only on input change", memo_recomputes_on_input_change);
    ("peek does not track", peek_does_not_track);
    ("outer effect keeps its dependency", outer_keeps_dependency_after_inner);
    ("effect sees a consistent memo", effect_sees_consistent_memo);
    ("memo uses the default equality", memo_equal_by_default);
    ("effect writing its own State settles", effect_writing_own_state_settles);
    ("effect writing its own State stops at a limit", effect_writing_own_state_stops);
    ("html escaping", html_escaping);
    ("html adjacent texts", html_adjacent_texts);
    ("html empty text", html_empty_text);
    ("html hole markers", html_hole);
    ("html each markers", html_each);
    ("html dynamic attribute", html_dynamic_attribute);
    ("html handler not written", html_handler);
    ("html void tag", html_void);
    ("html nested", html_nested);
    ("html skips effects", html_effect_skipped);
    ("json round trip", json_round_trip);
    ("json printing", json_printing);
    ("json script safety", json_script_safety);
    ("json parser", json_parser);
    ("json invalid input", json_invalid);
    ("codec round trip", codec_round_trip);
    ("codec errors", codec_errors);
    ("async settles once", async_settle_once);
    ("async on_settled", async_on_settled);
    ("async map and bind", async_map_bind);
    ("async watch", async_watch);
    ("action call", action_call);
    ("html island", html_island);
    ("island entry", island_entry);
    ("untracked", untracked_no_dependency);
    ("html await", html_await);
    ("html streaming session", html_streaming_session);
    ("codec async", codec_async_inline);
    ("html int float list", html_int_float_list);
    ("platform delegation", platform_delegation);
    ("async on_result", async_on_result);
    ("html slot", html_slot);
    ("html island loading", html_island_loading);
    ("default equality", default_equality);
    ("structural equality on request", structural_equal_option);
    ("closure in a State", closure_state);
    ("batch delays effects", batch_delays);
    ("batch nests", batch_nests);
    ("batch with an exception", batch_raises);
    ("owned removed from its parent", owned_removed_from_parent);
    ("disposal order", disposal_order);
    ("disposal order after removal", disposal_order_after_removal);
    ("effect run order", effect_run_order);
    ("html select value", html_select_value);
    ("html textarea value", html_textarea_value);
    ("codec result", codec_result);
    ("html template", html_template);
    ("template parts print", template_parts_print);
    ("template shape html", template_shape_html);
    ("template values", template_values);
    ("only child markers", only_child_markers);
    ("Await component", await_component);
    ("mount disposes when the function raises", mount_raises_disposes);
    ("json depth limit", json_depth_limit);
    ("html float special values", html_float_special);
    ("html array", html_array);
    ("owned disposes when the function raises", owned_raises_disposes);
  ]
