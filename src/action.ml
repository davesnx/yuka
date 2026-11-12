  type (_, _, _) form =
    | Mutation : (_, _, [ `Mutation ]) form
    | Query : (_, _, [ `Query ]) form
    | Form : ('i, 'f) Form_core.t * 'x Codec.t -> ('i, ('x, ('f option * string) list) result, [ `Form ]) form

  type ('i, 'o, 'kind) t = {
    name : string;
    input : 'i Codec.t;
    output : 'o Codec.t;
    form : ('i, 'o, 'kind) form;
  }

  let mutation ~name ~input ~output = { name; input; output; form = Mutation }
  let query ~name ~input ~output = { name; input; output; form = Query }
  let name a = a.name

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

  let transport : (string -> Json.t -> (Json.t, Status.error) result Async.t) ref =
    ref (fun _ _ -> Async.return (Error (Status.Network "no action transport")))

  let call a i =
    Async.map
      (function
        | Ok j -> Result.map_error (fun m -> Status.Protocol m) (a.output.decode j)
        | Error e -> Error e)
      (!transport a.name (a.input.encode i))
