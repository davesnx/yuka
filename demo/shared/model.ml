module User = struct
  type t = { id : string; name : string } [@@deriving codec]

  let initials u =
    String.split_on_char ' ' u.name
    |> List.filter_map (fun w -> if w = "" then None else Some (String.sub w 0 1))
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

  let status_of_slug s = List.find_opt (fun x -> status_slug x = s) all_statuses
  let priority_of_slug s = List.find_opt (fun x -> priority_slug x = s) all_priorities

  let group issues =
    List.filter_map
      (fun s ->
        match List.filter (fun i -> i.status = s) issues with
        | [] -> None
        | items -> Some (s, items))
      all_statuses

  let contains ~sub s =
    let n = String.length sub and m = String.length s in
    let rec at i = i + n <= m && (String.sub s i n = sub || at (i + 1)) in
    at 0

  let matches ~query i =
    contains ~sub:(String.lowercase_ascii query) (String.lowercase_ascii i.title)
end

module Comment = struct
  type t = { id : string; author : User.t; body : string; created_at : string }
  [@@deriving codec]
end
