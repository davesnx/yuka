module Team = struct
  type t = string

  let of_string s = if s = "" || s = "BAD" then None else Some s
  let to_string s = s
end
