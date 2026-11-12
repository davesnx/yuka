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
  let with_form ~name ~input ~output form : (_, _, [ `Mutation ]) t = { name; input; output; form = Some form }
  let name a = a.name
  let input a = a.input
  let output a = a.output
  let form a = a.form
  let send name json =
    Client.use_actions ();
    !Types.transport name json

  let call a i =
    Async.bind (send a.name (a.input.encode i)) (fun j ->
        match a.output.decode j with
        | Ok v -> Async.return v
        | Error e -> Async.failed e)
