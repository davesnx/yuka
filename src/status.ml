type error = Status_error.t =
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

let map f = function
  | Idle -> Idle
  | Loading d -> Loading (Option.map f d)
  | Ready { data; stale } -> Ready { data = f data; stale }
  | Failed { error; last } -> Failed { error; last = Option.map f last }

let error_to_string = function
  | Rejected m -> m
  | Forbidden -> "forbidden"
  | Not_found -> "not found"
  | Server -> "server error"
  | Network m -> "network error: " ^ m
  | Protocol m -> "protocol error: " ^ m

let error_codec : error Codec.t =
  let kind k extra : Json.t = `Assoc (("kind", `String k) :: extra) in
  let message m = [ ("message", `String m) ] in
  {
    encode =
      (function
      | Rejected m -> kind "rejected" (message m)
      | Forbidden -> kind "forbidden" []
      | Not_found -> kind "not_found" []
      | Server -> kind "server" []
      | Network m -> kind "network" (message m)
      | Protocol m -> kind "protocol" (message m));
    decode =
      (fun j ->
        match j with
        | `Assoc fields -> (
            let text () =
              match List.assoc_opt "message" fields with Some (`String m) -> m | _ -> ""
            in
            match List.assoc_opt "kind" fields with
            | Some (`String "rejected") -> Ok (Rejected (text ()))
            | Some (`String "forbidden") -> Ok Forbidden
            | Some (`String "not_found") -> Ok Not_found
            | Some (`String "server") -> Ok Server
            | Some (`String "network") -> Ok (Network (text ()))
            | Some (`String "protocol") -> Ok (Protocol (text ()))
            | _ -> Codec.mismatch "status error" j)
        | _ -> Codec.mismatch "status error" j);
  }
