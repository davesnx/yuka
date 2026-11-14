open Demo_app
open Demo_shared

let conninfo = Sys.getenv_opt "YUKA_DEMO_DATABASE"
let yuka = Model.Workspace.Yuka
let application = ref ""

let sql ?(params = [||]) query =
  let connection = new Postgresql.connection ~conninfo:(Option.get conninfo) () in
  let result = connection#exec ~expect:[ Postgresql.Command_ok; Tuples_ok ] ~params query in
  connection#finish;
  result

let version () = int_of_string ((sql "SELECT version FROM yuka_demo_state WHERE workspace = 'yuka'")#getvalue 0 0)

let connect () =
  match Store.connect ~conninfo:(Option.get conninfo) ~reset_days:7 with
  | Ok () -> ()
  | Error message -> Alcotest.failf "connect: %s" message

let settle async =
  Lwt_main.run (Lwt.pause ());
  match Yuka.Async.status async with
  | Yuka.Async.Done (Ok value) -> Ok value
  | Done (Error error) -> Error (Yuka.Status.error_to_string error)
  | Failed message -> Error message
  | Pending -> Error "pending"

let add_note text =
  match Store.change yuka (fun () -> Ok (Store.add_note yuka ~text)) with
  | Ok () -> ()
  | Error _ -> Alcotest.failf "add_note %S was refused" text

let note_ids () =
  List.filter_map
    (fun (item : Board.item) -> match item.content with Note _ -> Some item.id | Card _ -> None)
    (Store.board yuka)

let title id = (Option.get (Store.find id)).title

let instances_at_once () =
  let read, write = Unix.pipe () in
  let child () =
    match Unix.fork () with
    | 0 ->
        Unix.close write;
        ignore (Unix.read read (Bytes.create 1) 0 1);
        let ok =
          match Store.connect ~conninfo:(Option.get conninfo) ~reset_days:7 with
          | Error _ -> false
          | Ok () ->
              List.for_all
                (fun index ->
                  Result.is_ok (Store.change yuka (fun () -> Ok (Store.add_note yuka ~text:(Printf.sprintf "Note %d of %d" index (Unix.getpid ()))))))
                (List.init 5 Fun.id)
        in
        Unix._exit (if ok then 0 else 1)
    | pid -> pid
  in
  let first = child () and second = child () in
  Unix.close read;
  Unix.close write;
  let exit_code pid = match Unix.waitpid [] pid with _, Unix.WEXITED code -> code | _ -> -1 in
  Alcotest.(check (list int)) "both instances started and wrote" [ 0; 0 ] [ exit_code first; exit_code second ];
  connect ();
  Alcotest.(check int) "ten writes, one version each" 10 (version ());
  let ids = note_ids () in
  Alcotest.(check int) "ten notes" 10 (List.length ids);
  Alcotest.(check int) "ten different ids" 10 (List.length (List.sort_uniq compare ids))

let change_from_another_instance () =
  let row = sql "SELECT state FROM yuka_demo_state WHERE workspace = 'yuka'" in
  let state = row#getvalue 0 0 in
  let seed_title = "Hydration mismatch on nested holes" in
  let at = Option.get (List.find_opt (fun index -> String.sub state index (String.length seed_title) = seed_title) (List.init (String.length state - String.length seed_title) Fun.id)) in
  let changed =
    String.sub state 0 at ^ "Changed by another instance" ^ String.sub state (at + String.length seed_title) (String.length state - at - String.length seed_title)
  in
  ignore
    (sql ~params:[| changed |] "UPDATE yuka_demo_state SET state = $1, version = version + 1 WHERE workspace = 'yuka'");
  Alcotest.(check string) "the cache before refresh" seed_title (title "YUK-1");
  Store.refresh ();
  Alcotest.(check string) "after refresh" "Changed by another instance" (title "YUK-1")

let restart () =
  connect ();
  Alcotest.(check int) "the notes" 10 (List.length (note_ids ()));
  Alcotest.(check string) "the changed title" "Changed by another instance" (title "YUK-1")

let rejected_writes_nothing () =
  let before_version = version () and before_board = Store.board yuka in
  (match settle (Yuka.Action.call Board.move { Board.workspace = yuka; id = "NOPE"; x = 0; y = 0 }) with
  | Ok _ -> Alcotest.fail "a move of an unknown item was accepted"
  | Error _ -> ());
  (match
     Store.change yuka (fun () ->
         Store.add_note yuka ~text:"Not kept";
         Error "refused after a change")
   with
  | Error (Store.Refused "refused after a change") -> ()
  | _ -> Alcotest.fail "expected the refusal");
  Alcotest.(check int) "the version" before_version (version ());
  Alcotest.(check bool) "the cache" true (Store.board yuka = before_board);
  (match settle (Yuka.Action.call Board.move { Board.workspace = yuka; id = "YUK-1"; x = 10; y = 20 }) with
  | Ok _ -> ()
  | Error message -> Alcotest.failf "move failed: %s" message);
  Alcotest.(check int) "an accepted action writes one version" (before_version + 1) (version ());
  connect ();
  let spot = List.find (fun (item : Board.item) -> item.id = "YUK-1") (Store.board yuka) in
  Alcotest.(check (pair int int)) "the move is in the row" (10, 20) (spot.x, spot.y)

let old_row_gives_the_seed () =
  let before_version = version () in
  ignore (sql "UPDATE yuka_demo_state SET started = now() - interval '8 days' WHERE workspace = 'yuka'");
  Store.refresh ();
  Alcotest.(check int) "no note" 0 (List.length (note_ids ()));
  Alcotest.(check string) "the seed title" "Hydration mismatch on nested holes" (title "YUK-1");
  Alcotest.(check int) "a read writes nothing" before_version (version ());
  add_note "After the reset";
  Alcotest.(check (list string)) "the seed and the change" [ "note-1" ] (note_ids ());
  Alcotest.(check int) "the next version" (before_version + 1) (version ());
  let fresh = sql "SELECT started > now() - interval '1 minute' FROM yuka_demo_state WHERE workspace = 'yuka'" in
  Alcotest.(check string) "a new start time" "t" (fresh#getvalue 0 0);
  connect ();
  Alcotest.(check (list string)) "a restart loads the new row" [ "note-1" ] (note_ids ())

let lost_connection () =
  let killed =
    sql ~params:[| !application |]
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND application_name = $1"
  in
  Alcotest.(check bool) "the store connection was closed" true (killed#ntuples >= 1);
  Store.refresh ();
  Alcotest.(check (list string)) "a failed read keeps the cache" [ "note-1" ] (note_ids ());
  add_note "After a reconnect";
  Alcotest.(check int) "the next write connects again" 2 (List.length (note_ids ()))

let bad_database () =
  match Store.connect ~conninfo:"postgresql://postgres:hidden-password@127.0.0.1:1/postgres" ~reset_days:7 with
  | Ok () -> Alcotest.fail "connected to a closed port"
  | Error message ->
      Alcotest.(check bool) "the password is not in the message" false (Model.Issue.contains ~sub:"hidden-password" message);
      List.iter
        (fun conninfo ->
          match Store.connect ~conninfo ~reset_days:7 with
          | Ok () -> Alcotest.fail "connected with a malformed connection string"
          | Error message ->
              Alcotest.(check bool) ("the password is not in the message for " ^ String.sub conninfo 0 24) false
                (Model.Issue.contains ~sub:"hidden-password" message))
        [
          "postgresql://postgres:hidden-password@[127.0.0.1:1/postgres";
          "postgresql://postgres:hidden-password@127.0.0.1:port/postgres";
          "postgresql://postgres:hidden-password@127.0.0.1:1/postgres?nonsense=1";
        ];
      Alcotest.(check int) "the store still works" 2 (List.length (note_ids ()));
      add_note "Still on the first database";
      Alcotest.(check int) "and writes" 3 (List.length (note_ids ()))

let stress_round_trip () =
  let stress = Model.Workspace.Stress in
  (match
     Store.change stress (fun () -> Option.to_result ~none:"no STR-2000" (Store.update ~id:"STR-2000" ~status:Model.Issue.Canceled ()))
   with
  | Ok _ -> ()
  | Error _ -> Alcotest.fail "the stress write was refused");
  let stored = sql "SELECT state FROM yuka_demo_state WHERE workspace = 'stress'" in
  Alcotest.(check int) "the row holds every stress issue" Stress.issue_count
    (List.length (Result.get_ok (Result.bind (Yuka.Json.of_string (stored#getvalue 0 0)) (Yuka.Codec.decode Store.saved_codec))).issues);
  connect ();
  Alcotest.(check int) "a restart loads every stress issue" Stress.issue_count (List.length (Store.issues stress));
  Alcotest.(check bool) "with the change" true ((Option.get (Store.find "STR-2000")).status = Model.Issue.Canceled)

let () =
  Printexc.register_printer (function Postgresql.Error error -> Some (Postgresql.string_of_error error) | _ -> None);
  match conninfo with
  | None | Some "" -> print_endline "demo store: YUKA_DEMO_DATABASE is not set, the Postgres tests are skipped"
  | Some _ ->
      Random.self_init ();
      let schema = Printf.sprintf "yuka_demo_test_%d" (Random.bits ()) in
      ignore (sql ("CREATE SCHEMA " ^ schema));
      application := schema;
      Unix.putenv "PGOPTIONS" ("-c search_path=" ^ schema ^ " -c application_name=" ^ schema);
      Handlers.register ();
      let case name f = Alcotest.test_case name `Quick f in
      at_exit (fun () -> ignore (sql ("DROP SCHEMA " ^ schema ^ " CASCADE")));
      Alcotest.run "demo store"
        [
          ( "postgres",
            [
              case "two instances start and write the first row at once" instances_at_once;
              case "a change made by another instance is seen after refresh" change_from_another_instance;
              case "a restarted instance loads the row" restart;
              case "a rejected action leaves the row and the cache unchanged" rejected_writes_nothing;
              case "a row older than the reset age gives the seed" old_row_gives_the_seed;
              case "a lost connection: the read keeps the cache, the write connects again" lost_connection;
              case "a database that does not answer: an error without the password" bad_database;
              case "the stress workspace: a write stores every issue and a restart loads them" stress_round_trip;
            ] );
        ]
