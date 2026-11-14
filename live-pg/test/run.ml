module Async = Yuka.Async
module Live = Yuka.Server.Live

let conninfo = Sys.getenv_opt "YUKA_LIVE_PG"
let ( let* ) = Lwt.bind

let rec until ?(tries = 250) f =
  if f () then Lwt.return true
  else if tries = 0 then Lwt.return false
  else
    let* () = Lwt_unix.sleep 0.02 in
    until ~tries:(tries - 1) f

let wait a =
  let p, r = Lwt.wait () in
  Async.on_settled a (fun s -> Lwt.wakeup_later r s);
  p

let channel () = "yuka_test_" ^ string_of_int (Random.bits ())
let bus ch = Yuka_live_pg.bus ~retry:0.1 ~conninfo:(Option.get conninfo) ~channel:ch ()

let check_true msg b = Alcotest.(check bool) msg true b

let notes_cross () =
  let ch = channel () in
  let a = bus ch and b = bus ch in
  let heard = ref [] in
  let* _ = wait (b.listen (fun n -> heard := n :: !heard)) in
  let* _ = wait (a.send "one") in
  let* _ = wait (a.send "two") in
  let* ok = until (fun () -> List.length !heard = 2) in
  check_true "both notes" ok;
  Alcotest.(check (list string)) "in send order" [ "one"; "two" ] (List.rev !heard);
  Lwt.return_unit

let too_long () =
  let a = bus (channel ()) in
  let* r = wait (a.send (String.make 8001 'x')) in
  check_true "refused by Postgres" (match r with Async.Failed _ -> true | _ -> false);
  let* r = wait (a.send "small") in
  check_true "the next note works" (r = Async.Done ());
  Lwt.return_unit

let terminate pattern =
  let c = new Postgresql.connection ~conninfo:(Option.get conninfo) () in
  let r =
    c#exec
      ("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND query = 'LISTEN \""
     ^ pattern ^ "\"'")
  in
  let n = r#ntuples in
  c#finish;
  n

let restart () =
  let ch = channel () in
  let a = bus ch and b = bus ch in
  let heard = ref [] and restarts = ref 0 in
  b.on_restart (fun () -> incr restarts);
  let* _ = wait (b.listen (fun n -> heard := n :: !heard)) in
  Alcotest.(check int) "one listener killed" 1 (terminate ch);
  let* ok = until (fun () -> !restarts = 1) in
  check_true "on_restart after the listener came back" ok;
  let* _ = wait (a.send "after") in
  let* ok = until (fun () -> !heard = [ "after" ]) in
  check_true "notes arrive again" ok;
  Lwt.return_unit

let close () =
  let ch = channel () in
  let a = bus ch and b = bus ch in
  let heard = ref [] in
  let* _ = wait (b.listen (fun n -> heard := n :: !heard)) in
  let* _ = wait (a.send "before") in
  let* ok = until (fun () -> !heard = [ "before" ]) in
  check_true "heard before close" ok;
  let* _ = wait (Live.close_bus b) in
  let* _ = wait (a.send "after") in
  let* () = Lwt_unix.sleep 0.3 in
  Alcotest.(check (list string)) "nothing after close" [ "before" ] !heard;
  let* r = wait (b.send "x") in
  check_true "a closed bus does not send" (match r with Async.Failed _ -> true | _ -> false);
  Lwt.return_unit

let topic = Yuka.Topic.declare ~name:"pg-count" ~key:Yuka.Codec.string ~state:Yuka.Codec.int
let truth = ref 0
let () = Live.serve topic (fun _ -> Async.return !truth)

let lwt_sleep s =
  let a, resolve, _ = Async.make () in
  Lwt.async (fun () ->
      let* () = Lwt_unix.sleep s in
      resolve ();
      Lwt.return_unit);
  a

let two_nodes () =
  let ch = channel () in
  let na = Live.node () and nb = Live.node () in
  let* _ = wait (Live.use_bus ~node:na ~name:"A" (bus ch)) in
  let* _ = wait (Live.use_bus ~node:nb ~name:"B" (bus ch)) in
  let out = ref [] in
  let inbox = ref [ Some {|{"t":"hello","v":1,"csrf":"ok"}|}; Some {|{"t":"sub","id":1,"topic":"pg-count","key":"k"}|} ] in
  let connection =
    Live.connection
      ~send:(fun t ->
        out := !out @ [ t ];
        Async.return ())
      ~receive:(fun () ->
        match !inbox with
        | x :: rest ->
            inbox := rest;
            Async.return x
        | [] ->
            let a, _, _ = Async.make () in
            a)
      ~close:(fun _ -> Async.return ())
  in
  ignore
    (Yuka.Server.Testing.live_run ~node:nb ~sleep:lwt_sleep (Yuka.Server.Testing.context ~session:"s" ())
       ~verify_csrf:(fun _ -> Async.return true)
       ~token:(fun () -> Some "t")
       connection);
  let has v = List.exists (String.ends_with ~suffix:(Printf.sprintf {|"state":%d}|} v)) !out in
  check_true "the first state on B" (has 0);
  truth := 42;
  Live.publish ~node:na topic "k" 42;
  let* ok = until (fun () -> has 42) in
  check_true "a publish on A reaches the subscriber on B through Postgres" ok;
  Lwt.return_unit

let case name f = Alcotest.test_case name `Quick (fun () -> Lwt_main.run (f ()))

let () =
  match conninfo with
  | None -> print_endline "yuka-live-pg: YUKA_LIVE_PG is not set, the Postgres tests are skipped"
  | Some _ ->
      Random.self_init ();
      Alcotest.run "yuka-live-pg"
        [
          ( "bus",
            [
              case "a note from one connection reaches a listener on another" notes_cross;
              case "a note over 8,000 bytes is refused" too_long;
              case "a killed listener connects again and calls on_restart" restart;
              case "close stops listening and sending" close;
              case "two nodes: a publish on A reaches a subscriber on B" two_nodes;
            ] );
        ]
