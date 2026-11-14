open Yuka

let check = Cases.check
let log = Cases.log
let before (f : unit -> unit) = Effect.before f
let after (f : unit -> unit) = Effect.after f
let int = string_of_int

let since read f =
  let old = read () in
  f ();
  let all = read () in
  let n = String.length old in
  let n = if n > 0 && String.length all > n then n + 1 else n in
  String.sub all n (String.length all - n)

let memo_in_first_run kind () =
  let runs = ref 0 in
  let other = State.make 0 and count = State.make 0 in
  kind (fun () ->
      ignore (State.get other);
      let c = State.memo (fun () -> State.get count + 1) in
      ignore (State.peek c);
      ignore (State.get count);
      incr runs);
  State.set count 1;
  State.set count 2;
  check "the effect keeps its dependency after a memo made in its first run" "3"
    (int !runs)

let memo_in_deferred_first_run () =
  let runs = ref 0 in
  let other = State.make 0 and count = State.make 0 in
  batch (fun () ->
      Effect.after (fun () ->
          ignore (State.get other);
          let c = State.memo (fun () -> State.get count + 1) in
          ignore (State.get c);
          ignore (State.get count);
          incr runs));
  State.set count 1;
  State.set count 2;
  check "a deferred first run keeps its dependency after a memo made in it" "3"
    (int !runs)

let effect_in_memo_compute () =
  let other = State.make 0 and count = State.make 0 in
  let c =
    State.memo (fun () ->
        ignore (State.get other);
        Effect.before (fun () -> ignore (State.get count));
        State.get count)
  in
  State.set count 5;
  check "a memo keeps its dependency after an effect made in its compute" "5"
    (int (State.peek c));
  State.set other 1;
  check "recompute" "5" (int (State.peek c));
  State.set count 6;
  check "and after a recompute" "6" (int (State.peek c))

let memo_in_memo_compute () =
  let other = State.make 0 and count = State.make 0 in
  let c =
    State.memo (fun () ->
        ignore (State.get other);
        let inner = State.memo (fun () -> State.get count * 2) in
        ignore (State.peek inner);
        State.get count)
  in
  let seen = ref [] in
  Effect.before (fun () -> seen := State.get c :: !seen);
  State.set count 5;
  State.set other 1;
  State.set count 6;
  check "a memo keeps its dependency after a memo made in its compute" "6,5,0"
    (String.concat "," (List.map int !seen))

let self_write_first_run kind () =
  let add, read = log () in
  let s = State.make 0 in
  kind (fun () ->
      let v = State.get s in
      add (int v);
      if v < 1 then State.set s 1);
  check "the write in the first run is a change of a State the effect read" "0 1"
    (read ());
  State.set s 5;
  check "the effect keeps its dependency on the State it wrote" "0 1 5" (read ());
  check "value" "5" (int (State.peek s))

let self_write_first_run_in_batch () =
  let add, read = log () in
  let s = State.make 0 in
  batch (fun () ->
      Effect.before (fun () ->
          let v = State.get s in
          add (int v);
          if v < 1 then State.set s 1);
      add "end");
  check "the re-run waits for the end of the batch" "0 end 1" (read ());
  State.set s 5;
  check "the effect keeps its dependency" "0 end 1 5" (read ())

let self_write_deferred_first_run () =
  let add, read = log () in
  let s = State.make 0 in
  batch (fun () ->
      Effect.after (fun () ->
          let v = State.get s in
          add (int v);
          if v < 1 then State.set s 1);
      add "end");
  check "the deferred first run, then the re-run" "end 0 1" (read ());
  State.set s 5;
  check "the effect keeps its dependency" "end 0 1 5" (read ())

let self_write_through_memo kind () =
  let add, read = log () in
  let s = State.make 0 in
  let m = State.memo (fun () -> State.get s) in
  kind (fun () ->
      let v = State.get m in
      add (int v);
      if v < 1 then State.set s 1);
  check "the write reaches the effect through the memo" "0 1" (read ());
  State.set s 5;
  check "the effect keeps its dependency on the memo" "0 1 5" (read ())

let self_write_in_nested_first_run () =
  let add, read = log () in
  let trigger = State.make 0 and s = State.make 0 in
  before (fun () ->
      if State.get trigger = 1 then
        before (fun () ->
            let v = State.get s in
            add ("i" ^ int v);
            if v < 1 then State.set s 1));
  State.set trigger 1;
  check "an inner effect made during a flush re-runs after its own write" "i0 i1"
    (read ());
  State.set s 5;
  check "and keeps its dependency" "i0 i1 i5" (read ())

let inner_writes_outer_dependency () =
  let add, read = log () in
  let s = State.make 0 in
  before (fun () ->
      add ("a" ^ int (State.get s));
      before (fun () -> State.set s 1));
  check "the outer effect re-runs after the write of its inner effect" "a0 a1" (read ());
  State.set s 5;
  check "and keeps its dependency" "a0 a1 a5 a1" (read ());
  State.set s 7;
  check "again" "a0 a1 a5 a1 a7 a1" (read ())

let clamp kind () =
  let add, read = log () in
  let s = State.make 0 in
  kind (fun () ->
      let v = State.get s in
      if v > 10 then State.set s 10;
      add (int v));
  State.set s 15;
  check "a write in a re-run runs the effect again until it settles" "0 15 10"
    (read ());
  check "value" "10" (int (State.peek s));
  State.set s 3;
  check "the effect keeps its dependency" "0 15 10 3" (read ())

let clamp_in_batch kind () =
  let add, read = log () in
  let s = State.make 0 in
  kind (fun () ->
      let v = State.get s in
      if v > 10 then State.set s 10;
      add (int v));
  batch (fun () ->
      State.set s 15;
      State.set s 20);
  check "one run for the batch, then one for the clamp" "0 20 10" (read ());
  check "value" "10" (int (State.peek s))

let clamp_through_memo kind () =
  let add, read = log () in
  let s = State.make 0 in
  let m = State.memo (fun () -> State.get s) in
  kind (fun () ->
      let v = State.get m in
      if v > 10 then State.set s 10;
      add (int v));
  State.set s 15;
  check "the clamp reaches the effect through the memo" "0 15 10" (read ());
  State.set s 3;
  check "the effect keeps its dependency" "0 15 10 3" (read ())

let clamp_in_after_render_in_before () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.after (fun () ->
      let v = State.get s in
      if v > 10 then State.set s 10);
  before (fun () -> add ("r" ^ int (State.get s)));
  State.set s 15;
  check "the before effect ends on the settled value" "r0 r15 r10" (read ())

let indirect_cycle effect_a effect_b () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  effect_b (fun () ->
      let w = State.get t in
      add ("b" ^ int w);
      if w = 1 then State.set s 2);
  effect_a (fun () ->
      let v = State.get s in
      add ("a" ^ int v);
      State.set t (v + 1));
  check "the cycle settles" "b0 a0 b1 a2 b3" (read ());
  State.set s 10;
  check "the first effect keeps its dependency on s" "b0 a0 b1 a2 b3 a10 b11" (read ())

let indirect_cycle_in_batch kind () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  batch (fun () ->
      kind (fun () ->
          let w = State.get t in
          add ("b" ^ int w);
          if w = 1 then State.set s 2);
      kind (fun () ->
          let v = State.get s in
          add ("a" ^ int v);
          State.set t (v + 1)));
  check "settled values" "2 3" (Printf.sprintf "%d %d" (State.peek s) (State.peek t));
  check "the first effect keeps its dependency on s" "a10 b11"
    (since read (fun () -> State.set s 10))

let indirect_cycle_through_memo () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  let mt = State.memo (fun () -> State.get t) in
  before (fun () ->
      let w = State.get mt in
      add ("b" ^ int w);
      if w = 1 then State.set s 2);
  before (fun () ->
      let v = State.get s in
      add ("a" ^ int v);
      State.set t (v + 1));
  check "the cycle settles" "b0 a0 b1 a2 b3" (read ());
  State.set s 10;
  check "the first effect keeps its dependency" "b0 a0 b1 a2 b3 a10 b11" (read ())

let three_node_cycle kind () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 and u = State.make 0 in
  kind (fun () ->
      let w = State.get u in
      add ("c" ^ int w);
      if w = 2 then State.set s 5);
  kind (fun () ->
      let v = State.get t in
      add ("b" ^ int v);
      State.set u (v + 1));
  kind (fun () ->
      let v = State.get s in
      add ("a" ^ int v);
      State.set t (v + 1));
  check "the cycle settles" "c0 b0 c1 a0 b1 c2 a5 b6 c7" (read ());
  check "every effect keeps its dependency" "a10 b11 c12"
    (since read (fun () -> State.set s 10))

let cycle_from_rerun kind () =
  let add, read = log () in
  let on = State.make false and s = State.make 0 and t = State.make 0 in
  kind (fun () ->
      let v = State.get s in
      add ("a" ^ int v);
      if State.get on then State.set t (v + 1));
  kind (fun () ->
      let w = State.get t in
      add ("b" ^ int w);
      if w = 1 then State.set s 2);
  check "first runs" "a0 b0" (read ());
  check "the cycle starts in a re-run and settles" "a0 b1 a2 b3"
    (since read (fun () -> State.set on true));
  check "the first effect keeps its dependency" "a10 b11"
    (since read (fun () -> State.set s 10))

let indirect_cycle_limit () =
  let go = State.make false and s = State.make 0 and t = State.make 0 in
  let seen = ref 0 in
  before (fun () ->
      let v = State.get s in
      seen := v;
      if State.get go then State.set t (v + 1));
  before (fun () ->
      let w = State.get t in
      if State.peek go then State.set s (w + 1));
  let result =
    match State.set go true with
    | () -> "no error"
    | exception Failure m when Cases.contains m "keeps changing a State it reads" -> "limit"
  in
  check "an indirect cycle that does not settle stops at the limit" "limit" result;
  State.set go false;
  State.set s 1000;
  check "the effect still runs on a later write" "1000" (int !seen)

let mutual_disposal () =
  let s = State.make 0 in
  let runs = ref 0 and clean_a = ref 0 and clean_b = ref 0 in
  let other_a = ref ignore and other_b = ref ignore in
  let (), dispose_a =
    owner (fun () ->
        Effect.before
          ~cleanup:(fun () -> incr clean_a)
          (fun () ->
            if State.get s > 0 then !other_a ();
            incr runs))
  in
  let (), dispose_b =
    owner (fun () ->
        Effect.before
          ~cleanup:(fun () -> incr clean_b)
          (fun () ->
            if State.get s > 0 then !other_b ();
            incr runs))
  in
  other_a := dispose_b;
  other_b := dispose_a;
  check "both ran once" "2" (int !runs);
  State.set s 1;
  check "an effect disposed while pending does not run" "3" (int !runs);
  dispose_a ();
  dispose_b ();
  check "the survivor cleaned up twice, the other once" "2 1"
    (Printf.sprintf "%d %d" (max !clean_a !clean_b) (min !clean_a !clean_b))

let raising_memo_in_first_run () =
  let tracked = State.make 0 and other = State.make 0 in
  let runs = ref 0 in
  before (fun () ->
      (try
         ignore
           (State.memo (fun () ->
                ignore (State.get other);
                failwith "boom")
             : int State.read)
       with Failure _ -> ());
      ignore (State.get tracked);
      incr runs);
  State.set tracked 1;
  check "reads after a raising memo are still tracked" "2" (int !runs);
  State.set other 1;
  check "the reads of the raising memo are not the effect's" "2" (int !runs)

let unobserved_memo () =
  let src = State.make 1 in
  let computes = ref 0 in
  let c =
    State.memo (fun () ->
        incr computes;
        State.get src * 2)
  in
  let (), dispose = owner (fun () -> before (fun () -> ignore (State.get c))) in
  check "observed" "true" (string_of_bool (Private.has_readers src));
  dispose ();
  check "contract silent: the memo still reads its source after its reader is gone"
    "true"
    (string_of_bool (Private.has_readers src));
  State.set src 5;
  check "an unobserved memo is up to date on read" "10" (int (State.peek c));
  let seen = ref 0 in
  let (), dispose = owner (fun () -> before (fun () -> seen := State.get c)) in
  State.set src 6;
  check "and its new reader runs" "12" (int !seen);
  check "value" "12" (int (State.peek c));
  dispose ()

let cleanup_reads_state () =
  let s = State.make 0 and x = State.make 0 in
  let runs = ref 0 in
  Effect.before
    ~cleanup:(fun () -> ignore (State.get x))
    (fun () ->
      ignore (State.get s);
      incr runs);
  State.set s 1;
  State.set x 1;
  check "contract silent: a State read with get in a cleanup is a dependency" "3"
    (int !runs)

let effects_in_recomputed_memo () =
  let n = State.make 0 and tick = State.make 0 in
  let alive = ref 0 in
  let m =
    State.memo (fun () ->
        let v = State.get n in
        Effect.before (fun () ->
            ignore (State.get tick);
            incr alive);
        v)
  in
  State.set n 1;
  ignore (State.peek m);
  State.set n 2;
  ignore (State.peek m);
  alive := 0;
  State.set tick 1;
  check "contract silent: effects made by each compute of an unowned memo all stay"
    "3" (int !alive)

let memo_released_with_owner () =
  let src = State.make 1 in
  let (), dispose =
    owner (fun () ->
        let doubled = State.memo (fun () -> State.get src * 2) in
        before (fun () -> ignore (State.get doubled)))
  in
  check "observed" "true" (string_of_bool (Private.has_readers src));
  dispose ();
  check "a memo made in an owner stops reading its source with it" "false"
    (string_of_bool (Private.has_readers src))

let detached_owner_in_rerun () =
  let s = State.make 0 and t = State.make 0 in
  let inner = ref 0 in
  let disposers = ref [] in
  before (fun () ->
      ignore (State.get s);
      let (), dispose =
        owner (fun () ->
            before (fun () ->
                ignore (State.get t);
                incr inner))
      in
      disposers := dispose :: !disposers);
  State.set s 1;
  inner := 0;
  State.set t 1;
  check "an owner made in an effect is not disposed when the effect runs again" "2"
    (int !inner);
  List.iter (fun d -> d ()) !disposers;
  inner := 0;
  State.set t 2;
  check "its own dispose stops it" "0" (int !inner)

let on_change_clamp () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.on_change s (fun ~prev ~next ->
      add (Printf.sprintf "%d->%d" prev next);
      if next > 10 then State.set s 10);
  State.set s 15;
  check "on_change sees the clamp it wrote" "0->15 15->10" (read ());
  State.set s 3;
  check "and later changes" "0->15 15->10 10->3" (read ())

let clamp_in_raising_batch () =
  let add, read = log () in
  let s = State.make 0 in
  before (fun () ->
      let v = State.get s in
      if v > 10 then State.set s 10;
      add (int v));
  let raised =
    match
      batch (fun () ->
          State.set s 15;
          failwith "stop")
    with
    | () -> "no"
    | exception Failure m -> m
  in
  check "the exception of the batch" "stop" raised;
  check "the pending runs settle before it is raised" "0 15 10" (read ())

let self_write_then_raise_in_first_run () =
  let runs = ref 0 in
  let s = State.make 0 in
  let raised =
    match
      Effect.before (fun () ->
          incr runs;
          let v = State.get s in
          if v < 1 then begin
            State.set s 1;
            failwith "first"
          end)
    with
    | () -> "no"
    | exception Failure m -> m
  in
  check "the first run raises to the caller" "first" raised;
  check "a first run that raises after a self-write does not run again" "1" (int !runs);
  State.set s 5;
  check "and the effect is stopped" "1" (int !runs)

let indirect_write_then_raise_in_first_run () =
  let runs = ref 0 in
  let s = State.make 0 and t = State.make 0 in
  before (fun () -> if State.get t = 1 then State.set s 1);
  let raised =
    match
      Effect.before (fun () ->
          incr runs;
          if State.get s = 0 then begin
            State.set t 1;
            failwith "first"
          end)
    with
    | () -> "no"
    | exception Failure m -> m
  in
  check "the first run raises to the caller" "first" raised;
  check "a first run that raises after an indirect cycle does not run again" "1"
    (int !runs)

let memo_peek_after_write () =
  let s = State.make 0 in
  let m = State.memo (fun () -> State.get s * 2) in
  let seen = ref [] in
  before (fun () ->
      seen := State.get m :: !seen;
      if State.peek s = 0 then begin
        State.set s 1;
        ignore (State.peek m)
      end);
  check "the effect runs again after the memo it read changed" "2,0"
    (String.concat "," (List.map int !seen))

let memo_peek_after_write_in_rerun () =
  let go = State.make false and s = State.make 0 in
  let m = State.memo (fun () -> State.get s * 2) in
  let seen = ref [] in
  before (fun () ->
      seen := State.get m :: !seen;
      if State.get go && State.peek s = 0 then begin
        State.set s 1;
        ignore (State.peek m)
      end);
  State.set go true;
  check "a re-run that peeks the memo after a write runs again" "2,0,0"
    (String.concat "," (List.map int !seen));
  State.set s 7;
  check "and keeps its dependency" "14,2,0,0" (String.concat "," (List.map int !seen))

let memo_untrack_after_write () =
  let s = State.make 0 in
  let m = State.memo (fun () -> State.get s * 2) in
  let seen = ref [] in
  before (fun () ->
      seen := State.get m :: !seen;
      if State.peek s = 0 then begin
        State.set s 1;
        ignore (State.untrack (fun () -> State.get m))
      end);
  check "with untrack the effect runs again" "2,0"
    (String.concat "," (List.map int !seen))

let memo_chain_after_write () =
  let add, read = log () in
  let s = State.make 0 in
  let m = State.memo (fun () -> State.get s * 2) in
  let m2 = State.memo (fun () -> State.get m + 1) in
  before (fun () ->
      let a = State.get m in
      if State.peek s = 0 then State.set s 1;
      add (Printf.sprintf "%d/%d" a (State.get m2)));
  check "the effect runs again after the memo it read changed" "0/3 2/3" (read ())

let all =
  [
    ("reativa: a memo made in a first run (before)", memo_in_first_run before);
    ("reativa: a memo made in a first run (after)", memo_in_first_run after);
    ("reativa: a memo made in a deferred first run", memo_in_deferred_first_run);
    ("reativa: an effect made in a memo compute", effect_in_memo_compute);
    ("reativa: a memo made in a memo compute", memo_in_memo_compute);
    ("reativa: self-write in a first run (before)", self_write_first_run before);
    ("reativa: self-write in a first run (after)", self_write_first_run after);
    ("reativa: self-write in a first run in a batch", self_write_first_run_in_batch);
    ("reativa: self-write in a deferred first run", self_write_deferred_first_run);
    ("reativa: self-write through a memo (before)", self_write_through_memo before);
    ("reativa: self-write through a memo (after)", self_write_through_memo after);
    ("reativa: self-write in a first run during a flush", self_write_in_nested_first_run);
    ("reativa: an inner effect writes the outer dependency", inner_writes_outer_dependency);
    ("reativa: clamp in a re-run (before)", clamp before);
    ("reativa: clamp in a re-run (after)", clamp after);
    ("reativa: clamp after a batch (before)", clamp_in_batch before);
    ("reativa: clamp after a batch (after)", clamp_in_batch after);
    ("reativa: clamp through a memo (before)", clamp_through_memo before);
    ("reativa: clamp through a memo (after)", clamp_through_memo after);
    ("reativa: clamp in after, render in before", clamp_in_after_render_in_before);
    ("reativa: indirect cycle in a first run (before)", indirect_cycle before before);
    ("reativa: indirect cycle in a first run (after)", indirect_cycle after after);
    ("reativa: indirect cycle in a first run (after, before)", indirect_cycle after before);
    ("reativa: indirect cycle in a batch (before)", indirect_cycle_in_batch before);
    ("reativa: indirect cycle in a batch (after)", indirect_cycle_in_batch after);
    ("reativa: indirect cycle through a memo", indirect_cycle_through_memo);
    ("reativa: three-node cycle (before)", three_node_cycle before);
    ("reativa: three-node cycle (after)", three_node_cycle after);
    ("reativa: cycle from a re-run (before)", cycle_from_rerun before);
    ("reativa: cycle from a re-run (after)", cycle_from_rerun after);
    ("reativa: indirect cycle at the limit", indirect_cycle_limit);
    ("reativa: mutual disposal while pending", mutual_disposal);
    ("reativa: a raising memo in a first run", raising_memo_in_first_run);
    ("reativa: unobserved memo", unobserved_memo);
    ("reativa: a cleanup that reads a State", cleanup_reads_state);
    ("reativa: effects in a recomputed memo", effects_in_recomputed_memo);
    ("reativa: a memo is released with its owner", memo_released_with_owner);
    ("reativa: a detached owner in a re-run", detached_owner_in_rerun);
    ("reativa: on_change clamp", on_change_clamp);
    ("reativa: clamp in a raising batch", clamp_in_raising_batch);
    ("reativa: peek a memo with untrack after a write", memo_untrack_after_write);
    ("reativa: self-write, then raise, in a first run", self_write_then_raise_in_first_run);
    ("reativa: indirect write, then raise, in a first run", indirect_write_then_raise_in_first_run);
    ("reativa: peek a memo after a write in a first run", memo_peek_after_write);
    ("reativa: peek a memo after a write in a re-run", memo_peek_after_write_in_rerun);
    ("reativa: read a memo chain after a write", memo_chain_after_write);
  ]

let known_failing : (string * (unit -> unit)) list = []
