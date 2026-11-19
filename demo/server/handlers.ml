open Demo_shared

let register () =
  Yuka.Server.Live.implement Topics.issues (fun list ->
      Store.refresh ();
      Yuka.Async.return (Store.view_issues list));
  Yuka.Server.Live.implement Topics.issue (fun id ->
      Store.refresh ();
      match Store.find id with Some issue -> Yuka.Async.return issue | None -> Yuka.Server.Action.reject ("No issue " ^ id));
  Yuka.Server.Form.implement Actions.create_issue
    ~redirect:(fun (issue : Model.Issue.t) -> Links.issue issue.workspace ~id:issue.id)
    (fun _ { workspace; title; description; status; priority } ->
      let title = String.trim title in
      let title_error message = Yuka.Async.return (Error [ (Some `Title, message) ]) in
      if title = "" then title_error "Title is required"
      else if String.length title > 80 then title_error "Title is too long (at most 80 characters)"
      else
        match
          Store.change workspace (fun () ->
              match Store.find_title workspace title with
              | Some (issue : Model.Issue.t) -> Error ("An issue with this title already exists: " ^ issue.id)
              | None -> Ok (Store.create workspace ~title ~description ~status ~priority))
        with
        | Ok issue ->
            Store.publish_issue issue;
            Yuka.Async.return (Ok issue)
        | Error (Refused message) -> title_error message
        | Error Unavailable -> Yuka.Server.Action.reject Store.unavailable);
  Yuka.Server.Live.implement Topics.board (fun workspace ->
      Store.refresh ();
      Yuka.Async.return (Store.board workspace))

let issues_json (_ : Yuka.Server.request) =
  Yuka.Server.json (Yuka.Codec.list Model.Issue.codec) (Store.issues Model.Workspace.default)
