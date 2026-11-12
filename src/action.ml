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
  let with_form ~name ~input ~output form = { name; input; output; form }
  let name a = a.name
  let input a = a.input
  let output a = a.output
  let form a = a.form

  let send name json =
    Client.use_actions ();
    !Types.transport name json

  let call a i =
    Async.map
      (function
        | Ok j -> Result.map_error (fun m -> Status.Protocol m) (a.output.decode j)
        | Error e -> Error e)
      (send a.name (a.input.encode i))
