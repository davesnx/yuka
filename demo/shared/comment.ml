type t = { id : string; author : Model.User.t; body : Markup.node list; created_at : string } [@@deriving codec]
type input = { issue_id : string; body : string } [@@deriving codec]

let add = Yuka.Action.mutation ~name:"add_comment" ~input:input_codec ~output:codec
