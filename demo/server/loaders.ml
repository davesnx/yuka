open Demo_shared.Model

let issue_in workspace id =
  Yuka.Async.return
    (match Store.find id with
    | Some (issue : Issue.t) when issue.workspace = workspace -> Ok issue
    | _ -> Error Yuka.Server.Not_found)

let issue (_ : Dream.request) ~id = issue_in Workspace.default id

module Workspace = struct
  let issue (_ : Dream.request) ~workspace ~id = issue_in workspace id
end
