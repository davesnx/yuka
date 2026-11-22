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

let%action update_issue =
  Yuka.Action.mutation ~input:update_input_codec ~output:Issue.codec (fun _ ({ id; status; priority } : update_input) ->
      match Store.workspace_of id with
      | None -> Yuka.Server.Action.reject ("No issue " ^ id)
      | Some workspace ->
          Store.write workspace
            (fun () -> Option.to_result ~none:("No issue " ^ id) (Store.update ~id ?status ?priority ()))
            (fun issue ->
              Store.publish_issue issue;
              Yuka.Async.return issue))

let create_issue = Yuka.Form.action ~name:"create_issue" ~fields:new_issue_form ~output:Issue.codec
