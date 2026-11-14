module Team = struct
  type t = string

  let param =
    Yuka.Router.Param.make
      ~decode:(fun s -> if s = "" || s = "BAD" then None else Some s)
      ~encode:(fun s -> s)
end

module Fragile = struct
  type t = string

  let param =
    Yuka.Router.Param.make ~decode:(fun s -> if s = "boom" then failwith "decoder" else Some s) ~encode:(fun s -> s)
end
