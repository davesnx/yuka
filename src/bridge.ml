let fields body = match Json.of_string body with Ok (`Assoc f) -> Some f | _ -> None

let of_response status fields : (Json.t, Status.error) result =
  let message () =
    match Option.bind fields (List.assoc_opt "error") with
    | Some (`String m) -> m
    | _ -> "HTTP " ^ string_of_int status
  in
  match (status, Option.bind fields (List.assoc_opt "ok")) with
  | 200, Some v -> Ok v
  | 400, _ -> Error (Status.Rejected (message ()))
  | 403, _ -> Error Status.Forbidden
  | 404, _ -> Error Status.Not_found
  | (413 | 415), _ -> Error (Status.Protocol (message ()))
  | s, _ when s >= 500 -> Error Status.Server
  | _ -> Error (Status.Protocol ("unexpected response (HTTP " ^ string_of_int status ^ ")"))

let send : (string -> Json.t -> ((Json.t, Status.error) result -> unit) -> unit -> unit) ref =
  ref (fun _ _ k ->
      k (Error (Status.Network "no action transport"));
      ignore)

let live_state : (string -> Json.t -> (Json.t, Status.error) result Async.t) ref =
  ref (fun name _ -> Async.return (Error (Status.Network ("no live topic " ^ name))))

let reset_live : (unit -> unit) ref = ref ignore
