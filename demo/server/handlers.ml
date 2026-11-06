open Demo_shared

let register () =
  Yuka_server.Action.implement Actions.update_issue
    (fun ({ id; status; priority } : Actions.update_input) ->
      match Store.update ~id ?status ?priority () with
      | Some i -> Lwt.return i
      | None -> Yuka_server.Action.reject ("No issue " ^ id));
  Yuka_server.Action.implement Actions.create_issue
    (fun { title; description; status; priority } ->
      let title = String.trim title in
      Lwt.return
        (if title = "" then Error Actions.Empty_title
         else if String.length title > 80 then Error (Actions.Title_too_long 80)
         else
           match Store.find_title title with
           | Some (i : Model.Issue.t) -> Error (Actions.Duplicate_title i.id)
           | None -> Ok (Store.create ~title ~description ~status ~priority)));
  Yuka_server.Action.implement Actions.add_comment
    (fun { issue_id; body } ->
      match Store.find issue_id with
      | Some _ when String.trim body <> "" -> Lwt.return (Store.add_comment ~issue_id ~body)
      | Some _ -> Yuka_server.Action.reject "Comment is empty"
      | None -> Yuka_server.Action.reject "No such issue")
