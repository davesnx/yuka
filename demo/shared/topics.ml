let issues =
  Yuka.Topic.declare ~name:"issues" ~key:Queries_types.issue_list_codec ~state:(Yuka.Codec.list Model.Issue.codec)

let issue = Yuka.Topic.declare ~name:"issue" ~key:Yuka.Codec.string ~state:Model.Issue.codec

let board = Yuka.Topic.declare ~name:"board" ~key:Model.Workspace.codec ~state:Board_types.codec
