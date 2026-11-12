type issue_id = int

let prefix = "YUK-"

let decode_issue_id s =
  let n = Stdlib.String.length prefix in
  if
    Stdlib.( > ) (Stdlib.String.length s) n
    && Stdlib.String.equal (Stdlib.String.sub s 0 n) prefix
  then
    match
      Yuka.Router.Param.decode Yuka.Router.Param.int
        (Stdlib.String.sub s n (Stdlib.( - ) (Stdlib.String.length s) n))
    with
    | Some i when Stdlib.( > ) i 0 -> Some i
    | _ -> None
  else None

let issue_id_param =
  Yuka.Router.Param.make ~decode:decode_issue_id ~encode:(fun i ->
      Stdlib.( ^ ) prefix (Yuka.Router.Param.encode Yuka.Router.Param.int i))

module Tab = struct
  type t = Overview | Activity

  let param =
    Yuka.Router.Param.make
      ~decode:(function
        | "overview" -> Some Overview | "activity" -> Some Activity | _ -> None)
      ~encode:(function Overview -> "overview" | Activity -> "activity")
end
