let recent = Yuka.Topic.declare ~name:"async_feed_recent" ~key:Yuka.Codec.unit ~state:(Yuka.Codec.list Model.event_codec)
let simulate = Yuka.Action.mutation ~name:"async_feed_simulate" ~input:Yuka.Codec.unit ~output:Yuka.Codec.int
