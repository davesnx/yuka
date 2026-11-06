open Model

type update_input = {
  id : string;
  status : Issue.status option;
  priority : Issue.priority option;
}
[@@deriving codec]

type create_input = {
  title : string;
  description : string;
  status : Issue.status;
  priority : Issue.priority;
}
[@@deriving codec]

type create_error =
  | Empty_title
  | Title_too_long of int
  | Duplicate_title of string
[@@deriving codec]

type comment_input = { issue_id : string; body : string } [@@deriving codec]

let update_issue =
  Yuka.Action.declare ~name:"update_issue" ~input:update_input_codec
    ~output:Issue.codec

let create_issue =
  Yuka.Action.declare ~name:"create_issue" ~input:create_input_codec
    ~output:(Yuka.Codec.result Issue.codec create_error_codec)

let add_comment =
  Yuka.Action.declare ~name:"add_comment" ~input:comment_input_codec
    ~output:Comment.codec
