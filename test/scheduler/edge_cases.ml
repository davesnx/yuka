open Yuka

let check = Cases.check
let log = Cases.log
let ints = string_of_int
let bools = string_of_bool
let js = Obj.is_int (Obj.repr 0.5)

let raises f =
  match f () with
  | () -> "no"
  | exception Failure m -> m
  | exception Invalid_argument m -> m

let limit_message m =
  Cases.contains m "keeps changing a State it reads"

let read_many_times () =
  let runs = ref 0 in
  let s = State.make 0 and on = State.make true in
  Effect.before (fun () ->
      incr runs;
      if State.get on then for _ = 1 to 5 do ignore (State.get s) done);
  State.set s 1;
  State.set s 2;
  check "one run per change" "3" (ints !runs);
  State.set on false;
  check "no link left after the reads stop" "false" (bools (Private.has_readers s));
  State.set s 3;
  check "no run after the reads stop" "4" (ints !runs)

let duplicate_read_around_memo () =
  let runs = ref 0 in
  let s = State.make 1 and mode = State.make 0 in
  let m = State.memo (fun () -> State.get s * 2) in
  Effect.before (fun () ->
      incr runs;
      match State.get mode with
      | 0 ->
          ignore (State.get s);
          ignore (State.get m);
          ignore (State.get s)
      | 1 -> ignore (State.get m)
      | _ -> ());
  State.set s 2;
  State.set s 3;
  check "a State read before and after a memo that reads it" "3" (ints !runs);
  State.set mode 1;
  State.set s 4;
  check "then only through the memo" "5" (ints !runs);
  State.set mode 2;
  State.set s 5;
  check "then nothing" "6" (ints !runs);
  check "the memo still reads the State" "true" (bools (Private.has_readers s));
  check "nobody reads the memo" "false" (bools (Private.has_readers m))

let dependency_dropped_then_read_again () =
  let add, read = log () in
  let phase = State.make 0 in
  let a = State.make 0 and b = State.make 0 and c = State.make 0 in
  Effect.before (fun () ->
      let p = State.get phase in
      let v =
        match p mod 3 with
        | 0 -> State.get a + State.get b
        | 1 -> State.get c
        | _ -> State.get b + State.get a + State.get c
      in
      add (Printf.sprintf "p%d=%d" p v));
  State.set a 1;
  State.set phase 1;
  State.set a 2;
  State.set b 2;
  State.set c 3;
  State.set phase 2;
  State.set a 4;
  State.set phase 3;
  State.set c 9;
  State.set b 5;
  check "each run tracks exactly the States it read"
    "p0=0 p0=1 p1=0 p1=3 p2=7 p2=9 p3=6 p3=9" (read ())

let get_and_untrack_same_state () =
  let runs = ref 0 in
  let s = State.make 0 in
  Effect.before (fun () ->
      incr runs;
      ignore (State.untrack (fun () -> State.get s));
      ignore (State.get s);
      ignore (State.untrack (fun () -> State.get s)));
  State.set s 1;
  State.set s 2;
  check "a tracked read between two untracked reads" "3" (ints !runs)

let dependency_after_exception () =
  let runs = ref 0 in
  let x = State.make 0 and b = State.make 0 and c = State.make 0 in
  Effect.before (fun () ->
      incr runs;
      if State.get x = 1 then begin
        ignore (State.get b);
        failwith "stop"
      end
      else ignore (State.get c));
  let first = raises (fun () -> State.set x 1) in
  let second = raises (fun () -> State.set c 1) in
  let third = raises (fun () -> State.set b 1) in
  check "errors" "stop stop stop" (String.concat " " [ first; second; third ]);
  check "the State read before the raise and the one kept from before" "4" (ints !runs);
  State.set x 2;
  State.set b 2;
  check "the State read only in the failed run is dropped" "5" (ints !runs);
  check "no reader of b" "false" (bools (Private.has_readers b))

let many_dependencies () =
  let states = Array.init 10_000 (fun i -> State.make i) in
  let on = State.make true in
  let total = ref 0 and runs = ref 0 in
  let (), dispose =
    owner (fun () ->
        Effect.before (fun () ->
            incr runs;
            if State.get on then
              total := Array.fold_left (fun acc s -> acc + State.get s) 0 states))
  in
  State.set states.(9_999) 0;
  State.set states.(0) 10;
  check "sum" (ints ((9_999 * 10_000 / 2) - 9_999 + 10)) (ints !total);
  check "runs" "3" (ints !runs);
  State.set on false;
  check "links dropped" "false"
    (bools (Array.exists (fun s -> Private.has_readers s) states));
  State.set on true;
  dispose ();
  check "dispose drops the links" "false"
    (bools (Array.exists (fun s -> Private.has_readers s) states))

let many_readers () =
  let s = State.make 0 in
  let runs = ref 0 in
  let (), dispose =
    owner (fun () ->
        for _ = 1 to 10_000 do
          Effect.before (fun () ->
              ignore (State.get s);
              incr runs)
        done)
  in
  State.set s 1;
  check "each reader runs once" "20000" (ints !runs);
  dispose ();
  State.set s 2;
  check "none after dispose" "20000" (ints !runs);
  check "no reader left" "false" (bools (Private.has_readers s))

let many_memo_readers () =
  let s = State.make 1 in
  let total = ref 0 and runs = ref 0 in
  let (), dispose =
    owner (fun () ->
        let memos = List.init 10_000 (fun i -> State.memo (fun () -> State.get s + i)) in
        Effect.before (fun () ->
            incr runs;
            total := List.fold_left (fun acc m -> acc + State.get m) 0 memos))
  in
  State.set s 2;
  check "one run of the reader" "2" (ints !runs);
  check "fresh values" (ints ((2 * 10_000) + (9_999 * 10_000 / 2))) (ints !total);
  dispose ()

let chain n s =
  let rec go i m = if i = 0 then m else go (i - 1) (State.memo (fun () -> State.get m + 1)) in
  go n (State.memo (fun () -> State.get s))

let short_chain () =
  let s = State.make 0 in
  let seen = ref 0 in
  let last, dispose =
    owner (fun () ->
        let last = chain 2_000 s in
        Effect.before (fun () -> seen := State.get last);
        last)
  in
  State.set s 1;
  check "a chain of 2,000 memos" "2001 2001" (Printf.sprintf "%d %d" !seen (State.peek last));
  dispose ()

let level_grows () =
  let add, read = log () in
  let s = State.make 0 and deep = State.make false in
  let m1 = State.memo (fun () -> State.get s) in
  let m2 = State.memo (fun () -> State.get m1) in
  let m3 = State.memo (fun () -> State.get m2) in
  let grows = State.memo (fun () -> if State.get deep then State.get m3 else State.get s) in
  Effect.before (fun () -> add ("g" ^ ints (State.get grows)));
  Effect.before (fun () -> add ("m" ^ ints (State.get m2)));
  State.set s 1;
  State.set deep true;
  State.set s 2;
  check "order after the memo got deeper" "g0 m0 g1 m1 g2 m2" (read ())

let parent_first_over_level () =
  let add, read = log () in
  let o = State.make (Some 1) in
  let m1 = State.memo (fun () -> State.get o) in
  let m2 = State.memo (fun () -> State.get m1) in
  Effect.before (fun () ->
      match State.get m2 with
      | Some _ -> Effect.before (fun () -> add (ints (Option.get (State.get o))))
      | None -> add "none");
  State.set o None;
  check "a deep parent runs before its shallow child" "1 none" (read ())

let grandparent_first_after_rerun () =
  let add, read = log () in
  let o = State.make (Some 1) and x = State.make 0 in
  Effect.before (fun () ->
      Effect.before (fun () ->
          ignore (State.get x);
          match State.get o with
          | Some _ ->
              Effect.before (fun () ->
                  add (match State.get o with Some v -> "c" ^ ints v | None -> "zombie"))
          | None -> add "none"));
  State.set x 1;
  State.set o None;
  check "a child made in a re-run does not run before its parent" "c1 c1 none" (read ())

let lattice () =
  let add, read = log () in
  let s = State.make 1 in
  let computes = ref 0 in
  let row prev =
    Array.init 4 (fun i ->
        State.memo (fun () ->
            incr computes;
            State.get prev.(i) + State.get prev.((i + 1) mod 4)))
  in
  let first = Array.init 4 (fun i -> State.memo (fun () -> State.get s * (i + 1))) in
  let r2 = row first in
  let r3 = row r2 in
  let r4 = row r3 in
  Effect.before (fun () ->
      let v = Array.map State.get r4 in
      let w = Array.map State.get r2 in
      add (Printf.sprintf "%d,%d/%d" v.(0) v.(3) (w.(0) + w.(1) + w.(2) + w.(3))));
  computes := 0;
  State.set s 2;
  State.set s 3;
  check "one consistent run per write" "20,16/20 40,32/40 60,48/60" (read ());
  check "each memo computes once per write" "24" (ints !computes)

let cut_off_stops_readers () =
  let s = State.make 1 in
  let computes = ref 0 and runs = ref 0 in
  let parity = State.memo (fun () -> State.get s mod 2) in
  let scaled =
    State.memo (fun () ->
        incr computes;
        State.get parity * 10)
  in
  let label = State.memo (fun () -> ints (State.get scaled)) in
  Effect.before (fun () ->
      ignore (State.get label);
      incr runs);
  State.set s 3;
  State.set s 5;
  check "no recompute below an equal memo" "1 1" (Printf.sprintf "%d %d" !computes !runs);
  State.set s 6;
  State.set s 8;
  check "once when it changes" "2 2" (Printf.sprintf "%d %d" !computes !runs)

let peek_dirty_memo_in_effect () =
  let add, read = log () in
  let s = State.make 1 and t = State.make 0 in
  let m = State.memo (fun () -> State.get s * 10) in
  Effect.before (fun () -> add (Printf.sprintf "%d:%d" (State.get t) (State.peek m)));
  batch (fun () ->
      State.set s 2;
      State.set t 1);
  State.set s 3;
  State.set t 2;
  check "peek in an effect sees the new memo value" "0:10 1:20 2:30" (read ())

let memo_write_with_reader_effect () =
  let s = State.make 0 in
  let m2 = State.memo (fun () -> State.get s * 10) in
  let seen = ref [] in
  Effect.before (fun () -> seen := State.get m2 :: !seen);
  let m =
    State.memo (fun () ->
        let a = State.get m2 in
        if State.peek s = 0 then State.set s 1;
        a)
  in
  check "the effect saw the write" "10,0" (String.concat "," (List.map ints !seen));
  check "a memo whose compute wrote its own source is fresh on the next read" "10"
    (ints (State.peek m))

let memo_write_without_reader_effect () =
  let s = State.make 0 in
  let m2 = State.memo (fun () -> State.get s * 10) in
  let m =
    State.memo (fun () ->
        let a = State.get m2 in
        if State.peek s = 0 then State.set s 1;
        a)
  in
  check "without another reader the next read recomputes" "10" (ints (State.peek m))

let memo_writes_other_state () =
  let add, read = log () in
  let s = State.make 0 and echo = State.make 0 in
  let m =
    State.memo (fun () ->
        let v = State.get s in
        State.set echo (v * 100);
        v)
  in
  Effect.before (fun () -> add ("echo" ^ ints (State.get echo)));
  Effect.before (fun () -> add ("m" ^ ints (State.get m)));
  State.set s 1;
  check "a write in a memo compute reaches the readers of that State"
    "echo0 m0 m1 echo100" (read ())

let second_round () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  Effect.before (fun () -> State.set t (State.get s * 10));
  Effect.before (fun () -> add (Printf.sprintf "%d/%d" (State.get s) (State.get t)));
  State.set s 1;
  check "an effect that already ran runs again for a later write" "0/0 1/0 1/10" (read ())

let write_in_cleanup_on_rerun () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  Effect.before ~cleanup:(fun v -> State.set t v) (fun () -> State.get s);
  Effect.before (fun () -> add ("t" ^ ints (State.get t)));
  State.set s 1;
  State.set s 2;
  check "a write in a cleanup during a re-run" "t0 t1" (read ())

let write_in_cleanup_on_dispose () =
  let add, read = log () in
  let s = State.make 0 in
  let (), dispose =
    owner (fun () ->
        Effect.before (fun () -> add ("a" ^ ints (State.get s)));
        Effect.before ~cleanup:(fun () -> State.set s 1) (fun () -> ()))
  in
  dispose ();
  State.set s 2;
  check "an effect of the disposed owner runs once more for a write in a sibling cleanup"
    "a0 a1" (read ())

let batch_in_memo () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  Effect.before (fun () -> add ("t" ^ ints (State.get t)));
  let m =
    State.memo (fun () ->
        let v = State.get s in
        batch (fun () ->
            State.set t v;
            State.set t (v + 1));
        add ("m" ^ ints v);
        v)
  in
  State.set s 5;
  check "value" "5" (ints (State.peek m));
  check "a batch in a top-level recompute flushes after the compute" "t0 t1 m0 m5 t6" (read ())

let write_in_first_run () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.before (fun () -> add ("e" ^ ints (State.get s)));
  Effect.before (fun () -> State.set s 1);
  add "made";
  batch (fun () ->
      Effect.before (fun () -> State.set s 2);
      add "in-batch");
  check "outside a batch the readers run before the creation returns, inside after the batch"
    "e0 e1 made in-batch e2" (read ())

let disposes_own_owner_then_creates () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  let d = ref ignore in
  let (), dispose =
    owner (fun () ->
        Effect.before
          ~cleanup:(fun v -> add ("clean" ^ ints v))
          (fun () ->
            let v = State.get s in
            if v = 1 then begin
              !d ();
              Effect.before (fun () -> add ("inner" ^ ints (State.get t)))
            end;
            v))
  in
  d := dispose;
  State.set s 1;
  State.set t 1;
  dispose ();
  State.set t 2;
  check "an effect made after its parent disposed itself lives on" "clean0 inner0 inner1 inner2"
    (read ())

let disposed_memo_with_queued_reader () =
  let s = State.make 1 in
  let m, dispose_m = owner (fun () -> State.memo (fun () -> State.get s * 2)) in
  let seen = ref [] in
  Effect.before (fun () -> seen := State.get m :: !seen);
  Effect.before (fun () -> if State.get s = 2 then dispose_m ());
  State.set s 2;
  State.set s 3;
  check "a reader of a memo disposed in the same flush keeps the old value" "2"
    (String.concat "," (List.map ints !seen));
  check "the memo keeps its last value" "2" (ints (State.peek m))

let read_disposed_memo () =
  let s = State.make 1 in
  let computes = ref 0 in
  let m, dispose =
    owner (fun () ->
        State.memo (fun () ->
            incr computes;
            State.get s * 2))
  in
  dispose ();
  State.set s 2;
  let runs = ref 0 in
  Effect.before (fun () ->
      ignore (State.get m);
      incr runs);
  State.set s 3;
  check "a disposed memo returns its last value, does not compute, and does not notify"
    "2 2 1 1 false"
    (Printf.sprintf "%d %d %d %d %b" (State.peek m) (State.untrack (fun () -> State.get m))
       !computes !runs (Private.has_readers s))

let write_without_live_readers () =
  let runs = ref 0 in
  let s = State.make 0 in
  let (), dispose =
    owner (fun () ->
        Effect.before (fun () -> ignore (State.get s); incr runs);
        ignore (State.memo (fun () -> State.get s));
        Effect.after (fun () -> ignore (State.get s); incr runs))
  in
  dispose ();
  check "no reader left" "false" (bools (Private.has_readers s));
  State.set s 1;
  check "no run" "2" (ints !runs)

let reentrant_dispose () =
  let add, read = log () in
  let d = ref ignore in
  let (), dispose =
    owner (fun () ->
        Effect.before ~cleanup:(fun () -> add "a") (fun () -> ());
        Effect.before
          ~cleanup:(fun () ->
            add "b";
            !d ())
          (fun () -> ());
        Effect.before ~cleanup:(fun () -> add "c") (fun () -> ()))
  in
  d := dispose;
  dispose ();
  dispose ();
  check "a cleanup that disposes its own owner" "c b a" (read ())

let raising_cleanup_disposes_the_rest () =
  let runs = ref 0 and cleaned = ref 0 in
  let s = State.make 0 in
  let (), dispose =
    owner (fun () ->
        Effect.before
          ~cleanup:(fun () -> incr cleaned)
          (fun () ->
            ignore (State.get s);
            incr runs);
        Effect.before ~cleanup:(fun () -> failwith "cleanup") (fun () -> ()))
  in
  let raised = raises dispose in
  State.set s 1;
  check "raised to the caller" "cleanup" raised;
  check "the other effect is stopped and cleaned" "1 1" (Printf.sprintf "%d %d" !runs !cleaned)

let effect_in_cleanup () =
  let add, read = log () in
  let s = State.make 0 in
  let (), dispose =
    owner (fun () ->
        Effect.before
          ~cleanup:(fun () -> Effect.before (fun () -> add ("late" ^ ints (State.get s))))
          (fun () -> ()))
  in
  dispose ();
  State.set s 1;
  check "an effect made in a cleanup at dispose has no owner and lives on" "late0 late1" (read ())

let detached_owner_in_effect () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  let stops = ref [] in
  Effect.before (fun () ->
      let v = State.get s in
      let (), stop = owner (fun () -> Effect.before (fun () -> add (Printf.sprintf "%d:%d" v (State.get t)))) in
      stops := stop :: !stops);
  State.set s 1;
  State.set t 1;
  List.iter (fun stop -> stop ()) !stops;
  State.set t 2;
  check "an owner made in an effect outlives its re-run until its own dispose"
    "0:0 1:0 1:1 0:1" (read ())

let memo_raises_two_readers () =
  let n = State.make 0 in
  let computes = ref 0 in
  let m =
    State.memo (fun () ->
        incr computes;
        if State.get n = 1 then failwith "bad" else State.get n)
  in
  let a = ref [] and b = ref [] in
  Effect.before (fun () -> a := State.get m :: !a);
  Effect.before (fun () -> b := State.get m :: !b);
  computes := 0;
  let raised = raises (fun () -> State.set n 1) in
  let peeked = try ints (State.peek m) with Failure e -> e in
  let after_error = !computes in
  State.set n 2;
  check "the error, then the peek" "bad bad" (raised ^ " " ^ peeked);
  check "both readers recover" "2,0 2,0"
    (String.concat "," (List.map ints !a) ^ " " ^ String.concat "," (List.map ints !b));
  check "a failed memo computes again for each check, each read and each peek" "5 6"
    (Printf.sprintf "%d %d" after_error !computes)

let two_errors_one_round () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.before (fun () -> if State.get s = 1 then failwith "older");
  Effect.before (fun () -> add (ints (State.get s)));
  Effect.before (fun () -> if State.get s = 1 then failwith "newer");
  let raised = raises (fun () -> State.set s 1) in
  check "the first error in run order" "newer" raised;
  check "the other effect ran" "0 1" (read ())

let batch_and_effect_raise () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.before (fun () -> if State.get s = 1 then failwith "effect");
  Effect.before (fun () -> add (ints (State.get s)));
  let raised =
    raises (fun () ->
        batch (fun () ->
            State.set s 1;
            failwith "body"))
  in
  check "the exception of the body wins" "body" raised;
  check "the pending effects ran" "0 1" (read ());
  State.set s 2;
  check "no batch left open" "0 1 2" (read ())

let failed_chain_recovers () =
  let n = State.make 0 in
  let a = State.memo (fun () -> State.get n + 1) in
  let b = State.memo (fun () -> if State.get a = 2 then failwith "b" else State.get a * 10) in
  let c = State.memo (fun () -> State.get b + 1) in
  let seen = ref [] in
  Effect.before (fun () -> seen := State.get c :: !seen);
  let e1 = raises (fun () -> State.set n 1) in
  let e2 = try ints (State.peek c) with Failure e -> e in
  let e3 = try ints (State.peek c) with Failure e -> e in
  State.set n 2;
  check "errors" "b b b" (String.concat " " [ e1; e2; e3 ]);
  check "the chain recovers" "31,11" (String.concat "," (List.map ints !seen));
  check "peek" "31" (ints (State.peek c))

let memo_self_write_reaches_the_limit () =
  let t = State.make 0 and go = State.make true in
  let m =
    State.memo (fun () ->
        let v = State.get t in
        if State.peek go then State.set t (v + 1);
        v)
  in
  let seen = ref (-1) in
  let first = raises (fun () -> Effect.before (fun () -> seen := State.get m)) in
  State.set go false;
  State.set t 1000;
  Effect.before (fun () -> seen := State.get m);
  State.set t 2000;
  check "a memo that keeps writing the State it reads raises the limit to its reader" "true"
    (bools (limit_message first));
  check "after it stops writing, a reader follows later writes" "2000" (ints !seen)

let memo_self_write_settles () =
  let add, read = log () in
  let t = State.make 15 in
  let m =
    State.memo (fun () ->
        let v = State.get t in
        if v > 10 then State.set t 10;
        v)
  in
  Effect.before (fun () -> add (ints (State.get m)));
  State.set t 12;
  check "a memo that clamps the State it reads gives its reader only settled values" "10 10" (read ());
  check "the State is clamped" "10" (ints (State.peek t))

let after_dropped_at_limit () =
  let s = State.make 0 and t = State.make 0 in
  let runs = ref 0 and bystander = ref (-1) in
  Effect.before (fun () ->
      let v = State.get s in
      if v > 0 && v < 1000 then State.set s (v + 1));
  Effect.before (fun () -> bystander := State.get s);
  let result =
    raises (fun () ->
        batch (fun () ->
            Effect.after (fun () ->
                ignore (State.get t);
                incr runs);
            State.set s 1))
  in
  check "limit" "true" (bools (limit_message result));
  State.set s 0;
  State.set t 1;
  check "a queued bystander runs again" "0" (ints !bystander);
  check "an after effect whose first run was dropped at the limit never runs" "0" (ints !runs)

let equal_raises () =
  let runs = ref 0 and seen = ref 0 in
  let bad _ _ = failwith "equal" in
  let s = State.make ~equal:bad 0 in
  let m = State.memo ~equal:bad (fun () -> State.get s / 10) in
  Effect.before (fun () -> ignore (State.get m); incr runs);
  Effect.on_change ~equal:bad s (fun ~prev:_ ~next:_ -> incr seen);
  seen := 0;
  State.set s 0;
  State.set s 1;
  check "a raising equal is a change for a State, a memo and on_change" "3 2"
    (Printf.sprintf "%d %d" !runs !seen)

let on_change_not_at_creation () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.on_change ~equal:(fun _ _ -> false) s (fun ~prev ~next ->
      add (Printf.sprintf "%d->%d" prev next));
  State.set s 1;
  check "on_change is not called for the value at creation" "0->1" (read ())

let double_run () =
  let add, read = log () in
  let s = State.make 0 in
  let a = State.memo (fun () -> State.get s * 10) in
  let y =
    State.memo (fun () ->
        let v = State.get s in
        v + State.get a)
  in
  Effect.before (fun () ->
      let v = State.get s in
      let w = State.get y in
      add (Printf.sprintf "%d/%d/%d" v w (State.get a)));
  State.set s 1;
  check "one run per write" "0/0/0 1/11/10" (read ())

let literal_tuple () =
  let runs = ref 0 in
  let p = State.make (1, "a") in
  Effect.before (fun () -> ignore (State.get p); incr runs);
  State.set p (1, "a");
  check "a tuple literal written again: native shares the constant" (if js then "2" else "1")
    (ints !runs)

let cleanup_raises_on_rerun () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  Effect.before (fun () ->
      let v = State.get s in
      add ("o" ^ ints v);
      Effect.before (fun () -> add (Printf.sprintf "i%d/%d" v (State.get t)));
      Effect.before ~cleanup:(fun () -> if v = 1 then failwith "clean") (fun () -> ()));
  State.set s 1;
  let raised = raises (fun () -> State.set s 2) in
  State.set t 1;
  State.set s 3;
  check "raised" "clean" raised;
  check "a raising inner cleanup stops the re-run and its sibling" "o0 i0/0 o1 i1/0 o3 i3/1"
    (read ())

let many_after_writers () =
  let s = State.make 0 and t = State.make 0 in
  let seen = ref 0 in
  Effect.before (fun () -> seen := State.get s);
  for i = 1 to 60 do
    Effect.after (fun () -> if State.get t > 0 then State.set s i)
  done;
  check "60 after effects that write one State raise no loop error" "no"
    (raises (fun () -> State.set t 1));
  check "the before effect has the last value" (ints (State.peek s)) (ints !seen)

let dropped_failed_effect_reacts () =
  let lp = State.make 0 and b = State.make 0 in
  let runs = ref 0 in
  Effect.before (fun () ->
      incr runs;
      if State.get lp > 0 then failwith "x";
      ignore (State.get b));
  ignore (raises (fun () -> Effect.before (fun () -> State.set lp (State.get lp + 1))));
  let before = !runs in
  ignore (raises (fun () -> State.set b 1));
  check "an effect dropped at the limit runs again when a State it read changes" "1"
    (ints (!runs - before))

let after_makes_before_pending () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 and u = State.make 0 in
  Effect.after (fun () -> add ("x" ^ ints (State.get u)));
  Effect.before (fun () ->
      let v = State.get t in
      add ("b" ^ ints v);
      State.set u v);
  Effect.after (fun () ->
      let v = State.get s in
      add ("a" ^ ints v);
      State.set t v);
  State.set s 1;
  check "an after effect write runs before effects first, then the after effects"
    "x0 b0 a0 a1 b1 x1" (read ())

let on_change_custom_equal () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.on_change ~equal:(fun a b -> abs (a - b) < 2) s (fun ~prev ~next ->
      add (Printf.sprintf "%d->%d" prev next));
  State.set s 1;
  State.set s 2;
  State.set s 3;
  State.set s 4;
  check "prev is the last reported value" "0->2 2->4" (read ())

let on_change_write_in_callback () =
  let add, read = log () in
  let s = State.make 0 in
  Effect.on_change s (fun ~prev ~next ->
      add (Printf.sprintf "%d->%d" prev next);
      if next > 10 then State.set s 10);
  State.set s 15;
  State.set s 3;
  check "a write in the callback calls it again" "0->15 15->10 10->3" (read ())

let on_change_in_batch () =
  let add, read = log () in
  let s = State.make 0 in
  let report ~prev ~next = add (Printf.sprintf "%d->%d" prev next) in
  Effect.on_change s report;
  batch (fun () ->
      State.set s 1;
      State.set s 2);
  batch (fun () ->
      State.set s 3;
      State.set s 2);
  batch (fun () ->
      Effect.on_change s (fun ~prev ~next -> add (Printf.sprintf "new%d->%d" prev next));
      State.set s 7);
  check "one call per batch with the value before it; none when it comes back"
    "0->2 new2->7 2->7" (read ())

let float_zero_and_nan () =
  let runs = ref 0 in
  let f = State.make 0. in
  Effect.before (fun () -> ignore (State.get f); incr runs);
  State.set f (-0.);
  check "minus zero is the same as zero" "1" (ints !runs);
  State.set f (Float.of_string "1e-400");
  check "an underflow to zero is the same" "1" (ints !runs);
  State.set f (0.1 +. 0.2);
  State.set f 0.30000000000000004;
  check "the same float built two ways" "2" (ints !runs)

let boxed_numbers () =
  let runs v set =
    let count = ref 0 in
    let s = State.make v in
    Effect.before (fun () -> ignore (State.get s); incr count);
    set s;
    !count
  in
  let one = Int64.of_string "1" in
  check "a new Int64 with the same value is a change" "2"
    (ints (runs one (fun s -> State.set s (Int64.add one 0L))));
  check "the same Int64 is not" "1" (ints (runs one (fun s -> State.set s one)));
  let five = Int32.of_string "5" in
  check "Int32: a change on native, not in the browser (DESIGN: Int32 is a JS number)"
    (if js then "1" else "2")
    (ints (runs five (fun s -> State.set s (Int32.add five 0l))));
  check "Some x around the same x: a change on native, not in the browser (mli)"
    (if js then "1" else "2")
    (ints (runs (Some "a") (fun s -> State.set s (Some (State.peek s |> Option.get)))));
  let b = Bytes.of_string "ab" in
  check "bytes: by value on native, by identity in the browser (DESIGN)"
    (if js then "2" else "1")
    (ints (runs b (fun s -> State.set s (Bytes.of_string "ab"))))

let float_record () =
  let runs = ref 0 in
  let p = State.make (Float.of_string "1", 2.0) in
  Effect.before (fun () -> ignore (State.get p); incr runs);
  State.set p (Float.of_string "1", 2.0);
  let same = State.peek p in
  State.set p same;
  check "a new tuple of floats is a change, the same one is not" "2" (ints !runs);
  let l = State.make (lazy 1) in
  let lruns = ref 0 in
  Effect.before (fun () -> ignore (State.get l); incr lruns);
  ignore (Lazy.force (State.peek l));
  State.set l (State.peek l);
  check "the same lazy value after force is not a change" "1" (ints !lruns)

let deferred_on_native () =
  if not js then begin
    let s = State.make 1 in
    let (d, dm), dispose =
      owner (fun () ->
          let m = State.memo (fun () -> State.get s * 2) in
          (State.deferred s, State.deferred m))
    in
    let add, read = log () in
    Effect.before (fun () -> add (Printf.sprintf "%d/%d" (State.get d) (State.get dm)));
    State.set s 2;
    dispose ();
    State.set s 3;
    check "on native a deferred State follows its source at once, until disposed"
      "1/2 2/4" (read ())
  end

let write_from_memo_the_effect_reads () =
  let add, read = log () in
  let s = State.make 0 and trigger = State.make 0 in
  let m =
    State.memo (fun () ->
        let v = State.get trigger in
        if v > 0 then State.set s (v * 100);
        v)
  in
  Effect.before (fun () ->
      let a = State.get s in
      let b = State.get m in
      add (Printf.sprintf "%d:%d" a b));
  State.set trigger 1;
  check "the effect runs once, with the value the memo wrote" "0:0 100:1" (read ())

let effect_in_memo () =
  let add, read = log () in
  let s = State.make 0 and t = State.make 0 in
  let m =
    State.memo (fun () ->
        let v = State.get s in
        Effect.before (fun () -> add (Printf.sprintf "e%d/%d" v (State.get t)));
        v)
  in
  State.set s 1;
  ignore (State.peek m);
  State.set s 2;
  ignore (State.peek m);
  State.set t 1;
  check "each recompute adds an effect that nobody disposes" "e0/0 e1/0 e2/0 e0/1 e2/1 e1/1"
    (read ())

let memo_reads_itself () =
  let s = State.make 1 in
  let self = ref None in
  let computes = ref 0 in
  let m =
    State.memo (fun () ->
        incr computes;
        let prev = match !self with Some m -> State.get m | None -> 0 in
        prev + State.get s)
  in
  self := Some m;
  State.set s 2;
  let a = State.peek m in
  let b = State.peek m in
  check "a memo that reads itself sees its previous value" "3 3 2"
    (Printf.sprintf "%d %d %d" a b !computes)

let all =
  [
    ("edge: the same State read five times", read_many_times);
    ("edge: a State read before and after a memo that reads it", duplicate_read_around_memo);
    ("edge: dependency dropped then read again", dependency_dropped_then_read_again);
    ("edge: get between two untracked reads", get_and_untrack_same_state);
    ("edge: dependency read only in a failed run", dependency_after_exception);
    ("edge: 10,000 dependencies", many_dependencies);
    ("edge: 10,000 readers", many_readers);
    ("edge: 10,000 memo readers", many_memo_readers);
    ("edge: order after a memo gets deeper", level_grows);
    ("edge: deep parent before shallow child", parent_first_over_level);
    ("edge: cut-off stops readers", cut_off_stops_readers);
    ("edge: peek of a dirty memo in an effect", peek_dirty_memo_in_effect);
    ("edge: memo writes its source without a reader effect", memo_write_without_reader_effect);
    ("edge: memo writes another State", memo_writes_other_state);
    ("edge: second round for an effect that ran", second_round);
    ("edge: write in a cleanup during a re-run", write_in_cleanup_on_rerun);
    ("edge: write in a cleanup during dispose", write_in_cleanup_on_dispose);
    ("edge: batch in a memo", batch_in_memo);
    ("edge: write in a first run", write_in_first_run);
    ("edge: effect disposes its own owner then creates one", disposes_own_owner_then_creates);
    ("edge: memo disposed while its reader is queued", disposed_memo_with_queued_reader);
    ("edge: read of a disposed memo", read_disposed_memo);
    ("edge: write without live readers", write_without_live_readers);
    ("edge: re-entrant dispose", reentrant_dispose);
    ("edge: effect made in a cleanup", effect_in_cleanup);
    ("edge: detached owner made in an effect", detached_owner_in_effect);
    ("edge: memo raises with two readers", memo_raises_two_readers);
    ("edge: two errors in one round", two_errors_one_round);
    ("edge: batch and effect both raise", batch_and_effect_raise);
    ("edge: failed chain recovers", failed_chain_recovers);
    ("edge: after effect dropped at the limit", after_dropped_at_limit);
    ("edge: equal raises", equal_raises);
    ("edge: cleanup raises on a re-run", cleanup_raises_on_rerun);
    ("edge: after effect makes a before effect pending", after_makes_before_pending);
    ("edge: on_change with a custom equal", on_change_custom_equal);
    ("edge: on_change writes in its callback", on_change_write_in_callback);
    ("edge: on_change in a batch", on_change_in_batch);
    ("edge: float zero", float_zero_and_nan);
    ("edge: boxed numbers", boxed_numbers);
    ("edge: float tuple and lazy", float_record);
    ("edge: literal tuple", literal_tuple);
    ("edge: deferred on native", deferred_on_native);
    ("edge: write from a memo the effect reads", write_from_memo_the_effect_reads);
    ("edge: effect made in a memo", effect_in_memo);
    ("edge: memo reads itself", memo_reads_itself);
    ("edge: chain of 2,000 memos", short_chain);
    ("edge: one run per write when a memo recomputes inside another", double_run);
    ("edge: lattice of memos", lattice);
    ("edge: grandparent before a child made in a re-run", grandparent_first_after_rerun);
    ("edge: memo writes its source with a reader effect", memo_write_with_reader_effect);
    ("edge: memo that keeps writing its source", memo_self_write_reaches_the_limit);
    ("edge: memo that clamps its source", memo_self_write_settles);
    ("edge: many after effects write one State", many_after_writers);
    ("edge: failed effect dropped at the limit", dropped_failed_effect_reacts);
    ("edge: raising cleanup at dispose", raising_cleanup_disposes_the_rest);
    ("edge: on_change with an equal that is never true", on_change_not_at_creation);
  ]
