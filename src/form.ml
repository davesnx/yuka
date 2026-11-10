open Types

type 'f errors = ('f option * string) list
type 'a kind = { read : string list -> ('a, string) result; write : 'a -> string list }

let first k = function v :: _ -> k v | [] -> Error "Missing"
let string = { read = first (fun v -> Ok v); write = (fun v -> [ v ]) }

let int =
  {
    read = first (fun v -> match int_of_string_opt (String.trim v) with Some n -> Ok n | None -> Error "Not a whole number");
    write = (fun n -> [ string_of_int n ]);
  }

let float =
  {
    read = first (fun v -> match float_of_string_opt (String.trim v) with Some f -> Ok f | None -> Error "Not a number");
    write = (fun f -> [ Json.float_repr f ]);
  }

let bool = { read = (function [] -> Ok false | _ -> Ok true); write = (fun b -> if b then [ "on" ] else []) }

let option k =
  {
    read = (function [] | [ "" ] -> Ok None | vs -> Result.map Option.some (k.read vs));
    write = (function None -> [] | Some v -> k.write v);
  }

let list k =
  {
    read =
      (fun vs ->
        List.fold_right
          (fun v acc ->
            match (k.read [ v ], acc) with
            | Ok x, Ok xs -> Ok (x :: xs)
            | Error m, _ | _, Error m -> Error m)
          vs (Ok []));
    write = List.concat_map k.write;
  }

let custom of_string to_string =
  {
    read = first (fun v -> match of_string v with Some x -> Ok x | None -> Error "Not valid");
    write = (fun v -> [ to_string v ]);
  }

type 'f decoding = { values : (string * string) list; mutable failed : 'f errors }

let field d f name k =
  match k.read (List.filter_map (fun (n, v) -> if String.equal n name then Some v else None) d.values) with
  | Ok v -> Some v
  | Error m ->
      d.failed <- (Some f, m) :: d.failed;
      None

let get = function Some v -> v | None -> invalid_arg "Yuka.Form.get"
let finish d build = if d.failed = [] then Ok (build ()) else Error (List.rev d.failed)
let put name k v = List.map (fun s -> (name, s)) (k.write v)

type ('i, 'f) t = {
  names : ('f * string) list;
  read : 'f decoding -> ('i, 'f errors) result;
  write : 'i -> (string * string) list;
}

type ('i, 'o, 'f) action = ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t

let fields ~names ~decode ~encode = { names; read = decode; write = encode }
let decode t values = t.read { values; failed = [] }
let encode t v = t.write v
let name t f = snd (List.find (fun (g, _) -> g == f) t.names)
let of_name t n = Option.map fst (List.find_opt (fun (_, m) -> String.equal m n) t.names)

let errors_json t (errors : _ errors) : Json.t =
  `List
    (List.map
       (fun (f, m) -> `List [ (match f with Some f -> `String (name t f) | None -> `Null); `String m ])
       errors)

let errors_of_json t (j : Json.t) : _ errors =
  match j with
  | `List items ->
      List.filter_map
        (function
          | `List [ `String n; `String m ] -> Some (of_name t n, m)
          | `List [ `Null; `String m ] -> Some (None, m)
          | _ -> None)
        items
  | _ -> []

let redirect : string option ref = ref None

let pairs_json values : Json.t = `List (List.map (fun (k, v) -> `List [ `String k; `String v ]) values)

let pairs_of_json = function
  | `List items ->
      Some (List.filter_map (function `List [ `String k; `String v ] -> Some (k, v) | _ -> None) items)
  | _ -> None

let action ~name ~fields:t ~(output : 'o Codec.t) =
  let input : _ Codec.t =
    {
      encode = (fun i -> pairs_json (t.write i));
      decode =
        (fun j ->
          match pairs_of_json j with
          | None -> Codec.mismatch "form fields" j
          | Some values -> (
              match decode t values with
              | Ok i -> Ok i
              | Error e -> Error (String.concat "; " (List.map snd e))));
    }
  in
  let result : (('o, _) result) Codec.t =
    {
      encode =
        (function
        | Ok o -> `Assoc [ ("value", output.encode o) ]
        | Error e -> `Assoc [ ("errors", errors_json t e) ]);
      decode =
        (fun j ->
          match j with
          | `Assoc fields -> (
              match (List.assoc_opt "value" fields, List.assoc_opt "errors" fields) with
              | Some v, _ ->
                  redirect := (match List.assoc_opt "redirect" fields with Some (`String l) -> Some l | _ -> None);
                  Result.map Result.ok (output.decode v)
              | None, Some e -> Ok (Error (errors_of_json t e))
              | None, None -> Codec.mismatch "form answer" j)
          | _ -> Codec.mismatch "form answer" j);
    }
  in
  let form values =
    match decode t values with
    | Ok i -> Ok (pairs_json (t.write i))
    | Error e -> Error (errors_json t e)
  in
  ({ Action.name; input; output = result; form = Some form } : (_, _, [ `Mutation ]) Action.t)

type ('o, 'f) form = {
  sent : (string * string) list;
  failed : 'f errors State.t;
  busy : bool State.t;
  field_name : 'f -> string;
}

let value form f = Option.value (List.assoc_opt (form.field_name f) form.sent) ~default:""

let error form f =
  List.find_map
    (fun (g, m) -> match g with Some g when g == f -> Some m | _ -> None)
    (State.get form.failed)

let form_errors form = List.filter_map (fun (g, m) -> if g = None then Some m else None) (State.get form.failed)
let error_view form f view = Hole (fun () -> match error form f with Some m -> view m | None -> Fragment [])

let form_error_view form view =
  Hole (fun () -> Fragment (List.map view (form_errors form)))

let pending form = State.get form.busy

let sent_state name =
  match !current_session with
  | Some { form = Some (n, values, errors); _ } when String.equal n name -> Some (values, errors)
  | Some _ -> None
  | None when Web.in_browser ->
      List.find_map
        (fun el ->
          if Web.get_attribute el "data-yuka-action" <> Some name then None
          else
            match Option.map Json.of_string (Web.get_attribute el "data-yuka-sent") with
            | Some (Ok (`Assoc fields)) -> (
                match (Option.bind (List.assoc_opt "fields" fields) pairs_of_json, List.assoc_opt "errors" fields) with
                | Some values, Some errors -> Some (values, errors)
                | _ -> None)
            | _ -> None)
        (Array.to_list (Web.query_all (Web.document ()) "form[data-yuka-sent]"))
  | None -> None

let make ~(action : ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t) ?run ?on_ok ~children () =
  let name = action.name in
  let field_name f =
    match action.output.encode (Error [ (Some f, "") ]) with
    | `Assoc [ ("errors", `List [ `List [ `String n; _ ] ]) ] -> n
    | _ -> ""
  in
  let decode_errors j =
    match action.output.decode (`Assoc [ ("errors", j) ]) with Ok (Error e) -> e | _ -> []
  in
  let sent = sent_state name in
  let form =
    {
      sent = (match sent with Some (v, _) -> v | None -> []);
      failed = State.make (match sent with Some (_, e) -> decode_errors e | None -> []);
      busy = State.make false;
      field_name;
    }
  in
  let finish result =
    State.set form.busy false;
    match result with
    | Ok (Ok o) -> (
        match on_ok with
        | Some f -> f o
        | None -> Option.iter Platform.Browser.navigate !redirect)
    | Ok (Error e) -> State.set form.failed e
    | Error m -> State.set form.failed [ (None, m) ]
  in
  let submit ev =
    Web.prevent_default ev;
    match Option.map (fun f -> f (Array.to_list (Web.form_values (Web.target ev)))) action.form with
    | Some (Error j) -> State.set form.failed (decode_errors j)
    | Some (Ok j) -> (
        match action.input.decode j with
        | Ok input ->
            State.set form.failed [];
            State.set form.busy true;
            redirect := None;
            let call = match run with Some f -> f input | None -> Action.call action input in
            Async.on_result call finish
        | Error m -> State.set form.failed [ (None, m) ])
    | None -> ()
  in
  let sent_attr =
    match sent with
    | Some (values, errors) ->
        [ Static ("data-yuka-sent", Json.to_string (`Assoc [ ("fields", pairs_json values); ("errors", errors) ])) ]
    | None -> []
  in
  Element
    {
      tag = "form";
      attrs = [ Static ("method", "post"); Static ("data-yuka-action", name) ] @ sent_attr @ [ Handler ("submit", submit) ];
      children =
        [
          Element
            {
              tag = "input";
              attrs = [ Static ("type", "hidden"); Static ("name", "_yuka_action"); Static ("value", name) ];
              children = [];
            };
          children form;
        ];
    }
