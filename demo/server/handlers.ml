open Demo_shared

let view_issues ({ workspace; view } : Queries.issue_list) =
  match view with Queries.All -> Store.issues workspace | Mine -> Store.mine workspace

let publish_issue (issue : Model.Issue.t) =
  Yuka.Server.Live.publish Topics.issue issue.id issue;
  List.iter
    (fun view ->
      let list = { Queries.workspace = issue.workspace; view } in
      Yuka.Server.Live.publish Topics.issues list (view_issues list))
    [ Queries.All; Queries.Mine ]

let register () =
  Yuka.Server.Action.make Queries.labels (fun _ workspace -> Yuka.Async.return (Store.label_counts workspace));
  Yuka.Server.Action.make User_popup.stats (fun _ { workspace; user } -> Yuka.Async.return (Store.user_stats workspace user));
  Yuka.Server.Live.serve Topics.issues (fun list -> Yuka.Async.return (view_issues list));
  Yuka.Server.Live.serve Topics.issue (fun id ->
      match Store.find id with Some issue -> Yuka.Async.return issue | None -> Yuka.Server.Action.reject ("No issue " ^ id));
  Yuka.Server.Action.make Actions.update_issue
    (fun _ ({ id; status; priority } : Actions.update_input) ->
      match Store.update ~id ?status ?priority () with
      | Some issue ->
          publish_issue issue;
          Yuka.Async.return issue
      | None -> Yuka.Server.Action.reject ("No issue " ^ id));
  Yuka.Server.Form.implement Actions.create_issue
    ~redirect:(fun (issue : Model.Issue.t) -> Links.issue issue.workspace ~id:issue.id)
    (fun _ { workspace; title; description; status; priority } ->
      let title = String.trim title in
      let title_error message = Yuka.Async.return (Error [ (Some `Title, message) ]) in
      if title = "" then title_error "Title is required"
      else if String.length title > 80 then title_error "Title is too long (at most 80 characters)"
      else
        match Store.find_title workspace title with
        | Some (issue : Model.Issue.t) -> title_error ("An issue with this title already exists: " ^ issue.id)
        | None ->
            let issue = Store.create workspace ~title ~description ~status ~priority in
            publish_issue issue;
            Yuka.Async.return (Ok issue));
  Yuka.Server.Action.make Comment.add
    (fun _ { issue_id; body } ->
      match Store.find issue_id with
      | Some _ when String.trim body <> "" -> Yuka.Async.return (Store.add_comment ~issue_id ~body)
      | Some _ -> Yuka.Server.Action.reject "Comment is empty"
      | None -> Yuka.Server.Action.reject "No such issue")

let issues_json (_ : Dream.request) =
  Yuka.Server.json (Yuka.Codec.encode (Yuka.Codec.list Model.Issue.codec) (Store.issues Model.Workspace.default))
