  type ('i, 'o) t = { name : string; input : 'i Codec.t; output : 'o Codec.t }

  let declare ~name ~input ~output = { name; input; output }
  let name a = a.name
  let transport : (string -> Json.t -> Json.t Async.t) ref =
    ref (fun _ _ -> Async.failed "no action transport")

  let call a i =
    Async.bind (!transport a.name (a.input.encode i)) (fun j ->
        match a.output.decode j with
        | Ok v -> Async.resolved v
        | Error e -> Async.failed e)
