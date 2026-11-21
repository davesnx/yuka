open Yuka

let check = Cases.check

type call = { label : string; resolve : (int, Status.error) result -> unit; fail : string -> unit }

let calls : call list ref = ref []

let call label =
  let a, resolve, fail = Async.make () in
  calls := { label; resolve; fail } :: !calls;
  a

let find label =
  match List.find_opt (fun c -> String.equal c.label label) !calls with
  | Some c -> c
  | None -> raise (Cases.Failed ("no call " ^ label))

let resolve label v = (find label).resolve (Ok v)
let reject label e = (find label).resolve (Error e)
let fail label m = (find label).fail m

let show = function
  | Status.Ready { data; _ } -> string_of_int data
  | Status.Loading None -> "…"
  | Status.Loading (Some d) -> string_of_int d ^ "~"
  | Status.Failed { error; last } ->
      "E(" ^ Status.error_to_string error ^ ")" ^ (match last with Some d -> string_of_int d | None -> "")
  | Status.Idle -> "idle"

let screen render =
  let seen = ref [] in
  Effect.after (fun () ->
      let s = render () in
      match !seen with
      | last :: _ when String.equal last s -> ()
      | _ -> seen := s :: !seen);
  fun () -> String.concat " | " (List.rev !seen)

let fresh () = calls := []

let busy_text b = if State.get b then " [busy]" else ""

let latest_wins_without_boundary () =
  fresh ();
  let filter = State.make "a" in
  let history, dispose =
    with_owner (fun () ->
        let rows = Async.memo (fun () -> call (State.get filter)) in
        screen (fun () -> show (State.get rows)))
  in
  resolve "a" 1;
  State.set filter "b";
  State.set filter "c";
  resolve "c" 3;
  resolve "b" 2;
  check "T1a: the stale answer for b does not show" "… | 1 | 1~ | 3" (history ());
  dispose ()

let latest_wins_in_a_boundary () =
  fresh ();
  let filter = State.make "a" in
  let (history, busy), dispose =
    with_owner (fun () ->
        let rows, busy = Private.boundary (fun () -> Async.memo (fun () -> call (State.get filter))) in
        (screen (fun () -> show (State.get rows) ^ busy_text busy), busy))
  in
  resolve "a" 1;
  State.set filter "b";
  State.set filter "c";
  resolve "b" 2;
  let while_c = State.peek busy in
  resolve "c" 3;
  check "T1b: the old value stays while busy, the stale answer is dropped" "… [busy] | 1 | 1 [busy] | 3"
    (history ());
  check "T1b: still busy after the stale answer" "true" (string_of_bool while_c);
  check "T1b: not busy at the end" "false" (string_of_bool (State.peek busy));
  dispose ()

let pending_source_disposed () =
  fresh ();
  let filter = State.make "x" in
  let keep = State.make true in
  let (history, busy), dispose =
    with_owner (fun () ->
        let (one, two), busy =
          Private.boundary (fun () ->
              let one = Async.memo (fun () -> call ("1" ^ State.get filter)) in
              let two = State.make None in
              Effect.before (fun () ->
                  if State.get keep then State.set two (Some (Async.memo (fun () -> call ("2" ^ State.get filter))))
                  else State.set two None);
              (one, two))
        in
        let view () =
          show (State.get one) ^ ","
          ^ (match State.get two with Some t -> show (State.get t) | None -> "gone")
          ^ busy_text busy
        in
        (screen view, busy))
  in
  resolve "1x" 1;
  let held = history () in
  State.set keep false;
  let after_dispose = State.peek busy in
  resolve "2x" 2;
  check "T4a: 1x waits for 2x" "…,… [busy]" held;
  check "T4a: the disposed source leaves, the boundary switches" "…,… [busy] | 1,gone" (history ());
  check "T4a: not busy after the dispose" "false" (string_of_bool after_dispose);
  dispose ()

let boundary_disposed_in_flight () =
  fresh ();
  let rows = ref None in
  let busy, dispose =
    with_owner (fun () ->
        let r, busy = Private.boundary (fun () -> Async.memo (fun () -> call "late")) in
        rows := Some r;
        busy)
  in
  let before = State.peek busy in
  dispose ();
  let after = State.peek busy in
  resolve "late" 5;
  check "T4b: busy while in flight" "true" (string_of_bool before);
  check "T4b: not busy after the dispose" "false" (string_of_bool after);
  check "T4b: a late answer writes nothing"
    "…"
    (match !rows with Some r -> show (State.peek r) | None -> "none")

let memo_disposed_in_flight () =
  fresh ();
  let rows, dispose = with_owner (fun () -> Async.memo (fun () -> call "late")) in
  dispose ();
  resolve "late" 5;
  check "a late answer after the dispose writes nothing" "…" (show (State.peek rows))

let errors () =
  fresh ();
  let filter = State.make "a" in
  let history, dispose =
    with_owner (fun () ->
        let rows = Async.memo (fun () -> if String.equal (State.get filter) "raise" then failwith "boom" else call (State.get filter)) in
        screen (fun () -> show (State.get rows)))
  in
  resolve "a" 1;
  State.set filter "b";
  reject "b" Status.Not_found;
  State.set filter "c";
  fail "c" "broken";
  State.set filter "d";
  resolve "d" 4;
  State.set filter "raise";
  check "Error, failed Async and exception keep the last data"
    "… | 1 | 1~ | E(not found)1 | 1~ | E(server error)1 | 1~ | 4 | E(server error)4" (history ());
  dispose ()

let settled_at_once () =
  fresh ();
  let n = State.make 1 in
  let history, dispose =
    with_owner (fun () ->
        let doubled = Async.memo (fun () -> Async.return (Ok (2 * State.get n))) in
        screen (fun () -> show (State.get doubled)))
  in
  State.set n 2;
  check "a settled Async gives Ready in the same run, with no Loading" "2 | 4" (history ());
  dispose ()

let equal_data () =
  fresh ();
  let n = State.make 1 in
  let runs = ref 0 in
  let dispose =
    snd
      (with_owner (fun () ->
           let parity = Async.memo ~equal:Int.equal (fun () -> Async.return (Ok (State.get n mod 2))) in
           Effect.after (fun () ->
               ignore (State.get parity);
               incr runs)))
  in
  State.set n 3;
  check "equal data is not a change" "1" (string_of_int !runs);
  State.set n 4;
  check "other data is a change" "2" (string_of_int !runs);
  dispose ()

let boundary_switches_once () =
  fresh ();
  let filter = State.make "x" in
  let history, dispose =
    with_owner (fun () ->
        let (a, b), busy =
          Private.boundary (fun () ->
              (Async.memo (fun () -> call ("a" ^ State.get filter)), Async.memo (fun () -> call ("b" ^ State.get filter))))
        in
        screen (fun () -> show (State.get a) ^ "," ^ show (State.get b) ^ busy_text busy))
  in
  resolve "bx" 2;
  resolve "ax" 1;
  State.set filter "y";
  resolve "ay" 11;
  resolve "by" 12;
  check "two sources in a boundary switch in one step" "…,… [busy] | 1,2 | 1,2 [busy] | 11,12" (history ());
  dispose ()

let all =
  [
    ("async memo: T1a latest run wins, no boundary", latest_wins_without_boundary);
    ("async memo: T1b latest run wins in a boundary", latest_wins_in_a_boundary);
    ("async memo: T4a a pending source is disposed", pending_source_disposed);
    ("async memo: T4b the boundary is disposed with a run in flight", boundary_disposed_in_flight);
    ("async memo: a disposed memo drops a late answer", memo_disposed_in_flight);
    ("async memo: Error, a failed Async and an exception", errors);
    ("async memo: a settled Async gives Ready at once", settled_at_once);
    ("async memo: equal compares Ready data", equal_data);
    ("async memo: two sources in a boundary switch together", boundary_switches_once);
  ]
