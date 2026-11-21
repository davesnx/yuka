open Yuka

let check = Cases.check

external get_attribute : Browser.element -> string -> string option = "getAttribute"
[@@mel.send] [@@mel.return nullable]

type pending = { mutable calls : string list; mutable waiting : (string * (unit -> unit) * (string -> unit)) list }

let pending () = { calls = []; waiting = [] }

let waits p =
  exit_after (fun el ->
      let k = Option.value (get_attribute el "data-key") ~default:"?" in
      p.calls <- p.calls @ [ k ];
      let a, resolve, fail = Async.make () in
      p.waiting <- p.waiting @ [ (k, resolve, fail) ];
      a)

let settle p k =
  match List.find_opt (fun (k', _, _) -> k' = k) p.waiting with
  | Some ((_, resolve, _) as w) ->
      p.waiting <- List.filter (fun x -> x != w) p.waiting;
      resolve ()
  | None -> failwith ("no exit is waiting for " ^ k)

let fail p k =
  match List.find_opt (fun (k', _, _) -> k' = k) p.waiting with
  | Some ((_, _, fail) as w) ->
      p.waiting <- List.filter (fun x -> x != w) p.waiting;
      fail "stopped"
  | None -> failwith ("no exit is waiting for " ^ k)

let order c = Dom_cases.texts c "li"
let li k children = Dom_cases.li k children

let list ?exit items row =
  let c = Dom_cases.container "" in
  let dispose =
    Private.render (Dom_cases.as_element c) (fun () ->
        element "ul" [] [ each ?exit ~key:Fun.id (fun () -> Array.of_list (State.get items)) row ])
  in
  (c, dispose)

let removed_item_stays_until_exit_settles () =
  let p = pending () and items = State.make [ "a"; "b"; "c" ] and label = State.make "" in
  let c, dispose = list ~exit:(waits p) items (fun k -> li k [ text k; hole (fun () -> text (State.get label)) ]) in
  let b = Dom_cases.query c "[data-key=b]" in
  State.set items [ "a"; "c" ];
  check "exit gets the element of the row" "b" (String.concat "," p.calls);
  check "the row stays during its exit" "a,b,c" (order c);
  Dom_cases.same "the same element" b (Dom_cases.query c "[data-key=b]");
  State.set label "!";
  check "the row is live during its exit" "a!,b!,c!" (order c);
  settle p "b";
  check "the row goes when the exit settles" "a!,c!" (order c);
  State.set label "?";
  check "the row is disposed" "a?,c?" (order c);
  dispose ()

let failed_exit_removes () =
  let p = pending () and items = State.make [ "a"; "b" ] in
  let c, dispose = list ~exit:(waits p) items (fun k -> li k [ text k ]) in
  State.set items [ "a" ];
  check "waits" "a,b" (order c);
  fail p "b";
  check "a failed exit removes the row" "a" (order c);
  dispose ()

let raising_exit_removes_at_once () =
  let items = State.make [ "a"; "b" ] in
  let c, dispose =
    list ~exit:(exit_after (fun _ -> failwith "exit")) items (fun k -> li k [ text k ])
  in
  State.set items [ "a" ];
  check "an exception in exit removes the row at once" "a" (order c);
  dispose ()

let fragment_row_goes_at_once () =
  let p = pending () and items = State.make [ "a"; "b" ] in
  let c, dispose = list ~exit:(waits p) items (fun k -> fragment [ li k [ text k ]; li k [ text k ] ]) in
  State.set items [ "a" ];
  check "a row of more than one element is not given to exit" "" (String.concat "," p.calls);
  check "and goes at once" "a,a" (order c);
  dispose ()

let same_key_back_during_exit () =
  let p = pending () and items = State.make [ "a"; "b"; "c" ] in
  let c, dispose = list ~exit:(waits p) items (fun k -> li k [ text k ]) in
  let old_b = Dom_cases.query c "[data-key=b]" in
  State.set items [ "a"; "c" ];
  State.set items [ "a"; "b"; "c" ];
  check "the old row and a new row" "b,b" (Dom_cases.texts c "[data-key=b]");
  settle p "b";
  check "after the exit, one row per item" "a,b,c" (order c);
  let b = Dom_cases.query c "[data-key=b]" in
  check "the new row stays" "different" (if b == old_b then "same" else "different");
  State.set items [ "a"; "c" ];
  check "the new row exits too" "b,b" (String.concat "," p.calls);
  settle p "b";
  check "and goes" "a,c" (order c);
  dispose ()

let newer_update_during_exit () =
  let p = pending () and items = State.make [ "a"; "b"; "c" ] in
  let c, dispose = list ~exit:(waits p) items (fun k -> li k [ text k ]) in
  State.set items [ "a"; "c" ];
  State.set items [ "c"; "d"; "a" ];
  State.set items [ "d"; "e" ];
  check "every removed row waits" "b,c,a" (String.concat "," p.calls);
  settle p "a";
  settle p "c";
  settle p "b";
  check "no stale row" "d,e" (order c);
  State.set items [];
  check "all rows exit" "b,c,a,d,e" (String.concat "," p.calls);
  check "and stay" "d,e" (order c);
  State.set items [ "f" ];
  settle p "d";
  settle p "e";
  check "only the new row" "f" (order c);
  dispose ()

let owner_disposed_during_exit () =
  let p = pending () and items = State.make [ "a"; "b" ] and on = State.make true and label = State.make "" in
  let reads = ref 0 in
  let c = Dom_cases.container "" in
  let dispose =
    Private.render (Dom_cases.as_element c) (fun () ->
        element "div" []
          [ hole (fun () ->
                if State.get on then
                  element "ul" []
                    [ each ~exit:(waits p) ~key:Fun.id
                        (fun () -> Array.of_list (State.get items))
                        (fun k ->
                          li k
                            [ hole (fun () ->
                                  incr reads;
                                  text (k ^ State.get label)) ]) ]
                else text "off") ])
  in
  State.set items [ "a" ];
  check "b exits" "a,b" (order c);
  State.set on false;
  check "the list and the exiting row go" "off" (Dom_cases.text_content c);
  let before = !reads in
  State.set label "!";
  check "the exiting row is disposed" (string_of_int before) (string_of_int !reads);
  settle p "b";
  check "a late settle changes nothing" "off" (Dom_cases.text_content c);
  dispose ()

let unmount_during_exit () =
  let p = pending () and items = State.make [ "a"; "b" ] and label = State.make "" in
  let reads = ref 0 in
  let c, dispose =
    list ~exit:(waits p) items (fun k ->
        li k
          [ hole (fun () ->
                incr reads;
                text (k ^ State.get label)) ])
  in
  State.set items [ "a" ];
  dispose ();
  let before = !reads in
  State.set label "!";
  check "the exiting row is disposed with its owner" (string_of_int before) (string_of_int !reads);
  check "and its element goes" "" (Dom_cases.texts c "[data-key=b]");
  settle p "b"

let without_exit_unchanged () =
  let items = State.make [ "a"; "b"; "c" ] in
  let c, dispose = list items (fun k -> li k [ text k ]) in
  State.set items [ "a"; "c" ];
  check "removed at once" "a,c" (order c);
  State.set items [];
  check "cleared" "" (order c);
  dispose ()

let show_view ?exit st =
  Show.make
    ~status:(fun () -> State.get st)
    ~loading:(element "li" [ attr "data-key" "loading" ] [ text "loading" ])
    ?exit
    ~children:(fun d -> element "li" [ attr "data-key" d ] [ text d ])
    ()

let show_exit () =
  let p = pending () and st = State.make (Status.Ready { data = "a"; stale = false }) in
  let c = Dom_cases.container "" in
  let dispose = Private.render (Dom_cases.as_element c) (fun () -> element "ul" [] [ show_view ~exit:(waits p) st ]) in
  check "first" "a" (order c);
  State.set st (Status.Ready { data = "b"; stale = false });
  check "the old content exits" "a" (String.concat "," p.calls);
  check "old and new content" "a,b" (order c);
  State.set st (Status.Loading None);
  check "a newer change during the exit" "a,b,loading" (order c);
  settle p "b";
  settle p "a";
  check "no stale content" "loading" (order c);
  dispose ()

let show_exit_hydrates () =
  let p = pending () and st = State.make (Status.Ready { data = "a"; stale = false }) in
  let tree () = element "ul" [] [ show_view ~exit:(waits p) st ] in
  let html = Dom_cases.server (tree ()) in
  let c = Dom_cases.container html in
  let a = Dom_cases.query c "[data-key=a]" in
  Dom_cases.capture_warnings ();
  let dispose = Private.hydrate (Dom_cases.as_element c) tree in
  check "no mismatch" "" (Dom_cases.warnings ());
  Dom_cases.same "the server row is adopted" a (Dom_cases.query c "[data-key=a]");
  State.set st (Status.Ready { data = "b"; stale = false });
  check "the adopted row exits" "a,b" (order c);
  settle p "a";
  check "then goes" "b" (order c);
  dispose ()

let all =
  [
    ("exit: a removed item stays until its exit settles", removed_item_stays_until_exit_settles);
    ("exit: a failed exit removes the row", failed_exit_removes);
    ("exit: an exception in exit removes the row at once", raising_exit_removes_at_once);
    ("exit: a row of more than one element goes at once", fragment_row_goes_at_once);
    ("exit: the same key back during its exit", same_key_back_during_exit);
    ("exit: a newer update during an exit leaves no stale row", newer_update_during_exit);
    ("exit: the owner goes during an exit", owner_disposed_during_exit);
    ("exit: unmount during an exit", unmount_during_exit);
    ("exit: each without exit removes at once", without_exit_unchanged);
    ("exit: Show keeps the old content until its exit settles", show_exit);
    ("exit: Show with exit hydrates", show_exit_hydrates);
  ]
