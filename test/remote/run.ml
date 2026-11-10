open Yuka
module Server = Yuka.Server

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

let index text part =
  let n = String.length part in
  let rec at i =
    if i + n > String.length text then -1 else if String.sub text i n = part then i else at (i + 1)
  in
  at 0

let show (s : string Status.t) =
  match s with
  | Status.Idle -> "idle"
  | Status.Loading None -> "loading"
  | Status.Loading (Some d) -> "loading " ^ d
  | Status.Ready { data; _ } -> "ready " ^ data
  | Status.Failed { error; last } ->
      "failed " ^ Status.error_to_string error
      ^ match last with Some d -> " last " ^ d | None -> ""

let check_status msg expected r = Alcotest.(check string) msg expected (show (Remote.status r))
let logged = ref []
let () = Server.log_error := fun m -> logged := m :: !logged

let gates : (string * (string Async.t * (string -> unit) * (string -> unit))) list ref = ref []
let calls = ref []

let gated = Action.query ~name:"gated" ~input:Codec.string ~output:Codec.string

let () =
  Server.Action.implement gated (fun input ->
      calls := input :: !calls;
      let ((a, _, _) as g) = Async.make () in
      gates := !gates @ [ (input, g) ];
      a)

let settle i v =
  let _, (_, resolve, _) = List.nth !gates i in
  resolve v

let fail i m =
  let _, (_, _, failure) = List.nth !gates i in
  failure m

let reset () =
  gates := [];
  calls := [];
  logged := []

let echo = Action.query ~name:"echo" ~input:Codec.string ~output:Codec.string
let rejecting = Action.query ~name:"rejecting" ~input:Codec.int ~output:Codec.string
let broken = Action.query ~name:"broken" ~input:Codec.int ~output:Codec.string
let counted = ref 0

let () =
  Server.Action.implement echo (fun s -> Async.resolved ("echo " ^ s));
  Server.Action.implement rejecting (fun _ ->
      incr counted;
      Server.Action.reject "no way");
  Server.Action.implement broken (fun _ ->
      incr counted;
      failwith "secret detail")

let in_owner f = Yuka.owner f

let transport =
  [
    ( "server status mapping: reject, bad input, raise, unknown",
      fun () ->
        reset ();
        let r, _ = in_owner (fun () -> Remote.use ~retry:Remote.no_retry rejecting (fun () -> 1)) in
        check_status "reject" "failed no way" r;
        let r, _ = in_owner (fun () -> Remote.use ~retry:Remote.no_retry broken (fun () -> 1)) in
        check_status "raise" "failed server error" r;
        Alcotest.(check bool) "logged" true (List.exists (fun m -> contains m "secret detail") !logged);
        let unknown = Action.query ~name:"nobody" ~input:Codec.int ~output:Codec.string in
        let r, _ = in_owner (fun () -> Remote.use unknown (fun () -> 1)) in
        check_status "unknown" "failed not found" r;
        let wrong = Action.query ~name:"echo" ~input:Codec.int ~output:Codec.string in
        let r, _ = in_owner (fun () -> Remote.use wrong (fun () -> 1)) in
        Alcotest.(check bool) "bad input" true (contains (show (Remote.status r)) "failed invalid input") );
    ( "a key change sends a new call and the old answer is dropped",
      fun () ->
        reset ();
        let input = State.make "a" in
        let r, _ = in_owner (fun () -> Remote.use gated (fun () -> State.get input)) in
        check_status "first" "loading" r;
        State.set input "b";
        Alcotest.(check (list string)) "two calls" [ "b"; "a" ] !calls;
        settle 1 "B";
        check_status "new answer" "ready B" r;
        settle 0 "A";
        check_status "old answer dropped" "ready B" r );
    ( "the same JSON key sends no new call",
      fun () ->
        reset ();
        let input = State.make (String.make 1 'x') in
        let r, _ = in_owner (fun () -> Remote.use gated (fun () -> State.get input)) in
        State.set input (String.make 1 'x');
        Alcotest.(check int) "one call" 1 (List.length !calls);
        settle 0 "X";
        check_status "ready" "ready X" r );
    ( "enabled false is Idle and true sends",
      fun () ->
        reset ();
        let on = State.make false in
        let r, _ = in_owner (fun () -> Remote.use ~enabled:(fun () -> State.get on) echo (fun () -> "e")) in
        check_status "idle" "idle" r;
        State.set on true;
        check_status "ready" "ready echo e" r );
    ( "invalidate refetches mounted uses only",
      fun () ->
        reset ();
        let a, _ = in_owner (fun () -> Remote.use gated (fun () -> "a")) in
        let b, _ = in_owner (fun () -> Remote.use gated (fun () -> "b")) in
        let _, dispose = in_owner (fun () -> Remote.use gated (fun () -> "c")) in
        dispose ();
        settle 0 "A";
        settle 1 "B";
        let before = List.length !calls in
        Remote.invalidate gated;
        let added = List.filteri (fun i _ -> i < List.length !calls - before) !calls in
        Alcotest.(check bool) "a and b again" true (List.mem "a" added && List.mem "b" added);
        Alcotest.(check bool) "not the disposed c" false (List.mem "c" added);
        check_status "a keeps its data while loading" "loading A" a;
        check_status "b" "loading B" b );
    ( "Rejected is not retried",
      fun () ->
        reset ();
        counted := 0;
        let r, _ =
          in_owner (fun () ->
              Remote.use ~retry:{ Remote.attempts = 2; delay_ms = (fun _ -> 0) } rejecting (fun () -> 1))
        in
        check_status "failed" "failed no way" r;
        Alcotest.(check int) "one call" 1 !counted );
    ( "a disposed use aborts and writes nothing",
      fun () ->
        reset ();
        let r, dispose = in_owner (fun () -> Remote.use gated (fun () -> "a")) in
        dispose ();
        settle 0 "A";
        check_status "still loading" "loading" r );
    ( "a failed refetch keeps the last data",
      fun () ->
        reset ();
        let r, _ = in_owner (fun () -> Remote.use ~retry:Remote.no_retry gated (fun () -> "a")) in
        settle 0 "A";
        Remote.refetch r;
        check_status "loading with last" "loading A" r;
        fail 1 "down";
        check_status "failed with last" "failed server error last A" r );
  ]

let island q input =
  Client.island ~name:"Q" ~props:`Null (fun () ->
      let r = Remote.use q (fun () -> input) in
      lower "b" [] [ text (show (Remote.status r)) ])

let answers =
  [
    ( "a settled query is written after the island, before its props",
      fun () ->
        reset ();
        let html = Server.to_string (fun () -> island echo "hi") in
        Alcotest.(check bool) "data in the HTML" true (contains html "<b>ready echo hi</b>");
        let answer = {|<script type="application/json" data-yuka-answer="r:echo &quot;hi&quot;">{"ok":"echo hi"}</script>|} in
        let a = index html answer and close = index html "</yuka-island>" and props = index html "data-yuka-props" in
        Alcotest.(check bool) "between the island and its props" true (close < a && a < props) );
    ( "a failed query writes the error kind without the detail",
      fun () ->
        reset ();
        let html = Server.to_string (fun () -> island broken 1 |> fun x -> x) in
        Alcotest.(check bool) "server kind" true (contains html {|{"error":{"kind":"server"}}|});
        Alcotest.(check bool) "no detail" false (contains html "secret") );
    ( "outside an island nothing is written",
      fun () ->
        reset ();
        let html =
          Server.to_string (fun () ->
              let r = Remote.use echo (fun () -> "out") in
              lower "b" [] [ text (show (Remote.status r)) ])
        in
        Alcotest.(check bool) "data" true (contains html "ready echo out");
        Alcotest.(check bool) "no answer" false (contains html "data-yuka-answer") );
    ( "streaming: a pending answer, then the full element",
      fun () ->
        reset ();
        let chunks = ref [] in
        let write c =
          chunks := c :: !chunks;
          Async.resolved ()
        in
        let never _ =
          let a, _, _ = Async.make () in
          a
        in
        let p = Private.stream ~sleep:never ~write (fun () -> island gated "s") in
        let all () = String.concat "" (List.rev !chunks) in
        Alcotest.(check bool) "pending element" true
          (contains (all ()) {|data-yuka-answer="r:gated &quot;s&quot;" data-pending></script>|});
        Alcotest.(check bool) "loading shown" true (contains (all ()) "<b>loading</b>");
        settle 0 "S";
        Alcotest.(check bool) "done" true (Async.status p = Async.Done ());
        Alcotest.(check bool) "full element later" true
          (contains (List.nth (List.rev !chunks) (List.length !chunks - 2))
             {|data-yuka-answer="r:gated &quot;s&quot;">{"ok":"S"}</script>|}) );
    ( "streaming timeout writes a network error",
      fun () ->
        reset ();
        let chunks = ref [] in
        let write c =
          chunks := c :: !chunks;
          Async.resolved ()
        in
        let fire = ref ignore in
        let sleep _ =
          let a, resolve, _ = Async.make () in
          fire := resolve;
          a
        in
        let p = Private.stream ~sleep ~write (fun () -> island gated "t") in
        !fire ();
        Alcotest.(check bool) "done" true (Async.status p = Async.Done ());
        Alcotest.(check bool) "timeout" true
          (contains (String.concat "" !chunks) {|{"error":{"kind":"network","message":"timeout"}}|}) );
    ( "settled render writes every answer",
      fun () ->
        reset ();
        let never _ =
          let a, _, _ = Async.make () in
          a
        in
        let p = Private.settled ~sleep:never (fun () -> island gated "n") in
        settle 0 "N";
        match Async.status p with
        | Async.Done html ->
            Alcotest.(check bool) "full answer" true
              (contains html {|data-yuka-answer="r:gated &quot;n&quot;">{"ok":"N"}</script>|})
        | _ -> Alcotest.fail "not settled" );
  ]

let edit = Action.declare ~name:"edit" ~input:Codec.string ~output:Codec.string
let edits = ref []

let () =
  Server.Action.implement edit (fun s ->
      let ((a, _, _) as g) = Async.make () in
      edits := !edits @ [ (s, g) ];
      a)

let settle_edit i v =
  let _, (_, resolve, _) = List.nth !edits i in
  resolve v

let fail_edit i =
  let _, (_, _, failure) = List.nth !edits i in
  failure "no"

let optimistic =
  [
    ( "Optimistic: order, remove, new base",
      fun () ->
        let t, first = Optimistic.add Optimistic.empty (fun s -> s ^ "1") in
        let t, _ = Optimistic.add t (fun _ -> "two") in
        let t, _ = Optimistic.add t (fun s -> s ^ "3") in
        let run = Optimistic.apply (fun d f -> f d) in
        Alcotest.(check string) "later wins, oldest first" "two3" (run t "base");
        let t = Optimistic.remove t first in
        Alcotest.(check string) "remove the first keeps the others" "two3" (run t "x");
        let t2, _ = Optimistic.add Optimistic.empty (fun s -> s ^ "!") in
        Alcotest.(check string) "new base" "new!" (run t2 "new");
        Alcotest.(check bool) "empty" true (Optimistic.is_empty Optimistic.empty) );
    ( "mutate: shown at once, commit on Ok, rollback on Error",
      fun () ->
        reset ();
        edits := [];
        let r, _ = in_owner (fun () -> Remote.use gated (fun () -> "m")) in
        settle 0 "base";
        let a = Remote.mutate r (fun d -> d ^ "+x") (fun () -> Action.call edit "x") in
        check_status "shown before the call settles" "ready base+x" r;
        settle_edit 0 "server";
        Alcotest.(check bool) "settled" true (Async.status a = Async.Done "server");
        check_status "change kept as the base" "ready base+x" r;
        let _ = Remote.mutate r (fun d -> d ^ "+y") ~commit:(fun v d -> d ^ "|" ^ v) (fun () -> Action.call edit "y") in
        settle_edit 1 "Y";
        check_status "commit" "ready base+x|Y" r;
        let b = Remote.mutate r (fun d -> d ^ "+z") (fun () -> Action.call edit "z") in
        check_status "shown" "ready base+x|Y+z" r;
        fail_edit 2;
        Alcotest.(check bool) "failed" true (match Async.status b with Async.Failed _ -> true | _ -> false);
        check_status "rolled back" "ready base+x|Y" r );
    ( "mutate: a refetch during a pending change keeps the change",
      fun () ->
        reset ();
        edits := [];
        let r, _ = in_owner (fun () -> Remote.use gated (fun () -> "p")) in
        settle 0 "old";
        let _ = Remote.mutate r (fun d -> d ^ "+c") (fun () -> Action.call edit "c") in
        Remote.refetch r;
        check_status "loading keeps last data with the change" "loading old+c" r;
        settle 1 "fresh";
        check_status "change on the new base" "ready fresh+c" r;
        settle_edit 0 "ok";
        check_status "settled" "ready fresh+c" r );
  ]

let cases tests = List.map (fun (name, f) -> Alcotest.test_case name `Quick f) tests

let () =
  Alcotest.run "remote"
    [ ("transport", cases transport); ("answers", cases answers); ("optimistic", cases optimistic) ]
