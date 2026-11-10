  type ('i, 'o) form =
    | Form : ('i, 'f) Form_core.t * 'x Codec.t -> ('i, ('x, ('f option * string) list) result) form

  type ('i, 'o, 'kind) t = {
    name : string;
    input : 'i Codec.t;
    output : 'o Codec.t;
    form : ('i, 'o) form option;
  }

  let declare ~name ~input ~output : (_, _, [ `Mutation ]) t = { name; input; output; form = None }
  let query ~name ~input ~output : (_, _, [ `Query ]) t = { name; input; output; form = None }
  let name a = a.name
  let transport : (string -> Json.t -> Json.t Async.t) ref =
    ref (fun _ _ -> Async.failed "no action transport")

  let call a i =
    Async.bind (!transport a.name (a.input.encode i)) (fun j ->
        match a.output.decode j with
        | Ok v -> Async.return v
        | Error e -> Async.failed e)
