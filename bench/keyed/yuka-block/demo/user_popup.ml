open Demo_shared
open Model
open User_popup
module State = Yuka.State

let stat_template =
  Block_stubs.template ~markup:"<div><dt> </dt><dd> </dd></div>" ~walk:[| 0; 0; 2; 0; 3; 1; 6; 0 |]
    ~targets:[| 0; 2; 4 |] ~kinds:[| Block_stubs.Class; Block_stubs.Text; Block_stubs.Text |]

let stats_template =
  Block_stubs.template ~markup:"<dl><!----><!----><!----></dl>" ~walk:[| 0; 0; 3; 1; 5; 1 |] ~targets:[| 0; 1; 2; 3 |]
    ~kinds:[| Block_stubs.Class; Block_stubs.Node; Block_stubs.Node; Block_stubs.Node |]

let loading_template =
  Block_stubs.template ~markup:"<p>Loading...</p>" ~walk:[||] ~targets:[| 0 |] ~kinds:[| Block_stubs.Class |]

let failed_template =
  Block_stubs.template ~markup:"<p>Could not load the numbers.</p>" ~walk:[||] ~targets:[| 0 |]
    ~kinds:[| Block_stubs.Class |]

let stat name value =
  Block_stubs.block stat_template [| Block.class_name Css.stat; Block.text name; Block_stubs.int_text value |]

let card_props ~workspace ~(user : User.t) ~id () = (workspace, user, id)

let card =
  Block_stubs.component
    ~markup:
      {|<div popover="auto" role="dialog"><div><span aria-hidden="true"> </span><div><div> </div><div> </div></div></div><!----></div>|}
    ~walk:[| 0; 0; 2; 0; 4; 0; 5; 1; 8; 0; 10; 0; 11; 1; 14; 0; 3; 1 |]
    ~targets:[| 0; 0; 0; 1; 2; 3; 5; 6; 7; 8; 9 |]
    ~kinds:
      [|
        Block_stubs.Attr "id";
        Block_stubs.Attr "aria-label";
        Block_stubs.Class;
        Block_stubs.Class;
        Block_stubs.Class;
        Block_stubs.Text;
        Block_stubs.Class;
        Block_stubs.Text;
        Block_stubs.Class;
        Block_stubs.Text;
        Block_stubs.Node;
      |]
    (fun (workspace, (user : User.t), _) ->
      let stats = Yuka.Remote.make stats (fun () -> { workspace; user = user.id }) in
      let view ~workspace:_ ~(user : User.t) ~id () =
        [|
          Block.attr id;
          Block.attr user.name;
          Block.class_name Css.card;
          Block.class_name Css.head;
          Block.class_name Css.picture;
          Block.text (User.initials user);
          Block.class_name Css.name;
          Block.text user.name;
          Block.class_name Css.handle;
          Block.text ("@" ^ user.id);
          Block_stubs.node
            (match Yuka.State.get (Yuka.Remote.state stats) with
            | Yuka.Status.Ready { data = stats; _ } | Yuka.Status.Loading (Some stats) ->
                Block_stubs.block stats_template
                  [|
                    Block.class_name Css.stats;
                    Block_stubs.node (stat "Open" stats.open_);
                    Block_stubs.node (stat "In progress" stats.in_progress);
                    Block_stubs.node (stat "Done" stats.done_);
                  |]
            | Yuka.Status.Idle | Yuka.Status.Loading None -> Block_stubs.block loading_template [| Block.class_name Css.note |]
            | Yuka.Status.Failed _ -> Block_stubs.block failed_template [| Block.class_name Css.note |]);
        |]
      in
      fun (workspace, user, id) -> view ~workspace ~user ~id ())

let make_props ~(workspace : Workspace.t) ~(user : User.t) ~(row : string) () = (workspace, user, row)

let make =
  Block_stubs.component ~markup:{|<span><button aria-haspopup="dialog"></button><!----></span>|} ~walk:[| 0; 0; 3; 1 |]
    ~targets:[| 0; 1; 1; 1; 1; 1; 2 |]
    ~kinds:
      [|
        Block_stubs.Class;
        Block_stubs.Class;
        Block_stubs.Attr "popovertarget";
        Block_stubs.Attr "aria-label";
        Block_stubs.Click;
        Block_stubs.child_kind Views_blocks.avatar;
        Block_stubs.Node;
      |]
    (fun _ ->
      let opened = State.make false in
      let view ~workspace ~(user : User.t) ~row () =
        let id = "user-" ^ row in
        [|
          Block.class_name Css.wrap;
          Block.class_name Css.trigger;
          Block.attr id;
          Block.attr user.name;
          Block.on_click (fun _ -> State.set opened true);
          Block.child (Views_blocks.avatar_props ~user:(Some user) ());
          Block_stubs.node
            (if State.get opened then Block_stubs.instance card (card_props ~workspace ~user ~id ())
             else Block_stubs.empty);
        |]
      in
      fun (workspace, user, row) -> view ~workspace ~user ~row ())
