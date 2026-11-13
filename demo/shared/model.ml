module User = struct
  type t = { id : string; name : string } [@@deriving codec]

  let initials user =
    String.split_on_char ' ' user.name
    |> List.filter_map (fun word -> if word = "" then None else Some (String.sub word 0 1))
    |> String.concat ""
end

module Workspace = struct
  type t = Yuka | Stress [@@deriving codec]

  let all = [ Yuka; Stress ]
  let default = Yuka

  let slug = function Yuka -> "yuka" | Stress -> "stress"
  let name = function Yuka -> "Yuka" | Stress -> "Stress"
  let issue_prefix = function Yuka -> "YUK" | Stress -> "STR"
  let of_slug text = List.find_opt (fun workspace -> slug workspace = text) all
  let param = Yuka.Router.Param.make ~decode:of_slug ~encode:slug
end

module Issue = struct
  type status = Backlog | Todo | In_progress | Done | Canceled [@@deriving codec]
  type priority = No_priority | Urgent | High | Medium | Low [@@deriving codec]

  type t = {
    id : string;
    workspace : Workspace.t;
    title : string;
    description : string;
    status : status;
    priority : priority;
    assignee : User.t option;
    labels : string list;
    created_at : string;
  }
  [@@deriving codec]

  let number issue =
    match String.index_opt issue.id '-' with
    | Some dash -> Option.value (int_of_string_opt (String.sub issue.id (dash + 1) (String.length issue.id - dash - 1))) ~default:0
    | None -> 0

  let all_statuses = [ In_progress; Todo; Backlog; Done; Canceled ]

  let all_priorities = [ No_priority; Urgent; High; Medium; Low ]

  let status_label = function
    | Backlog -> "Backlog"
    | Todo -> "Todo"
    | In_progress -> "In Progress"
    | Done -> "Done"
    | Canceled -> "Canceled"

  let status_slug = function
    | Backlog -> "backlog"
    | Todo -> "todo"
    | In_progress -> "in-progress"
    | Done -> "done"
    | Canceled -> "canceled"

  let priority_label = function
    | No_priority -> "No priority"
    | Urgent -> "Urgent"
    | High -> "High"
    | Medium -> "Medium"
    | Low -> "Low"

  let priority_slug = function
    | No_priority -> "none"
    | Urgent -> "urgent"
    | High -> "high"
    | Medium -> "medium"
    | Low -> "low"

  let status_of_slug slug = List.find_opt (fun status -> status_slug status = slug) all_statuses
  let priority_of_slug slug = List.find_opt (fun priority -> priority_slug priority = slug) all_priorities

  let group issues =
    List.filter_map
      (fun status ->
        match List.filter (fun issue -> issue.status = status) issues with
        | [] -> None
        | items -> Some (status, items))
      all_statuses

  let contains ~sub text =
    let sub_length = String.length sub and text_length = String.length text in
    let rec at index = index + sub_length <= text_length && (String.sub text index sub_length = sub || at (index + 1)) in
    at 0

  let matches ~query issue =
    contains ~sub:(String.lowercase_ascii query) (String.lowercase_ascii issue.title)
end
