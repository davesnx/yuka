open Model

let default workspace = workspace = Workspace.default

let issues ?q ?label workspace =
  if default workspace then Routes.issues ?q ?label () else Routes.workspace_issues ~workspace ?q ?label ()

let my_issues ?q ?label workspace =
  if default workspace then Routes.my_issues ?q ?label () else Routes.workspace_my_issues ~workspace ?q ?label ()

let insights workspace =
  if default workspace then Routes.insights () else Routes.workspace_insights ~workspace ()

let report workspace =
  if default workspace then Routes.report () else Routes.workspace_report ~workspace ()

let canvas workspace =
  if default workspace then Routes.canvas () else Routes.workspace_canvas ~workspace ()

let create workspace =
  if default workspace then Routes.create () else Routes.workspace_create ~workspace ()

let issue workspace ~id =
  if default workspace then Routes.issue ~id () else Routes.workspace_issue ~workspace ~id ()
