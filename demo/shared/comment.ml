type t = { id : string; author : Model.User.t; body : Markup.node list; created_at : string } [@@deriving codec]
type thread = { first : t list; hidden : int; last : t list } [@@deriving codec]
type range = { issue : string; offset : int; limit : int } [@@deriving codec]
type input = { issue_id : string; body : string } [@@deriving codec]

let add = Yuka.Action.mutation ~name:"add_comment" ~input:input_codec ~output:codec
let range = Yuka.Action.query ~name:"comment_range" ~input:range_codec ~output:(Yuka.Codec.list codec)
