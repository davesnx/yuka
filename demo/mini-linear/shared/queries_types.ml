type view = All | Mine [@@deriving codec]
type issue_list = { workspace : Model.Workspace.t; view : view } [@@deriving codec]
type label_count = { label : string; open_ : int } [@@deriving codec]
