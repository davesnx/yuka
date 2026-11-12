module User = struct
  type t = { id : string; name : string } [@@deriving codec]

  let initials user =
    String.split_on_char ' ' user.name
    |> List.filter_map (fun word -> if word = "" then None else Some (String.sub word 0 1))
    |> String.concat ""
end

module Issue = struct
  type status = Backlog | Todo | In_progress | Done | Canceled [@@deriving codec]
  type priority = No_priority | Urgent | High | Medium | Low [@@deriving codec]

  type t = {
    id : string;
    title : string;
    description : string;
    status : status;
    priority : priority;
    assignee : User.t option;
    labels : string list;
    created_at : string;
  }
  [@@deriving codec]

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

module Comment = struct
  type t = { id : string; author : User.t; body : string; created_at : string }
  [@@deriving codec]
end
