open Demo_shared

let view_issues = function Queries.All -> !Store.issues | Queries.Mine -> Store.mine ()

let publish_issue (issue : Model.Issue.t) =
  Yuka.Server.Live.publish Topics.issue issue.id issue;
  List.iter (fun view -> Yuka.Server.Live.publish Topics.issues view (view_issues view)) [ Queries.All; Queries.Mine ]

let register () =
  Yuka.Server.Action.make Queries.labels (fun _ () -> Yuka.Async.return (Store.label_counts ()));
  Yuka.Server.Live.serve Topics.issues (fun view -> Yuka.Async.return (view_issues view));
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
    ~redirect:(fun (issue : Model.Issue.t) -> Routes.issue ~id:issue.id ())
    (fun _ { title; description; status; priority } ->
      let title = String.trim title in
      let title_error message = Yuka.Async.return (Error [ (Some `Title, message) ]) in
      if title = "" then title_error "Title is required"
      else if String.length title > 80 then title_error "Title is too long (at most 80 characters)"
      else
        match Store.find_title title with
        | Some (issue : Model.Issue.t) -> title_error ("An issue with this title already exists: " ^ issue.id)
        | None ->
            let issue = Store.create ~title ~description ~status ~priority in
            publish_issue issue;
            Yuka.Async.return (Ok issue));
  Yuka.Server.Action.make Actions.add_comment
    (fun _ { issue_id; body } ->
      match Store.find issue_id with
      | Some _ when String.trim body <> "" -> Yuka.Async.return (Store.add_comment ~issue_id ~body)
      | Some _ -> Yuka.Server.Action.reject "Comment is empty"
      | None -> Yuka.Server.Action.reject "No such issue")

let issues_json (_ : Dream.request) =
  Yuka.Server.json (Yuka.Codec.encode (Yuka.Codec.list Model.Issue.codec) !Store.issues)
