type error =
  | Rejected of string
  | Forbidden
  | Not_found
  | Server
  | Network of string
  | Protocol of string

type 'a t =
  | Idle
  | Loading of 'a option
  | Ready of { data : 'a; stale : bool }
  | Failed of { error : error; last : 'a option }

let data = function
  | Idle -> None
  | Loading d -> d
  | Ready { data; _ } -> Some data
  | Failed { last; _ } -> last

let error_to_string = function
  | Rejected m -> m
  | Forbidden -> "forbidden"
  | Not_found -> "not found"
  | Server -> "server error"
  | Network m -> "network error: " ^ m
  | Protocol m -> "protocol error: " ^ m
