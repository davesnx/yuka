open Yuka

let check = Cases.check
let log = Cases.log

let num : int Context.t = Context.make ~name:"num" ()
let other : int Context.t = Context.make ~name:"other" ()
let show c = match Context.get c with Some n -> string_of_int n | None -> "none"
let read c = text (show c)
let later c = hole (fun () -> read c)
let render build = Private.render_html (fun () -> Private.node (build ()))
let server_hole c = Private.element (Private.hole (fun () -> Private.node (read c)))

let raises f =
  match f () with
  | _ -> "no exception"
  | exception Invalid_argument m -> m

let nearest_wins () =
  check "the nearest provide wins; a sibling outside sees the outer value or None"
    "<!--[-->none<!--]--><!--[--><!--[-->1<!--]--><!--[--><!--[-->2<!--]--><!--]--><!--[-->1<!--]--><!--]--><!--[-->none<!--]-->"
    (render (fun () ->
         fragment
           [ later num;
             Context.provide num 1 (fun () ->
                 fragment [ later num; Context.provide num 2 (fun () -> later num); later num ]);
             later num ]))

let same_type_distinct () =
  check "two contexts of the same type are distinct" "<!--[-->1 none<!--]-->"
    (render (fun () -> Context.provide num 1 (fun () -> text (show num ^ " " ^ show other))))

let provide_all_as_nested () =
  let both () = text (show num ^ " " ^ show other) in
  check "nested provide" "<!--[--><!--[-->1 2<!--]--><!--]-->"
    (render (fun () -> Context.provide num 1 (fun () -> Context.provide other 2 both)));
  check "provide_all gives the same values in one node" "<!--[-->1 2<!--]-->"
    (render (fun () -> Context.provide_all [ Context.bind num 1; Context.bind other 2 ] both));
  check "the last duplicate wins" "<!--[-->3 2<!--]-->"
    (render (fun () -> Context.provide_all [ Context.bind num 1; Context.bind other 2; Context.bind num 3 ] both))

let get_exn_names () =
  let m = raises (fun () -> Context.get_exn num) in
  check "get_exn raises Invalid_argument with the name" "true" (string_of_bool (Cases.contains m "num"));
  check "get_exn gives the value" "<!--[-->4<!--]-->"
    (render (fun () -> Context.provide num 4 (fun () -> int (Context.get_exn num))))

let built_before () =
  let comp () = fragment [ read num; later num ] in
  check "an element built before provide: its function sees the outer value, its hole the inner one"
    "<!--[-->none<!--[-->4<!--]--><!--]-->"
    (render (fun () ->
         let built = comp () in
         Context.provide num 4 (fun () -> built)))

let every_place () =
  check "a component function, a hole, a row, a dynamic attribute and Catch children see the value"
    "<!--[--><p title=\"5\">5<!--[-->5<!--]--><!--[--><i>a5</i><!--]--><!--[-->5<!--]--></p><!--]-->"
    (render (fun () ->
         Context.provide num 5 (fun () ->
             let v = show num in
             element "p"
               [ hole_attr "title" (fun () -> Some (show num)) ]
               [ text v;
                 later num;
                 each ~key:Fun.id (fun () -> [| "a" |]) (fun k -> element "i" [] [ text (k ^ show num) ]);
                 Catch.make ~fallback:(fun ~error:_ ~reset:_ -> text "f") ~children:(fun () -> read num) () ])))

let catch_restores () =
  check "Catch children that raise under provide: the fallback and the next sibling see the outer value"
    "<!--[--><!--[!-->1<!--]--><!--[-->1<!--]--><!--]-->"
    (render (fun () ->
         Context.provide num 1 (fun () ->
             fragment
               [ Catch.make
                   ~fallback:(fun ~error:_ ~reset:_ -> read num)
                   ~children:(fun () ->
                     Context.provide num 2 (fun () -> fragment [ later num; hole (fun () -> failwith "boom") ]))
                   ();
                 later num ])))

let island_boundary () =
  let island render = runtime_island ~name:"I" ~props:`Null render in
  let inside html =
    let open_tag = "style=\"display:contents\">" and close = "</yuka-island>" in
    let rec find s i = if String.sub html i (String.length s) = s then i else find s (i + 1) in
    let a = find open_tag 0 + String.length open_tag in
    String.sub html a (find close a - a)
  in
  let page body = render (fun () -> Context.provide num 1 (fun () -> island body)) in
  check "get in the island render is None" "none" (inside (page (fun () -> read num)));
  check "a provide inside the island reaches its hole" "<!--[--><!--[-->3<!--]--><!--]-->"
    (inside (page (fun () -> Context.provide num 3 (fun () -> later num))));
  check "a hole in slot content sees the page value, not the island value"
    "<!--[--><!--[$--><!--[-->1<!--]--><!--]--><!--]-->"
    (inside (page (fun () -> Context.provide num 9 (fun () -> runtime_slot (Some (server_hole num))))));
  check "a page provide inside slot content reaches its holes" "<!--[$--><!--[--><!--[-->2<!--]--><!--]--><!--]-->"
    (inside
       (page (fun () -> runtime_slot (Some (Context.provide num 2 (fun () -> server_hole num))))));
  let m = ref "" in
  ignore
    (page (fun () ->
         m := raises (fun () -> Context.get_exn num);
         empty));
  check "the get_exn message names the island" "true"
    (string_of_bool (Cases.contains !m "num" && Cases.contains !m "outside this island"));
  let n = ref "" in
  ignore (render (fun () -> island (fun () -> n := raises (fun () -> Context.get_exn num); empty)));
  check "no island in the message when nothing is provided" "false" (string_of_bool (Cases.contains !n "island"))

let fills s =
  List.filter_map
    (function Private.Pending_await { fill; fill_failed; _ } -> Some (fill, fill_failed) | _ -> None)
    (Private.take_pending s)

let streamed_fill () =
  let a, resolve_a, _ = Async.make () and b, resolve_b, _ = Async.make () in
  let s = Private.session ~streaming:true ~islands_only:false in
  let await async = Await.make ~async ~loading:(text "L") ~failed:(fun _ -> read num) ~children:(fun () -> read num) () in
  ignore
    (Private.print s (fun () ->
         Private.node
           (Context.provide num 1 (fun () -> fragment [ Context.provide num 7 (fun () -> await a); await b ]))));
  match fills s with
  | [ (fill_a, failed_a); (fill_b, failed_b) ] ->
      resolve_a ();
      resolve_b ();
      check "the second fill first prints the outer value" "1" (fill_b ());
      check "the first fill prints its provide" "7" (fill_a ());
      check "fill_failed of the second prints the outer value" "1" (failed_b "x");
      check "fill_failed of the first prints its provide" "7" (failed_a "x");
      check "no value after the fills" "none" (show num)
  | l -> raise (Cases.Failed ("pending awaits: " ^ string_of_int (List.length l)))

let streamed_fill_in_island () =
  let a, resolve, _ = Async.make () in
  let s = Private.session ~streaming:true ~islands_only:false in
  ignore
    (Private.print s (fun () ->
         Private.node
           (Context.provide num 1 (fun () ->
                runtime_island ~name:"I" ~props:`Null (fun () ->
                    Context.provide num 2 (fun () ->
                        Await.make ~async:a ~loading:(text "L")
                          ~children:(fun () ->
                            fragment [ later num; runtime_slot (Some (server_hole num)) ])
                          ()))))));
  match fills s with
  | [ (fill, _) ] ->
      resolve ();
      check "a fill in an island: its hole sees the island value, the slot the page value"
        "<!--[-->2<!--]--><!--[$--><!--[-->1<!--]--><!--]-->" (fill ())
  | l -> raise (Cases.Failed ("pending awaits: " ^ string_of_int (List.length l)))

let fixed_value () =
  let st = State.make 0 and comp = ref 0 and same = ref true in
  let sc : int State.t Context.t = Context.make () in
  let add, read = log () in
  let () =
    Private.with_context [ Context.bind sc st ] (fun () ->
        incr comp;
        let given = Context.get_exn sc in
        Effect.before (fun () ->
            same := !same && Context.get_exn sc == given;
            add (string_of_int (State.get given))))
  in
  State.set st 1;
  State.set st 2;
  check "a State in the value updates the effect" "0 1 2" (read ());
  check "the function that read the context ran once" "1" (string_of_int !comp);
  check "each run gets the same value" "true" (string_of_bool !same)

let detached_owner_keeps () =
  let s = State.make 0 in
  let add, read = log () in
  let (), dispose =
    owner (fun () ->
        Private.with_context [ Context.bind num 1 ] (fun () ->
            Effect.before (fun () ->
                ignore (State.get s);
                add (show num))))
  in
  Private.with_context [ Context.bind num 2 ] (fun () -> State.set s 1);
  State.set s 2;
  check "an effect keeps its value when a write from another scope runs it" "1 1 1" (read ());
  dispose ()

let none_outside () =
  let a, resolve, _ = Async.make () in
  let add, read = log () in
  Private.with_context [ Context.bind num 1 ] (fun () ->
      add (show num);
      Async.on_settled a (fun _ -> add (show num)));
  add (show num);
  resolve ();
  check "get in the scope, after it, and in an Async callback" "1 none none" (read ());
  ignore (render (fun () -> Context.provide num 1 (fun () -> empty)));
  check "get after a render" "none" (show num)

let later_effect () =
  let s = State.make 0 in
  let add, read = log () in
  let (), dispose =
    owner (fun () ->
        Private.with_context [ Context.bind num 1 ] (fun () ->
            Effect.before (fun () -> if State.get s > 0 then Effect.before (fun () -> add (show num)))))
  in
  Private.with_context [ Context.bind num 2 ] (fun () -> State.set s 1);
  check "an effect made in a later run of an effect sees the value" "1" (read ());
  dispose ()

let all =
  [
    ("context: the nearest provide wins", nearest_wins);
    ("context: two contexts of one type are distinct", same_type_distinct);
    ("context: provide_all equals nested provide", provide_all_as_nested);
    ("context: get_exn names the context", get_exn_names);
    ("context: an element built before provide", built_before);
    ("context: every place of a print sees the value", every_place);
    ("context: Catch restores the outer value", catch_restores);
    ("context: an island is a boundary, its slot is not", island_boundary);
    ("context: a streamed fill sees the value of its place", streamed_fill);
    ("context: a streamed fill in an island", streamed_fill_in_island);
    ("context: the value is fixed", fixed_value);
    ("context: a detached owner keeps its value", detached_owner_keeps);
    ("context: no value outside a scope", none_outside);
    ("context: an effect made in a later run", later_effect);
  ]
