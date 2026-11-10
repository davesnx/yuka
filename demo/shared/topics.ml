let issues =
  Yuka.Topic.declare ~name:"issues" ~key:Queries.view_codec ~state:(Yuka.Codec.list Model.Issue.codec)

let issue = Yuka.Topic.declare ~name:"issue" ~key:Yuka.Codec.string ~state:Model.Issue.codec
