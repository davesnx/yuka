open Demo_shared.Model

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
      id = Printf.sprintf "YUK-%d" number;
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
    mk 1 "Hydration mismatch on nested holes" In_progress Urgent (Some "maya") [ "bug"; "client" ] "Nov 2" "A hole inside an each item loses its marker when the item is empty. Reproduce with a filter that matches nothing, then clear it.";
    mk 2 "Stream comments after the shell" In_progress High (Some "dev") [ "feature"; "server" ] "Nov 2" "Send the shell first and the comments later in the same response, with out of order placement.";
    mk 3 "Keyboard navigation in the issue list" Done Medium (Some "sofia") [ "feature" ] "Oct 30" "j and k move the selection, Enter opens the issue. Ignore keys while the filter has focus.";
    mk 4 "Status menu closes on outside click" Todo Medium (Some "sofia") [ "bug" ] "Nov 3" "The menu stays open when the user clicks the page. Use a backdrop.";
    mk 5 "Decode props of islands" Todo High (Some "dev") [ "feature"; "codec" ] "Nov 3" "The client reads the JSON script of each island and decodes the props with the codec.";
    mk 6 "Document the ppx attribute checks" Backlog Low None [ "docs" ] "Oct 28" "List the valid attributes and the error messages.";
    mk 7 "Escape attribute values with quotes" Done High (Some "tomas") [ "bug"; "server" ] "Oct 27" "A quote in a title attribute broke the markup.";
    mk 8 "Add a new issue dialog" Todo Medium (Some "maya") [ "feature" ] "Nov 4" "Press c to open a dialog with title and description.";
    mk 9 "Keyed list moves lose focus" Backlog High None [ "bug"; "client" ] "Nov 1" "Moving an item in a keyed list recreates its DOM when the key stays.";
    mk 10 "Server action for status change" Todo High (Some "dev") [ "feature"; "server" ] "Nov 4" "POST the new status and answer with the updated issue.";
    mk 11 "Optimistic update rolls back on error" Backlog Medium None [ "feature" ] "Nov 4" "Show the new status now and restore the old one when the action fails.";
    mk 12 "Dark theme contrast on labels" Done Low (Some "sofia") [ "design" ] "Oct 25" "Raise the contrast of label text on the dark background.";
    mk 13 "Sidebar collapses on small screens" Backlog Low None [ "design" ] "Oct 24" "Hide the sidebar under 700px.";
    mk 14 "Effects must not run on the server" Done Urgent (Some "tomas") [ "bug"; "server" ] "Oct 22" "Component bodies run with effects off during rendering.";
    mk 15 "Priority icons for each level" Done Low (Some "sofia") [ "design" ] "Oct 21" "Four bars, filled by level.";
    mk 16 "Assign issues from the page" Backlog Medium None [ "feature" ] "Nov 5" "A menu on the properties panel to change the assignee.";
    mk 17 "Label filter in the list" Backlog Low None [ "feature" ] "Nov 5" "Filter by label next to the title filter.";
    mk 18 "Cancel the board view" Canceled No_priority None [ "design" ] "Oct 18" "Out of scope for v0.1.";
    mk 19 "Slow first byte on the issue page" In_progress Medium (Some "tomas") [ "perf"; "server" ] "Nov 5" "The page waits for every comment before it sends the first byte.";
    mk 20 "Bundle size of the client entry" Todo Medium (Some "dev") [ "perf"; "client" ] "Nov 5" "Measure the emitted modules and remove what the page does not use.";
    mk 21 "Duplicate of YUK-9" Canceled No_priority None [ "bug" ] "Oct 29" "Closed as duplicate.";
    mk 22 "Show relative dates" Backlog Low None [ "design" ] "Nov 6" "Show 3 days ago and keep the full date in the title.";
    mk 23 "Empty state for the filter" Done Low (Some "maya") [ "design" ] "Oct 26" "Show a message when no issue matches.";
    mk 24 "Reconnect after server restart" Backlog Medium None [ "server" ] "Nov 6" "The client shows an error and retries the action.";
    mk 25 "Write the release notes" Todo No_priority (Some "maya") [ "docs" ] "Nov 6" "Summarize what v0.1 includes.";
  ]

let issues = ref seed

let comments : (string, Comment.t list) Hashtbl.t =
  let comment id author body created_at : Comment.t =
    { id; author = user author; body; created_at }
  in
  Hashtbl.of_seq
    (List.to_seq
       [
         ( "YUK-1",
           [
             comment "c1" "dev" "I can reproduce it. The marker after the empty item is missing." "Nov 2";
             comment "c2" "maya" "Found it: the printer skips the closing marker. Working on a fix." "Nov 3";
             comment "c3" "tomas" "Please add a test with an empty filter result." "Nov 3";
           ] );
         ( "YUK-2",
           [
             comment "c4" "sofia" "Should the loading state keep the height of the list?" "Nov 3";
             comment "c5" "dev" "Yes, a fixed height avoids a jump." "Nov 3";
           ] );
         ("YUK-3", [ comment "c6" "maya" "Works well. Shipping it." "Oct 30" ]);
         ("YUK-19", [ comment "c7" "tomas" "Profile shows 80 ms spent waiting on the comments query." "Nov 5" ]);
       ])

let find id = List.find_opt (fun (issue : Issue.t) -> issue.id = id) !issues
let find_title title =
  let wanted = String.lowercase_ascii title in
  List.find_opt (fun (issue : Issue.t) -> String.lowercase_ascii issue.title = wanted) !issues

let comments_of id = Option.value (Hashtbl.find_opt comments id) ~default:[]
let today = "Nov 6"

let after delay compute =
  if delay <= 0. then Yuka.Async.return (compute ())
  else
    Yuka_dream.to_async (Lwt.map compute (Lwt_unix.sleep delay))

let comments_async ~delay id = after delay (fun () -> comments_of id)

let related_async ~delay (issue : Issue.t) =
  after delay (fun () ->
      List.filter
        (fun (other : Issue.t) ->
          other.id <> issue.id && List.exists (fun label -> List.mem label issue.labels) other.labels)
        !issues
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
      issues := List.map (fun (existing : Issue.t) -> if existing.id = id then updated else existing) !issues;
      Some updated

let create ~title ~description ~status ~priority =
  let next =
    1
    + List.fold_left
        (fun highest (issue : Issue.t) -> max highest (int_of_string (String.sub issue.id 4 (String.length issue.id - 4))))
        0 !issues
  in
  let issue : Issue.t =
    {
      id = Printf.sprintf "YUK-%d" next;
      title;
      description;
      status;
      priority;
      assignee = None;
      labels = [];
      created_at = today;
    }
  in
  issues := issue :: !issues;
  issue

let add_comment ~issue_id ~body =
  let comment : Comment.t =
    {
      id = Printf.sprintf "c%d" (Hashtbl.length comments * 1000 + List.length (comments_of issue_id) + 100);
      author = me;
      body;
      created_at = today;
    }
  in
  Hashtbl.replace comments issue_id (comments_of issue_id @ [ comment ]);
  comment

let mine () =
  List.filter
    (fun (issue : Issue.t) ->
      match issue.assignee with Some user -> user.id = me.id | None -> false)
    !issues

let label_counts () =
  let open_ (issue : Issue.t) = match issue.status with Issue.Done | Issue.Canceled -> false | _ -> true in
  let labels = List.sort_uniq compare (List.concat_map (fun (issue : Issue.t) -> issue.labels) !issues) in
  List.map
    (fun label ->
      { Demo_shared.Queries.label; open_ = List.length (List.filter (fun issue -> open_ issue && List.mem label issue.Issue.labels) !issues) })
    labels
