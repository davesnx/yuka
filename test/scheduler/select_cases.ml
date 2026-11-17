open Yuka

let check = Cases.check
let ints = string_of_int
let bools = string_of_bool

let readers is_selected keys runs answers =
  for key = 0 to keys - 1 do
    Effect.before (fun () ->
        answers.(key) <- is_selected key;
        incr runs)
  done

let selected answers =
  let found = ref [] in
  Array.iteri (fun key answer -> if answer then found := ints key :: !found) answers;
  String.concat " " (List.rev !found)

let change_runs_two_readers () =
  let source = State.make 3 in
  let runs = ref 0 and answers = Array.make 1_000 false in
  let (), dispose =
    with_owner (fun () -> readers (State.select source) 1_000 runs answers)
  in
  check "first answers" "3" (selected answers);
  runs := 0;
  State.set source 7;
  check "a change runs the readers of the old and the new key" "2" (ints !runs);
  check "answers after the change" "7" (selected answers);
  State.set source 2_000;
  check "a change to a key with no reader runs the old key only" "3" (ints !runs);
  check "no answer is true" "" (selected answers);
  dispose ()

let same_value_runs_nothing () =
  let source = State.make ~equal:(fun _ _ -> false) 3 in
  let runs = ref 0 and answers = Array.make 100 false in
  let (), dispose =
    with_owner (fun () -> readers (State.select source) 100 runs answers)
  in
  runs := 0;
  State.set source 3;
  check "a write of the same value runs no reader" "0" (ints !runs);
  check "answers" "3" (selected answers);
  dispose ()

let untracked_read_makes_no_entry () =
  let source = State.make 3 in
  let (is_selected, size), dispose =
    with_owner (fun () -> State.select_with_size source)
  in
  check "untracked answers" "false true" (bools (is_selected 5) ^ " " ^ bools (is_selected 3));
  let (), dispose_reader =
    with_owner (fun () ->
        Effect.before (fun () -> ignore (State.untrack (fun () -> is_selected 5))))
  in
  check "no entry for an untracked read" "0" (ints (size ()));
  State.set source 5;
  check "untracked answer after a change" "true" (bools (is_selected 5));
  dispose_reader ();
  dispose ()

let disposed_readers_leave_the_table () =
  let source = State.make 0 in
  let window = 100 in
  let (is_selected, size), dispose =
    with_owner (fun () -> State.select_with_size source)
  in
  let live = Queue.create () and largest = ref 0 in
  for key = 0 to 29_999 do
    let (), dispose_reader =
      with_owner (fun () -> Effect.before (fun () -> ignore (is_selected key)))
    in
    Queue.push dispose_reader live;
    if Queue.length live > window then (Queue.pop live) ();
    if size () > !largest then largest := size ()
  done;
  check "the table stays at most twice the live readers" "true"
    (bools (!largest <= 2 * window));
  check "the table keeps the live readers" "true" (bools (size () >= window));
  Queue.iter (fun dispose_reader -> dispose_reader ()) live;
  dispose ()

let owner_dispose_stops_the_selector () =
  let source = State.make 3 in
  let runs = ref 0 and answers = Array.make 10 false in
  let size, dispose =
    with_owner (fun () ->
        let is_selected, size = State.select_with_size source in
        readers is_selected 10 runs answers;
        size)
  in
  check "one entry per read key" "10" (ints (size ()));
  dispose ();
  check "dispose clears the table" "0" (ints (size ()));
  runs := 0;
  let raised = match State.set source 7 with () -> "no" | exception e -> Printexc.to_string e in
  check "a write after dispose raises nothing" "no" raised;
  check "a write after dispose runs nothing" "0" (ints !runs)

let memo_recomputes_for_its_key () =
  let source = State.make 3 in
  let computes = ref 0 in
  let memos, dispose =
    with_owner (fun () ->
        let is_selected = State.select source in
        Array.init 100 (fun key ->
            State.memo (fun () ->
                incr computes;
                is_selected key)))
  in
  computes := 0;
  State.set source 7;
  let answers = Array.map State.get memos in
  check "only the memos of the old and the new key compute" "2" (ints !computes);
  check "memo answers" "7" (selected answers);
  dispose ()

let reader_sees_the_new_source () =
  let source = State.make 3 in
  let seen = ref [] in
  let (), dispose =
    with_owner (fun () ->
        let is_selected = State.select source in
        Effect.before (fun () ->
            let value = State.get source in
            seen := (ints value ^ ":" ^ bools (is_selected 3)) :: !seen))
  in
  State.set source 7;
  State.set source 3;
  check "one run per change, with the answer of the new value" "3:true 7:false 3:true"
    (String.concat " " (List.rev !seen));
  dispose ()

let reader_of_a_memo_runs_once () =
  let base = State.make 3 in
  let seen = ref [] in
  let (), dispose =
    with_owner (fun () ->
        let source = State.memo (fun () -> State.get base) in
        let is_selected = State.select source in
        let three = State.memo (fun () -> is_selected 3) in
        Effect.before (fun () ->
            let value = State.get source in
            seen := (ints value ^ ":" ^ bools (State.get three)) :: !seen))
  in
  State.set base 7;
  check "one run per change, with the new answer of the memo" "3:true 7:false"
    (String.concat " " (List.rev !seen));
  dispose ()

let memo_read_in_a_batch () =
  let source = State.make 3 in
  let (pair, dispose) =
    with_owner (fun () ->
        let is_selected = State.select source in
        State.memo (fun () -> ints (State.get source) ^ ":" ^ bools (is_selected 3)))
  in
  let inside =
    batch (fun () ->
        State.set source 7;
        State.get pair)
  in
  check "a memo read in a batch sees the new answer" "7:false" inside;
  check "after the batch" "7:false" (State.get pair);
  dispose ()

type item = { id : int }

let records_are_keys_by_identity () =
  let first = { id = Sys.opaque_identity 1 } and twin = { id = Sys.opaque_identity 1 } in
  let source = State.make first in
  let log = ref [] in
  let (), dispose =
    with_owner (fun () ->
        let is_selected = State.select source in
        Effect.before (fun () -> log := ("first " ^ bools (is_selected first)) :: !log);
        Effect.before (fun () -> log := ("twin " ^ bools (is_selected twin)) :: !log))
  in
  check "an equal record is another key" "first true twin false" (String.concat " " (List.rev !log));
  log := [];
  State.set source twin;
  check "a change to the equal record runs both readers" "true true"
    (bools (List.mem "first false" !log) ^ " " ^ bools (List.mem "twin true" !log));
  dispose ()

let all =
  [
    ("select: a change runs the readers of two keys", change_runs_two_readers);
    ("select: the same value runs no reader", same_value_runs_nothing);
    ("select: an untracked read makes no entry", untracked_read_makes_no_entry);
    ("select: disposed readers leave the table", disposed_readers_leave_the_table);
    ("select: owner dispose stops the selector", owner_dispose_stops_the_selector);
    ("select: a memo computes for its key only", memo_recomputes_for_its_key);
    ("select: a reader of the source sees the new answer", reader_sees_the_new_source);
    ("select: a reader of a memo runs once", reader_of_a_memo_runs_once);
    ("select: a memo read in a batch sees the new answer", memo_read_in_a_batch);
    ("select: records are keys by identity", records_are_keys_by_identity);
  ]
