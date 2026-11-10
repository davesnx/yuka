open Demo_shared

let view_issues = function Queries.All -> !Store.issues | Queries.Mine -> Store.mine ()

let register () =
  Yuka.Server.Action.implement Queries.issues (fun view -> Yuka.Async.return (view_issues view));
  Yuka.Server.Action.implement Actions.update_issue
    (fun ({ id; status; priority } : Actions.update_input) ->
      match Store.update ~id ?status ?priority () with
      | Some i -> Yuka.Async.return i
      | None -> Yuka.Server.Action.rejected ("No issue " ^ id));
  Yuka.Server.Action.implement Actions.create_issue
    (fun { title; description; status; priority } ->
      let title = String.trim title in
      Yuka.Async.return
        (if title = "" then Error Actions.Empty_title
         else if String.length title > 80 then Error (Actions.Title_too_long 80)
         else
           match Store.find_title title with
           | Some (i : Model.Issue.t) -> Error (Actions.Duplicate_title i.id)
           | None -> Ok (Store.create ~title ~description ~status ~priority)));
  Yuka.Server.Action.implement Actions.add_comment
    (fun { issue_id; body } ->
      match Store.find issue_id with
      | Some _ when String.trim body <> "" -> Yuka.Async.return (Store.add_comment ~issue_id ~body)
      | Some _ -> Yuka.Server.Action.rejected "Comment is empty"
      | None -> Yuka.Server.Action.rejected "No such issue")

let issues_json (_ : Dream.request) =
  Yuka.Server.json (Yuka.Codec.encode (Yuka.Codec.list Model.Issue.codec) !Store.issues)
