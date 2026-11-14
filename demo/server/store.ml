open Demo_shared
open Model

let users : User.t list =
  [
    { id = "maya"; name = "Maya Chen" };
    { id = "dev"; name = "Dev Patel" };
    { id = "sofia"; name = "Sofia Rossi" };
    { id = "tomas"; name = "Tomas Novak" };
  ]

let me = List.hd users
let user id = List.find (fun (user : User.t) -> user.id = id) users

let seed =
  let open Issue in
  let mk number title status priority assignee labels created_at description =
    {
      id = Printf.sprintf "%s-%d" (Workspace.issue_prefix Yuka) number;
      workspace = Yuka;
      title;
      description;
      status;
      priority;
      assignee = Option.map user assignee;
      labels;
      created_at;
    }
  in
  [
    mk 1 "Hydration mismatch on nested holes" In_progress Urgent (Some "maya") [ "bug"; "client" ] "Nov 2" Description.yuk_1;
    mk 2 "Stream comments after the shell" In_progress High (Some "dev") [ "feature"; "server" ] "Nov 2" Description.yuk_2;
    mk 3 "Keyboard navigation in the issue list" Done Medium (Some "sofia") [ "feature" ] "Oct 30" "j and k move the selection, Enter opens the issue. Ignore keys while the filter has focus.";
    mk 4 "Status menu closes on outside click" Todo Medium (Some "sofia") [ "bug" ] "Nov 3" "The menu stays open when the user clicks the page. Use a backdrop.";
    mk 5 "Decode props of islands" Todo High (Some "dev") [ "feature"; "codec" ] "Nov 3" Description.yuk_5;
    mk 6 "Document the ppx attribute checks" Backlog Low None [ "docs" ] "Oct 28" "List the valid attributes and the error messages.";
    mk 7 "Escape attribute values with quotes" Done High (Some "tomas") [ "bug"; "server" ] "Oct 27" "A quote in a title attribute broke the markup.";
    mk 8 "Add a new issue dialog" Todo Medium (Some "maya") [ "feature" ] "Nov 4" "Press c to open a dialog with title and description.";
    mk 9 "Keyed list moves lose focus" Backlog High None [ "bug"; "client" ] "Nov 1" "Moving an item in a keyed list recreates its DOM when the key stays.";
    mk 10 "Server action for status change" Todo High (Some "dev") [ "feature"; "server" ] "Nov 4" Description.yuk_10;
    mk 11 "Optimistic update rolls back on error" Backlog Medium None [ "feature" ] "Nov 4" "Show the new status now and restore the old one when the action fails.";
    mk 12 "Dark theme contrast on labels" Done Low (Some "sofia") [ "design" ] "Oct 25" Description.yuk_12;
    mk 13 "Sidebar collapses on small screens" Backlog Low None [ "design" ] "Oct 24" "Hide the sidebar under 700px.";
    mk 14 "Effects must not run on the server" Done Urgent (Some "tomas") [ "bug"; "server" ] "Oct 22" "Component bodies run with effects off during rendering.";
    mk 15 "Priority icons for each level" Done Low (Some "sofia") [ "design" ] "Oct 21" "Four bars, filled by level.";
    mk 16 "Assign issues from the page" Backlog Medium None [ "feature" ] "Nov 5" "A menu on the properties panel to change the assignee.";
    mk 17 "Label filter in the list" Backlog Low None [ "feature" ] "Nov 5" "Filter by label next to the title filter.";
    mk 18 "Cancel the board view" Canceled No_priority None [ "design" ] "Oct 18" "Out of scope for v0.1.";
    mk 19 "Slow first byte on the issue page" In_progress Medium (Some "tomas") [ "perf"; "server" ] "Nov 5" Description.yuk_19;
    mk 20 "Bundle size of the client entry" Todo Medium (Some "dev") [ "perf"; "client" ] "Nov 5" Description.yuk_20;
    mk 21 "Duplicate of YUK-9" Canceled No_priority None [ "bug" ] "Oct 29" "Closed as duplicate.";
    mk 22 "Show relative dates" Backlog Low None [ "design" ] "Nov 6" "Show 3 days ago and keep the full date in the title.";
    mk 23 "Empty state for the filter" Done Low (Some "maya") [ "design" ] "Oct 26" "Show a message when no issue matches.";
    mk 24 "Reconnect after server restart" Backlog Medium None [ "server" ] "Nov 6" "The client shows an error and retries the action.";
    mk 25 "Write the release notes" Todo No_priority (Some "maya") [ "docs" ] "Nov 6" Description.yuk_25;
  ]

let seed_comments =
  let comment id author body created_at : Comment.t =
    { id; author = user author; body = Markdown.render body; created_at }
  in
  [
    ( "YUK-1",
      [
        comment "c1" "dev" "I can reproduce it. The marker after the empty item is missing." "Nov 2";
        comment "c2" "maya" "Found it: `print_hole` skips the closing marker when the item is **empty**. Working on a fix." "Nov 3";
        comment "c3" "tomas" "Please add a test with an empty filter result." "Nov 3";
      ] );
    ( "YUK-2",
      [
        comment "c4" "sofia" "Should the loading state keep the height of the list?" "Nov 3";
        comment "c5" "dev" "Yes, a fixed height avoids a jump:\n\n```css\n.comments-loading {\n  min-height: 120px;\n}\n```" "Nov 3";
      ] );
    ("YUK-3", [ comment "c6" "maya" "Works well. Shipping it." "Oct 30" ]);
    ("YUK-5", [ comment "c8" "maya" "The codec for `Comment.t` works. Two open questions:\n\n- Do we keep the `$async` key?\n- Should a bad prop **throw** or only log?" "Nov 4" ]);
    ("YUK-19", [ comment "c7" "tomas" "Profile shows *80 ms* spent waiting on the comments query:\n\n```shell\nperf record -g -- ./demo_server.exe --port 8080\nperf report --sort symbol\n```\n\nMost of it is in `Store.comments_of`." "Nov 5" ]);
  ]

type saved = {
  issues : Issue.t list;
  comments : (string * Comment.t list) list;
  spots : (string * (int * int)) list;
  notes : (string * string) list;
  comment_count : int;
  note_count : int;
}
[@@deriving codec]

let empty = { issues = []; comments = []; spots = []; notes = []; comment_count = 0; note_count = 0 }
let yuka_seed = { empty with issues = seed; comments = seed_comments }
let stress_users = Array.of_list users
let stress_seed = { empty with issues = Stress.issues ~users:stress_users }
let stress_comments = Stress.comments ~users:stress_users
let initial = function Workspace.Yuka -> yuka_seed | Stress -> stress_seed
let generated_comments = function Workspace.Yuka -> fun _ -> [] | Stress -> stress_comments

type cell = { mutable saved : saved; mutable held : int option }

let yuka = { saved = yuka_seed; held = None }
let stress = { saved = stress_seed; held = None }
let cell = function Workspace.Yuka -> yuka | Stress -> stress
let issues workspace = (cell workspace).saved.issues

let workspace_of id =
  List.find_opt (fun workspace -> String.starts_with ~prefix:(Workspace.issue_prefix workspace ^ "-") id) Workspace.all

let find id =
  List.find_map (fun workspace -> List.find_opt (fun (issue : Issue.t) -> issue.id = id) (issues workspace)) Workspace.all

let find_title workspace title =
  let wanted = String.lowercase_ascii title in
  List.find_opt (fun (issue : Issue.t) -> String.lowercase_ascii issue.title = wanted) (issues workspace)

let comments_of id =
  match find id with
  | Some issue ->
      generated_comments issue.workspace issue
      @ Option.value (List.assoc_opt id (cell issue.workspace).saved.comments) ~default:[]
  | None -> []

let today = "Nov 6"

let after delay compute =
  if delay <= 0. then Yuka.Async.return (compute ())
  else
    Yuka_dream.to_async (Lwt.map compute (Lwt_unix.sleep delay))

let first_shown = 3
let last_shown = 5
let collapse_above = 12

let thread ~all id : Comment.thread =
  let comments = comments_of id in
  let total = List.length comments in
  if all || total <= collapse_above then { first = comments; hidden = 0; last = [] }
  else
    {
      first = List.filteri (fun index _ -> index < first_shown) comments;
      hidden = total - first_shown - last_shown;
      last = List.filteri (fun index _ -> index >= total - last_shown) comments;
    }

let comment_range ({ issue; offset; limit } : Comment.range) =
  List.filteri (fun index _ -> index >= offset && index < offset + limit) (comments_of issue)

let thread_async ~delay ~all id = after delay (fun () -> thread ~all id)

let related_async ~delay (issue : Issue.t) =
  after delay (fun () ->
      List.filter
        (fun (other : Issue.t) ->
          other.id <> issue.id && List.exists (fun label -> List.mem label issue.labels) other.labels)
        (issues issue.workspace)
      |> List.filteri (fun index _ -> index < 4))

let update ~id ?status ?priority () =
  match find id with
  | None -> None
  | Some issue ->
      let updated =
        {
          issue with
          status = Option.value status ~default:issue.status;
          priority = Option.value priority ~default:issue.priority;
        }
      in
      let cell = cell issue.workspace in
      cell.saved <-
        {
          cell.saved with
          issues = List.map (fun (existing : Issue.t) -> if existing.id = id then updated else existing) cell.saved.issues;
        };
      Some updated

let create workspace ~title ~description ~status ~priority =
  let cell = cell workspace in
  let next = 1 + List.fold_left (fun highest issue -> max highest (Issue.number issue)) 0 cell.saved.issues in
  let issue : Issue.t =
    {
      id = Printf.sprintf "%s-%d" (Workspace.issue_prefix workspace) next;
      workspace;
      title;
      description;
      status;
      priority;
      assignee = None;
      labels = [];
      created_at = today;
    }
  in
  cell.saved <- { cell.saved with issues = issue :: cell.saved.issues };
  issue

let add_comment (issue : Issue.t) ~body =
  let cell = cell issue.workspace in
  let count = cell.saved.comment_count + 1 in
  let comment : Comment.t = { id = Printf.sprintf "c%d" (100 + count); author = me; body = Markdown.render body; created_at = today } in
  let added = Option.value (List.assoc_opt issue.id cell.saved.comments) ~default:[] in
  cell.saved <-
    { cell.saved with comments = (issue.id, added @ [ comment ]) :: List.remove_assoc issue.id cell.saved.comments; comment_count = count };
  comment

let mine workspace =
  List.filter
    (fun (issue : Issue.t) ->
      match issue.assignee with Some user -> user.id = me.id | None -> false)
    (issues workspace)

let label_counts workspace =
  let issues = issues workspace in
  let open_ (issue : Issue.t) = match issue.status with Issue.Done | Issue.Canceled -> false | _ -> true in
  let labels = List.sort_uniq compare (List.concat_map (fun (issue : Issue.t) -> issue.labels) issues) in
  List.map
    (fun label ->
      { Demo_shared.Queries.label; open_ = List.length (List.filter (fun issue -> open_ issue && List.mem label issue.Issue.labels) issues) })
    labels

let user_stats workspace user_id =
  let assigned =
    List.filter
      (fun (issue : Issue.t) -> match issue.assignee with Some user -> user.id = user_id | None -> false)
      (issues workspace)
  in
  let count statuses = List.length (List.filter (fun (issue : Issue.t) -> List.mem issue.status statuses) assigned) in
  {
    Demo_shared.User_popup.open_ = count [ Issue.Backlog; Todo; In_progress ];
    in_progress = count [ In_progress ];
    done_ = count [ Done ];
  }

let random = Random.State.make_self_init ()
let random_spot () = (Random.State.int random (Board.width - Board.item_width + 1), Random.State.int random (Board.height - Board.item_height + 1))

let seeded_spot number =
  ( Insights_data.hash number mod (Board.width - Board.item_width + 1),
    Insights_data.hash (number + 50021) mod (Board.height - Board.item_height + 1) )

let carded issues = List.filteri (fun index _ -> index < Board.card_limit) issues

let board workspace : Board.t =
  let saved = (cell workspace).saved in
  let spots = Hashtbl.of_seq (List.to_seq saved.spots) in
  let at id default = Option.value (Hashtbl.find_opt spots id) ~default in
  let cards =
    List.rev_map
      (fun (issue : Issue.t) ->
        let x, y = at issue.id (seeded_spot (Issue.number issue)) in
        { Board.id = issue.id; x; y; content = Card { title = issue.title; status = issue.status } })
      (carded saved.issues)
  in
  let notes =
    List.filter_map
      (fun (id, text) -> Option.map (fun (x, y) -> { Board.id; x; y; content = Note text }) (Hashtbl.find_opt spots id))
      saved.notes
  in
  cards @ notes

let on_board workspace id =
  List.exists (fun (issue : Issue.t) -> issue.id = id) (carded (issues workspace)) || List.mem_assoc id (cell workspace).saved.notes

let move_item workspace ~id ~x ~y =
  let cell = cell workspace in
  cell.saved <- { cell.saved with spots = (id, (x, y)) :: List.remove_assoc id cell.saved.spots }

let add_note workspace ~text =
  let cell = cell workspace in
  let count = cell.saved.note_count + 1 in
  let id = Printf.sprintf "note-%d" count in
  cell.saved <-
    {
      cell.saved with
      spots = (id, random_spot ()) :: cell.saved.spots;
      notes = cell.saved.notes @ [ (id, text) ];
      note_count = count;
    }

let note_total workspace = List.length (cell workspace).saved.notes

let remove_note workspace ~id =
  let cell = cell workspace in
  if List.mem_assoc id cell.saved.notes then begin
    cell.saved <-
      { cell.saved with notes = List.remove_assoc id cell.saved.notes; spots = List.remove_assoc id cell.saved.spots };
    true
  end
  else false

let shuffle workspace =
  List.iter
    (fun (item : Board.item) ->
      let x, y = random_spot () in
      move_item workspace ~id:item.id ~x ~y)
    (board workspace)

type database = { conninfo : string; reset_days : int; mutable connection : Postgresql.connection option }

let process_id = Printf.sprintf "%06x" (Random.State.bits random land 0xffffff)
let notifies = ref false
let store_facts = ref [ ("Data", "In the memory of this server process") ]

let region_of_host host =
  let cell label =
    String.starts_with ~prefix:"c-" label && Option.is_some (int_of_string_opt (String.sub label 2 (String.length label - 2)))
  in
  match Filename.chop_suffix_opt ~suffix:".neon.tech" host with
  | None -> None
  | Some name -> (
      match String.split_on_char '.' name with
      | _endpoint :: labels -> (
          match List.filter (fun label -> not (cell label)) labels with [] -> None | kept -> Some (String.concat ", " kept))
      | [] -> None)

let place_facts (connection : Postgresql.connection) =
  let host = connection#host in
  let major, _, _ = connection#server_version in
  let region = region_of_host host in
  let version = Printf.sprintf "Postgres %d" major in
  [ ("Data", if String.ends_with ~suffix:".neon.tech" host then "Neon, " ^ version else version) ]
  @ Option.fold region ~none:[] ~some:(fun region -> [ ("Region", region) ])
  @ [ ("Database", connection#db) ]

let facts () =
  let server_region = match Sys.getenv_opt "VERCEL_REGION" with Some "" | None -> [] | Some region -> [ ("Server region", region) ] in
  !store_facts
  @ (if !notifies then [ ("Live updates", "Changes go to the other servers over Postgres LISTEN/NOTIFY") ] else [])
  @ server_region
  @ [ ("Server process", process_id) ]

let database = ref None
let unavailable = "The data store is not available. Try again."

let close db =
  Option.iter (fun (connection : Postgresql.connection) -> try connection#finish with _ -> ()) db.connection;
  db.connection <- None

let exec db ?(params = [||]) sql =
  let connection =
    match db.connection with
    | Some connection -> connection
    | None ->
        let connection = new Postgresql.connection ~conninfo:db.conninfo () in
        db.connection <- Some connection;
        connection
  in
  connection#exec ~expect:[ Postgresql.Command_ok; Tuples_ok ] ~params sql

let attempt db what f =
  match f () with
  | value -> Ok value
  | exception Postgresql.Error error ->
      close db;
      let message =
        match Postgresql.string_of_error error with
        | text when Issue.contains ~sub:"://" text -> "the connection string is not valid (libpq quotes it, so the message is not shown)"
        | text -> text
      in
      Dream.error (fun log -> log "store: %s failed: %s" what message);
      Error message
  | exception other ->
      close db;
      raise other

let encode saved = Yuka.Json.to_string (Yuka.Codec.encode saved_codec saved)

let decode workspace text =
  match Result.bind (Yuka.Json.of_string text) (Yuka.Codec.decode saved_codec) with
  | Ok saved -> saved
  | Error message ->
      Dream.error (fun log -> log "store: the saved %s state does not decode, using the seed: %s" (Workspace.slug workspace) message);
      initial workspace

let expired days = Printf.sprintf "started <= now() - make_interval(days => $%d::int)" days

let refresh () =
  match !database with
  | None -> ()
  | Some db ->
      ignore
        (attempt db "refresh" (fun () ->
             let rows =
               exec db ~params:[| string_of_int db.reset_days |]
                 ("SELECT workspace, version, " ^ expired 1 ^ " FROM yuka_demo_state")
             in
             List.iter
               (fun workspace ->
                 let cell = cell workspace in
                 let slug = Workspace.slug workspace in
                 let stamp =
                   List.find_map
                     (fun row ->
                       if rows#getvalue row 0 = slug && rows#getvalue row 2 = "f" then Some (int_of_string (rows#getvalue row 1))
                       else None)
                     (List.init rows#ntuples Fun.id)
                 in
                 if stamp <> cell.held then
                   match stamp with
                   | None ->
                       cell.saved <- initial workspace;
                       cell.held <- None
                   | Some _ ->
                       let row = exec db ~params:[| slug |] "SELECT version, state FROM yuka_demo_state WHERE workspace = $1" in
                       cell.saved <- decode workspace (row#getvalue 0 1);
                       cell.held <- Some (int_of_string (row#getvalue 0 0)))
               Workspace.all))

type 'e refusal = Refused of 'e | Unavailable

let change workspace f =
  let cell = cell workspace in
  let run () =
    let before = cell.saved in
    match f () with
    | Ok value -> Ok value
    | Error error ->
        cell.saved <- before;
        Error (Refused error)
    | exception other ->
        cell.saved <- before;
        raise other
  in
  match !database with
  | None -> run ()
  | Some db -> (
      let slug = Workspace.slug workspace in
      let result =
        attempt db "write" (fun () ->
            ignore (exec db "BEGIN");
            ignore
              (exec db ~params:[| slug |]
                 "INSERT INTO yuka_demo_state (workspace, version, started, state) VALUES ($1, 0, '-infinity', '') ON CONFLICT (workspace) DO NOTHING");
            let row =
              exec db ~params:[| slug; string_of_int db.reset_days |]
                ("SELECT version, " ^ expired 2 ^ ", state FROM yuka_demo_state WHERE workspace = $1 FOR UPDATE")
            in
            let old = row#getvalue 0 1 = "t" in
            let stamp = if old then None else Some (int_of_string (row#getvalue 0 0)) in
            if stamp <> cell.held then begin
              cell.saved <- (if old then initial workspace else decode workspace (row#getvalue 0 2));
              cell.held <- stamp
            end;
            let before = cell.saved in
            match run () with
            | Error _ as refused ->
                ignore (exec db "ROLLBACK");
                refused
            | Ok _ as done_ -> (
                try
                  let written =
                    exec db ~params:[| slug; encode cell.saved; Bool.to_string old |]
                      "UPDATE yuka_demo_state SET version = version + 1, state = $2, started = CASE WHEN $3::boolean THEN now() ELSE started END WHERE workspace = $1 RETURNING version"
                  in
                  ignore (exec db "COMMIT");
                  cell.held <- Some (int_of_string (written#getvalue 0 0));
                  done_
                with failure ->
                  cell.saved <- before;
                  raise failure))
      in
      match result with Ok result -> result | Error _ -> Error Unavailable)

let connect ~conninfo ~reset_days =
  let db = { conninfo; reset_days; connection = None } in
  let started =
    attempt db "start" (fun () ->
        ignore (exec db "BEGIN");
        ignore (exec db "SELECT pg_advisory_xact_lock(hashtext('yuka_demo_state'))");
        ignore
          (exec db
             "CREATE TABLE IF NOT EXISTS yuka_demo_state (workspace text PRIMARY KEY, version bigint NOT NULL, started timestamptz NOT NULL, state text NOT NULL)");
        ignore (exec db "COMMIT");
        Option.iter (fun connection -> store_facts := place_facts connection) db.connection)
  in
  Result.map
    (fun () ->
      database := Some db;
      List.iter
        (fun workspace ->
          let cell = cell workspace in
          cell.saved <- initial workspace;
          cell.held <- None)
        Workspace.all;
      refresh ())
    started
