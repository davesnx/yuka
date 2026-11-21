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

  let send name json k =
    Client.use_actions ();
    !Bridge.send name json k

  let start_with send a i =
    let settled, resolve, _ = Async.make () in
    let live = ref true in
    let stop =
      send a.name (Codec.encode a.input i) (fun answer ->
          if !live then
            resolve
              (match answer with
              | Ok j -> Result.map_error (fun m -> Status.Protocol m) (Codec.decode a.output j)
              | Error e -> Error e))
    in
    let abort () =
      if !live then begin
        live := false;
        stop ()
      end
    in
    (settled, abort)

  let start a i = start_with send a i

  let call : type i o kind. (i, o, kind) t -> i -> (o, Status.error) result Async.t =
   fun a i ->
    match a.form with
    | Query ->
        let settled, abort = start_with Client.query a i in
        Client.own_call settled abort;
        settled
    | Mutation | Form _ -> fst (start a i)
