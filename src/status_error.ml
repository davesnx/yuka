type t =
  | Rejected of string
  | Forbidden
  | Not_found
  | Server
  | Network of string
  | Protocol of string
