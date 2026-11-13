open Yuka

let check = Cases.check
let ints = string_of_int
let next_task : (unit -> unit) -> unit = [%mel.raw "function (f) { setTimeout(f, 0) }"]

let reads d =
  let seen = ref [] in
  Effect.after (fun () -> seen := ints (State.get d) :: !seen);
  fun () -> String.concat " " (List.rev !seen)

let after_paint finish =
  Dom_cases.stub_frames ();
  let source = State.make 0 in
  let (d, seen), dispose =
    owner (fun () ->
        let d = State.deferred source in
        (d, reads d))
  in
  State.set source 1;
  State.set source 2;
  State.set source 3;
  check "not changed before the frame" "0" (ints (State.peek d));
  check "one frame requested" "1" (ints (Dom_cases.pending_frames ()));
  Dom_cases.run_frame 16.;
  check "not changed in the frame, before the paint" "0" (ints (State.peek d));
  next_task (fun () ->
      let latest = ints (State.peek d) and runs = seen () and left = ints (Dom_cases.pending_frames ()) in
      State.set source 4;
      Dom_cases.run_frame 32.;
      next_task (fun () ->
          finish (fun () ->
              check "the latest value after the paint" "3" latest;
              check "values in between are skipped" "0 3" runs;
              check "no frame left" "0" left;
              check "a later change follows too" "0 3 4" (seen ());
              dispose ())))

let one_batch finish =
  Dom_cases.stub_frames ();
  let a = State.make 0 and b = State.make 0 in
  let runs = ref 0 in
  let (da, db), dispose =
    owner (fun () ->
        let da = State.deferred a and db = State.deferred b in
        Effect.after (fun () ->
            ignore (State.get da + State.get db);
            incr runs);
        (da, db))
  in
  State.set a 1;
  State.set b 2;
  check "one frame for two deferred States" "1" (ints (Dom_cases.pending_frames ()));
  Dom_cases.run_frame 16.;
  next_task (fun () ->
      finish (fun () ->
          check "both changed" "1 2" (ints (State.peek da) ^ " " ^ ints (State.peek db));
          check "one effect run for both" "2" (ints !runs);
          dispose ()))

let disposed finish =
  Dom_cases.stub_frames ();
  let source = State.make 0 in
  let d, dispose = owner (fun () -> State.deferred source) in
  State.set source 1;
  dispose ();
  Dom_cases.run_frame 16.;
  next_task (fun () ->
      finish (fun () ->
          check "a disposed deferred State does not change" "0" (ints (State.peek d));
          State.set source 2;
          check "a write after dispose requests no frame" "0" (ints (Dom_cases.pending_frames ()))))

let memo_source finish =
  Dom_cases.stub_frames ();
  let n = State.make 1 in
  let (d, seen), dispose =
    owner (fun () ->
        let parity = State.memo (fun () -> State.get n mod 2) in
        let d = State.deferred parity in
        (d, reads d))
  in
  State.set n 3;
  check "an unchanged memo requests no frame" "0" (ints (Dom_cases.pending_frames ()));
  State.set n 4;
  Dom_cases.run_frame 16.;
  next_task (fun () ->
      finish (fun () ->
          check "follows a memo" "0" (ints (State.peek d));
          check "runs" "1 0" (seen ());
          dispose ()))

let chained finish =
  Dom_cases.stub_frames ();
  let a = State.make 0 and b = State.make 0 in
  let (first, second, seen), dispose =
    owner (fun () ->
        let first = State.deferred a in
        let sum = State.memo (fun () -> State.get first + State.get b) in
        let second = State.deferred sum in
        let seen = ref [] in
        Effect.after (fun () -> seen := (ints (State.get first) ^ "," ^ ints (State.get second)) :: !seen);
        (first, second, fun () -> String.concat " " (List.rev !seen)))
  in
  State.set a 1;
  State.set b 1;
  Dom_cases.run_frame 16.;
  next_task (fun () ->
      finish (fun () ->
          check "both have the latest value" "1 2" (ints (State.peek first) ^ " " ^ ints (State.peek second));
          check "one run for both" "0,0 1,2" (seen ());
          check "no frame left" "0" (ints (Dom_cases.pending_frames ()));
          dispose ()))

let in_frame_handler finish =
  Dom_cases.stub_frames ();
  let source = State.make 0 in
  let d, dispose =
    owner (fun () ->
        Effect.after (fun () -> Browser.on_frame (fun _ -> State.set source (State.peek source + 1)));
        State.deferred source)
  in
  Dom_cases.run_frame 16.;
  check "not changed in the frame" "0" (ints (State.peek d));
  next_task (fun () ->
      finish (fun () ->
          check "changed after the paint of the same frame" "1" (ints (State.peek d));
          dispose ()))

let async =
  [
    ("deferred: changes after the paint, to the latest value", after_paint);
    ("deferred: several change in one batch", one_batch);
    ("deferred: dispose drops the waiting change", disposed);
    ("deferred: a memo as the source", memo_source);
    ("deferred: a memo of a deferred State as the source", chained);
    ("deferred: a change in a frame handler", in_frame_handler);
  ]
