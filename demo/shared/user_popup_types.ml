open Model

type input = { workspace : Workspace.t; user : string } [@@deriving codec]
type stats = { open_ : int; in_progress : int; done_ : int } [@@deriving codec]
