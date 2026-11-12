type t = { ok : string; error : string; some : int; none : bool } [@@deriving form]

let parse s = match int_of_string_opt s with Some n -> Ok n | None -> Error s
let names = List.map (Yuka.Form.name form) [ `Ok; `Error; `Some; `None ]
