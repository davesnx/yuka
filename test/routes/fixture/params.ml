module Issue_id = struct
  type t = int

  let prefix = "YUK-"

  let of_string s =
    let n = String.length prefix in
    if String.length s > n && String.sub s 0 n = prefix then
      match Yuka.Router.int_param (String.sub s n (String.length s - n)) with
      | Some i when i > 0 -> Some i
      | _ -> None
    else None

  let to_string i = prefix ^ string_of_int i
end

module Tab = struct
  type t = Overview | Activity

  let of_string = function
    | "overview" -> Some Overview
    | "activity" -> Some Activity
    | _ -> None

  let to_string = function Overview -> "overview" | Activity -> "activity"
end
