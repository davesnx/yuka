open Demo_shared.Model

let users : User.t list =
  [
    { id = "maya"; name = "Maya Chen" };
    { id = "dev"; name = "Dev Patel" };
    { id = "sofia"; name = "Sofia Rossi" };
    { id = "tomas"; name = "Tomas Novak" };
  ]

let me = List.hd users
let user id = List.find (fun (u : User.t) -> u.id = id) users

let seed =
  let open Issue in
  let mk n title status priority assignee labels created_at description =
    {
      id = Printf.sprintf "YUK-%d" n;
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
  let c id author body created_at : Comment.t =
    { id; author = user author; body; created_at }
  in
  Hashtbl.of_seq
    (List.to_seq
       [
         ( "YUK-1",
           [
             c "c1" "dev" "I can reproduce it. The marker after the empty item is missing." "Nov 2";
             c "c2" "maya" "Found it: the printer skips the closing marker. Working on a fix." "Nov 3";
             c "c3" "tomas" "Please add a test with an empty filter result." "Nov 3";
           ] );
         ( "YUK-2",
           [
             c "c4" "sofia" "Should the loading state keep the height of the list?" "Nov 3";
             c "c5" "dev" "Yes, a fixed height avoids a jump." "Nov 3";
           ] );
         ("YUK-3", [ c "c6" "maya" "Works well. Shipping it." "Oct 30" ]);
         ("YUK-19", [ c "c7" "tomas" "Profile shows 80 ms spent waiting on the comments query." "Nov 5" ]);
       ])

let find id = List.find_opt (fun (i : Issue.t) -> i.id = id) !issues
let find_title title =
  let t = String.lowercase_ascii title in
  List.find_opt (fun (i : Issue.t) -> String.lowercase_ascii i.title = t) !issues

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
        (fun (i : Issue.t) ->
          i.id <> issue.id && List.exists (fun l -> List.mem l issue.labels) i.labels)
        !issues
      |> List.filteri (fun n _ -> n < 4))

let update ~id ?status ?priority () =
  match find id with
  | None -> None
  | Some i ->
      let i =
        {
          i with
          status = Option.value status ~default:i.status;
          priority = Option.value priority ~default:i.priority;
        }
      in
      issues := List.map (fun (x : Issue.t) -> if x.id = id then i else x) !issues;
      Some i

let create ~title ~description ~status ~priority =
  let next =
    1
    + List.fold_left
        (fun m (i : Issue.t) -> max m (int_of_string (String.sub i.id 4 (String.length i.id - 4))))
        0 !issues
  in
  let i : Issue.t =
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
  issues := i :: !issues;
  i

let add_comment ~issue_id ~body =
  let c : Comment.t =
    {
      id = Printf.sprintf "c%d" (Hashtbl.length comments * 1000 + List.length (comments_of issue_id) + 100);
      author = me;
      body;
      created_at = today;
    }
  in
  Hashtbl.replace comments issue_id (comments_of issue_id @ [ c ]);
  c

let mine () =
  List.filter
    (fun (i : Issue.t) ->
      match i.assignee with Some u -> u.id = me.id | None -> false)
    !issues
