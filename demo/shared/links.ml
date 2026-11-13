open Model

let default workspace = workspace = Workspace.default

let issues workspace =
  if default workspace then Routes.issues () else Routes.workspace_issues ~workspace ()

let my_issues workspace =
  if default workspace then Routes.my_issues () else Routes.workspace_my_issues ~workspace ()

let insights workspace =
  if default workspace then Routes.insights () else Routes.workspace_insights ~workspace ()

let create workspace =
  if default workspace then Routes.create () else Routes.workspace_create ~workspace ()

let issue workspace ~id =
  if default workspace then Routes.issue ~id () else Routes.workspace_issue ~workspace ~id ()
