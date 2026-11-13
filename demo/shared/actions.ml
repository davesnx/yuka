open Model

type update_input = {
  id : string;
  status : Issue.status option;
  priority : Issue.priority option;
}
[@@deriving codec]

module Status_field = struct
  type t = Issue.status

  let of_string = Issue.status_of_slug
  let to_string = Issue.status_slug
end

module Priority_field = struct
  type t = Issue.priority

  let of_string = Issue.priority_of_slug
  let to_string = Issue.priority_slug
end

module Workspace_field = struct
  type t = Workspace.t

  let of_string = Workspace.of_slug
  let to_string = Workspace.slug
end

type new_issue = {
  workspace : Workspace_field.t;
  title : string;
  description : string;
  status : Status_field.t;
  priority : Priority_field.t;
}
[@@deriving form]

type comment_input = { issue_id : string; body : string } [@@deriving codec]

let update_issue =
  Yuka.Action.mutation ~name:"update_issue" ~input:update_input_codec
    ~output:Issue.codec

let create_issue = Yuka.Form.action ~name:"create_issue" ~fields:new_issue_form ~output:Issue.codec

let add_comment =
  Yuka.Action.mutation ~name:"add_comment" ~input:comment_input_codec
    ~output:Comment.codec
