type view = All | Mine [@@deriving codec]

let issues =
  Yuka.Action.query ~name:"issues" ~input:view_codec ~output:(Yuka.Codec.list Model.Issue.codec)
