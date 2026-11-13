open Demo_shared

let view_issues ({ workspace; view } : Queries.issue_list) =
  match view with Queries.All -> Store.issues workspace | Mine -> Store.mine workspace

let publish_board workspace =
  let board = Store.board workspace in
  Yuka.Server.Live.publish Topics.board workspace board;
  Yuka.Async.return board

let publish_issue (issue : Model.Issue.t) =
  Yuka.Server.Live.publish Topics.issue issue.id issue;
  Yuka.Server.Live.publish Topics.board issue.workspace (Store.board issue.workspace);
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
      | None -> Yuka.Server.Action.reject "No such issue");
  Yuka.Server.Live.serve Topics.board (fun workspace -> Yuka.Async.return (Store.board workspace));
  Yuka.Server.Action.make Board.move (fun _ { workspace; id; x; y } ->
      if not (Store.on_board workspace id) then Yuka.Server.Action.reject ("No item " ^ id)
      else if not (Board.inside ~x ~y) then Yuka.Server.Action.reject "The position is outside the board"
      else begin
        Store.move_item workspace ~id ~x ~y;
        publish_board workspace
      end);
  Yuka.Server.Action.make Board.add_note (fun _ { workspace; text } ->
      let text = String.trim text in
      if text = "" then Yuka.Server.Action.reject "Note is empty"
      else if not (String.is_valid_utf_8 text) then Yuka.Server.Action.reject "Note is not valid UTF-8 text"
      else if String.fold_left (fun count char -> if Char.code char land 0xC0 = 0x80 then count else count + 1) 0 text > Board.note_length then
        Yuka.Server.Action.reject (Printf.sprintf "Note is too long (at most %d characters)" Board.note_length)
      else if Store.note_total workspace >= Board.note_limit then
        Yuka.Server.Action.reject (Printf.sprintf "The board has %d notes, the most it can have" Board.note_limit)
      else begin
        Store.add_note workspace ~text;
        publish_board workspace
      end);
  Yuka.Server.Action.make Board.remove_note (fun _ { workspace; note_id } ->
      if Store.remove_note workspace ~id:note_id then publish_board workspace
      else Yuka.Server.Action.reject ("No note " ^ note_id));
  Yuka.Server.Action.make Board.shuffle (fun _ workspace ->
      Store.shuffle workspace;
      publish_board workspace)

let issues_json (_ : Dream.request) =
  Yuka.Server.json (Yuka.Codec.encode (Yuka.Codec.list Model.Issue.codec) (Store.issues Model.Workspace.default))
