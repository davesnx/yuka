open Model

type content = Card of { title : string; status : Issue.status } | Note of string [@@deriving codec]
type item = { id : string; x : int; y : int; content : content } [@@deriving codec]
type t = item list [@@deriving codec]

let width = 2400
let height = 1600
let item_width = 200
let item_height = 72
let note_length = 140
let note_limit = 100
let card_limit = 200
let inside ~x ~y = x >= 0 && y >= 0 && x <= width - item_width && y <= height - item_height

type move = { workspace : Workspace.t; id : string; x : int; y : int } [@@deriving codec]
type note = { workspace : Workspace.t; text : string } [@@deriving codec]
type remove = { workspace : Workspace.t; note_id : string } [@@deriving codec]
