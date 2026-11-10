module Issue_id = struct
  type t = int

  let prefix = "YUK-"

  let of_string s =
    let n = Stdlib.String.length prefix in
    if
      Stdlib.( > ) (Stdlib.String.length s) n
      && Stdlib.String.equal (Stdlib.String.sub s 0 n) prefix
    then
      match
        Yuka.Router.int_param
          (Stdlib.String.sub s n (Stdlib.( - ) (Stdlib.String.length s) n))
      with
      | Some i when Stdlib.( > ) i 0 -> Some i
      | _ -> None
    else None

  let to_string i = Stdlib.( ^ ) prefix (Stdlib.string_of_int i)
end

module Tab = struct
  type t = Overview | Activity

  let of_string = function
    | "overview" -> Some Overview
    | "activity" -> Some Activity
    | _ -> None

  let to_string = function Overview -> "overview" | Activity -> "activity"
end
