module Actions = Demo_shared.Actions
module Links = Demo_shared.Links
module Queries = Demo_shared.Queries
module Topics = Demo_shared.Topics
open Demo_shared.Model
open Demo_shared.Issue_list
module State = Yuka.State

let backdrop_template =
  Block_stubs.template ~markup:{|<div class="backdrop"></div>|} ~walk:[||] ~targets:[| 0 |] ~kinds:[| Block_stubs.Click |]

let popup_list_template =
  Block_stubs.template ~markup:{|<ul class="menu"><!----></ul>|} ~walk:[| 0; 0 |] ~targets:[| 1 |]
    ~kinds:[| Block_stubs.Node |]

let status_item_template =
  Block_stubs.template ~markup:{|<li><button class="menu-item"><!----> </button></li>|} ~walk:[| 0; 0; 2; 0; 5; 1 |]
    ~targets:[| 1; 2; 3 |]
    ~kinds:[| Block_stubs.Click; Block_stubs.child_at_kind Views_blocks.status_icon; Block_stubs.Text |]

let priority_item_template =
  Block_stubs.template ~markup:{|<li><button class="menu-item"><!----> </button></li>|} ~walk:[| 0; 0; 2; 0; 5; 1 |]
    ~targets:[| 1; 2; 3 |]
    ~kinds:[| Block_stubs.Click; Block_stubs.child_at_kind Views_blocks.priority_icon; Block_stubs.Text |]

let row_template =
  Block_stubs.template
    ~markup:
      {|<div><span class="status-wrap"><button class="icon-button" aria-label="Change priority"></button><!----></span><span class="row-id"> </span><span class="status-wrap"><button class="icon-button" aria-label="Change status"></button><!----></span><a class="row-title"> </a><!----><!----><span class="row-date"> </span></div>|}
    ~walk:[| 0; 0; 2; 0; 5; 1; 3; 1; 8; 0; 9; 1; 12; 0; 15; 1; 13; 1; 18; 0; 19; 1; 23; 1; 25; 1; 26; 0 |]
    ~targets:[| 0; 0; 0; 2; 2; 3; 5; 7; 7; 8; 9; 10; 11; 12; 14 |]
    ~kinds:
      [|
        Block_stubs.Attr "id";
        Block_stubs.Class;
        Block_stubs.Attr "data-id";
        Block_stubs.Click;
        Block_stubs.child_kind Views_blocks.priority_icon;
        Block_stubs.Node;
        Block_stubs.Text;
        Block_stubs.Click;
        Block_stubs.child_kind Views_blocks.status_icon;
        Block_stubs.Node;
        Block_stubs.Attr "href";
        Block_stubs.Text;
        Block_stubs.child_at_kind Views_blocks.labels;
        Block_stubs.Node;
        Block_stubs.Text;
      |]

let make_props ~(workspace : Workspace.t) ~(view : Queries.view) () = (workspace, view)

let make =
  Block_stubs.component ~markup:{|<div class="list"></div>|} ~walk:[||] ~targets:[| 0 |] ~kinds:[| Block_stubs.Rows |]
    (fun (workspace, view) ->
      let source = Yuka.Live.make Topics.issues (fun () -> { Queries.workspace; view }) in
      let issues = State.memo (fun () -> Option.value (Yuka.Status.data (Yuka.Live.status source)) ~default:[]) in
      let selected : string option State.t = State.make None in
      let menu : menu option State.t = State.make None in
      let toast : string option State.t = State.make None in
      let block_view ~workspace ~view:_ () =
        let change ~id ?status ?priority () =
          State.set menu None;
          State.set toast None;
          let edit (issue : Issue.t) =
            if issue.id <> id then issue
            else
              {
                issue with
                status = Option.value status ~default:issue.status;
                priority = Option.value priority ~default:issue.priority;
              }
          in
          Yuka.Async.on_result
            (Yuka.Live.optimistic source ~change:(List.map edit) (fun () ->
                 Yuka.Action.call Actions.update_issue { Actions.id; status; priority }))
            (function
              | Ok (Ok _) ->
                  if status <> None then begin
                    Yuka.Remote.invalidate Queries.labels;
                    Yuka.Remote.invalidate Demo_shared.User_popup.stats
                  end
              | Ok (Error _) | Error _ -> State.set toast (Some ("Could not update " ^ id ^ ".")))
        in
        let popup items =
          Block_stubs.many
            [
              Block_stubs.block backdrop_template [| Block.on_click (fun _ -> State.set menu None) |];
              Block_stubs.block popup_list_template [| Block_stubs.node (Block_stubs.many items) |];
            ]
        in
        let status_menu (issue : Issue.t) =
          popup
            (List.map
               (fun status ->
                 Block_stubs.block status_item_template
                   [|
                     Block.on_click (fun _ -> change ~id:issue.id ~status ());
                     Block.child (Views_blocks.status_icon_props ~status ());
                     Block.text (Issue.status_label status);
                   |])
               Issue.all_statuses)
        in
        let priority_menu (issue : Issue.t) =
          popup
            (List.map
               (fun priority ->
                 Block_stubs.block priority_item_template
                   [|
                     Block.on_click (fun _ -> change ~id:issue.id ~priority ());
                     Block.child (Views_blocks.priority_icon_props ~priority ());
                     Block.text (Issue.priority_label priority);
                   |])
               Issue.all_priorities)
        in
        let row (issue : Issue.t) =
          Block_stubs.block row_template
            [|
              Block.attr ("row-" ^ issue.id);
              Block.class_name (if State.get selected = Some issue.id then "row selected" else "row");
              Block.attr issue.id;
              Block.on_click (fun _ -> State.set menu (Some (Priority issue.id)));
              Block.child (Views_blocks.priority_icon_props ~priority:issue.priority ());
              Block_stubs.node
                (if State.get menu = Some (Priority issue.id) then priority_menu issue else Block_stubs.empty);
              Block.text issue.id;
              Block.on_click (fun _ -> State.set menu (Some (Status issue.id)));
              Block.child (Views_blocks.status_icon_props ~status:issue.status ());
              Block_stubs.node (if State.get menu = Some (Status issue.id) then status_menu issue else Block_stubs.empty);
              Block.attr (Links.issue workspace ~id:issue.id);
              Block.text issue.title;
              Block.child (Views_blocks.labels_props ~labels:issue.labels ());
              Block_stubs.node
                (match issue.assignee with
                | Some user -> Block_stubs.instance User_popup.make (User_popup.make_props ~workspace ~user ~row:issue.id ())
                | None -> Block_stubs.instance Views_blocks.avatar (Views_blocks.avatar_props ~user:None ()));
              Block.text issue.created_at;
            |]
        in
        [| Block_stubs.rows ~key:(fun (issue : Issue.t) -> issue.id) (Array.of_list (State.get issues)) row |]
      in
      fun (workspace, view) -> block_view ~workspace ~view ())
