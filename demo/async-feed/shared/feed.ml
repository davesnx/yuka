let kept = 500
let recent = Yuka.Topic.declare ~name:"async_feed_recent" ~key:Yuka.Codec.unit ~state:(Yuka.Codec.list Model.event_codec)
let simulate = Yuka.Action.mutation ~name:"async_feed_simulate" ~input:Yuka.Codec.unit ~output:Yuka.Codec.int

type comment_input = { item : int; text : string } [@@deriving codec]

let max_comment = 1000
let comment = Yuka.Action.mutation ~name:"async_feed_comment" ~input:comment_input_codec ~output:(Yuka.Codec.list Model.comment_codec)
let counts : (int * int) list Yuka.State.t = Yuka.State.make []
let count ~id initial = Option.value (List.assoc_opt id (Yuka.State.get counts)) ~default:initial
let set_count ~id n = Yuka.State.set counts ((id, n) :: List.remove_assoc id (Yuka.State.peek counts))
