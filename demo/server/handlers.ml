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
      match
        Store.change workspace (fun () ->
            match Store.find_title workspace title with
            | Some (issue : Model.Issue.t) -> Error ("An issue with this title already exists: " ^ issue.id)
            | None -> Ok (Store.create workspace ~title ~description ~status ~priority))
      with
      | Ok issue ->
          Store.publish_issue issue;
          Yuka.Async.return (Ok issue)
      | Error (Refused message) -> Yuka.Async.return (Error [ (Some `Title, message) ])
      | Error Unavailable -> Yuka.Server.Action.reject Store.unavailable);
  Yuka.Server.Form.implement Attach_form.attach
    ~redirect:(fun summary -> Routes.attach ~got:summary ())
    (fun _ { note; file } ->
      let content = file.content in
      Yuka.Async.return
        (Ok
           (Printf.sprintf "%s: %s, %s, %d bytes, starts with %s" note file.filename file.content_type
              (String.length content)
              (String.sub content 0 (min 5 (String.length content))))));
  Yuka.Server.Live.implement Topics.board (fun workspace ->
      Store.refresh ();
      Yuka.Async.return (Store.board workspace))

let issues_json (_ : Yuka.Server.request) =
  Yuka.Server.json (Yuka.Codec.list Model.Issue.codec) (Store.issues Model.Workspace.default)
