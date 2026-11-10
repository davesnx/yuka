open Demo_shared

let view_issues = function Queries.All -> !Store.issues | Queries.Mine -> Store.mine ()

let register () =
  Yuka.Server.Action.implement Queries.issues (fun view -> Yuka.Async.return (view_issues view));
  Yuka.Server.Action.implement Actions.update_issue
    (fun ({ id; status; priority } : Actions.update_input) ->
      match Store.update ~id ?status ?priority () with
      | Some i -> Yuka.Async.return i
      | None -> Yuka.Server.Action.rejected ("No issue " ^ id));
  Yuka.Server.Form.implement Actions.create_issue
    ~redirect:(fun (i : Model.Issue.t) -> Routes.href (Issue { id = i.id }))
    (fun { title; description; status; priority } ->
      let title = String.trim title in
      let title_error m = Yuka.Async.return (Error [ (Some Actions.Title, m) ]) in
      if title = "" then title_error "Title is required"
      else if String.length title > 80 then title_error "Title is too long (at most 80 characters)"
      else
        match Store.find_title title with
        | Some (i : Model.Issue.t) -> title_error ("An issue with this title already exists: " ^ i.id)
        | None -> Yuka.Async.return (Ok (Store.create ~title ~description ~status ~priority)));
  Yuka.Server.Action.implement Actions.add_comment
    (fun { issue_id; body } ->
      match Store.find issue_id with
      | Some _ when String.trim body <> "" -> Yuka.Async.return (Store.add_comment ~issue_id ~body)
      | Some _ -> Yuka.Server.Action.rejected "Comment is empty"
      | None -> Yuka.Server.Action.rejected "No such issue")

let issues_json (_ : Dream.request) =
  Yuka.Server.json (Yuka.Codec.encode (Yuka.Codec.list Model.Issue.codec) !Store.issues)
